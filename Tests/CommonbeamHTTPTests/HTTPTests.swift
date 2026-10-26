import Foundation
import Testing
import Hummingbird
import HummingbirdTesting
import CommonbeamCore
@testable import CommonbeamHTTP

// Hummingbird's router harness inserts authority "localhost" independently of
// supplied Host fields. Remove that harness-only value; live wire authority and
// duplicate Host handling are covered by Tests/e2e.test.mjs.
private struct RouterHarness: HTTPResponder {
    typealias Context = BeamContext
    let responder: BeamHTTPResponder
    func respond(to request: Request, context: BeamContext) async throws -> Response {
        var head = request.head
        head.authority = nil
        return try await responder.respond(to: Request(head: head, body: request.body), context: context)
    }
}

struct HTTPTests {
    private func setup() async throws -> (Application<RouterHarness>, String, String, Broker) {
        let broker = Broker(store: try GrantStore(key: GrantStore.randomKey()), profile: DevelopmentAdapter.profile, adapter: DevelopmentAdapter())
        let (_, a) = try await broker.createGrant(label: "A"), (_, b) = try await broker.createGrant(label: "B")
        return (Application(responder: RouterHarness(responder: BeamHTTPResponder(broker: broker, port: 52441))), a, b, broker)
    }
    func request(stream: Bool = false) -> ByteBuffer {
        ByteBuffer(string: "{\"profile\":\"fixture-text\",\"profileRevision\":2,\"messages\":[{\"role\":\"user\",\"content\":\"synthetic\"}],\"maxOutputTokens\":1,\"stream\":\(stream)}")
    }
    @Test func healthHasNoInventoryAndCapabilitiesRequireGrant() async throws {
        let (app, token, _, _) = try await setup()
        try await app.test(.router) { client in
            try await client.execute(uri: "/healthz", method: .get, headers: [.host:"127.0.0.1:52441"]) { response in
                #expect(response.status == .ok)
                let object = try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as! [String: Any]
                #expect(Set(object.keys) == ["service","protocol","ready"])
            }
            try await client.execute(uri: "/v1/capabilities", method: .get, headers: [.host:"127.0.0.1:52441"]) { response in
                #expect(response.status.code == 401)
            }
            try await client.execute(uri: "/v1/capabilities", method: .get, headers: [.host:"127.0.0.1:52441", .authorization:"Bearer \(token)"]) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body).contains("synthetic-fixture"))
            }
        }
    }
    @Test func browserHostQueryAndFormRejected() async throws {
        let (app, token, _, _) = try await setup()
        try await app.test(.router) { client in
            let cases: [(String, HTTPFields)] = [
                ("/healthz", [.host:"evil.test"]),
                ("/healthz", [.host:"127.0.0.1:52441", .origin:"null"]),
                ("/healthz", [.host:"127.0.0.1:52441", .cookie:"x=y"]),
                ("/healthz?token=x", [.host:"127.0.0.1:52441"])
            ]
            for (path, headers) in cases {
                try await client.execute(uri: path, method: .get, headers: headers) { response in #expect(response.status.code >= 400) }
            }
            try await client.execute(uri: "/v1/text/generate", method: .post,
                headers: [.host:"127.0.0.1:52441", .authorization:"Bearer \(token)", .contentType:"application/x-www-form-urlencoded"], body: request()) { response in
                #expect(response.status.code == 400)
            }
        }
    }
    @Test func bothResponseModesAndIsolation() async throws {
        let (app, a, b, _) = try await setup()
        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/text/generate", method: .post,
                headers: [.host:"127.0.0.1:52441", .authorization:"Bearer \(a)", .contentType:"application/json"], body: request()) { response in
                #expect(response.status == .ok)
                let result = try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as! [String: Any]
                #expect(result["text"] as? String == "[Synthetic")
                #expect(result["modelDigest"] is NSNull)
                let id = result["id"] as! String
                try await client.execute(uri: "/v1/requests/\(id)/cancel", method: .post,
                    headers: [.host:"127.0.0.1:52441", .authorization:"Bearer \(b)", .contentType:"application/json"], body: ByteBuffer(string: "{}")) { response in #expect(response.status.code == 404) }
            }
            try await client.execute(uri: "/v1/text/generate", method: .post,
                headers: [.host:"127.0.0.1:52441", .authorization:"Bearer \(b)", .contentType:"application/json"], body: request(stream: true)) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "application/x-ndjson")
                let events = try String(buffer: response.body).split(separator:"\n").map { try JSONDecoder().decode(TextEvent.self, from: Data($0.utf8)) }
                #expect(events.map(\.type) == ["start","delta","done"])
            }
        }
    }
    @Test func oversizedInputRejectedAndRevokedGrantDenied() async throws {
        let (app, token, _, broker) = try await setup()
        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/text/generate", method: .post,
                headers: [.host:"127.0.0.1:52441", .authorization:"Bearer \(token)", .contentType:"application/json"],
                body: ByteBuffer(bytes: [UInt8](repeating: 32, count: 98305))) { response in #expect(response.status.code == 413) }
            let grants = await broker.grants(); try await broker.revoke(grants[0].id)
            try await client.execute(uri: "/v1/capabilities", method: .get, headers: [.host:"127.0.0.1:52441", .authorization:"Bearer \(token)"]) { response in #expect(response.status.code == 401) }
        }
    }
}
