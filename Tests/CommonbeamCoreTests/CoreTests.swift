import XCTest
@testable import CommonbeamCore

private struct EchoAdapter: TextAdapter {
    func generate(_ request: GenerateRequest, emit: @escaping @Sendable (String) async throws -> Void) async throws -> AdapterResult {
        try await emit(request.messages.last!.content)
        return AdapterResult()
    }
}
private struct SleepingAdapter: TextAdapter {
    func generate(_ request: GenerateRequest, emit: @escaping @Sendable (String) async throws -> Void) async throws -> AdapterResult {
        try await Task.sleep(for: .seconds(60)); return AdapterResult()
    }
}
private actor GateAdapter: TextAdapter {
    var seen: [String] = []
    var waiting: [CheckedContinuation<Void, Never>] = []
    func generate(_ request: GenerateRequest, emit: @escaping @Sendable (String) async throws -> Void) async throws -> AdapterResult {
        seen.append(request.messages[0].content)
        await withCheckedContinuation { waiting.append($0) }
        try await emit(request.messages[0].content)
        return AdapterResult()
    }
    func release() { if !waiting.isEmpty { waiting.removeFirst().resume() } }
    func count() -> Int { seen.count }
}

@MainActor
final class CoreTests: XCTestCase {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    func body(_ text: String = "hello", revision: Int = 1, deadline: Int = 30000) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["profile":"local-text", "profileRevision":revision,
            "messages":[["role":"user", "content":text]], "stream":true, "deadlineMs":deadline])
    }
    func broker(_ adapter: any TextAdapter = EchoAdapter(), grace: Duration = .seconds(2)) throws -> Broker {
        Broker(store: try GrantStore(key: GrantStore.randomKey()), profile: Profile(id: "local-text", revision: 1, state: "ready", backend: "fixture"), adapter: adapter, cancellationGrace: grace)
    }
    func drain(_ stream: AsyncThrowingStream<TextEvent, Error>) async throws -> [TextEvent] {
        var result: [TextEvent] = []; for try await event in stream { result.append(event) }; return result
    }
    func waitFor(_ condition: () async -> Bool) async throws {
        for _ in 0..<100 { if await condition() { return }; try await Task.sleep(for: .milliseconds(5)) }
        XCTFail("Condition did not become true within 500 ms")
    }
    func testSharedRequestFixtureAndDefaults() throws {
        let request = try GenerateRequest.decode(Data(contentsOf: root.appendingPathComponent("protocol/fixtures/request.json")))
        XCTAssertEqual(request.maxOutputTokens, 128); XCTAssertEqual(request.messages[0].role, "user")
        let defaults = try GenerateRequest.decode(body())
        XCTAssertEqual(defaults.maxOutputTokens, 256)
    }
    func testUnknownProvenanceAndUsageEncodeAsExplicitNull() throws {
        let profile = Profile(id: "local-text", revision: 1, state: "ready", backend: "fixture")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as! [String: Any]
        XCTAssertTrue(json["modelDigest"] is NSNull)
        XCTAssertTrue((json["limits"] as! [String: Any])["contextTokens"] is NSNull)
        var event = TextEvent(type: "start", id: "fixture-request")
        event.profile = "local-text"; event.profileRevision = 1; event.execution = "local"; event.backend = "fixture"
        let start = try JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as! [String: Any]
        XCTAssertTrue(start["modelDigest"] is NSNull)
        let usage = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Usage())) as! [String: Any]
        XCTAssertTrue(usage["inputTokens"] is NSNull); XCTAssertTrue(usage["outputTokens"] is NSNull)
    }
    func testValidationRejectsUnknownFieldsRolesBooleansAndFractions() throws {
        let base = try JSONSerialization.jsonObject(with: body()) as! [String: Any]
        let mutations: [[String: Any]] = [
            ["tools": []], ["profileRevision":true], ["maxOutputTokens":1.5], ["deadlineMs":999],
            ["stream":1], ["messages":[["role":"tool", "content":"x"]]],
            ["messages":[["role":"user", "content":"x", "name":"hidden"]]],
            ["messages":[]], ["profileRevision":0], ["maxOutputTokens":513]
        ]
        for mutation in mutations {
            let object = base.merging(mutation) { _, new in new }
            XCTAssertThrowsError(try GenerateRequest.decode(JSONSerialization.data(withJSONObject: object)))
        }
    }
    func testByteAndBodyLimitsAndInvalidUTF8() throws {
        XCTAssertThrowsError(try GenerateRequest.decode(body(String(repeating: "🌍", count: 16385))))
        XCTAssertThrowsError(try GenerateRequest.decode(Data(repeating: 32, count: 98_305)))
        XCTAssertThrowsError(try GenerateRequest.decode(Data([0xff])))
    }
    func testHostOriginCookieAndQueryBoundary() throws {
        let headers = [("Host", "127.0.0.1:52441"), ("Content-Type", "application/json")]
        try HTTPBoundary.validate(method: "POST", target: "/v1/text/generate", headers: headers, port: 52441, hasBody: true)
        for bad in [[("Origin", "null")], [("Cookie", "a=b")], [("Host", "attacker.test")], [("Authorization", "a"), ("authorization", "b")]] {
            XCTAssertThrowsError(try HTTPBoundary.validate(method: "POST", target: "/v1/text/generate", headers: headers + bad, port: 52441, hasBody: true))
        }
        XCTAssertThrowsError(try HTTPBoundary.validate(method: "GET", target: "/healthz?token=x", headers: headers, port: 52441, hasBody: false))
        XCTAssertThrowsError(try HTTPBoundary.validate(method: "OPTIONS", target: "/healthz", headers: headers, port: 52441, hasBody: false))
    }
    func testGrantVerifierPersistenceAndRevocation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = try GrantStore.randomKey(), file = directory.appendingPathComponent("grants.json")
        var store = try GrantStore(key: key, file: file)
        let (grant, token) = try store.create(label: "Notes", profiles: ["local-text":1])
        XCTAssertEqual(token.count, 43)
        XCTAssertFalse(try String(contentsOf: file, encoding: .utf8).contains(token))
        XCTAssertEqual(try GrantStore(key: key, file: file).authenticate(token).id, grant.id)
        XCTAssertThrowsError(try GrantStore(key: GrantStore.randomKey(), file: file).authenticate(token))
        try store.revoke(grant.id)
        XCTAssertThrowsError(try store.authenticate(token))
        XCTAssertThrowsError(try GrantStore(key: key, file: file).authenticate(token))
    }
    func testInsecureGrantFileRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions:0o700])
        let file = directory.appendingPathComponent("grants.json")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: Data("[]".utf8), attributes: [.posixPermissions:0o644]))
        XCTAssertThrowsError(try GrantStore(key: GrantStore.randomKey(), file: file))
    }
    func testGrantCannotSeeDisallowedProfile() async throws {
        var store = try GrantStore(key: GrantStore.randomKey())
        let (_, token) = try store.create(label: "Other", profiles: ["other":1])
        let broker = Broker(store: store, profile: Profile(id: "local-text", revision: 1, state: "ready", backend: "fixture"), adapter: EchoAdapter())
        let profiles = try await broker.capabilities(token: token)
        XCTAssertTrue(profiles.isEmpty)
        do { _ = try await broker.submit(token: token, body: body()); XCTFail() } catch { XCTAssertEqual((error as? BeamError)?.code, "permissionDenied") }
    }
    func testEchoStreamAndTerminalOwnership() async throws {
        let broker = try broker()
        let (_, a) = try await broker.createGrant(label: "A"), (_, b) = try await broker.createGrant(label: "B")
        let events = try await drain(broker.submit(token: a, body: body("sentinel-A")))
        XCTAssertEqual(events.map(\.type), ["start", "delta", "done"])
        XCTAssertEqual(events[1].text, "sentinel-A")
        let status = try await broker.cancel(token: a, id: events[0].id); XCTAssertEqual(status, 204)
        do { _ = try await broker.cancel(token: b, id: events[0].id); XCTFail() } catch { XCTAssertEqual((error as? BeamError)?.code, "unknownRequest") }
        let others = try await drain(broker.submit(token: b, body: body("sentinel-B")))
        XCTAssertEqual(others[1].text, "sentinel-B")
    }
    func testStaleRevisionRejectedBeforeWork() async throws {
        let broker = try broker(); let (_, token) = try await broker.createGrant(label: "A")
        do { _ = try await broker.submit(token: token, body: body(revision: 2)); XCTFail() } catch { XCTAssertEqual((error as? BeamError)?.code, "profileChanged") }
    }
    func testRevokeCancelsActiveAndQueued() async throws {
        let broker = try broker(SleepingAdapter()); let (grant, token) = try await broker.createGrant(label: "A")
        let first = try await broker.submit(token: token, body: body()), second = try await broker.submit(token: token, body: body())
        try await broker.revoke(grant.id)
        let a = try await drain(first), b = try await drain(second)
        XCTAssertEqual(a.last?.type, "cancelled"); XCTAssertEqual(b.last?.type, "cancelled")
        do { _ = try await broker.submit(token: token, body: body()); XCTFail() } catch { XCTAssertEqual((error as? BeamError)?.code, "unauthenticated") }
    }
    func testPauseCancelsAndRejectsWork() async throws {
        let broker = try broker(SleepingAdapter()); let (_, token) = try await broker.createGrant(label: "A")
        let stream = try await broker.submit(token: token, body: body())
        await broker.setPaused(true)
        let events = try await drain(stream); XCTAssertEqual(events.last?.type, "cancelled")
        do { _ = try await broker.submit(token: token, body: body()); XCTFail() } catch { XCTAssertEqual((error as? BeamError)?.code, "serviceUnavailable") }
    }
    func testBurstRateLimit() async throws {
        let broker = try broker(SleepingAdapter()); let (_, token) = try await broker.createGrant(label: "A")
        let a = try await broker.submit(token: token, body: body()), b = try await broker.submit(token: token, body: body())
        do { _ = try await broker.submit(token: token, body: body()); XCTFail() } catch { XCTAssertEqual((error as? BeamError)?.code, "rateLimited") }
        await broker.shutdown(); _ = try await drain(a); _ = try await drain(b)
    }
    func testGlobalQueueBound() async throws {
        let broker = try broker(SleepingAdapter()); var streams: [AsyncThrowingStream<TextEvent, Error>] = []
        for i in 0..<9 {
            let (_, token) = try await broker.createGrant(label: "\(i)")
            streams.append(try await broker.submit(token: token, body: body()))
        }
        let (_, token) = try await broker.createGrant(label: "overflow")
        do { _ = try await broker.submit(token: token, body: body()); XCTFail() } catch { XCTAssertEqual((error as? BeamError)?.code, "queueFull") }
        await broker.shutdown(); for stream in streams { _ = try await drain(stream) }
    }
    func testRoundRobinAcrossThreeGrants() async throws {
        let adapter = GateAdapter(), broker = try broker(adapter)
        let (_, a) = try await broker.createGrant(label: "A"), (_, b) = try await broker.createGrant(label: "B"), (_, c) = try await broker.createGrant(label: "C")
        var streams: [AsyncThrowingStream<TextEvent, Error>] = []
        for (token, label) in [(a,"A1"),(a,"A2"),(b,"B1"),(b,"B2"),(c,"C1"),(c,"C2")] {
            streams.append(try await broker.submit(token: token, body: body(label)))
        }
        for count in 1...6 { try await waitFor { await adapter.count() == count }; await adapter.release() }
        for stream in streams { _ = try await drain(stream) }
        let order = await adapter.seen; XCTAssertEqual(order, ["A1","B1","C1","A2","B2","C2"])
    }
    func testDeadlineIncludesQueueTime() async throws {
        let broker = try broker(SleepingAdapter()); let (_, a) = try await broker.createGrant(label: "A"), (_, b) = try await broker.createGrant(label: "B")
        let first = try await broker.submit(token: a, body: body())
        let queued = try await broker.submit(token: b, body: body(deadline: 1000))
        let events = try await drain(queued)
        XCTAssertEqual(events.last?.error?.code, "deadlineExceeded")
        await broker.shutdown(); _ = try await drain(first)
    }
    func testNoncooperativeAdapterQuarantined() async throws {
        let adapter = GateAdapter(), broker = try broker(adapter, grace: .milliseconds(20))
        let (_, token) = try await broker.createGrant(label: "A")
        let stream = try await broker.submit(token: token, body: body())
        try await waitFor { await adapter.count() == 1 }
        await broker.setPaused(true)
        try await waitFor { await broker.isQuarantined() }
        await broker.setPaused(false)
        do { _ = try await broker.submit(token: token, body: body()); XCTFail() } catch { XCTAssertEqual((error as? BeamError)?.code, "backendUnavailable") }
        await adapter.release(); _ = try await drain(stream)
    }
    func testSlowConsumerFailsWithBoundedBuffer() async throws {
        struct Flood: TextAdapter {
            func generate(_ request: GenerateRequest, emit: @escaping @Sendable (String) async throws -> Void) async throws -> AdapterResult {
                for _ in 0..<100 { try await emit("x") }; return AdapterResult()
            }
        }
        let broker = try broker(Flood()); let (_, token) = try await broker.createGrant(label: "A")
        let stream = try await broker.submit(token: token, body: body())
        try await Task.sleep(for: .milliseconds(50))
        do { _ = try await drain(stream); XCTFail() } catch { XCTAssertEqual((error as? BeamError)?.code, "payloadTooLarge") }
    }
}
