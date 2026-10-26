import Foundation
import Hummingbird
import Logging
import NIOCore
import NIOHTTPTypes
import CommonbeamCore

public struct BeamContext: RequestContext {
    public var coreContext: CoreRequestContextStorage
    public let channel: any Channel
    public init(source: ApplicationRequestContextSource) {
        coreContext = .init(source: source); channel = source.channel
    }
}

public struct BeamHTTPResponder: HTTPResponder {
    public typealias Context = BeamContext
    public let broker: Broker
    public let port: Int
    public init(broker: Broker, port: Int) { self.broker = broker; self.port = port }

    public func respond(to request: Request, context: BeamContext) async throws -> Response {
        let received = ContinuousClock.now
        do {
            var headers = request.headers.map { ($0.name.rawName, $0.value) }
            // HTTPTypes moves HTTP/1 Host to :authority; retain any extra Host fields
            // so conflicting/duplicate values still fail the boundary check.
            if let authority = request.head.authority { headers.append(("Host", authority)) }
            let path = request.head.path ?? ""
            try HTTPBoundary.validate(method: request.method.rawValue, target: path, headers: headers,
                                      port: port, hasBody: request.method == .post)
            guard request.headers[.transferEncoding] == nil else { throw BeamError("invalidRequest") }
            let lengths = headers.filter { $0.0.lowercased() == "content-length" }.map(\.1)
            guard lengths.count <= 1 else { throw BeamError("invalidRequest") }
            if let length = lengths.first {
                guard !length.isEmpty, length.allSatisfy(\.isNumber), let count = Int(length), count >= 0 else { throw BeamError("invalidRequest") }
                guard count <= 98_304 else { throw BeamError("payloadTooLarge") }
                if request.method == .get && count != 0 { throw BeamError("invalidRequest") }
            }
            if request.method == .get && path == "/healthz" {
                return Self.json(Health(service: "commonbeam", protocol: 1, ready: true))
            }
            guard let authorization = request.headers[.authorization], authorization.hasPrefix("Bearer "),
                  authorization.utf8.count == 50 else { throw BeamError("unauthenticated") }
            let token = String(authorization.dropFirst(7))
            // Authenticate even unknown routes; never collect an unauthorized body.
            let profiles = try await broker.capabilities(token: token)
            if request.method == .get && path == "/v1/capabilities" {
                return Self.json(Capabilities(protocol: 1, profiles: profiles))
            }
            if request.method == .post && path == "/v1/text/generate" {
                let body = try await collect(request, context: context)
                let parsed = try GenerateRequest.decode(body)
                let events = try await broker.submit(token: token, body: body, receivedAt: received)
                if parsed.stream {
                    let broker = self.broker
                    return Response(status: .ok, headers: [.contentType: "application/x-ndjson", .cacheControl: "no-store", .connection: "close"], body: .init { writer in
                        let closer = context.channel.eventLoop.scheduleTask(in: .milliseconds(Int64(parsed.deadlineMs + 1000))) { context.channel.close(promise: nil) }
                        defer { closer.cancel() }
                        var id: String?
                        do {
                            for try await event in events {
                                id = event.id
                                var data = try JSONEncoder().encode(event); data.append(10)
                                guard data.count <= 131_072 else { throw BeamError("backendProtocolError") }
                                try await writer.write(ByteBuffer(bytes: data))
                            }
                            try await writer.finish(nil)
                        } catch {
                            if let id { _ = try? await broker.cancel(token: token, id: id) }
                            throw BeamError("backendUnavailable")
                        }
                    })
                }
                var start: TextEvent?; var text = ""; var done: TextEvent?
                for try await event in events {
                    if event.type == "start" { start = event }
                    if event.type == "delta" { text += event.text ?? "" }
                    if event.type == "error" || event.type == "cancelled" { throw event.error ?? BeamError("cancelled") }
                    if event.type == "done" { done = event }
                }
                guard let start, let done, let reason = done.finishReason, let usage = done.usage else { throw BeamError("backendProtocolError") }
                return Self.json(Result(id: start.id, profile: parsed.profile, profileRevision: parsed.profileRevision,
                    execution: "local", backend: start.backend, modelDigest: start.modelDigest, text: text, finishReason: reason, usage: usage))
            }
            if request.method == .post && path.hasPrefix("/v1/requests/") && path.hasSuffix("/cancel") {
                let parts = path.split(separator: "/", omittingEmptySubsequences: false)
                guard parts.count == 5, parts[1] == "v1", parts[2] == "requests", parts[4] == "cancel",
                      !parts[3].isEmpty, parts[3].utf8.count <= 128,
                      parts[3].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { throw BeamError("invalidRequest") }
                let body = try await collect(request, context: context)
                guard body.isEmpty || (try? JSONSerialization.jsonObject(with: body) as? [String: String])?.isEmpty == true else { throw BeamError("invalidRequest") }
                let status = try await broker.cancel(token: token, id: String(parts[3]))
                return Response(status: .init(code: status), headers: [.cacheControl: "no-store", .connection: "close"])
            }
            return Self.json(Failure(error: BeamError("invalidRequest")), status: 404)
        } catch let error as BeamError {
            return Self.json(Failure(error: error), status: error.status)
        } catch {
            return Self.json(Failure(error: BeamError("invalidRequest")), status: 400)
        }
    }
    private func collect(_ request: Request, context: BeamContext) async throws -> Data {
        // An absolute receipt timeout closes trickling bodies, not just idle ones.
        let timeout = context.channel.eventLoop.scheduleTask(in: .seconds(2)) { context.channel.close(promise: nil) }
        defer { timeout.cancel() }
        var data = Data()
        for try await buffer in request.body {
            guard data.count + buffer.readableBytes <= 98_304 else { throw BeamError("payloadTooLarge") }
            data.append(contentsOf: buffer.readableBytesView)
        }
        return data
    }
    private static func json<T: Encodable>(_ value: T, status: Int = 200) -> Response {
        // Every call uses concrete Encodable values; fallback contains no raw errors.
        let data = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        return Response(status: .init(code: status), headers: [.contentType: "application/json", .cacheControl: "no-store", .connection: "close"], body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
    private struct Health: Encodable { let service: String; let `protocol`: Int; let ready: Bool }
    private struct Capabilities: Encodable { let `protocol`: Int; let profiles: [Profile] }
    private struct Failure: Encodable { let error: BeamError }
    private struct Result: Encodable {
        let id: String; let profile: String; let profileRevision: Int; let execution: String
        let backend: String?; let modelDigest: String?; let text: String; let finishReason: String; let usage: Usage
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id); try c.encode(profile, forKey: .profile); try c.encode(profileRevision, forKey: .profileRevision)
            try c.encode(execution, forKey: .execution); try c.encode(backend, forKey: .backend); try c.encode(modelDigest, forKey: .modelDigest)
            try c.encode(text, forKey: .text); try c.encode(finishReason, forKey: .finishReason); try c.encode(usage, forKey: .usage)
        }
        enum CodingKeys: String, CodingKey { case id, profile, profileRevision, execution, backend, modelDigest, text, finishReason, usage }
    }
}

public enum CommonbeamServer {
    public static func application(broker: Broker, port: Int = 52441, onReady: @escaping @Sendable () async -> Void = {}) throws -> Application<BeamHTTPResponder> {
        guard (1024...65535).contains(port) else { throw BeamError("invalidRequest") }
        let logger = Logger(label: "commonbeam", factory: { _ in SwiftLogNoOpLogHandler() })
        return Application(responder: BeamHTTPResponder(broker: broker, port: port),
            server: .http1(configuration: .init(additionalChannelHandlers: [HeaderDeadline()], idleTimeout: .seconds(5), httpDecoderConfiguration: .init(maxHeaderFieldSize: 8192, maxHeaderListSize: 16_384, maxHeaderFieldCount: 32))),
            configuration: .init(address: .hostname("127.0.0.1", port: port), backlog: 32, reuseAddress: false,
                                 availableConnectionsDelegate: MaximumAvailableConnections(32, logger: logger)),
            onServerRunning: { _ in await onReady() }, logger: logger)
    }
    public static func run(broker: Broker, port: Int = 52441, onReady: @escaping @Sendable () async -> Void = {}) async throws {
        let app = try application(broker: broker, port: port, onReady: onReady)
        try await app.run()
    }
}

/// Uses NIO's parsed request parts; this does not parse HTTP itself.
private final class HeaderDeadline: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPRequestPart
    typealias InboundOut = HTTPRequestPart
    private var timer: Scheduled<Void>?
    func handlerAdded(context: ChannelHandlerContext) {
        let channel = context.channel
        timer = context.eventLoop.scheduleTask(in: .seconds(2)) { channel.close(promise: nil) }
    }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if case .head = unwrapInboundIn(data) { timer?.cancel(); timer = nil }
        context.fireChannelRead(data)
    }
    func handlerRemoved(context: ChannelHandlerContext) { timer?.cancel() }
}
