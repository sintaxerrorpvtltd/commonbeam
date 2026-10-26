import Foundation

public struct CommonbeamError: Error, Sendable, LocalizedError {
    public let code: String
    public var errorDescription: String? { "Commonbeam: \(code)" }
    public init(_ code: String) { self.code = code }
}
public struct Message: Codable, Sendable {
    public let role: String; public let content: String
    public init(role: String, content: String) { self.role = role; self.content = content }
    public static func user(_ content: String) -> Self { Self(role: "user", content: content) }
}
public struct Profile: Codable, Sendable {
    public let id: String; public let revision: Int; public let state: String
    public let execution: String; public let backend: String; public let modelDigest: String?
    public let operations: [String]
}
public enum Operation: String, Sendable { case textGenerate = "text.generate" }
public struct Capabilities: Decodable, Sendable {
    public let `protocol`: Int
    public let profiles: [Profile]
    public func require(_ id: String, operation: Operation = .textGenerate) throws -> Profile {
        guard let p = profiles.first(where: { $0.id == id }) else { throw CommonbeamError("unknownProfile") }
        guard p.state == "ready" else { throw CommonbeamError("modelNotReady") }
        guard p.execution == "local" else { throw CommonbeamError("localExecutionUnverified") }
        guard p.operations.contains(operation.rawValue) else { throw CommonbeamError("unsupportedCapability") }
        return p
    }
}
public struct Usage: Codable, Sendable {
    public let inputTokens: Int?; public let outputTokens: Int?
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.contains(.inputTokens), c.contains(.outputTokens) else { throw CommonbeamError("backendProtocolError") }
        inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens)
        outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens)
    }
}
public struct TextEvent: Decodable, Sendable {
    public struct Failure: Decodable, Sendable { public let code: String }
    public let type: String; public let id: String
    public let profile: String?; public let profileRevision: Int?; public let execution: String?
    public let backend: String?; public let modelDigest: String?
    public let text: String?; public let finishReason: String?; public let usage: Usage?; public let error: Failure?
}
public struct TextResult: Sendable {
    public let id: String; public let profile: String; public let profileRevision: Int
    public let backend: String?; public let modelDigest: String?; public let execution: String
    public let text: String; public let finishReason: String; public let usage: Usage
}

/// Bounded byte framing; used directly by the URLSession stream and shared-fixture tests.
public struct EventDecoder: Sendable {
    private var pending = Data()
    private var id: String?
    private var terminal = false
    private var total = 0
    public init() {}
    public mutating func append(_ byte: UInt8) throws -> TextEvent? {
        guard byte == 10 else {
            guard pending.count < 131_072 else { throw CommonbeamError("backendProtocolError") }
            pending.append(byte); return nil
        }
        guard !terminal, String(data: pending, encoding: .utf8) != nil,
              let event = try? JSONDecoder().decode(TextEvent.self, from: pending),
              !event.id.isEmpty, event.id.utf8.count <= 128 else { throw CommonbeamError("backendProtocolError") }
        pending.removeAll(keepingCapacity: true)
        if id == nil {
            guard event.type == "start", event.profile != nil, (event.profileRevision ?? 0) > 0, event.execution == "local" else { throw CommonbeamError("backendProtocolError") }
            id = event.id
        } else {
            guard event.id == id else { throw CommonbeamError("backendProtocolError") }
            switch event.type {
            case "delta":
                guard let text = event.text else { throw CommonbeamError("backendProtocolError") }
                total += text.utf8.count
                guard total <= 262_144 else { throw CommonbeamError("backendProtocolError") }
            case "done":
                guard ["stop", "length"].contains(event.finishReason ?? ""), let usage = event.usage,
                      (usage.inputTokens ?? 0) >= 0, (usage.outputTokens ?? 0) >= 0 else { throw CommonbeamError("backendProtocolError") }
                terminal = true
            case "error":
                guard event.error != nil else { throw CommonbeamError("backendProtocolError") }
                terminal = true
            case "cancelled": terminal = true
            default: throw CommonbeamError("backendProtocolError")
            }
        }
        return event
    }
    public func finish() throws {
        guard pending.isEmpty, terminal else { throw CommonbeamError("backendProtocolError") }
    }
}

private final class NoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

public struct CommonbeamClient: Sendable {
    private let port: Int; private let token: String; private let session: URLSession
    public var text: Self { self }
    public init(port: Int = 52441, token: String) throws {
        guard (1024...65535).contains(port), token.utf8.count == 43,
              token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { throw CommonbeamError("invalidRequest") }
        self.port = port; self.token = token
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]; config.httpCookieStorage = nil; config.urlCache = nil
        config.httpShouldSetCookies = false; config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 2; config.timeoutIntervalForResource = 121
        session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }
    private func request(_ path: String, body: Data? = nil, timeout: Double = 2) -> URLRequest {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!, timeoutInterval: timeout)
        req.httpMethod = body == nil ? "GET" : "POST"; req.httpBody = body
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return req
    }
    private func response(_ req: URLRequest) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        do {
            let (bytes, response) = try await session.bytes(for: req)
            guard let http = response as? HTTPURLResponse, !(300...399).contains(http.statusCode) else { throw CommonbeamError("backendProtocolError") }
            return (bytes, http)
        } catch let error as CommonbeamError { throw error }
        catch { throw CommonbeamError(Task.isCancelled ? "cancelled" : "serviceUnavailable") }
    }
    private func collect(_ bytes: URLSession.AsyncBytes, limit: Int = 262_144) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { bytes.task.cancel(); throw CommonbeamError("backendProtocolError") }
            data.append(byte)
        }
        return data
    }
    private func check(_ status: Int, data: Data) throws {
        guard status == 200 else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let code = (object?["error"] as? [String: Any])?["code"] as? String
            throw CommonbeamError(Self.safe(code))
        }
    }
    public func capabilities() async throws -> Capabilities {
        let (bytes, response) = try await response(request("/v1/capabilities"))
        defer { bytes.task.cancel() }
        let data = try await collect(bytes)
        try check(response.statusCode, data: data)
        guard response.mimeType == "application/json", let caps = try? JSONDecoder().decode(Capabilities.self, from: data) else { throw CommonbeamError("backendProtocolError") }
        guard caps.protocol == 1 else { throw CommonbeamError("protocolMismatch") }
        guard caps.profiles.count <= 64, caps.profiles.allSatisfy({ !$0.id.isEmpty && $0.revision > 0 }) else { throw CommonbeamError("backendProtocolError") }
        return caps
    }
    public func stream(profile: Profile, messages: [Message], maxOutputTokens: Int = 256, deadline: Duration = .seconds(30)) -> AsyncThrowingStream<TextEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingOldest(32)) { continuation in
            let task = Task {
                var requestID: String?
                var complete = false
                do {
                    let components = deadline.components
                    let msDouble = Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
                    guard msDouble.isFinite, (1000...120000).contains(msDouble), msDouble.rounded() == msDouble,
                          (1...512).contains(maxOutputTokens), (1...32).contains(messages.count),
                          messages.allSatisfy({ ["system", "user", "assistant"].contains($0.role) }) else { throw CommonbeamError("invalidRequest") }
                    guard messages.reduce(0, { $0 + $1.content.utf8.count }) <= 65_536 else { throw CommonbeamError("payloadTooLarge") }
                    let current = try await capabilities().require(profile.id)
                    guard current.revision == profile.revision else { throw CommonbeamError("profileChanged") }
                    struct Body: Encodable { let profile: String; let profileRevision: Int; let messages: [Message]; let maxOutputTokens: Int; let deadlineMs: Int; let stream = true }
                    let body = try JSONEncoder().encode(Body(profile: profile.id, profileRevision: profile.revision, messages: messages, maxOutputTokens: maxOutputTokens, deadlineMs: Int(msDouble)))
                    guard body.count <= 98_304 else { throw CommonbeamError("payloadTooLarge") }
                    let (bytes, response) = try await response(request("/v1/text/generate", body: body, timeout: msDouble / 1000 + 1))
                    defer { bytes.task.cancel() }
                    if response.statusCode != 200 { try check(response.statusCode, data: await collect(bytes, limit: 8192)) }
                    guard response.mimeType == "application/x-ndjson" else { throw CommonbeamError("backendProtocolError") }
                    var decoder = EventDecoder()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        if let event = try decoder.append(byte) {
                            if event.type == "start" { requestID = event.id }
                            if ["done", "error", "cancelled"].contains(event.type) { complete = true }
                            if event.type == "error" { throw CommonbeamError(Self.safe(event.error?.code)) }
                            if event.type == "cancelled" { throw CommonbeamError("cancelled") }
                            switch continuation.yield(event) {
                            case .enqueued: break
                            case .dropped: throw CommonbeamError("payloadTooLarge")
                            case .terminated: throw CancellationError()
                            @unknown default: throw CommonbeamError("backendProtocolError")
                            }
                        }
                    }
                    try decoder.finish(); continuation.finish()
                } catch {
                    continuation.finish(throwing: error as? CommonbeamError ?? CommonbeamError(Task.isCancelled ? "cancelled" : "serviceUnavailable"))
                }
                if let requestID, !complete {
                    // Cancellation of the consumer must not cancel the explicit cleanup request.
                    let cleanup = Task.detached { try? await self.cancel(requestID: requestID) }
                    await cleanup.value
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
    public func generate(profile: Profile, messages: [Message], maxOutputTokens: Int = 256, deadline: Duration = .seconds(30)) async throws -> TextResult {
        var first: TextEvent?; var last: TextEvent?; var text = ""
        for try await event in stream(profile: profile, messages: messages, maxOutputTokens: maxOutputTokens, deadline: deadline) {
            if event.type == "start" { first = event }
            if event.type == "delta" { text += event.text ?? "" }
            if event.type == "done" { last = event }
        }
        guard let first, let last, let usage = last.usage else { throw CommonbeamError("backendProtocolError") }
        return TextResult(id: first.id, profile: first.profile!, profileRevision: first.profileRevision!, backend: first.backend,
                          modelDigest: first.modelDigest, execution: first.execution!, text: text, finishReason: last.finishReason!, usage: usage)
    }
    public func cancel(requestID: String) async throws {
        guard !requestID.isEmpty, requestID.utf8.count <= 128,
              requestID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { throw CommonbeamError("invalidRequest") }
        let (bytes, response) = try await response(request("/v1/requests/\(requestID)/cancel", body: Data("{}".utf8)))
        bytes.task.cancel()
        guard [202, 204].contains(response.statusCode) else { throw CommonbeamError(response.statusCode == 404 ? "unknownRequest" : "serviceUnavailable") }
    }
    private static func safe(_ code: String?) -> String {
        let codes = ["invalidRequest","unsupportedCapability","contextExceeded","unauthenticated","permissionDenied","unknownProfile","profileChanged","payloadTooLarge","queueFull","rateLimited","serviceUnavailable","modelNotReady","backendUnavailable","localExecutionUnverified","deadlineExceeded","backendProtocolError","cancelled"]
        return code.flatMap { codes.contains($0) ? $0 : nil } ?? "backendProtocolError"
    }
}
