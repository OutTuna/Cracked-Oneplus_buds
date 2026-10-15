import Foundation
import IOBluetooth

public struct PairedDevice {
    public let name: String
    public let address: String
    public let connected: Bool
}

public enum TransportError: Error, CustomStringConvertible {
    case bluetooth(String, Int32)
    case unavailable(String)
    public var description: String {
        switch self {
        case let .bluetooth(action, status): return "\(action): IOReturn \(status)"
        case let .unavailable(message): return message
        }
    }
}

public final class RFCOMMTransport: NSObject, IOBluetoothRFCOMMChannelDelegate {
    public static let serviceUUID = "0000079A-D102-11E1-9B23-00025B00A5A5"
    public var onOpen: (() -> Void)?
    public var onData: (([UInt8]) -> Void)?
    public var onError: ((Error) -> Void)?
    public var onLog: ((String) -> Void)?
    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var closing = false

    public static func pairedDevices() -> [PairedDevice] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).map {
            PairedDevice(name: $0.name ?? "", address: $0.addressString ?? "", connected: $0.isConnected())
        }
    }

    public func open(address: String) {
        closing = false
        guard let device = IOBluetoothDevice(addressString: address) else {
            onError?(TransportError.unavailable("Invalid Bluetooth address")); return
        }
        self.device = device
        onLog?("Querying SDP service \(Self.serviceUUID)")
        let status = device.performSDPQuery(self)
        if status != kIOReturnSuccess { onError?(TransportError.bluetooth("SDP query", status)) }
    }

    @objc public func sdpQueryComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        guard !closing else { return }
        guard status == kIOReturnSuccess else { onError?(TransportError.bluetooth("SDP completion", status)); return }
        let uuidBytes: [UInt8] = [0, 0, 7, 0x9A, 0xD1, 2, 0x11, 0xE1, 0x9B, 0x23, 0, 2, 0x5B, 0, 0xA5, 0xA5]
        let uuid = IOBluetoothSDPUUID(data: Data(uuidBytes))
        guard let record = device.getServiceRecord(for: uuid) else {
            onError?(TransportError.unavailable("Vendor service not found in SDP. Open case and disconnect HeyMelody, then retry.")); return
        }
        var channelID: BluetoothRFCOMMChannelID = 0
        let result = record.getRFCOMMChannelID(&channelID)
        guard result == kIOReturnSuccess, channelID > 0 else {
            onError?(TransportError.bluetooth("Resolve RFCOMM channel", result)); return
        }
        onLog?("Opening RFCOMM channel \(channelID)")
        let openStatus = device.openRFCOMMChannelAsync(&channel, withChannelID: channelID, delegate: self)
        if openStatus != kIOReturnSuccess { onError?(TransportError.bluetooth("RFCOMM open", openStatus)) }
    }

    public func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        guard !closing else { return }
        if error == kIOReturnSuccess { channel = rfcommChannel; onOpen?() }
        else { onError?(TransportError.bluetooth("RFCOMM completion", error)) }
    }

    public func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard !closing, let dataPointer, dataLength > 0 else { return }
        onData?(Array(UnsafeRawBufferPointer(start: dataPointer, count: dataLength)))
    }

    public func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        channel = nil
        if !closing { onError?(TransportError.unavailable("RFCOMM channel closed by device")) }
    }

    public func write(_ bytes: [UInt8]) throws {
        guard let channel else { throw TransportError.unavailable("RFCOMM is not open") }
        guard bytes.count <= Int(channel.getMTU()) else {
            throw TransportError.unavailable("Packet exceeds RFCOMM MTU; fragmentation not implemented for outgoing packets")
        }
        var copy = bytes
        let status = copy.withUnsafeMutableBytes { buffer in
            channel.writeSync(buffer.baseAddress, length: UInt16(buffer.count))
        }
        guard status == kIOReturnSuccess else { throw TransportError.bluetooth("RFCOMM write", status) }
    }

    public func close() {
        closing = true
        if let channel { _ = channel.setDelegate(nil); _ = channel.close() }
        channel = nil
        device = nil
    }
}
