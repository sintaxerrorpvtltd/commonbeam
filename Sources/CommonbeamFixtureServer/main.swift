import Foundation
import CommonbeamCore
import CommonbeamHTTP

@main
struct FixtureServer {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 3, let port = Int(args[1]), (1024...65535).contains(port) else {
            print("Usage: CommonbeamFixtureServer PORT NEW_PRIVATE_DIRECTORY\nSynthetic test server only; no AI model or Ollama required.")
            return
        }
        let directory = URL(fileURLWithPath: args[2], isDirectory: true)
        guard !FileManager.default.fileExists(atPath: directory.path) else { throw BeamError("invalidRequest") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let broker = Broker(store: try GrantStore(key: GrantStore.randomKey()), profile: DevelopmentAdapter.profile, adapter: DevelopmentAdapter())
        for name in ["node", "swift"] {
            let (_, token) = try await broker.createGrant(label: "Fixture \(name)")
            guard FileManager.default.createFile(atPath: directory.appendingPathComponent("\(name).secret").path,
                contents: Data(token.utf8), attributes: [.posixPermissions: 0o600]) else { throw BeamError("serviceUnavailable") }
        }
        let app = try CommonbeamServer.application(broker: broker, port: port, onReady: { print("FIXTURE_READY: synthetic responses, no model") })
        try await app.runService()
        await broker.shutdown()
    }
}
