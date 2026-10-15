import Foundation
import EncoCore

var failures = 0
func checkFail(_ message: String, file: StaticString = #file, line: UInt = #line) {
    failures += 1
    print("FAIL \(file):\(line): \(message)")
}
func checkEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    do { let a = try lhs(); let b = try rhs(); if a != b { checkFail("\(message) \(a) != \(b)", file: file, line: line) } }
    catch { checkFail("Unexpected error: \(error)", file: file, line: line) }
}
func checkThrows(_ expression: @autoclosure () throws -> Any, file: StaticString = #file, line: UInt = #line) {
    do { _ = try expression(); checkFail("Expected an error", file: file, line: line) } catch {}
}

final class ProtocolChecks {
    func bytes(_ text: String) -> [UInt8] {
        text.split(separator: " ").map { UInt8($0, radix: 16)! }
    }

    let captures = [
        "AA 07 00 00 00 01 00 00 00",
        "AA 10 00 00 00 81 00 09 00 00 FF 77 52 EA A4 0E 07 0F",
        "AA 0A 00 00 04 04 28 03 00 01 01 01",
        "AA 08 00 00 04 84 28 01 00 00",
        "AA 0A 00 00 04 04 2B 03 00 01 01 04",
        "AA 08 00 00 04 84 2B 01 00 00",
        "AA 0A 00 00 04 04 2E 03 00 01 01 02",
        "AA 08 00 00 04 84 2E 01 00 00",
        "AA 0C 00 00 04 02 4E 05 00 03 01 01 10 00"
    ]

    func testCapturedFramesAtEverySplitPoint() throws {
        for capture in captures {
            let wire = bytes(capture)
            for split in 0...wire.count {
                var decoder = PacketDecoder()
                var frames = try decoder.append(Array(wire[..<split]))
                frames += try decoder.append(Array(wire[split...]))
                checkEqual(frames.count, 1, capture)
                checkEqual(try frames.first?.encoded(), wire, capture)
                checkEqual(decoder.bufferedByteCount, 0)
            }
        }
    }

    func testANCMatchesCapturedCommands() throws {
        for (mode, sequence, capture) in [(ANCMode.on, UInt8(0x28), 2), (.off, 0x2B, 4), (.transparency, 0x2E, 6)] {
            checkEqual(try Packet(command: 0x0404, sequence: sequence, payload: [1, 1, mode.wireValue]).encoded(), bytes(captures[capture]))
        }
    }

    func testCoalescedFramesAndByteByByteStream() throws {
        let stream = captures.flatMap(bytes)
        var decoder = PacketDecoder()
        checkEqual(try decoder.append(stream).count, captures.count)
        var fragmented = PacketDecoder()
        var result: [Packet] = []
        for byte in stream { result += try fragmented.append([byte]) }
        checkEqual(result.count, captures.count)
    }

    func testLargeLengthEncoding() throws {
        let packet = Packet(command: 0x0204, sequence: 0x46, payload: Array(repeating: 0x42, count: 420))
        let encoded = try packet.encoded()
        checkEqual(Array(encoded.prefix(3)), [0xAA, 0xAB, 0x03])
        var decoder = PacketDecoder()
        checkEqual(try decoder.append(Array(encoded.prefix(2))), [])
        checkEqual(try decoder.append(Array(encoded.dropFirst(2))), [packet])
    }

    func testMalformedFramesRejected() throws {
        var decoder = PacketDecoder()
        checkThrows(try decoder.append(bytes("AA 08 00 00 04 84 28 02 00 00")))
        var badPrefix = PacketDecoder()
        checkThrows(try badPrefix.append([0xBB]))
        var overflow = PacketDecoder()
        checkThrows(try overflow.append(bytes("AA FF FF FF FF")))
        checkThrows(try Packet(command: 0, sequence: 0, payload: Array(repeating: 0, count: 65529)).encoded())
    }

    func testSessionMatchesCommandAndSequence() throws {
        let session = Session()
        var written: [[UInt8]] = []
        var replies = 0
        var events = 0
        session.send = { written.append($0) }
        session.onEvent = { _ in events += 1 }
        session.onError = { checkFail("Unexpected error: \($0)") }
        session.request(0x0404, payload: [1, 1, 1]) { _ in replies += 1 }
        session.receive(try Packet(command: 0x8404, sequence: 1, payload: [0]).encoded())
        session.receive(try Packet(command: 0x8204, sequence: 0, payload: [0]).encoded())
        checkEqual(replies, 0)
        checkEqual(events, 2)
        session.receive(try Packet(command: 0x8404, sequence: 0, payload: [0]).encoded())
        checkEqual(replies, 1)
        checkEqual(written.count, 1)
        session.cancel()
    }

    func testCapabilityAndStateModels() throws {
        let capabilities = try Capabilities(reply: Packet(command: 0x8100, sequence: 0,
            payload: bytes("00 FF 77 52 EA A4 0E 07 0F")))
        for command: UInt16 in [0x0105, 0x0106, 0x010C, 0x0404, 0x0205] {
            checkEqual(capabilities.supports(command), true)
        }
        checkEqual(capabilities.supports(0xFFFF), false)
        let battery = try BatteryEntry.parse(bytes("02 01 64 02 E4"))
        checkEqual(battery.map(\.percent), [100, 100])
        checkEqual(battery.map(\.charging), [false, true])
        checkEqual(try BatteryEntry.parse(bytes("01 03 FF")).first?.percent, nil)
        checkThrows(try BatteryEntry.parse(bytes("03 01 64 02 64")))
        checkEqual(try NoiseState.parse(bytes("01 01 08 00")).capturedMode, .on)
        checkEqual(try NoiseState.parse(bytes("01 01 00 01")).capturedMode, .off)
        checkEqual(try NoiseState.parse(bytes("01 01 10 00")).capturedMode, .transparency)
        checkEqual(try NoiseState.parse(bytes("01 01 20 00")).capturedMode, nil)
        let versions = try VersionComponent.parse([4] + Array("1,2,158,2,2,158,3,1,01,3,2,105".utf8))
        checkEqual(versions.map(\.value), ["158", "158", "01", "105"])
        checkThrows(try VersionComponent.parse([4] + Array("1,2,158".utf8)))
    }

    func testInitializationAndANCReadback() throws {
        let session = Session()
        let device = DeviceProtocol(session: session)
        var outgoing: [Packet] = []
        session.send = { wire in
            var decoder = PacketDecoder()
            outgoing += try decoder.append(wire)
        }
        device.onError = { checkFail("Unexpected device error: \($0)") }
        session.onError = { checkFail("Unexpected session error: \($0)") }
        func reply(_ payload: [UInt8]) throws {
            guard let last = outgoing.last else { checkFail("No request"); return }
            session.receive(try Packet(command: last.command | 0x8000, sequence: last.sequence, payload: payload).encoded())
        }
        var ready = false
        device.initialize { ready = true }
        checkEqual(outgoing.last?.command, 0x0100)
        try reply(bytes("00 FF 77 52 EA A4 0E 07 0F"))
        checkEqual(outgoing.last?.command, 0x0200)
        try reply(bytes("00 09 01 02 03 04 08 0B F1 F2 F3"))
        checkEqual(outgoing.last?.command, 0x0205)
        checkEqual(outgoing.last?.payload, [3, 1, 2, 3])
        try reply(bytes("00 03 01 00 02 00 03 00"))
        checkEqual(ready, true)
        var actual: NoiseState?
        device.setANC(.on) { actual = $0 }
        checkEqual(outgoing.last?.command, 0x010C)
        try reply(bytes("00 01 01 00 01"))
        checkEqual(outgoing.last?.command, 0x0404)
        checkEqual(outgoing.last?.payload, [1, 1, 1])
        session.receive(try Packet(command: 0x0204, sequence: 0x4C, payload: bytes("03 01 01 08 00")).encoded())
        checkEqual(device.noiseState?.capturedMode, .on)
        checkEqual(actual, nil)
        try reply([0])
        checkEqual(outgoing.last?.command, 0x010C)
        checkEqual(outgoing.last?.payload, [1, 1])
        checkEqual(actual, nil)
        try reply(bytes("00 01 01 08 00"))
        checkEqual(actual?.capturedMode, .on)
        let writesBefore = outgoing.filter { $0.command == 0x0404 }.count
        device.setANC(.on) { actual = $0 }
        try reply(bytes("00 01 01 08 00"))
        checkEqual(outgoing.filter { $0.command == 0x0404 }.count, writesBefore)
        session.cancel()
    }

    func testRejectedRequestsDoNotReportSuccess() throws {
        let session = Session()
        let device = DeviceProtocol(session: session)
        var errors = 0
        var completed = false
        session.send = { _ in }
        device.onError = { _ in errors += 1 }
        device.initialize { completed = true }
        session.receive(try Packet(command: 0x8100, sequence: 0, payload: [1]).encoded())
        checkEqual(completed, false)
        checkEqual(errors, 1)
        device.readBattery { _ in completed = true }
        checkEqual(completed, false)
        checkEqual(errors, 2)
        session.cancel()
    }

    func testEQAndGestureData() throws {
        let bindings = try GestureBinding.parse(bytes("02 01 01 02 05 02 01 03 06"))
        checkEqual(bindings.count, 2)
        checkEqual(bindings[0].deviceType, 1)
        checkEqual(bindings[1].function, 6)
        checkThrows(try GestureBinding.parse(bytes("02 01 01 02 05")))
        let profiles = try EQProfile.parse(bytes("01 01 FA 06 07 04 54 65 73 74 02 64 00 FE E8 03 04"))
        checkEqual(profiles.count, 1)
        checkEqual(profiles[0].name, "Test")
        checkEqual(profiles[0].minimumGain, -6)
        checkEqual(profiles[0].bands.map(\.frequency), [100, 1000])
        checkEqual(profiles[0].bands.map(\.gain), [-2, 4])
        checkEqual(try EQProfile.parse([0]), [])
        checkThrows(try EQProfile.parse(bytes("01 01 FA 06 07 04 54 65")))
        checkThrows(try EQProfile.parse(bytes("00 FF")))
    }
}

let checks = ProtocolChecks()
let cases: [(String, () throws -> Void)] = [
    ("captured frames at every split", checks.testCapturedFramesAtEverySplitPoint),
    ("ANC capture compatibility", checks.testANCMatchesCapturedCommands),
    ("stream fragmentation and coalescing", checks.testCoalescedFramesAndByteByByteStream),
    ("large length", checks.testLargeLengthEncoding),
    ("malformed frames", checks.testMalformedFramesRejected),
    ("request correlation", checks.testSessionMatchesCommandAndSequence),
    ("capabilities and state models", checks.testCapabilityAndStateModels),
    ("initialization and ANC readback", checks.testInitializationAndANCReadback),
    ("rejections and unsupported commands", checks.testRejectedRequestsDoNotReportSuccess),
    ("EQ and gesture data", checks.testEQAndGestureData)
]
for (name, run) in cases {
    let before = failures
    do { try run() } catch { checkFail("\(name): \(error)") }
    print("\(failures == before ? "PASS" : "FAIL") \(name)")
}
exit(failures == 0 ? 0 : 1)
