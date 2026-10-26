import Foundation
import CryptoKit
import Security

public struct Grant: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let profiles: [String: Int]
    public let scopes: [String]
    fileprivate let verifier: Data
}

public struct GrantStore: Sendable {
    private let key: SymmetricKey
    private let file: URL?
    public private(set) var grants: [Grant]

    /// No default file or key: tests never touch Keychain or user state.
    public init(key: Data, file: URL? = nil) throws {
        guard key.count == 32 else { throw BeamError("invalidRequest") }
        self.key = SymmetricKey(data: key); self.file = file
        if let file, FileManager.default.fileExists(atPath: file.path) {
            try Self.checkPrivate(file, directory: false)
            try Self.checkPrivate(file.deletingLastPathComponent(), directory: true)
            let data = try Data(contentsOf: file)
            guard data.count <= 1_048_576 else { throw BeamError("invalidRequest") }
            grants = try JSONDecoder().decode([Grant].self, from: data)
            guard grants.count <= 64 else { throw BeamError("invalidRequest") }
        } else { grants = [] }
    }

    public mutating func create(label: String, profiles: [String: Int], scopes: [String] = ["text.generate"]) throws -> (Grant, String) {
        guard grants.count < 64, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              label.utf8.count <= 128, !profiles.isEmpty, profiles.count <= 16,
              profiles.allSatisfy({ !$0.key.isEmpty && $0.key.utf8.count <= 128 && $0.value > 0 }),
              !scopes.isEmpty, scopes.allSatisfy({ $0 == "text.generate" }) else { throw BeamError("invalidRequest") }
        let token = try Self.randomKey().base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let verifier = Data(HMAC<SHA256>.authenticationCode(for: Data(token.utf8), using: key))
        let grant = Grant(id: UUID().uuidString, label: label, profiles: profiles, scopes: scopes, verifier: verifier)
        let next = grants + [grant]
        try persist(next); grants = next
        return (grant, token)
    }

    public func authenticate(_ token: String) throws -> Grant {
        guard token.utf8.count == 43 else { throw BeamError("unauthenticated") }
        // Validate every record with CryptoKit's constant-time MAC verification.
        var match: Grant?
        for grant in grants {
            if HMAC<SHA256>.isValidAuthenticationCode(grant.verifier, authenticating: Data(token.utf8), using: key) { match = grant }
        }
        guard let match else { throw BeamError("unauthenticated") }
        return match
    }

    public mutating func revoke(_ id: String) throws {
        let next = grants.filter { $0.id != id }
        try persist(next); grants = next
    }

    public static func randomKey() throws -> Data {
        var data = Data(count: 32)
        let result = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard result == errSecSuccess else { throw BeamError("serviceUnavailable") }
        return data
    }

    private static func checkPrivate(_ url: URL, directory: Bool) throws {
        let a = try FileManager.default.attributesOfItem(atPath: url.path)
        guard a[.type] as? FileAttributeType == (directory ? .typeDirectory : .typeRegular),
              let mode = a[.posixPermissions] as? NSNumber,
              mode.intValue & 0o777 == (directory ? 0o700 : 0o600),
              let owner = a[.ownerAccountID] as? NSNumber, owner.uint32Value == getuid()
        else { throw BeamError("permissionDenied") }
    }

    private func persist(_ records: [Grant]) throws {
        guard let file else { return }
        let directory = file.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try Self.checkPrivate(directory, directory: true)
        if FileManager.default.fileExists(atPath: file.path) { try Self.checkPrivate(file, directory: false) }
        let temporary = directory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let data = try JSONEncoder().encode(records)
        guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw BeamError("serviceUnavailable") }
        guard rename(temporary.path, file.path) == 0 else { throw BeamError("serviceUnavailable") }
    }
}

public enum GrantKeychain {
    /// Called only by the native app when the user chooses to enable grant storage.
    public static func loadOrCreate() throws -> Data {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.commonbeam.local-alpha.grant-key", kSecAttrAccount as String: "verifier"]
        var read = query
        read[kSecReturnData as String] = true; read[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &result)
        if status == errSecSuccess, let key = result as? Data, key.count == 32 { return key }
        guard status == errSecItemNotFound else { throw BeamError("permissionDenied") }
        let key = try GrantStore.randomKey()
        var insert = query
        insert[kSecValueData as String] = key
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw BeamError("permissionDenied") }
        return key
    }
}
