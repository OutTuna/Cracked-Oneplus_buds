import Foundation

public struct GestureBinding: Equatable {
    public let deviceType: UInt8
    public let button: UInt8
    public let action: UInt8
    public let function: UInt8
    public static func parse(_ data: [UInt8]) throws -> [GestureBinding] {
        guard let count = data.first, data.count == 1 + Int(count) * 4 else { throw ProtocolError.invalidLength }
        return (0..<Int(count)).map {
            let offset = 1 + $0 * 4
            return GestureBinding(deviceType: data[offset], button: data[offset + 1], action: data[offset + 2], function: data[offset + 3])
        }
    }
}

public struct EQBand: Equatable {
    public let frequency: Int
    public let gain: Int
}

public struct EQProfile: Equatable {
    public let id: UInt8
    public let selected: Bool
    public let minimumGain: Int
    public let maximumGain: Int
    public let name: String
    public let bands: [EQBand]

    public static func parse(_ data: [UInt8]) throws -> [EQProfile] {
        var cursor = 0
        func read() throws -> UInt8 {
            guard cursor < data.count else { throw ProtocolError.invalidLength }
            defer { cursor += 1 }
            return data[cursor]
        }
        let count = Int(try read())
        var profiles: [EQProfile] = []
        for _ in 0..<count {
            let selected = try read() != 0
            let minimum = Int(Int8(bitPattern: try read()))
            let maximum = Int(Int8(bitPattern: try read()))
            let id = try read()
            let nameLength = Int(try read())
            guard cursor + nameLength <= data.count,
                  let name = String(bytes: data[cursor..<(cursor + nameLength)], encoding: .utf8) else { throw ProtocolError.invalidLength }
            cursor += nameLength
            let bandCount = Int(try read())
            guard bandCount > 0 else { throw ProtocolError.invalidLength }
            var bands: [EQBand] = []
            for _ in 0..<bandCount {
                let lo = Int(try read())
                let hi = Int(try read())
                bands.append(EQBand(frequency: lo | hi << 8, gain: Int(Int8(bitPattern: try read()))))
            }
            profiles.append(EQProfile(id: id, selected: selected, minimumGain: minimum,
                                      maximumGain: maximum, name: name, bands: bands))
        }
        guard cursor == data.count else { throw ProtocolError.invalidLength }
        return profiles
    }
}
