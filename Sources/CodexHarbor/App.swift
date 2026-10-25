import AppKit
import SwiftUI

enum AppInfo {
    static let name = "Codex Harbor"
    static let version = "1.0.0"
    static let author = "Gh0stX"
}

@main struct CodexHarborApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup(AppInfo.name) {
            ContentView()
                .environmentObject(store)
                .environment(\.locale, store.language.locale)
                .frame(minWidth: 1040, minHeight: 780)
                .preferredColorScheme(store.theme.colorScheme)
        }
        .defaultSize(width: 1220, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu(store.t("Language", "语言")) {
                Button("English") { store.language = .english }
                Button("简体中文") { store.language = .chinese }
            }
            CommandMenu(store.t("Theme", "外观")) {
                Button(store.t("System", "跟随系统")) { store.theme = .system }
                Button(store.t("Light", "浅色")) { store.theme = .light }
                Button(store.t("Dark", "深色")) { store.theme = .dark }
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var search = ""
    @State private var switching: Account?
    @State private var removing: Account?
    @State private var editing: Account?
    @State private var alias = ""
    @State private var showHelp = false
    @State private var showGroups = false
    @State private var newGroupName = ""
    @State private var groupError: String?
    private var locked: Bool { store.busy || store.demo }
    private var filtered: [Account] {
        store.accounts.filter { account in
            let matchesSearch = search.isEmpty || "\(store.title(account)) \(account.email ?? "")".localizedCaseInsensitiveContains(search)
            let matchesGroup = store.selectedGroup == nil || store.groupID(for: account) == store.selectedGroup
            return matchesSearch && matchesGroup
        }
    }
    private func t(_ en: String, _ zh: String) -> String { store.t(en, zh) }
    private var harborSymbol: String {
        NSImage(systemSymbolName: "sailboat", accessibilityDescription: nil) == nil ? "ferry" : "sailboat"
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Palette.line).frame(width: 1)
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    summary
                    controls
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)
                .padding(.bottom, 18)
                Rectangle().fill(Palette.line).frame(height: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if filtered.isEmpty {
                            emptyState
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                                ForEach(filtered) { account in card(account) }
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 18)
                }
                footer
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(Palette.ink)
        .background(Palette.background)
        .font(.app(17))
        .tint(Palette.acid)
        .task { store.startupRefresh() }
        .alert(t("Operation incomplete", "操作未完成"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button(t("Got it", "知道了"), role: .cancel) {}
        } message: { Text(store.error.map { store.language.text($0) } ?? "") }
        .sheet(item: $switching) { account in
            dialog(icon: "arrow.triangle.2.circlepath", title: t("Switch. Restart. Ready.", "切换后，自动重启。"), detail: t("Apply the saved credentials for \(store.title(account)), sync the background service, then restart Codex. Finish active tasks first; restarting will interrupt them.", "将应用 \(store.title(account)) 的凭据并同步后台，随后自动重启 Codex。重启会中断当前任务，请先完成工作。")) {
                Button(t("Cancel", "取消")) { switching = nil }.buttonStyle(ActionStyle())
                Button(t("Switch & restart", "切换并重启")) { switching = nil; store.switchAccount(account) }.buttonStyle(ActionStyle(prominent: true))
            }
        }
        .sheet(item: $removing) { account in
            dialog(icon: "minus.circle", title: t("Remove this account?", "移除这个账号？"), detail: t("Remove \(store.title(account)) from local storage. Removing the active account may also change your current sign-in.", "将从本机移除 \(store.title(account))。移除当前账号还可能更改当前登录状态。")) {
                Button(t("Cancel", "取消")) { removing = nil }.buttonStyle(ActionStyle())
                Button(t("Remove account", "移除账号"), role: .destructive) {
                    removing = nil
                    store.mutate(["remove", account.id, "--json"], message: Copy("Account removed. Check your current sign-in.", "账号已移除，请确认当前登录状态。"))
                }.buttonStyle(ActionStyle())
            }
        }
        .sheet(item: $editing) { account in aliasEditor(account) }
        .sheet(isPresented: $showGroups) { groupManager }
        .sheet(isPresented: $showHelp) { help }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: harborSymbol).font(.app(24, weight: .medium))
                    .foregroundStyle(Palette.background).frame(width: 44, height: 44)
                    .background(Palette.acid, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("CODEX").font(.app(18, weight: .bold)).tracking(3)
                    Text("HARBOR / MAC").font(.app(14, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(Palette.muted)
                }
            }.padding(.bottom, 42)
            Text(t("WORKSPACE", "工作空间")).font(.app(14, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(Palette.muted).padding(.bottom, 10)
            GroupTargetRow(group: nil, selected: store.selectedGroup == nil) { store.selectedGroup = nil }
            HStack {
                Text(t("GROUPS", "账号组")).font(.app(14, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(Palette.muted)
                Spacer()
                Button { groupError = nil; showGroups = true } label: { Image(systemName: "plus").font(.app(14, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Palette.acid).accessibilityLabel(t("Manage groups", "管理账号组"))
            }.padding(.top, 22).padding(.bottom, 8)
            if store.groups.count > 5 {
                ScrollView {
                    VStack(spacing: 4) { ForEach(store.groups) { group in groupRow(group) } }
                }.frame(maxHeight: 210)
            } else {
                VStack(spacing: 4) { ForEach(store.groups) { group in groupRow(group) } }
            }
            if store.groups.isEmpty {
                Text(t("No groups yet. Use + to create one.", "还没有账号组，点击 + 创建。"))
                    .font(.app(12)).foregroundStyle(Palette.muted).padding(.horizontal, 12).padding(.vertical, 4)
            }
            Spacer(minLength: 20)
            Image(systemName: "arrow.up.right").font(.app(33, weight: .ultraLight)).foregroundStyle(Palette.acid).padding(.bottom, 12)
            Text(t("A little less friction.", "让切换，更轻松。"))
                .font(.app(23, weight: .medium)).fixedSize(horizontal: false, vertical: true).padding(.bottom, 8)
            Text(t("Switch accounts.\nKeep your flow.", "账号随心切换，\n专注你的工作。"))
                .font(.app(16)).foregroundStyle(Palette.muted).lineSpacing(4)
            Rectangle().fill(Palette.line).frame(height: 1).padding(.vertical, 20)
            HStack { Image(systemName: "circle.lefthalf.filled"); Text(t("Theme", "外观")); Spacer() }
                .font(.app(14)).foregroundStyle(Palette.muted).padding(.bottom, 8)
            HStack(spacing: 4) {
                themeButton(.system, "circle.lefthalf.filled", t("System", "跟随系统"))
                themeButton(.light, "sun.max", t("Light", "浅色"))
                themeButton(.dark, "moon", t("Dark", "深色"))
            }.padding(4).background(Palette.background, in: RoundedRectangle(cornerRadius: 9))
            HStack { Image(systemName: "globe"); Text(t("Language", "界面语言")); Spacer() }
                .font(.app(14)).foregroundStyle(Palette.muted).padding(.top, 14).padding(.bottom, 8)
            HStack(spacing: 4) {
                languageButton(.english, "EN")
                languageButton(.chinese, "中文")
            }.padding(4).background(Palette.background, in: RoundedRectangle(cornerRadius: 9))
            Button { showHelp = true } label: { HStack { Image(systemName: "questionmark.circle"); Text(t("Quick guide", "使用指南")); Spacer(); Image(systemName: "arrow.up.right").font(.app(14)) } }
                .buttonStyle(.plain).font(.app(16)).foregroundStyle(Palette.muted).padding(.top, 20)
            VStack(alignment: .leading, spacing: 1) {
                Text("v\(AppInfo.version)").font(.app(14, design: .monospaced))
                Text("by \(AppInfo.author)").font(.app(13))
            }.foregroundStyle(Palette.muted).padding(.top, 16)
        }.padding(.horizontal, 24).padding(.top, 48).padding(.bottom, 24).frame(width: 238).frame(maxHeight: .infinity).background(Palette.panel)
    }
    private func groupRow(_ group: AccountGroup) -> some View {
        GroupTargetRow(group: group, selected: store.selectedGroup == group.id) { store.selectedGroup = group.id }
    }
    private func themeButton(_ theme: AppTheme, _ icon: String, _ label: String) -> some View {
        Button { store.theme = theme } label: {
            Image(systemName: icon).font(.app(14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                .foregroundStyle(store.theme == theme ? Palette.ink : Palette.muted)
                .background(store.theme == theme ? Palette.raised : .clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).accessibilityLabel(label)
            .accessibilityValue(store.theme == theme ? t("Selected", "已选择") : "")
    }
    private func languageButton(_ language: AppLanguage, _ label: String) -> some View {
        Button { store.language = language } label: {
            Text(label).font(.app(15, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                .foregroundStyle(store.language == language ? Palette.ink : Palette.muted)
                .background(store.language == language ? Palette.raised : .clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).accessibilityLabel(language == .english ? "English" : "简体中文")
            .accessibilityValue(store.language == language ? t("Selected", "已选择") : "")
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(t("01 / ACCOUNT CONTROL", "01 / 账号管理")).font(.app(14, weight: .medium, design: .monospaced)).tracking(2).foregroundStyle(Palette.muted)
                Spacer()
                HStack(spacing: 8) {
                    Circle().fill(Palette.acid).frame(width: 6, height: 6)
                    Text(store.demo ? t("DEMO", "演示") : t("LOCAL STORAGE", "本地存储"))
                        .font(.app(14, weight: .semibold, design: .monospaced)).tracking(1)
                }.foregroundStyle(Palette.acid)
            }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(t("Accounts", "账号总览") + ".").font(.app(44, weight: .semibold)).tracking(-1.5)
                    Text(t("Every identity. One quiet workspace.", "每一个身份，都在这里。"))
                        .font(.app(18)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button { store.refresh(api: true) } label: {
                    HStack(spacing: 8) {
                        if store.busy { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                        Text(t("Refresh usage", "刷新额度"))
                    }
                }.buttonStyle(ActionStyle()).disabled(locked).keyboardShortcut("r", modifiers: .command)
            }
        }
    }
    private var summary: some View {
        HStack(alignment: .center, spacing: 20) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(format: "%02d", store.accounts.count)).font(.app(36, weight: .light, design: .monospaced)).foregroundStyle(Palette.acid)
                Text(t("saved accounts", "个已存账号")).font(.app(15)).foregroundStyle(Palette.muted)
            }
            Rectangle().fill(Palette.line).frame(width: 1, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(t("ACTIVE IDENTITY", "当前身份")).font(.app(14, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(Palette.muted)
                Text(store.accounts.first(where: { $0.active }).map { store.title($0) } ?? t("None selected", "尚未选择"))
                    .font(.app(17, weight: .medium)).lineLimit(1)
            }
            Spacer(minLength: 0)
            Label(t("Auto restart", "自动重启"), systemImage: "arrow.triangle.2.circlepath")
                .font(.app(14)).foregroundStyle(Palette.muted)
        }.padding(.vertical, 14)
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
    private var controls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField(t("Search accounts", "搜索账号"), text: $search).textFieldStyle(.plain).font(.app(17))
                    .accessibilityLabel(t("Search by email or alias", "按邮箱或别名搜索"))
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel(t("Clear search", "清空搜索"))
                }
            }.padding(10).background(Palette.panel, in: RoundedRectangle(cornerRadius: 9))
            Button { groupError = nil; showGroups = true } label: { Label(t("Groups", "账号组"), systemImage: "folder") }.buttonStyle(ActionStyle())
            Button { store.saveCurrent() } label: { Text(t("Save current", "保存当前登录")) }.buttonStyle(ActionStyle()).disabled(locked)
            Button { store.importFile() } label: { Label(t("Import", "导入账号"), systemImage: "plus") }.buttonStyle(ActionStyle(prominent: true)).disabled(locked)
        }
    }
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: emptyIcon).font(.app(38, weight: .ultraLight)).foregroundStyle(Palette.acid)
            Text(emptyTitle).font(.app(24, weight: .medium))
            Text(emptyDetail).font(.app(15)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).lineSpacing(4)
        }.frame(maxWidth: .infinity).padding(.vertical, 54)
    }
    private var emptyIcon: String {
        if store.accounts.isEmpty { return "rectangle.stack.badge.plus" }
        if !search.isEmpty { return "magnifyingglass" }
        return "folder"
    }
    private var emptyTitle: String {
        if store.accounts.isEmpty { return t("Your next workspace starts here.", "从第一个账号开始。") }
        if !search.isEmpty { return t("No matching accounts.", "没有匹配的账号。") }
        return t("This group is empty.", "这个账号组还没有账号。")
    }
    private var emptyDetail: String {
        if store.accounts.isEmpty { return t("Save your current Codex sign-in, or import an auth.json file.\nTo add a new identity, sign in with Codex first.", "保存 Codex 当前登录，或导入 auth.json 文件。\n添加新身份前，请先通过 Codex 完成登录。") }
        if !search.isEmpty { return t("Try a different email or alias.", "试试其他邮箱或别名。") }
        return t("Drag a card onto this group in the sidebar, or use Move to group from a card's menu.", "把卡片拖到侧栏的该账号组，或在卡片菜单中选择“移动到账号组”。")
    }
    private func card(_ account: Account) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text(String(store.title(account).prefix(1)).uppercased()).font(.app(17, weight: .medium, design: .monospaced))
                    .foregroundStyle(account.active ? Palette.acid : Palette.muted)
                    .frame(width: 36, height: 36).background(Palette.raised, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(store.title(account)).font(.app(19, weight: .semibold)).lineLimit(1)
                        if account.active {
                            Text(t("ACTIVE", "使用中")).font(.app(12, weight: .bold, design: .monospaced)).tracking(0.5)
                                .foregroundStyle(Palette.acid).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Palette.acid.opacity(0.10), in: Capsule())
                        }
                    }
                    if store.title(account) != account.email {
                        Text(account.email ?? t("API key account", "API 密钥账号")).font(.app(14)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    if let group = store.groupName(for: account) {
                        Label(group, systemImage: "folder").font(.app(12, weight: .medium)).foregroundStyle(Palette.acid).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(account.plan?.uppercased() ?? t("UNKNOWN", "未知套餐")).font(.app(12, weight: .medium, design: .monospaced)).tracking(0.5).foregroundStyle(Palette.muted)
                    Menu {
                        Button(t("Edit alias", "编辑别名")) { alias = account.alias ?? ""; editing = account }
                        Menu(t("Move to group", "移动到账号组")) {
                            Button(t("No group", "未分组")) { store.move(account, to: nil) }
                            if !store.groups.isEmpty { Divider() }
                            ForEach(store.groups) { group in Button(group.name) { store.move(account, to: group.id) } }
                        }
                        Divider()
                        Button(t("Remove account", "移除账号"), role: .destructive) { removing = account }
                    } label: { Image(systemName: "ellipsis").font(.app(15)).frame(width: 22, height: 22) }
                        .menuStyle(.borderlessButton).fixedSize().disabled(locked).accessibilityLabel(t("Account actions", "账号操作"))
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                quota(account.usage?.primary, plan: account.plan, fallback: t("Short window", "短周期额度"))
                if account.usage == nil || account.usage?.secondary != nil {
                    quota(account.usage?.secondary, plan: account.plan, fallback: t("Long window", "长周期额度"))
                }
            }
            Spacer(minLength: 0)
            Rectangle().fill(Palette.line).frame(height: 1)
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(source(account.usage)).font(.app(13)).foregroundStyle(Palette.muted).lineLimit(1)
                    if let status = account.usage?.refresh?.status, !["ok", "not_requested"].contains(status) {
                        Text(account.usage?.source == "none" ? t("No usage data yet. Try refreshing.", "暂无额度数据，请尝试刷新。") : t("Refresh unavailable. Showing an earlier snapshot.", "本次刷新未获取新数据，显示已有快照。"))
                            .font(.app(12)).foregroundStyle(.orange).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Button { switching = account } label: { HStack(spacing: 6) { Text(account.active ? t("Sync again", "重新同步") : t("Switch account", "切换账号")); Image(systemName: "arrow.up.right") } }
                    .buttonStyle(ActionStyle(prominent: !account.active, compact: true)).disabled(locked)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16).background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(account.active ? Palette.acid.opacity(0.45) : Palette.line, lineWidth: 1))
            .contextMenu {
                Button(t("Edit alias", "编辑别名")) { alias = account.alias ?? ""; editing = account }
                Menu(t("Move to group", "移动到账号组")) {
                    Button(t("No group", "未分组")) { store.move(account, to: nil) }
                    if !store.groups.isEmpty { Divider() }
                    ForEach(store.groups) { group in Button(group.name) { store.move(account, to: group.id) } }
                }
                Button(t("Remove account", "移除账号"), role: .destructive) { removing = account }
            }
            .draggable(account.id)
            .help(t("Drag this card onto a group in the sidebar.", "将此卡片拖到侧栏的账号组。"))
    }
    private func quota(_ value: Quota?, plan: String?, fallback: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(quotaLabel(value, plan: plan, fallback: fallback))
                    .font(.app(13)).foregroundStyle(Palette.muted).lineLimit(1)
                Spacer(minLength: 4)
                Text(value.map { "\(Int($0.remaining))%" } ?? "—").font(.app(22, weight: .medium, design: .monospaced))
                if value != nil { Text(t("left", "剩余")).font(.app(12)).foregroundStyle(Palette.muted) }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.raised)
                    if let value { Capsule().fill(value.remaining < 20 ? Color.orange : Palette.acid).frame(width: geometry.size.width * value.remaining / 100) }
                }
            }.frame(height: 4).accessibilityLabel(t("Remaining usage", "剩余额度")).accessibilityValue(value.map { "\(Int($0.remaining))%" } ?? t("Unknown", "未知"))
            Text(value?.resets_at.map { t("Resets ", "重置于 ") + store.language.date($0) } ?? t("Reset time unavailable", "重置时间未知"))
                .font(.app(13)).foregroundStyle(Palette.muted).lineLimit(1)
        }
    }
    private func quotaLabel(_ value: Quota?, plan: String?, fallback: String) -> String {
        guard let minutes = value?.window_minutes else { return fallback }
        if minutes == 300 { return t("5-hour window", "5 小时额度") }
        if minutes == 10080 { return t("Weekly", "每周额度") }
        if plan?.lowercased() == "free" { return t("Free quota", "免费额度") }
        return t("\(minutes)-minute window", "\(minutes) 分钟额度")
    }
    private func source(_ usage: Usage?) -> String {
        let label: String
        switch usage?.source {
        case "api": label = t("Live data", "在线数据")
        case "local": label = t("Local session", "本地会话")
        case "cache": label = t("Cached snapshot", "缓存快照")
        case "none", nil: label = t("No usage data", "暂无额度")
        default: label = t("Unknown source", "未知来源")
        }
        return label + (usage?.updated_at.map { " · " + store.language.date($0) } ?? "")
    }
    private var footer: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: store.demo ? "eye" : "circle.dotted").foregroundStyle(Palette.acid)
            Text(store.language.text(store.notice)).font(.app(14)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.padding(.horizontal, 32).padding(.vertical, 14)
            .background(Palette.background).overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
    private var groupManager: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("Account groups", "账号组")).font(.app(30, weight: .semibold))
                    Text(t("Create groups, then drag cards onto them in the sidebar or assign accounts below.", "创建账号组后，可将卡片拖到侧栏对应组，或在下方直接分配账号。"))
                        .font(.app(15)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Text("\(store.groups.count)").font(.app(28, weight: .light, design: .monospaced)).foregroundStyle(Palette.acid)
            }
            HStack(spacing: 8) {
                TextField(t("New group name", "新账号组名称"), text: $newGroupName)
                    .textFieldStyle(.plain).font(.app(16)).padding(10).background(Palette.background, in: RoundedRectangle(cornerRadius: 8))
                    .onSubmit { addGroup() }
                Button(t("Add", "添加")) { addGroup() }.buttonStyle(ActionStyle(prominent: true))
                    .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let groupError {
                Text(groupError).font(.app(13)).foregroundStyle(.red)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(t("Groups", "账号组")).font(.app(14, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(Palette.muted)
                if store.groups.isEmpty {
                    Text(t("No groups yet.", "还没有账号组。")).font(.app(14)).foregroundStyle(Palette.muted).padding(.vertical, 8)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(store.groups) { group in
                                HStack(spacing: 10) {
                                    Image(systemName: "folder").foregroundStyle(Palette.acid)
                                    TextField("", text: Binding(
                                        get: { store.groups.first(where: { $0.id == group.id })?.name ?? group.name },
                                        set: { store.renameGroup(group.id, to: $0) }
                                    )).textFieldStyle(.plain).font(.app(16))
                                    Text("\(store.groupCount(group.id))").font(.app(12, design: .monospaced)).foregroundStyle(Palette.muted)
                                    Button { store.deleteGroup(group.id) } label: { Image(systemName: "trash") }
                                        .buttonStyle(.plain).foregroundStyle(.red).accessibilityLabel(t("Delete group", "删除账号组"))
                                }.padding(10).background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }.frame(maxHeight: 170)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(t("Assign accounts", "分配账号")).font(.app(14, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(Palette.muted)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(store.accounts) { account in
                            HStack(spacing: 10) {
                                Text(store.title(account)).font(.app(15)).lineLimit(1)
                                Spacer(minLength: 8)
                                Picker("", selection: Binding(
                                    get: { store.groupID(for: account) },
                                    set: { store.move(account, to: $0) }
                                )) {
                                    Text(t("No group", "未分组")).tag(Optional<String>.none)
                                    ForEach(store.groups) { group in Text(group.name).tag(Optional(group.id)) }
                                }.labelsHidden().frame(width: 180)
                            }
                        }
                    }
                }.frame(maxHeight: 190)
            }
            HStack {
                Text("\(AppInfo.name) · by \(AppInfo.author)").font(.app(13)).foregroundStyle(Palette.muted)
                Spacer()
                Button(t("Done", "完成")) { showGroups = false }.buttonStyle(ActionStyle(prominent: true))
            }
        }.padding(28).frame(width: 620, height: 640).background(Palette.panel).foregroundStyle(Palette.ink)
    }
    private func addGroup() {
        let value = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if store.addGroup(value) {
            newGroupName = ""
            groupError = nil
        } else {
            groupError = t("That group already exists.", "该账号组已存在。")
        }
    }
    private func dialog<Actions: View>(icon: String, title: String, detail: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: icon).font(.app(30, weight: .light)).foregroundStyle(Palette.acid)
            Text(title).font(.app(28, weight: .semibold))
            Text(detail).font(.app(18)).foregroundStyle(Palette.muted).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); actions() }.padding(.top, 10)
        }.padding(32).frame(width: 550).background(Palette.panel).foregroundStyle(Palette.ink)
    }
    private func aliasEditor(_ account: Account) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(t("Make it yours.", "给账号一个名字。" )).font(.app(28, weight: .semibold))
            Text(t("Account alias", "账号别名")).font(.app(16)).foregroundStyle(Palette.muted)
            TextField(t("Personal, Studio, Work…", "例如：个人、工作室、工作…"), text: $alias)
                .textFieldStyle(.plain).font(.app(20)).padding(16).background(Palette.background, in: RoundedRectangle(cornerRadius: 9))
            Text(t("Leave blank to clear. Use a unique name, not just numbers.", "留空可清除别名。别名不能重复，也不能只包含数字。"))
                .font(.app(15)).foregroundStyle(Palette.muted)
            HStack {
                Spacer()
                Button(t("Cancel", "取消")) { editing = nil }.buttonStyle(ActionStyle())
                Button(t("Save alias", "保存别名")) {
                    let value = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.mutate(value.isEmpty ? ["alias", "clear", account.id] : ["alias", "set", account.id, value], json: false, message: Copy("Account alias updated.", "账号别名已更新。"))
                    editing = nil
                }.buttonStyle(ActionStyle(prominent: true))
            }
        }.padding(32).frame(width: 550).background(Palette.panel).foregroundStyle(Palette.ink)
    }
    private var help: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text(t("Quick guide", "使用指南")).font(.app(30, weight: .semibold)); Spacer(); Text("01—05").font(.app(15, design: .monospaced)).foregroundStyle(Palette.acid) }
            helpRow("01", t("Bring your accounts", "添加账号"), t("Sign in with Codex, then select Save current. Or import an auth.json file or a folder of JSON files.", "先使用 Codex 完成登录，再点击保存当前登录；也可导入 auth.json 文件或包含 JSON 的目录。"))
            helpRow("02", t("Know what is current", "识别数据时效"), t("Refresh usage for live data; the app also refreshes once at every launch. Cached and local snapshots may be older; failed refreshes keep the last available data.", "刷新额度可获取在线数据；应用每次启动时也会自动刷新一次。缓存与本地快照可能较旧；刷新失败时会保留已有数据。"))
            helpRow("03", t("Switch, then restart", "切换并自动重启"), t("The app syncs your current Codex login automatically at launch and before switching, preserving cached usage. Switching restarts Codex; finish active tasks first. Use Harbor to switch; signing out in Codex can revoke saved logins. If Codex asks you to sign in, sign in; the snapshot syncs automatically or use Save current.", "应用会在启动时和切换前自动同步当前 Codex 登录，并保留已缓存额度。切换会重启 Codex，请先结束当前任务。请使用 Harbor 切换；在 Codex 中退出登录可能会吊销已保存的登录。如果 Codex 要求登录，请登录；快照会自动同步，也可以点击“保存当前登录”。"))
            helpRow("04", t("Group your accounts", "整理账号"), t("Create groups from the Groups sheet. Drag a card onto a group in the sidebar, or use Move to group in a card's menu.", "在“账号组”面板中创建分组。把卡片拖到侧栏的账号组，或在卡片菜单中选择“移动到账号组”。"))
            helpRow("05", t("Stored on your Mac", "数据保存在本机"), t("Credentials remain in local files managed by the account core. This app does not add Keychain encryption and never displays your access tokens.", "凭据保存在核心管理的本地文件中，不使用钥匙串加密；本应用不展示访问令牌。"))
            HStack {
                Text("\(AppInfo.name) · by \(AppInfo.author)").font(.app(13)).foregroundStyle(Palette.muted)
                Spacer()
                Button(t("Done", "完成")) { showHelp = false }.buttonStyle(ActionStyle(prominent: true))
            }
        }.padding(32).frame(width: 620).background(Palette.panel).foregroundStyle(Palette.ink)
    }
    private func helpRow(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(number).font(.app(15, design: .monospaced)).foregroundStyle(Palette.acid).padding(.top, 3)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.app(19, weight: .semibold))
                Text(detail).font(.app(17)).foregroundStyle(Palette.muted).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct GroupTargetRow: View {
    @EnvironmentObject var store: Store
    let group: AccountGroup?
    let selected: Bool
    let action: () -> Void
    @State private var targeted = false
    private func t(_ en: String, _ zh: String) -> String { store.t(en, zh) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: group == nil ? "rectangle.stack" : "folder").font(.app(15)).frame(width: 18)
                Text(group?.name ?? t("All accounts", "全部账号")).font(.app(15, weight: selected ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(store.groupCount(group?.id))").font(.app(12, design: .monospaced)).foregroundStyle(Palette.muted)
                if selected { Circle().fill(Palette.acid).frame(width: 5, height: 5) }
            }
            .foregroundStyle(selected ? Palette.ink : Palette.muted)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(targeted ? Palette.acid.opacity(0.16) : (selected ? Palette.raised : Color.clear), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(targeted ? Palette.acid : Color.clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { keys, _ in
            guard let key = keys.first else { return false }
            store.move(key, to: group?.id)
            return true
        } isTargeted: { targeted = $0 }
        .accessibilityLabel(group?.name ?? t("All accounts", "全部账号"))
        .accessibilityHint(t("Drop an account card here to move it", "将账号卡片拖到这里即可移动"))
        .help(t("Drag an account card here", "将账号卡片拖到这里"))
    }
}
