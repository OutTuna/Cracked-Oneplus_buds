import Foundation

public enum SessionError: Error, CustomStringConvertible {
    case timeout(UInt16)
    case rejected(UInt16, [UInt8])
    case busy
    public var description: String {
        switch self {
        case let .timeout(command): return String(format: "No matching reply for command %04X", command)
        case let .rejected(command, payload): return String(format: "Command %04X rejected or unexpected reply: ", command) + payload.hex
        case .busy: return "Another request is pending"
        }
    }
}

public final class Session {
    public var onEvent: ((Packet) -> Void)?
    public var onLog: ((String, String) -> Void)?
    public var onError: ((Error) -> Void)?
    public var send: (([UInt8]) throws -> Void)?
    private var decoder = PacketDecoder()
    private var sequence: UInt8 = 0
    private var generation = 0
    private var pending: (command: UInt16, sequence: UInt8, completion: (Packet) -> Void)?

    public init() {}

    public func request(_ command: UInt16, payload: [UInt8] = [], completion: @escaping (Packet) -> Void) {
        guard pending == nil else { onError?(SessionError.busy); return }
        let packet = Packet(command: command, sequence: sequence, payload: payload)
        sequence &+= 1
        pending = (command | 0x8000, packet.sequence, completion)
        generation += 1
        let current = generation
        do {
            guard let send else { throw TransportError.unavailable("Session has no transport") }
            let bytes = try packet.encoded()
            onLog?("TX", bytes.hex)
            try send(bytes)
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                guard let self, self.generation == current, self.pending != nil else { return }
                self.pending = nil
                self.onError?(SessionError.timeout(command))
            }
        } catch { pending = nil; onError?(error) }
    }

    public func receive(_ bytes: [UInt8]) {
        onLog?("RX", bytes.hex)
        do {
            let packets = try decoder.append(bytes)
            for packet in packets {
                if let request = pending, packet.command == request.command, packet.sequence == request.sequence {
                    pending = nil
                    generation += 1
                    request.completion(packet)
                } else { onEvent?(packet) }
            }
        } catch { pending = nil; onError?(error) }
    }

    public func cancel() { generation += 1; pending = nil }
}
