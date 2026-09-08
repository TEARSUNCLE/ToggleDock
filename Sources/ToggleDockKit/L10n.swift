import Foundation

/// 轻量本地化：直接加载 `.strings`（NeXTSTEP plist 格式），
/// 不依赖 Xcode 的 String Catalog 编译步骤，因此 `swift build` / `swiftc` / Xcode 三种方式通用，
/// 且语言切换后可立即生效（无需重启）。
///
/// 查找链：当前语言 → zh-Hans（默认语言）→ en → 键名本身。
public enum L10n {

    /// 支持的语言（默认中文，可切换英文）。
    public static let supportedLanguages: [String] = ["zh-Hans", "en"]

    public static let didChangeNotification = Notification.Name("toggledock.languageDidChange")

    private static var cache: [String: [String: String]] = [:]
    private static var cachedSystemLanguage: String?

    // MARK: - 语言解析

    /// 解析当前生效的语言代码（"zh-Hans" 或 "en"）。
    public static func currentLanguageCode() -> String {
        switch Preferences.language {
        case .zhHans: return "zh-Hans"
        case .en: return "en"
        case .system: return systemLanguageCode()
        }
    }

    /// 跟随系统时：系统首选语言为中文则用 zh-Hans，否则回退 en。
    public static func systemLanguageCode(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        let first = (preferredLanguages.first ?? "en").lowercased()
        return first.hasPrefix("zh") ? "zh-Hans" : "en"
    }

    private static func systemLanguageCode() -> String {
        if let cached = cachedSystemLanguage { return cached }
        // 必须显式传参调用公开重载：无参调用会解析回本函数自身，造成无限递归（栈溢出崩溃）
        let code = systemLanguageCode(preferredLanguages: Locale.preferredLanguages)
        cachedSystemLanguage = code
        return code
    }

    // MARK: - 取词

    /// 按当前界面语言取文案。
    public static func string(_ key: String) -> String {
        lookup(key, in: currentLanguageCode())
    }

    private static func lookup(_ key: String, in language: String) -> String {
        var seen = Set<String>()
        for code in [language, "zh-Hans", "en"] {
            guard !seen.contains(code) else { continue }
            seen.insert(code)
            if let table = cache[code] ?? load(code), let value = table[key] {
                return value
            }
        }
        return key
    }

    /// 语言偏好改变后调用：清缓存并广播，UI 监听后重建。
    public static func reload() {
        cache.removeAll()
        cachedSystemLanguage = nil
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    // MARK: - 资源加载

    @discardableResult
    private static func load(_ code: String) -> [String: String]? {
        if let cached = cache[code] { return cached }
        let table = loadTable(code) ?? [:]
        cache[code] = table
        return table.isEmpty ? nil : table
    }

    private static func loadTable(_ code: String) -> [String: String]? {
        // 两种构建布局都要兼容：
        // 1) build.sh 组装的 .app —— lproj 直接位于 Contents/Resources（Bundle.main）
        // 2) SwiftPM / Xcode —— Bundle.module 资源包（SPM 构建会定义 SWIFT_PACKAGE）
        var candidates: [URL?] = [
            Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: "\(code).lproj"),
        ]
        #if SWIFT_PACKAGE
        candidates.append(Bundle.module.url(forResource: "Localizable", withExtension: "strings", subdirectory: "Resources/\(code).lproj"))
        candidates.append(Bundle.module.url(forResource: "Localizable", withExtension: "strings", subdirectory: "\(code).lproj"))
        #endif
        for case let url? in candidates {
            // .strings 本质是旧式 plist，NSDictionary 可直接解析
            if let dict = NSDictionary(contentsOf: url) as? [String: String] {
                return dict
            }
        }
        return nil
    }
}
