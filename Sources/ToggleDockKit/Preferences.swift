import Foundation

/// 用户偏好设置。所有键统一加 `toggledock.` 前缀，避免与其他 App 的全局域冲突。
public enum Preferences {

    // MARK: - 键名

    private enum Key {
        static let collapseMode = "toggledock.collapseMode"
        static let language = "toggledock.language"
        static let singleAppFocus = "toggledock.singleAppFocus"
        static let seenAccessibilityPrompt = "toggledock.seenAccessibilityPrompt"
    }

    /// 偏好变化通知（菜单栏、设置窗口监听此通知以刷新 UI）。
    public static let didChangeNotification = Notification.Name("toggledock.preferencesDidChange")

    /// 收起方式。
    public enum CollapseMode: String, CaseIterable, Sendable {
        /// 最小化（默认）：窗口带 genie 动画吸入 Dock 图标，还原时反向弹出，最接近 Windows 任务栏。
        case minimize
        /// 隐藏：等同 ⌘H，瞬间收起、无动画，但恢复最可靠。
        case hide
    }

    /// 界面语言。默认中文，可切换英文。
    public enum LanguageOption: String, CaseIterable, Sendable {
        case system
        case zhHans = "zh-Hans"
        case en
    }

    private static var defaults: UserDefaults { .standard }

    // MARK: - 读写

    /// 收起方式，默认 minimize（带 genie 动画）。
    public static var collapseMode: CollapseMode {
        get { CollapseMode(rawValue: defaults.string(forKey: Key.collapseMode) ?? "") ?? .minimize }
        set { set(newValue.rawValue, forKey: Key.collapseMode) }
    }

    /// 界面语言，默认跟随系统。
    public static var language: LanguageOption {
        get { LanguageOption(rawValue: defaults.string(forKey: Key.language) ?? "") ?? .system }
        set { set(newValue.rawValue, forKey: Key.language) }
    }

    /// 单应用聚焦：切换到另一个应用时自动收起上一个应用（多显示器感知）。
    public static var singleAppFocusEnabled: Bool {
        get { defaults.bool(forKey: Key.singleAppFocus) }
        set { set(newValue, forKey: Key.singleAppFocus) }
    }

    /// 是否已展示过辅助功能授权引导（避免每次启动都弹窗）。
    public static var seenAccessibilityPrompt: Bool {
        get { defaults.bool(forKey: Key.seenAccessibilityPrompt) }
        set { set(newValue, forKey: Key.seenAccessibilityPrompt) }
    }

    private static func set(_ value: Any?, forKey key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}
