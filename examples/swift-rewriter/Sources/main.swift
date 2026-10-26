import Foundation
import CommonbeamKit

@main
struct Rewriter {
    static func main() async {
        do {
            guard let path = ProcessInfo.processInfo.environment["COMMONBEAM_TOKEN_FILE"] else { throw CommonbeamError("invalidRequest") }
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            guard attrs[.type] as? FileAttributeType == .typeRegular,
                  (attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600,
                  (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw CommonbeamError("permissionDenied") }
            let token = try String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            let beam = try CommonbeamClient(port: Int(ProcessInfo.processInfo.environment["COMMONBEAM_PORT"] ?? "52441") ?? 0, token: token)
            let profile = try await beam.capabilities().require(ProcessInfo.processInfo.environment["COMMONBEAM_PROFILE"] ?? "fixture-text")
            let result = try await beam.text.generate(profile: profile, messages: [.user("Rewrite clearly: we made the thing work but there is more tests needed before release")])
            print(result.text)
        } catch { print((error as? CommonbeamError)?.code ?? "serviceUnavailable") }
    }
}
