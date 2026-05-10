import Foundation

/// Token storage for Glimpse.
///
/// Originally a Keychain wrapper; now a plain file in Application Support with
/// owner-only permissions. macOS Keychain ACLs on self-signed apps don't
/// persist "Always Allow" reliably, which made every rebuild re-prompt.
/// File-based storage matches the security model used by `gh`, `git credential.store`,
/// `~/.aws/credentials`, etc. FileVault encrypts at rest.
enum Keychain {
    private static let url: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Glimpse", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("token")
    }()

    static func read() -> String? {
        guard let data = try? Data(contentsOf: url),
              let token = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else { return nil }
        return token
    }

    static func write(_ token: String) {
        let data = Data(token.utf8)
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    static func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}
