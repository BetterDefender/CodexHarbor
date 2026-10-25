import SwiftUI
import AppKit

struct AccountGroup: Identifiable, Codable, Hashable {
    var id: String
    var name: String
}

private struct GroupState: Codable {
    var groups: [AccountGroup]
    var assignments: [String: String]
}

@MainActor final class Store: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var busy = false
    @Published var notice = Copy("Your accounts. On your Mac.", "你的账号，保存在你的 Mac。")
    @Published var error: Copy?
    @Published var language = AppLanguage.saved() {
        didSet { if !demo { UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.preferenceKey) } }
    }
    @Published var theme = AppTheme.saved() {
        didSet { if !demo { UserDefaults.standard.set(theme.rawValue, forKey: AppTheme.preferenceKey) } }
    }
    @Published var groups: [AccountGroup] = []
    @Published var assignments: [String: String] = [:]
    @Published var selectedGroup: String?
    let demo: Bool
    private static let groupsKey = "accountGroups"

    init(demo: Bool = ProcessInfo.processInfo.arguments.contains("--demo")) {
        self.demo = demo
        if demo {
            let work = AccountGroup(id: "preview-work", name: "Work")
            let personal = AccountGroup(id: "preview-personal", name: "Personal")
            groups = [work, personal]
            assignments = ["preview-studio": work.id, "preview-personal": personal.id]
            accounts = PreviewAccounts.make()
            notice = Copy("Preview mode · Fictional accounts. Actions are disabled.", "演示模式 · 虚构账号，账号操作已停用。")
        } else if let data = UserDefaults.standard.data(forKey: Self.groupsKey),
                  let state = try? JSONDecoder().decode(GroupState.self, from: data) {
            groups = state.groups
            assignments = state.assignments
        }
    }
    func t(_ en: String, _ zh: String) -> String { language.text(Copy(en, zh)) }
    func title(_ account: Account) -> String {
        account.alias ?? account.account_name ?? account.email ?? t("API account", "API 账号")
    }
    func refresh(api: Bool = false) {
        guard !demo else { return }
        execute {
            let accounts = try await Backend.run(["list", api ? "--api" : "--skip-api", "--json"])?.accounts ?? []
            self.accounts = accounts
            self.pruneAssignments()
            self.applyRefreshNotice(accounts, api: api)
        }
    }
    func startupRefresh() {
        guard !demo else { return }
        execute {
            await self.syncCurrentAuth()
            var local: [Account] = []
            var localLoaded = false
            do {
                local = try await Backend.run(["list", "--skip-api", "--json"])?.accounts ?? []
                localLoaded = true
            } catch {
                // Continue with the live request even if the local snapshot cannot be read.
            }
            self.accounts = local
            if localLoaded { self.pruneAssignments() }
            self.notice = Copy("Refreshing live usage…", "正在刷新在线额度…")
            do {
                let live = try await Backend.run(["list", "--api", "--json"])?.accounts ?? []
                self.accounts = live
                self.pruneAssignments()
                self.applyRefreshNotice(live, api: true)
            } catch {
                self.notice = Copy("Live refresh failed. Showing local data.", "在线刷新失败，正在显示本地数据。")
                self.error = (error as? AppError)?.message ?? Copy("Unable to complete the operation. Check your local configuration or connection.", "无法完成操作，请检查本地配置或网络连接。")
            }
        }
    }
    private func applyRefreshNotice(_ accounts: [Account], api: Bool) {
        if !api {
            self.notice = Copy("Local accounts loaded. Refresh to fetch live usage.", "已读取本地账号，可刷新获取在线额度。")
            return
        }
        let stale = accounts.contains { account in
            guard let status = account.usage?.refresh?.status else { return false }
            return status != "ok" && status != "not_requested"
        }
        self.notice = stale ? Copy("Refresh incomplete. Some accounts are showing cached data.", "刷新未完全成功，部分账号显示的是缓存数据。") : Copy("Refresh complete. Check each account's data source and status.", "刷新完成，请查看各账号的数据来源和状态。")
    }
    func execute(_ operation: @escaping () async throws -> Void) {
        guard !busy, !demo else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await operation() }
            catch { self.error = (error as? AppError)?.message ?? Copy("Unable to complete the operation. Check your local configuration or connection.", "无法完成操作，请检查本地配置或网络连接。") }
        }
    }
    func mutate(_ args: [String], json: Bool = true, message: Copy) {
        execute {
            _ = try await Backend.run(args, json: json)
            self.accounts = try await Backend.run(["list", "--skip-api", "--json"])?.accounts ?? []
            self.pruneAssignments()
            self.notice = message
        }
    }
    private func syncCurrentAuth() async {
        if AuthStore.syncCurrentSnapshot() { return }
        _ = try? await Backend.run(["import", AuthStore.authPath], json: false)
    }
    func saveCurrent() {
        execute {
            if !AuthStore.syncCurrentSnapshot() {
                _ = try await Backend.run(["import", AuthStore.authPath], json: false)
            }
            self.accounts = try await Backend.run(["list", "--skip-api", "--json"])?.accounts ?? []
            self.pruneAssignments()
            self.notice = Copy("Current sign-in saved.", "当前登录已保存。")
        }
    }
    func groupID(for account: Account) -> String? { assignments[account.id] }
    func groupName(for account: Account) -> String? {
        groups.first { $0.id == assignments[account.id] }?.name
    }
    func groupCount(_ id: String?) -> Int {
        guard let id else { return accounts.count }
        return accounts.reduce(0) { $0 + (assignments[$1.id] == id ? 1 : 0) }
    }
    @discardableResult
    func addGroup(_ name: String) -> Bool {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !groups.contains(where: { $0.name.caseInsensitiveCompare(value) == .orderedSame }) else { return false }
        groups.append(AccountGroup(id: UUID().uuidString, name: value))
        saveGroups()
        return true
    }
    func renameGroup(_ id: String, to name: String) {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              let index = groups.firstIndex(where: { $0.id == id }),
              !groups.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(value) == .orderedSame }) else { return }
        groups[index].name = value
        saveGroups()
    }
    func deleteGroup(_ id: String) {
        groups.removeAll { $0.id == id }
        assignments = assignments.filter { $0.value != id }
        if selectedGroup == id { selectedGroup = nil }
        saveGroups()
    }
    func move(_ account: Account, to groupID: String?) { move(account.id, to: groupID) }
    func move(_ accountID: String, to groupID: String?) {
        if let groupID, groups.contains(where: { $0.id == groupID }) {
            assignments[accountID] = groupID
        } else {
            assignments.removeValue(forKey: accountID)
        }
        saveGroups()
    }
    private func saveGroups() {
        guard !demo, let data = try? JSONEncoder().encode(GroupState(groups: groups, assignments: assignments)) else { return }
        UserDefaults.standard.set(data, forKey: Self.groupsKey)
    }
    private func pruneAssignments() {
        let keys = Set(accounts.map(\.id))
        let pruned = assignments.filter { keys.contains($0.key) }
        guard pruned.count != assignments.count else { return }
        assignments = pruned
        saveGroups()
    }
    func switchAccount(_ account: Account) {
        execute {
            await self.syncCurrentAuth()
            self.notice = Copy("Applying credentials and syncing the Codex background service…", "正在写入目标凭据并同步 Codex 后台…")
            var failure: Error?
            do {
                let reply = try await Backend.run(Backend.switchArguments(account.id))
                try Backend.validateSwitch(reply, key: account.id)
            } catch { failure = error }
            // Nonzero exit can follow a successful credential write. Always reconcile.
            do {
                self.accounts = try await Backend.run(["list", "--skip-api", "--json"])?.accounts ?? []
                self.pruneAssignments()
            } catch {
                self.notice = Copy("The local account state could not be confirmed. Refresh the list.", "切换后的本地状态未能确认，请刷新列表。")
                throw failure ?? error
            }
            if let failure {
                self.notice = Copy("Switching did not fully complete. The list was reloaded; you can sync again.", "切换流程未完全完成，列表已重新读取，可重新同步。")
                throw failure
            }
            guard self.accounts.contains(where: { $0.id == account.id && $0.active }) else {
                self.notice = Copy("The current credentials do not match the selected account.", "当前凭据与目标账号不一致。")
                throw AppError(message: Copy("Local account verification failed. Another client may have updated it. Finish your current task and try again.", "本地账号验证失败，可能被其他客户端更新。请结束当前任务后重试。"))
            }
            self.notice = Copy("Account switched. Restarting Codex…", "账号切换完成，正在重新打开 Codex…")
            do {
                try await ClientRestart.restart()
                self.notice = Copy("Account switched. Codex has reopened.", "账号已切换，Codex 已重新打开。")
            } catch {
                self.notice = Copy("Account switched. The automatic restart did not complete.", "账号已切换，客户端自动重启未完成。")
                throw error
            }
        }
    }
    func importFile() {
        guard !demo, !busy else { return }
        let panel = NSOpenPanel()
        panel.title = t("Import account credentials", "导入账号凭据")
        panel.prompt = t("Import", "导入")
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            mutate(["import", url.path], json: false, message: Copy("Import completed. The account list has been updated.", "导入操作完成，账号列表已更新。"))
        }
    }
}

enum PreviewAccounts {
    static func make() -> [Account] {
        // These are display-only fixtures, with no credentials or valid account IDs.
        let data = Data(#"""
        {"schema_version":1,"accounts":[
          {"account_key":"preview-studio","email":"studio@example.com","alias":"Studio","plan":"plus","active":true,"usage":{"source":"api","updated_at":1792886400,"primary":{"used_percent":24,"window_minutes":300,"resets_at":1792904400},"secondary":{"used_percent":42,"window_minutes":10080,"resets_at":1793491200},"refresh":{"status":"ok"}}},
          {"account_key":"preview-personal","email":"personal@example.com","alias":"Personal","plan":"pro","active":false,"usage":{"source":"cache","updated_at":1792882800,"primary":{"used_percent":8,"window_minutes":300,"resets_at":1792900800},"secondary":{"used_percent":14,"window_minutes":10080,"resets_at":1793487600},"refresh":{"status":"not_requested"}}}
        ]}
        """#.utf8)
        return (try? Backend.decode(data).accounts) ?? []
    }
}
