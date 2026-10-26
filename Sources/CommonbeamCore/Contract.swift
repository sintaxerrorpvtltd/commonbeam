import Foundation
import CoreFoundation

public struct BeamError: Error, Codable, Sendable, Equatable, LocalizedError {
    public let code: String
    public let message: String
    public let retryable: Bool
    public var requestID: String?
    public var errorDescription: String? { message }
    public var status: Int {
        switch code {
        case "unauthenticated": 401
        case "permissionDenied": 403
        case "unknownProfile", "unknownRequest": 404
        case "profileChanged": 409
        case "payloadTooLarge": 413
        case "queueFull", "rateLimited": 429
        case "deadlineExceeded": 504
        case "backendProtocolError": 502
        case "serviceUnavailable", "modelNotReady", "backendUnavailable", "localExecutionUnverified": 503
        default: 400
        }
    }
    public init(_ code: String, requestID: String? = nil) {
        self.code = code; self.requestID = requestID
        self.retryable = ["queueFull", "rateLimited", "serviceUnavailable", "backendUnavailable"].contains(code)
        self.message = Self.messages[code] ?? "The request could not be completed."
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(code, forKey: .code); try c.encode(message, forKey: .message)
        try c.encode(retryable, forKey: .retryable); try c.encode(requestID, forKey: .requestID)
    }
    private static let messages = [
        "invalidRequest": "Check the request fields and limits.",
        "unsupportedCapability": "This profile does not support that operation.",
        "contextExceeded": "Shorten the input for the selected model.",
        "unauthenticated": "Open Commonbeam to create a valid integration grant.",
        "permissionDenied": "This grant does not allow the requested operation.",
        "unknownProfile": "Select a profile available to this integration.",
        "unknownRequest": "The request is not available to this integration.",
        "profileChanged": "Discover capabilities again; the profile changed.",
        "payloadTooLarge": "The request or output exceeded its size limit.",
        "queueFull": "The local queue is full. Try again later.",
        "rateLimited": "The integration reached its request limit. Try again later.",
        "serviceUnavailable": "Open Commonbeam and check that serving is enabled.",
        "modelNotReady": "Open Commonbeam to select an installed local model.",
        "backendUnavailable": "Check the selected local backend in Commonbeam.",
        "localExecutionUnverified": "Local execution has not been verified for this profile.",
        "deadlineExceeded": "The request exceeded its deadline.",
        "backendProtocolError": "The backend returned an invalid response.",
        "cancelled": "The request was cancelled.",
        "protocolMismatch": "The Commonbeam service and client protocols are incompatible."
    ]
}

public struct Message: Codable, Sendable, Equatable {
    public let role: String
    public let content: String
    public init(role: String, content: String) { self.role = role; self.content = content }
}

public struct GenerateRequest: Codable, Sendable {
    public let profile: String
    public let profileRevision: Int
    public let messages: [Message]
    public let maxOutputTokens: Int
    public let deadlineMs: Int
    public let stream: Bool

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 98_304 else { throw BeamError("payloadTooLarge") }
        guard String(data: data, encoding: .utf8) != nil,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: ["profile", "profileRevision", "messages", "maxOutputTokens", "deadlineMs", "stream"]),
              let profile = object["profile"] as? String, !profile.isEmpty, profile.utf8.count <= 128,
              let revision = integer(object["profileRevision"]), revision > 0,
              let messages = object["messages"] as? [[String: Any]], (1...32).contains(messages.count)
        else { throw BeamError("invalidRequest") }
        var decoded: [Message] = []
        var bytes = 0
        for item in messages {
            guard Set(item.keys) == ["role", "content"],
                  let role = item["role"] as? String, ["system", "user", "assistant"].contains(role),
                  let content = item["content"] as? String else { throw BeamError("invalidRequest") }
            bytes += content.utf8.count
            decoded.append(Message(role: role, content: content))
        }
        guard bytes <= 65_536 else { throw BeamError("payloadTooLarge") }
        let tokens = try boundedInteger(object, "maxOutputTokens", default: 256, range: 1...512)
        let deadline = try boundedInteger(object, "deadlineMs", default: 30_000, range: 1_000...120_000)
        var stream = false
        if let value = object["stream"] {
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw BeamError("invalidRequest") }
            stream = number.boolValue
        }
        return Self(profile: profile, profileRevision: revision, messages: decoded,
                    maxOutputTokens: tokens, deadlineMs: deadline, stream: stream)
    }
    private static func integer(_ value: Any?) -> Int? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite, n.doubleValue >= 0, n.doubleValue <= 9_007_199_254_740_991,
              n.doubleValue.rounded() == n.doubleValue else { return nil }
        return n.intValue
    }
    private static func boundedInteger(_ object: [String: Any], _ key: String, default value: Int, range: ClosedRange<Int>) throws -> Int {
        guard let raw = object[key] else { return value }
        guard let result = integer(raw), range.contains(result) else { throw BeamError("invalidRequest") }
        return result
    }
}

public struct Profile: Codable, Sendable, Equatable {
    public struct Features: Codable, Sendable, Equatable {
        public var stream = true; public var jsonSchema = false; public var tools = false
    }
    public struct Limits: Codable, Sendable, Equatable {
        public var maxInputBytes = 65_536; public var maxOutputTokens = 512; public var contextTokens: Int? = nil
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(maxInputBytes, forKey: .maxInputBytes)
            try c.encode(maxOutputTokens, forKey: .maxOutputTokens)
            try c.encode(contextTokens, forKey: .contextTokens)
        }
    }
    public let id: String
    public let revision: Int
    public var state: String
    public let backend: String
    public let execution: String
    public let modelDigest: String?
    public var operations = ["text.generate"]
    public var features = Features()
    public var limits = Limits()
    public init(id: String, revision: Int, state: String, backend: String, modelDigest: String? = nil) {
        self.id = id; self.revision = revision; self.state = state; self.backend = backend
        self.execution = "local"; self.modelDigest = modelDigest
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(revision, forKey: .revision); try c.encode(state, forKey: .state)
        try c.encode(backend, forKey: .backend); try c.encode(execution, forKey: .execution)
        try c.encode(modelDigest, forKey: .modelDigest); try c.encode(operations, forKey: .operations)
        try c.encode(features, forKey: .features); try c.encode(limits, forKey: .limits)
    }
}

public struct Usage: Codable, Sendable, Equatable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public init(inputTokens: Int? = nil, outputTokens: Int? = nil) { self.inputTokens = inputTokens; self.outputTokens = outputTokens }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(inputTokens, forKey: .inputTokens); try c.encode(outputTokens, forKey: .outputTokens)
    }
}

public struct TextEvent: Codable, Sendable {
    public let type: String
    public let id: String
    public var profile: String?
    public var profileRevision: Int?
    public var execution: String?
    public var backend: String?
    public var modelDigest: String?
    public var text: String?
    public var finishReason: String?
    public var usage: Usage?
    public var error: BeamError?
    public init(type: String, id: String) { self.type = type; self.id = id }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type); try c.encode(id, forKey: .id)
        try c.encodeIfPresent(profile, forKey: .profile); try c.encodeIfPresent(profileRevision, forKey: .profileRevision)
        try c.encodeIfPresent(execution, forKey: .execution); try c.encodeIfPresent(backend, forKey: .backend)
        if type == "start" { try c.encode(modelDigest, forKey: .modelDigest) }
        try c.encodeIfPresent(text, forKey: .text); try c.encodeIfPresent(finishReason, forKey: .finishReason)
        try c.encodeIfPresent(usage, forKey: .usage); try c.encodeIfPresent(error, forKey: .error)
    }
}

/// Invoke before any routing or body collection in the future HTTP transport.
public enum HTTPBoundary {
    public static func validate(method: String, target: String, headers: [(String, String)], port: Int, hasBody: Bool) throws {
        guard (1024...65535).contains(port), ["GET", "POST"].contains(method),
              target.hasPrefix("/"), !target.contains("?"), !target.contains("#") else { throw BeamError("invalidRequest") }
        let values = Dictionary(grouping: headers, by: { $0.0.lowercased() })
        guard values["origin"] == nil, values["cookie"] == nil,
              values["host"]?.map(\.1) == ["127.0.0.1:\(port)"],
              (values["authorization"]?.count ?? 0) <= 1 else { throw BeamError("permissionDenied") }
        if hasBody {
            guard values["content-type"]?.map({ $0.1.lowercased() }) == ["application/json"] else { throw BeamError("invalidRequest") }
        }
    }
}
