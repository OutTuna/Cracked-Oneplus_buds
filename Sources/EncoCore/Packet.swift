import Foundation

public struct Packet: Equatable {
    public let command: UInt16
    public let sequence: UInt8
    public let payload: [UInt8]

    public init(command: UInt16, sequence: UInt8, payload: [UInt8] = []) {
        self.command = command
        self.sequence = sequence
        self.payload = payload
    }

    public func encoded() throws -> [UInt8] {
        guard payload.count <= 65528 else { throw ProtocolError.oversized }
        let length = payload.count + 7
        var remaining = length
        var result: [UInt8] = [0xAA]
        repeat {
            let byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            result.append(byte | (remaining > 0 ? 0x80 : 0))
        } while remaining > 0
        result += [0, 0, UInt8(command & 0xFF), UInt8(command >> 8), sequence,
                   UInt8(payload.count & 0xFF), UInt8(payload.count >> 8)]
        return result + payload
    }
}

public enum ProtocolError: Error, Equatable {
    case oversized
    case invalidLength
    case unsupportedHeader
}

public struct PacketDecoder {
    private var buffer: [UInt8] = []
    public init() {}
    public var bufferedByteCount: Int { buffer.count }

    public mutating func append(_ bytes: [UInt8]) throws -> [Packet] {
        buffer += bytes
        var packets: [Packet] = []
        while !buffer.isEmpty {
            guard buffer[0] == 0xAA else { throw ProtocolError.unsupportedHeader }
            var index = 1
            var length = 0
            var shift = 0
            var lengthComplete = false
            while index < buffer.count {
                let byte = buffer[index]
                index += 1
                length |= Int(byte & 0x7F) << shift
                if byte & 0x80 == 0 { lengthComplete = true; break }
                shift += 7
                if shift >= 21 { throw ProtocolError.invalidLength }
            }
            guard lengthComplete else { return packets }
            guard (7...65535).contains(length) else { throw ProtocolError.invalidLength }
            guard buffer.count >= index + length else { return packets }
            guard buffer[index] == 0, buffer[index + 1] == 0 else { throw ProtocolError.unsupportedHeader }
            let payloadLength = Int(buffer[index + 5]) | Int(buffer[index + 6]) << 8
            guard payloadLength == length - 7 else { throw ProtocolError.invalidLength }
            packets.append(Packet(command: UInt16(buffer[index + 2]) | UInt16(buffer[index + 3]) << 8,
                                  sequence: buffer[index + 4],
                                  payload: Array(buffer[(index + 7)..<(index + length)])))
            buffer.removeFirst(index + length)
        }
        return packets
    }
}

public extension Collection where Element == UInt8 {
    var hex: String { map { String(format: "%02X", $0) }.joined(separator: " ") }
}

public enum ANCMode: String, CaseIterable {
    case on, off, transparency
    public var wireValue: UInt8 {
        switch self { case .on: return 2; case .off: return 1; case .transparency: return 4 }
    }
}
