import CFNetwork
import Foundation

struct Account: Decodable, Identifiable {
    let account_key: String
    let email: String?
    let alias: String?
    let account_name: String?
    let plan: String?
    let active: Bool
    let usage: Usage?
    var id: String { account_key }
    var title: String { alias ?? account_name ?? email ?? "API account" }
}
struct Usage: Decodable {
    let source: String?
    let updated_at: Double?
    let primary: Quota?
    let secondary: Quota?
    let refresh: Refresh?
}
struct Refresh: Decodable { let status: String? }
struct Quota: Decodable {
    let used_percent: Double
    let window_minutes: Int?
    let resets_at: Double?
    var remaining: Double { max(0, min(100, 100 - used_percent)) }
}
struct Reply: Decodable {
    let schema_version: Int
    let accounts: [Account]?
    let switched_to: Account?
    let error: BackendError?
}
struct BackendError: Decodable { let code: String }
struct AppError: LocalizedError {
    let message: Copy
    var errorDescription: String? { message.en }
}
struct Backend {
    static func decode(_ data: Data) throws -> Reply {
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        guard reply.schema_version == 1 else { throw AppError(message: Copy("The backend interface is incompatible. Please update the app.", "核心接口版本不兼容，请更新应用。")) }
        if let error = reply.error {
            let messages = ["account_not_found": Copy("Account not found. Refresh the list and try again.", "未找到账号，请刷新列表。"), "ambiguous_query": Copy("More than one account matches this selection.", "账号匹配不唯一。"), "selector_resolution_failed": Copy("The account list has changed. Refresh and try again.", "账号已变更，请刷新后重试。"), "curl_unavailable": Copy("The curl network tool could not be found.", "找不到网络请求工具 curl。"), "registry_error": Copy("Account data could not be read. Check the directory permissions.", "无法读取账号数据，请检查目录权限。"), "state_uncertain": Copy("The write result is uncertain. Refresh and verify the account before trying again.", "写入状态不确定，请先刷新列表，确认结果后再操作。"), "usage": Copy("The command arguments are invalid.", "命令参数无效。")]
            throw AppError(message: messages[error.code] ?? Copy("The operation failed. Check the account configuration and try again.", "操作失败，请检查账号配置后重试。"))
        }
        return reply
    }
    static func switchArguments(_ key: String) -> [String] {
        ["switch", key, "--json", "--restart-daemon"]
    }
    static func validateSwitch(_ reply: Reply?, key: String) throws {
        guard reply?.switched_to?.id == key else {
            throw AppError(message: Copy("The backend returned a different account. Refresh and check the selection.", "核心返回的切换账号与目标不一致，请刷新后检查。"))
        }
    }
    static func validateExit(_ reply: Reply, status: Int32) throws {
        guard status == 0 else {
            if reply.switched_to != nil {
                throw AppError(message: Copy("Credentials were written, but background sync did not complete. Finish the current task, then select Sync again. You do not need to sign in again yet.", "目标凭据已写入，但后台同步未完成。请等待当前任务结束，再点击“重新同步”；无需立即重新登录。"))
            }
            throw AppError(message: Copy("The operation did not complete. Refresh and try again.", "操作未完成，请刷新后重试。"))
        }
    }
    static func proxyURL(type: String, host: String, port: Int) -> String? {
        if type == kCFProxyTypeHTTP as String || type == kCFProxyTypeHTTPS as String { return "http://\(host):\(port)" }
        if type == kCFProxyTypeSOCKS as String { return "socks5h://\(host):\(port)" }
        return nil
    }
    /// GUI apps launched by Finder do not inherit the shell's proxy variables.
    /// The backend refreshes usage through curl, so pass the system proxy explicitly.
    static func proxyEnvironment() -> [String: String] {
        let existing = ProcessInfo.processInfo.environment
        let keys = ["HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy", "ALL_PROXY", "all_proxy"]
        guard keys.contains(where: { existing[$0] == nil }) else { return [:] }
        guard let raw = CFNetworkCopySystemProxySettings()?.takeRetainedValue(),
              let settings = raw as? [String: Any],
              let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") as CFURL? else { return [:] }
        let proxies = CFNetworkCopyProxiesForURL(url, raw).takeRetainedValue() as? [[String: Any]] ?? []
        for proxy in proxies {
            guard let type = proxy[kCFProxyTypeKey as String] as? String,
                  let host = proxy[kCFProxyHostNameKey as String] as? String,
                  let port = proxy[kCFProxyPortNumberKey as String] as? Int,
                  let value = proxyURL(type: type, host: host, port: port) else { continue }
            var environment: [String: String] = [:]
            for key in keys where existing[key] == nil { environment[key] = value }
            if let exceptions = settings[kCFNetworkProxiesExceptionsList as String] as? [String], !exceptions.isEmpty,
               existing["NO_PROXY"] == nil, existing["no_proxy"] == nil {
                let list = exceptions.joined(separator: ",")
                environment["NO_PROXY"] = list
                environment["no_proxy"] = list
            }
            return environment
        }
        return [:]
    }
    static func childEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        for (key, value) in proxyEnvironment() { env[key] = value }
        return env
    }
    static func run(_ arguments: [String], json: Bool = true) async throws -> Reply? {
        try await Task.detached {
            let executable = Bundle.main.resourceURL!.appendingPathComponent("harbor-core")
            guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw AppError(message: Copy("The account core is missing. Rebuild or reinstall the app.", "应用缺少账号管理核心，请重新构建或安装。")) }
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.environment = childEnvironment()
            process.standardInput = FileHandle.nullDevice
            let output = Pipe()
            process.standardOutput = output
            // Never persist diagnostics: the account core may include sensitive details.
            process.standardError = FileHandle.nullDevice
            try process.run()
            let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + (arguments.contains("--restart-daemon") ? 150 : 90), execute: timer)
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timer.cancel()
            if json {
                guard !data.isEmpty else { throw AppError(message: Copy("The backend returned no result and may have timed out. Refresh in a moment.", "核心未返回结果，可能已超时。请稍后刷新。")) }
                let reply = try decode(data)
                try validateExit(reply, status: process.terminationStatus)
                return reply
            }
            guard process.terminationStatus == 0 else { throw AppError(message: Copy("The operation failed. Check the file format, account availability, and duplicate aliases.", "操作失败，请检查文件格式、账号是否存在或别名是否重复。")) }
            return nil
        }.value
    }
}
