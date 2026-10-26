import XCTest
@testable import CommonbeamKit

final class FixtureTests: XCTestCase {
    var fixtures: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("protocol/fixtures")
    }
    func parse(_ data: Data) throws -> [TextEvent] {
        var decoder = EventDecoder(), events: [TextEvent] = []
        for byte in data { if let event = try decoder.append(byte) { events.append(event) } }
        try decoder.finish(); return events
    }
    func testSharedByteFragmentedUTF8Fixture() throws {
        let events = try parse(Data(contentsOf: fixtures.appendingPathComponent("stream.ndjson")))
        XCTAssertEqual(events.map(\.type), ["start","delta","delta","done"])
        XCTAssertEqual(events[1].text, "Hello 🌍")
    }
    func testSharedCapabilitiesFixture() throws {
        let caps = try JSONDecoder().decode(Capabilities.self, from: Data(contentsOf: fixtures.appendingPathComponent("capabilities.json")))
        XCTAssertEqual(try caps.require("local-text").revision, 1)
        XCTAssertThrowsError(try caps.require("other"))
    }
    func testDuplicateTerminalMismatchedIDAndMissingTerminal() throws {
        let data = try Data(contentsOf: fixtures.appendingPathComponent("stream.ndjson"))
        let string = String(data: data, encoding: .utf8)!
        XCTAssertThrowsError(try parse(Data((string + "{\"type\":\"done\",\"id\":\"fixture-request\"}\n").utf8)))
        XCTAssertThrowsError(try parse(Data(string.replacingOccurrences(of: "\"type\":\"delta\",\"id\":\"fixture-request\"", with: "\"type\":\"delta\",\"id\":\"other\"").utf8)))
        XCTAssertThrowsError(try parse(Data(string.split(separator: "\n").dropLast().joined(separator: "\n").utf8)))
    }
    func testOversizedLineAndInvalidUTF8() throws {
        XCTAssertThrowsError(try parse(Data(repeating: 32, count: 131073)))
        XCTAssertThrowsError(try parse(Data([0xff, 10])))
    }
    func testClientRejectsUnsafePortAndToken() throws {
        XCTAssertThrowsError(try CommonbeamClient(port: 80, token: String(repeating: "a", count: 43)))
        XCTAssertThrowsError(try CommonbeamClient(token: "bad\r\nInjected: yes"))
    }
}
