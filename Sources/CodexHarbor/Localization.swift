import Foundation

struct Copy: Equatable, Sendable {
    let en: String
    let zh: String
    init(_ en: String, _ zh: String) { self.en = en; self.zh = zh }
}

enum AppLanguage: String, CaseIterable {
    case english = "en"
    case chinese = "zh-Hans"
    static let preferenceKey = "interfaceLanguage"
    static func saved(in defaults: UserDefaults = .standard) -> AppLanguage {
        AppLanguage(rawValue: defaults.string(forKey: preferenceKey) ?? "") ?? .english
    }
    var locale: Locale { Locale(identifier: self == .english ? "en_US" : "zh_CN") }
    func text(_ value: Copy) -> String { self == .english ? value.en : value.zh }
    func date(_ timestamp: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
}
