import Foundation

/// Explicit developer test mode. No inference, model, networking or semantic rewriting.
public struct DevelopmentAdapter: TextAdapter {
    public init() {}
    public func generate(_ request: GenerateRequest, emit: @escaping @Sendable (String) async throws -> Void) async throws -> AdapterResult {
        let words = ["[Synthetic", " test", " response", " —", " no", " AI", " model]", " Connection", " and", " streaming", " work."]
        for word in words.prefix(request.maxOutputTokens) {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(40))
            try await emit(word)
        }
        return AdapterResult(finishReason: request.maxOutputTokens < words.count ? "length" : "stop")
    }
    public static var profile: Profile { Profile(id: "fixture-text", revision: 2, state: "ready", backend: "synthetic-fixture") }
}
