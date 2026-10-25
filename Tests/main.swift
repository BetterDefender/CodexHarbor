import CFNetwork
import Foundation
let data = Data(#"{"schema_version":1,"future":true,"accounts":[{"account_key":"stable","active":false,"email":null}]}"#.utf8)
let decoded = try Backend.decode(data)
assert(decoded.accounts?.first?.id == "stable")
do { _ = try Backend.decode(Data(#"{"schema_version":2}"#.utf8)); fatalError("Accepted unknown schema") } catch {}
do { _ = try Backend.decode(Data(#"{"schema_version":1,"error":{"code":"state_uncertain","message":"secret"}}"#.utf8)); fatalError("Accepted error") } catch { assert(!error.localizedDescription.contains("secret")); assert(error.localizedDescription.contains("Refresh")) }
assert(Quota(used_percent: 27, window_minutes: 300, resets_at: nil).remaining == 73)
assert(Quota(used_percent: 120, window_minutes: nil, resets_at: nil).remaining == 0)
print("PASS: decoding, schema rejection, localized errors, quota calculation")
assert(Backend.proxyURL(type: kCFProxyTypeHTTP as String, host: "127.0.0.1", port: 7890) == "http://127.0.0.1:7890")
assert(Backend.proxyURL(type: kCFProxyTypeHTTPS as String, host: "proxy.local", port: 8080) == "http://proxy.local:8080")
assert(Backend.proxyURL(type: kCFProxyTypeSOCKS as String, host: "127.0.0.1", port: 1080) == "socks5h://127.0.0.1:1080")
assert(Backend.proxyURL(type: kCFProxyTypeNone as String, host: "127.0.0.1", port: 7890) == nil)
assert(Backend.childEnvironment()["PATH"]?.hasPrefix("/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:") == true)
print("PASS: system proxy translation and child environment")
let switched = try Backend.decode(Data(#"{"schema_version":1,"switched_to":{"account_key":"target","active":true}}"#.utf8))
try Backend.validateSwitch(switched, key: "target")
do { try Backend.validateSwitch(switched, key: "other"); fatalError("Accepted wrong account") } catch {}
do { try Backend.validateExit(switched, status: 1); fatalError("Accepted failed sync") } catch { assert(error.localizedDescription.contains("Credentials were written")) }
try Backend.validateExit(switched, status: 0)
assert(Backend.switchArguments("stable::key") == ["switch", "stable::key", "--json", "--restart-daemon"])
print("PASS: switch identity, partial success, daemon synchronization arguments")
let suite = "CodexHarborTests.\(UUID().uuidString)"
let preferences = UserDefaults(suiteName: suite)!
assert(AppLanguage.saved(in: preferences) == .english)
preferences.set("zh-Hans", forKey: AppLanguage.preferenceKey)
assert(AppLanguage.saved(in: preferences) == .chinese)
preferences.set("unsupported", forKey: AppLanguage.preferenceKey)
assert(AppLanguage.saved(in: preferences) == .english)
preferences.removePersistentDomain(forName: suite)
let bilingual = Copy("Ready", "就绪")
assert(AppLanguage.english.text(bilingual) == "Ready")
assert(AppLanguage.chinese.text(bilingual) == "就绪")
assert(AppLanguage.english.date(1792886400) != AppLanguage.chinese.date(1792886400))
do { try Backend.validateExit(switched, status: 1) } catch let error as AppError {
    assert(AppLanguage.chinese.text(error.message).contains("凭据已写入"))
    assert(AppLanguage.english.text(error.message).contains("Credentials were written"))
}
print("PASS: English default, saved language, unknown preference fallback, bilingual dates and errors")
let themeSuite = "CodexHarborTests.\(UUID().uuidString)"
let themePreferences = UserDefaults(suiteName: themeSuite)!
assert(AppTheme.saved(in: themePreferences) == .system)
themePreferences.set("light", forKey: AppTheme.preferenceKey)
assert(AppTheme.saved(in: themePreferences) == .light)
themePreferences.set("unsupported", forKey: AppTheme.preferenceKey)
assert(AppTheme.saved(in: themePreferences) == .system)
themePreferences.removePersistentDomain(forName: themeSuite)
print("PASS: theme preference fallback")
