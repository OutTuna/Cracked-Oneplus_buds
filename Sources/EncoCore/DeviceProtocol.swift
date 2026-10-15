import Foundation

public struct Capabilities {
    public let bitmap: [UInt8]
    public let commands: Set<UInt16>
    private static let mapping: [[UInt16]] = [
        [261], [262], [263], [264,1025,1046], [265], [1024], [1026], [1027],
        [268,1028], [1029], [1030,271], [1031], [], [1032], [1033], [], [], [276], [],
        [1038,1037,277,278], [1039], [1040,281], [517], [3840], [], [280,1041],
        [282,1042], [284,1043], [], [274,1035], [286,287,1045], [1037], [], [289,1047],
        [290,1048], [], [285,1044], [291,1050], [292,1051], [293,1052,295,1053,1055],
        [1057,35,36,34,294,297], [61185], [61186], [61187,1054], [1056], [28], [],
        [1058,298], [61188], [1059,299], [], [1060], [61190], [], [], [1061,302,1062],
        [303], [1063,304], [305,1064], [1065,306], [20], [1069,307], [1070],
        [61191], [61192], [61193], [1073,308]
    ]

    public init(reply: Packet) throws {
        guard reply.command == 0x8100, reply.payload.count > 1, reply.payload[0] == 0 else {
            throw SessionError.rejected(0x0100, reply.payload)
        }
        bitmap = Array(reply.payload.dropFirst())
        var supported = Set<UInt16>()
        for (index, commands) in Self.mapping.enumerated() where index / 8 < bitmap.count {
            if bitmap[index / 8] & (1 << (index % 8)) != 0 { supported.formUnion(commands) }
        }
        self.commands = supported
    }

    public func supports(_ command: UInt16) -> Bool { commands.contains(command) }
}

public struct BatteryEntry: Equatable {
    public let deviceType: UInt8
    public let rawLevel: UInt8
    public let charging: Bool
    public var label: String {
        switch deviceType { case 1: return "left"; case 2: return "right"; case 3: return "case"; default: return "type-\(deviceType)" }
    }
    public var percent: Int? { rawLevel <= 100 ? Int(rawLevel) : nil }

    public static func parse(_ data: [UInt8]) throws -> [BatteryEntry] {
        guard let count = data.first, count > 0, data.count == 1 + Int(count) * 2 else { throw ProtocolError.invalidLength }
        return (0..<Int(count)).map {
            let offset = 1 + $0 * 2
            return BatteryEntry(deviceType: data[offset], rawLevel: data[offset + 1] & 0x7F, charging: data[offset + 1] & 0x80 != 0)
        }
    }
}

public struct VersionComponent: Equatable {
    public let deviceType: String
    public let versionType: String
    public let value: String

    public static func parse(_ data: [UInt8]) throws -> [VersionComponent] {
        guard let count = data.first, let text = String(bytes: data.dropFirst(), encoding: .utf8) else { throw ProtocolError.invalidLength }
        let fields = text.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard count > 0, fields.count == Int(count) * 3 else { throw ProtocolError.invalidLength }
        return (0..<Int(count)).map { VersionComponent(deviceType: fields[$0 * 3], versionType: fields[$0 * 3 + 1], value: fields[$0 * 3 + 2]) }
    }
}

public struct NoiseState: Equatable {
    public let mask: [UInt8]
    public var activeIndices: [Int] {
        mask.enumerated().flatMap { offset, value in
            (0..<8).compactMap { bit in value & (1 << bit) == 0 ? nil : offset * 8 + bit }
        }
    }
    public var capturedMode: ANCMode? {
        switch activeIndices { case [3]: return .on; case [4]: return .transparency; case [8]: return .off; default: return nil }
    }
    public static func parse(_ data: [UInt8]) throws -> NoiseState {
        guard data.count >= 3, data[0] == 1, data[1] == 1 else { throw ProtocolError.unsupportedHeader }
        return NoiseState(mask: Array(data.dropFirst(2)))
    }
}

public final class DeviceProtocol {
    public let session: Session
    public private(set) var capabilities: Capabilities?
    public private(set) var noiseState: NoiseState?
    public private(set) var battery: [BatteryEntry] = []
    public var onStateChanged: (() -> Void)?
    public var onEvent: ((Packet) -> Void)?
    public var onError: ((Error) -> Void)?

    public init(session: Session) {
        self.session = session
        session.onEvent = { [weak self] in self?.receiveEvent($0) }
    }

    public func initialize(completion: @escaping () -> Void) {
        session.request(0x0100) { [weak self] reply in
            guard let self else { return }
            do { self.capabilities = try Capabilities(reply: reply) }
            catch { self.onError?(error); return }
            self.session.request(0x0200) { [weak self] reply in
                guard let self else { return }
                do {
                    let data = try self.successData(reply)
                    guard let count = data.first, data.count == Int(count) + 1 else { throw ProtocolError.invalidLength }
                    let wanted: Set<UInt8> = [1, 2, 3]
                    let events = data.dropFirst().filter { wanted.contains($0) }
                    guard !events.isEmpty else { completion(); return }
                    if self.capabilities?.supports(0x0205) == true {
                        self.session.request(0x0205, payload: [UInt8(events.count)] + events) { [weak self] reply in
                            guard let self else { return }
                            do {
                                let result = try self.successData(reply)
                                guard let count = result.first, Int(count) == events.count,
                                      result.count == 1 + Int(count) * 2 else { throw ProtocolError.invalidLength }
                                var registered = Set<UInt8>()
                                for index in 0..<Int(count) {
                                    guard result[2 + index * 2] == 0 else { throw SessionError.rejected(0x0205, reply.payload) }
                                    registered.insert(result[1 + index * 2])
                                }
                                guard registered == Set(events) else { throw ProtocolError.invalidLength }
                                completion()
                            } catch { self.onError?(error) }
                        }
                    } else { self.registerOne(Array(events), completion: completion) }
                } catch { self.onError?(error) }
            }
        }
    }

    private func registerOne(_ events: [UInt8], completion: @escaping () -> Void) {
        guard let first = events.first else { completion(); return }
        session.request(0x0201, payload: [first]) { [weak self] reply in
            guard let self else { return }
            do { _ = try self.successData(reply); self.registerOne(Array(events.dropFirst()), completion: completion) }
            catch { self.onError?(error) }
        }
    }

    private func successData(_ reply: Packet) throws -> [UInt8] {
        guard reply.payload.first == 0 else { throw SessionError.rejected(reply.command & 0x7FFF, reply.payload) }
        return Array(reply.payload.dropFirst())
    }

    private func require(_ command: UInt16) -> Bool {
        guard capabilities?.supports(command) == true else {
            onError?(TransportError.unavailable(String(format: "Device does not advertise command %04X", command)))
            return false
        }
        return true
    }

    public func readVersion(completion: @escaping ([VersionComponent]) -> Void) {
        guard require(0x0105) else { return }
        session.request(0x0105) { [weak self] reply in
            guard let self else { return }
            do { completion(try VersionComponent.parse(self.successData(reply))) } catch { self.onError?(error) }
        }
    }

    public func readBattery(completion: @escaping ([BatteryEntry]) -> Void) {
        guard require(0x0106) else { return }
        session.request(0x0106) { [weak self] reply in
            guard let self else { return }
            do {
                self.battery = try BatteryEntry.parse(self.successData(reply))
                self.onStateChanged?(); completion(self.battery)
            } catch { self.onError?(error) }
        }
    }

    public func readNoiseState(completion: @escaping (NoiseState) -> Void) {
        guard require(0x010C) else { return }
        session.request(0x010C, payload: [1, 1]) { [weak self] reply in
            guard let self else { return }
            do {
                let state = try NoiseState.parse(self.successData(reply))
                self.noiseState = state; self.onStateChanged?(); completion(state)
            } catch { self.onError?(error) }
        }
    }

    public func readGestures(completion: @escaping ([GestureBinding]) -> Void) {
        guard require(0x0108) else { return }
        session.request(0x0108) { [weak self] reply in
            guard let self else { return }
            do { completion(try GestureBinding.parse(self.successData(reply))) } catch { self.onError?(error) }
        }
    }

    public func readEQMode(completion: @escaping (UInt8) -> Void) {
        guard require(0x010F) else { return }
        session.request(0x010F) { [weak self] reply in
            guard let self else { return }
            do {
                let data = try self.successData(reply)
                guard data.count == 1 else { throw ProtocolError.invalidLength }
                completion(data[0])
            } catch { self.onError?(error) }
        }
    }

    public func readEQProfiles(completion: @escaping ([EQProfile]) -> Void) {
        guard require(0x0122) else { return }
        session.request(0x0122) { [weak self] reply in
            guard let self else { return }
            do { completion(try EQProfile.parse(self.successData(reply))) } catch { self.onError?(error) }
        }
    }

    public func setANC(_ mode: ANCMode, completion: @escaping (NoiseState) -> Void) {
        guard require(0x0404) else { return }
        readNoiseState { [weak self] current in
            guard let self else { return }
            if current.capturedMode == mode { completion(current); return }
            self.writeANC(mode, completion: completion)
        }
    }

    private func writeANC(_ mode: ANCMode, completion: @escaping (NoiseState) -> Void) {
        session.request(0x0404, payload: [1, 1, mode.wireValue]) { [weak self] reply in
            guard let self else { return }
            do { _ = try self.successData(reply) } catch { self.onError?(error); return }
            self.readNoiseState(completion: completion)
        }
    }

    private func receiveEvent(_ packet: Packet) {
        guard packet.command == 0x0204, let kind = packet.payload.first else { onEvent?(packet); return }
        do {
            switch kind {
            case 1: battery = try BatteryEntry.parse(Array(packet.payload.dropFirst())); onStateChanged?()
            case 3:
                if packet.payload.count >= 4, packet.payload[1] == 1, packet.payload[2] == 1 {
                    noiseState = try NoiseState.parse(Array(packet.payload.dropFirst())); onStateChanged?()
                }
            default: break
            }
            onEvent?(packet)
        } catch { onError?(error) }
    }
}
