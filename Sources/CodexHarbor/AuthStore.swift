import Foundation

/// Copies the current Codex login into the active account snapshot without
/// changing registry metadata, so cached usage and aliases are preserved.
enum AuthStore {
    static var codexHome: String {
        ProcessInfo.processInfo.environment["CODEX_HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
    }

    static var authPath: String { codexHome + "/auth.json" }

    static func syncCurrentSnapshot() -> Bool {
        let home = codexHome
        let authPath = home + "/auth.json"
        let registryPath = home + "/accounts/registry.json"
        guard let authData = FileManager.default.contents(atPath: authPath),
              let auth = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
              let tokens = auth["tokens"] as? [String: Any] else { return false }
        var accountId = tokens["account_id"] as? String
        if accountId == nil, let idToken = tokens["id_token"] as? String {
            accountId = self.accountId(fromJWT: idToken)
        }
        guard let registryData = FileManager.default.contents(atPath: registryPath),
              let registry = try? JSONSerialization.jsonObject(with: registryData) as? [String: Any],
              let activeKey = registry["active_account_key"] as? String,
              let accounts = registry["accounts"] as? [[String: Any]],
              let active = accounts.first(where: { $0["account_key"] as? String == activeKey }),
              let registryAccountId = active["chatgpt_account_id"] as? String,
              let accountId, accountId == registryAccountId else { return false }

        let safe = activeKey.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
            && activeKey != "." && activeKey != ".."
        let key = safe ? activeKey : Data(activeKey.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let snapshotPath = home + "/accounts/" + key + ".auth.json"
        guard FileManager.default.fileExists(atPath: snapshotPath) else { return false }
        do {
            try authData.write(to: URL(fileURLWithPath: snapshotPath), options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: snapshotPath)
            return true
        } catch {
            return false
        }
    }

    private static func accountId(fromJWT token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = json["https://api.openai.com/auth"] as? [String: Any] else { return nil }
        return auth["chatgpt_account_id"] as? String
    }
}
