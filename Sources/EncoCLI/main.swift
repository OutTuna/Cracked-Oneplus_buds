import Foundation
import EncoCore

let help = """
Enco Air5 Pro experimental RFCOMM controller
Usage:
  enco devices
  enco info [--address AA:BB:CC:DD:EE:FF] [--log path.jsonl]
  enco battery|status|capabilities [--address AA:BB:CC:DD:EE:FF] [--log path.jsonl]
  enco eq|gestures [--address AA:BB:CC:DD:EE:FF] [--log path.jsonl]
  enco anc on|off|transparency [--address AA:BB:CC:DD:EE:FF] [--log path.jsonl]
Pair earbuds in macOS first. Close HeyMelody or disconnect the phone before testing.
Basic ANC, battery, firmware, EQ reads and gesture reads tested on CN 158.158.105.
"""

struct Options {
    let action: String
    let mode: ANCMode?
    let address: String?
    let log: String

    init(_ args: [String]) throws {
        guard let action = args.first, ["devices", "info", "anc", "battery", "status", "capabilities", "eq", "gestures"].contains(action) else {
            throw TransportError.unavailable(help)
        }
        var index = 1
        var mode: ANCMode?
        if action == "anc" {
            guard args.count > 1, let value = ANCMode(rawValue: args[1]) else {
                throw TransportError.unavailable("Expected anc on|off|transparency")
            }
            mode = value; index += 1
        }
        var address: String?
        var log = "enco-\(Int(Date().timeIntervalSince1970)).jsonl"
        while index < args.count {
            guard index + 1 < args.count else { throw TransportError.unavailable("Missing option value") }
            switch args[index] {
            case "--address":
                let value = args[index + 1].replacingOccurrences(of: "-", with: ":")
                guard value.range(of: "^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$", options: .regularExpression) != nil else {
                    throw TransportError.unavailable("Invalid Bluetooth address")
                }
                address = value
            case "--log": log = args[index + 1]
            default: throw TransportError.unavailable("Unknown option: \(args[index])")
            }
            index += 2
        }
        self.action = action; self.mode = mode; self.address = address; self.log = log
    }
}

final class Controller {
    let transport = RFCOMMTransport()
    let session = Session()
    let deviceProtocol: DeviceProtocol
    let options: Options
    let file: FileHandle
    var finished = false

    init(options: Options) throws {
        self.options = options
        deviceProtocol = DeviceProtocol(session: session)
        let url = URL(fileURLWithPath: options.log)
        try Data().write(to: url)
        file = try FileHandle(forWritingTo: url)
    }

    func log(_ event: String, _ message: String) {
        guard !finished else { return }
        let row = ["time": ISO8601DateFormatter().string(from: Date()), "event": event, "message": message]
        do {
            var data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            data.append(10)
            try file.write(contentsOf: data)
            print("[\(event)] \(message)")
        } catch { fputs("Log write failed: \(error)\n", stderr); exit(1) }
    }

    func finish(_ status: Int32, _ message: String) {
        guard !finished else { return }
        log(status == 0 ? "DONE" : "ERROR", message)
        finished = true
        session.cancel(); transport.close(); try? file.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(status) }
    }

    func start() {
        let candidates = RFCOMMTransport.pairedDevices().filter { $0.name.localizedCaseInsensitiveContains("Enco") }
        let address: String
        if let explicit = options.address { address = explicit }
        else if candidates.count == 1 { address = candidates[0].address }
        else { finish(1, "Expected one paired Enco device; run enco devices and select --address"); return }
        log("TARGET", address)
        transport.onLog = { [weak self] in self?.log("TRANSPORT", $0) }
        transport.onError = { [weak self] in self?.finish(1, String(describing: $0)) }
        session.onError = { [weak self] in self?.finish(1, String(describing: $0)) }
        deviceProtocol.onError = { [weak self] in self?.finish(1, String(describing: $0)) }
        session.onLog = { [weak self] in self?.log($0, $1) }
        deviceProtocol.onEvent = { [weak self] packet in
            self?.log("EVENT", String(format: "%04X seq=%02X ", packet.command, packet.sequence) + packet.payload.hex)
        }
        session.send = { [weak self] bytes in
            guard let self else { throw TransportError.unavailable("Controller closed") }
            try self.transport.write(bytes)
        }
        transport.onData = { [weak self] in self?.session.receive($0) }
        transport.onOpen = { [weak self] in
            self?.deviceProtocol.initialize { [weak self] in self?.runAction() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.finish(1, "Overall timeout; open case, check macOS Bluetooth permission and disconnect HeyMelody")
        }
        transport.open(address: address)
    }

    func runAction() {
        guard let capabilities = deviceProtocol.capabilities else { finish(1, "Initialization incomplete"); return }
        log("CAPABILITIES", capabilities.commands.sorted().map { String(format: "%04X", $0) }.joined(separator: " "))
        if let mode = options.mode {
            deviceProtocol.setANC(mode) { [weak self] state in
                guard let self else { return }
                guard state.capturedMode == mode else {
                    self.finish(1, "ANC acknowledged, but readback did not match \(mode.rawValue): mask=\(state.mask.hex)"); return
                }
                self.finish(0, "ANC \(mode.rawValue): confirmed by device readback")
            }
        } else if options.action == "capabilities" {
            finish(0, "Capability bitmap: \(capabilities.bitmap.hex)")
        } else if options.action == "gestures" {
            deviceProtocol.readGestures { [weak self] bindings in
                guard let self else { return }
                for binding in bindings {
                    self.log("GESTURE", "device=\(binding.deviceType) button=\(binding.button) action=\(binding.action) function=\(binding.function)")
                }
                self.finish(0, "Read \(bindings.count) gesture bindings; identifiers preserved without guessed labels")
            }
        } else if options.action == "eq" {
            deviceProtocol.readEQMode { [weak self] mode in
                guard let self else { return }
                self.log("EQ", "Current mode id: \(mode)")
                self.deviceProtocol.readEQProfiles { [weak self] profiles in
                    guard let self else { return }
                    for profile in profiles {
                        self.log("EQ_PROFILE", "id=\(profile.id) name=\(profile.name) selected=\(profile.selected) gains=\(profile.minimumGain)...\(profile.maximumGain) bands=" + profile.bands.map { "\($0.frequency)Hz:\($0.gain)" }.joined(separator: ","))
                    }
                    self.finish(0, "Read \(profiles.count) custom EQ profiles")
                }
            }
        } else if options.action == "battery" {
            deviceProtocol.readBattery { [weak self] entries in
                guard let self else { return }
                self.printBattery(entries); self.finish(0, "Battery query complete; only reported components are shown")
            }
        } else if options.action == "status" {
            deviceProtocol.readBattery { [weak self] entries in
                guard let self else { return }
                self.printBattery(entries)
                self.deviceProtocol.readNoiseState { [weak self] state in
                    self?.finish(0, "ANC state: \(state.capturedMode?.rawValue ?? "unmapped") mask=\(state.mask.hex)")
                }
            }
        } else {
            deviceProtocol.readVersion { [weak self] components in
                guard let self else { return }
                for component in components {
                    self.log("VERSION", "device=\(component.deviceType) type=\(component.versionType) value=\(component.value)")
                }
                self.finish(0, "Version query complete")
            }
        }
    }

    func printBattery(_ entries: [BatteryEntry]) {
        for entry in entries {
            log("BATTERY", "\(entry.label): \(entry.percent.map { "\($0)%" } ?? "unavailable") charging=\(entry.charging)")
        }
    }
}

let args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty || args == ["--help"] || args == ["-h"] { print(help); exit(0) }
do {
    let options = try Options(args)
    if options.action == "devices" {
        let devices = RFCOMMTransport.pairedDevices()
        guard !devices.isEmpty else {
            fputs("No paired devices visible to this process. Pair earbuds in macOS and run from a terminal with Bluetooth permission.\n", stderr)
            exit(2)
        }
        for device in devices {
            print("\(device.address)  \(device.connected ? "connected" : "paired")  \(device.name)")
        }
        exit(0)
    }
    let controller = try Controller(options: options)
    controller.start()
    withExtendedLifetime(controller) { RunLoop.main.run() }
} catch { fputs("\(error)\n", stderr); exit(1) }
