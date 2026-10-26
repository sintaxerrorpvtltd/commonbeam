import Foundation
import XCTest
@testable import CommonbeamKit

final class LiveTests: XCTestCase {
    func testRealHTTPStreamingAndCancellation() async throws {
        guard let directory = ProcessInfo.processInfo.environment["COMMONBEAM_TEST_STATE"],
              let port = Int(ProcessInfo.processInfo.environment["COMMONBEAM_TEST_PORT"] ?? "") else {
            throw XCTSkip("Run scripts/test-e2e.sh to start the synthetic Swift HTTP server.")
        }
        let token = try String(contentsOfFile: directory + "/swift.secret", encoding: .utf8)
        let beam = try CommonbeamClient(port: port, token: token)
        let profile = try await beam.capabilities().require("fixture-text")
        let result = try await beam.generate(profile: profile, messages: [.user("synthetic fixture")])
        XCTAssertTrue(result.text.hasPrefix("[Synthetic test response"))
        XCTAssertEqual(result.backend, "synthetic-fixture"); XCTAssertNil(result.modelDigest)
        try await beam.cancel(requestID: result.id)
        let otherToken = try String(contentsOfFile: directory + "/node.secret", encoding: .utf8)
        let other = try CommonbeamClient(port: port, token: otherToken)
        do { try await other.cancel(requestID: result.id); XCTFail("Cross-grant cancellation was accepted") }
        catch { XCTAssertEqual((error as? CommonbeamError)?.code, "unknownRequest") }
    }
}
