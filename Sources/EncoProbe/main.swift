import Foundation
import CoreBluetooth

final class Probe: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var central: CBCentralManager!
    private var device: CBPeripheral?
    private var candidates: [UUID: CBPeripheral] = [:]
    private var seen = Set<UUID>()
    private var pendingDiscovery = 0
    private var pendingReads = Set<String>()
    private var finished = false
    private let target: UUID?
    private let logURL: URL

    init(target: UUID?, logURL: URL) throws {
        self.target = target
        self.logURL = logURL
        try Data().write(to: logURL)
        super.init()
        record("session", ["model": "OPPO Enco Air5 Pro", "region": "CN", "firmwareReportedByUser": "158.158.105"])
        central = CBCentralManager(delegate: self, queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) {
            self.finish(2, "Timeout: discovery or reads incomplete; see log")
        }
    }

    private func record(_ event: String, _ fields: [String: Any] = [:]) {
        var row = fields
        row["event"] = event
        row["time"] = ISO8601DateFormatter().string(from: Date())
        do {
            var data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            data.append(0x0A)
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            print(String(decoding: data, as: UTF8.self), terminator: "")
        } catch {
            fputs("Cannot write diagnostic log: \(error)\n", stderr)
            exit(1)
        }
    }

    private func finish(_ status: Int32, _ message: String) {
        guard !finished else { return }
        finished = true
        record("finished", ["status": status, "message": message])
        central.stopScan()
        if let device { central.cancelPeripheralConnection(device) }
        exit(status)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unknown, .resetting: return
        case .poweredOn:
            if let target, let known = central.retrievePeripherals(withIdentifiers: [target]).first {
                connect(known)
                return
            }
            record("scan", ["message": "Open case. Without --id, candidates are listed for 12 seconds; exactly one is required."])
            central.scanForPeripherals(withServices: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                guard self.device == nil else { return }
                self.central.stopScan()
                guard self.candidates.count == 1, let only = self.candidates.values.first else {
                    self.finish(2, "Expected one matching device. Select a discovered identifier with --id UUID, or retry with case open.")
                    return
                }
                self.connect(only)
            }
        default: finish(1, "Bluetooth unavailable; state=\(central.state.rawValue), authorization=\(CBManager.authorization.rawValue)")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        guard seen.insert(peripheral.identifier).inserted else { return }
        let manufacturer = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        record("advertisement", ["id": peripheral.identifier.uuidString, "name": name,
            "rssi": RSSI, "manufacturerHex": manufacturer.map(hex) ?? "",
            "services": (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map { $0.uuidString }])
        if let target {
            if target == peripheral.identifier { connect(peripheral) }
        } else if name.localizedCaseInsensitiveContains("Enco") {
            candidates[peripheral.identifier] = peripheral
        }
    }

    private func connect(_ peripheral: CBPeripheral) {
        guard device == nil else { return }
        device = peripheral
        peripheral.delegate = self
        central.stopScan()
        record("connecting", ["id": peripheral.identifier.uuidString, "name": peripheral.name ?? ""])
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        record("connected")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finish(1, "Connection failed: \(String(describing: error))")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        finish(1, "Disconnected: \(String(describing: error))")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { finish(1, "Service discovery failed: \(error)"); return }
        let services = peripheral.services ?? []
        pendingDiscovery = services.count
        for service in services {
            record("service", ["uuid": service.uuid.uuidString, "primary": service.isPrimary])
            peripheral.discoverCharacteristics(nil, for: service)
        }
        checkComplete()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { finish(1, "Characteristic discovery failed: \(error)"); return }
        for characteristic in service.characteristics ?? [] {
            record("characteristic", ["service": service.uuid.uuidString,
                "uuid": characteristic.uuid.uuidString, "properties": characteristic.properties.rawValue])
            if characteristic.properties.contains(.read) {
                pendingReads.insert(key(characteristic))
                peripheral.readValue(for: characteristic)
            }
        }
        pendingDiscovery -= 1
        checkComplete()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        record("read", ["service": characteristic.service?.uuid.uuidString ?? "",
            "uuid": characteristic.uuid.uuidString, "hex": characteristic.value.map(hex) ?? "",
            "error": error.map { String(describing: $0) } ?? ""])
        pendingReads.remove(key(characteristic))
        checkComplete()
    }

    private func key(_ characteristic: CBCharacteristic) -> String {
        String(describing: ObjectIdentifier(characteristic))
    }

    private func checkComplete() {
        if pendingDiscovery == 0 && pendingReads.isEmpty { finish(0, "GATT inventory complete; no vendor commands sent") }
    }

    private func hex(_ data: Data) -> String { data.map { String(format: "%02X", $0) }.joined(separator: " ") }
}

let args = Array(CommandLine.arguments.dropFirst())
if args.contains("--help") || args.contains("-h") {
    print("Usage: enco-probe [--id UUID] [--log path.jsonl]\nDiscover Enco devices and read GATT characteristics; no vendor writes. Logs include nearby device identifiers.")
    exit(0)
}
var target: UUID?
var logPath = "enco-probe-\(Int(Date().timeIntervalSince1970)).jsonl"
var index = 0
while index < args.count {
    guard index + 1 < args.count else { fputs("Missing option value\n", stderr); exit(1) }
    switch args[index] {
    case "--id":
        guard let id = UUID(uuidString: args[index + 1]) else { fputs("Invalid UUID\n", stderr); exit(1) }
        target = id
    case "--log": logPath = args[index + 1]
    default: fputs("Unknown option: \(args[index])\n", stderr); exit(1)
    }
    index += 2
}
do {
    let probe = try Probe(target: target, logURL: URL(fileURLWithPath: logPath))
    withExtendedLifetime(probe) { RunLoop.main.run() }
} catch {
    fputs("Cannot start: \(error)\n", stderr)
    exit(1)
}
