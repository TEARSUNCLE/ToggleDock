import AppKit
import os

/// 收起 / 还原 执行层：通过 Accessibility API 操作目标应用的窗口或整体可见性。
///
/// - minimize 模式：对每个窗口设置 `AXMinimized`，走系统 genie 动画（默认，最接近 Windows 任务栏）
/// - hide 模式：对应用设置 `AXHidden`（等同 ⌘H），瞬间完成
public enum AppToggle {

    static let log = Logger(subsystem: "com.tears.ToggleDock", category: "toggle")

    /// Dock 点击瞬间的意图。必须在点击后**立即**采样决定：
    /// 点击本身会触发系统/目标应用的后续动作（激活、自恢复窗口——微信等应用点击
    /// Dock 图标会自行还原主窗口），150ms 后现场的窗口状态已不可信，
    /// 据此推断「收起还是还原」会与用户意图相悖（表现为：点 Dock 还原后窗口又被自动收起）。
    public enum DockClickIntent: Equatable {
        /// 快照时应用有可见窗口 → 用户意图为「收起」
        case collapse
        /// 快照时应用不可见/无可见窗口 → 用户意图为「还原」
        case restore
    }

    /// 判断点击瞬间的用户意图（含同步 AX IPC，须在后台队列调用）。
    public static func dockClickIntent(of app: NSRunningApplication) -> DockClickIntent {
        let element = AccessibilitySupport.appElement(pid: app.processIdentifier)
        guard !AccessibilitySupport.isHidden(element) else { return .restore }
        for window in AccessibilitySupport.windows(of: element)
        where !AccessibilitySupport.isMinimized(window) {
            return .collapse
        }
        return .restore
    }

    /// 点击 Dock 图标后按「点击瞬间快照的意图」执行收起/还原。
    /// 执行时以当前现场为准做幂等收尾，但**绝不反向推翻**现场已发生的状态变化：
    /// - 意图=收起 但现场已自行收起（应用自己最小化/隐藏了）→ 尊重，不再还原
    /// - 意图=还原 但现场已自行还原（应用自恢复窗口）→ 尊重，不再收起
    public static func toggle(_ app: NSRunningApplication, mode: Preferences.CollapseMode, intent: DockClickIntent) {
        let element = AccessibilitySupport.appElement(pid: app.processIdentifier)
        let appName = app.localizedName ?? "?"

        switch intent {
        case .collapse:
            guard !AccessibilitySupport.isHidden(element) else {
                log.info("意图收起→跳过: \(appName, privacy: .public) 现场已自行隐藏")
                return
            }
            switch mode {
            case .hide:
                AccessibilitySupport.setHidden(element, true)
                log.info("意图收起(hide): \(appName, privacy: .public)")
            case .minimize:
                let windows = AccessibilitySupport.windows(of: element)
                if windows.isEmpty {
                    // 没有可最小化的窗口（例如只有面板），退回 hide 保证行为可用
                    AccessibilitySupport.setHidden(element, true)
                    log.info("意图收起→退回hide: \(appName, privacy: .public) 无AX窗口")
                    return
                }
                let visible = windows.filter { !AccessibilitySupport.isMinimized($0) }
                guard !visible.isEmpty else {
                    log.info("意图收起→跳过: \(appName, privacy: .public) 现场已自行全部最小化")
                    return
                }
                visible.forEach { AccessibilitySupport.setMinimized($0, true) }
                log.info("意图收起(minimize): \(appName, privacy: .public) 窗口数=\(visible.count)")
            }

        case .restore:
            let hidden = AccessibilitySupport.isHidden(element)
            var restoredMinimized = 0
            if hidden {
                AccessibilitySupport.setHidden(element, false)
            }
            if mode == .minimize {
                let minimized = AccessibilitySupport.windows(of: element)
                    .filter { AccessibilitySupport.isMinimized($0) }
                restoredMinimized = minimized.count
                minimized.forEach { AccessibilitySupport.setMinimized($0, false) }
            }
            log.info("还原 \(appName, privacy: .public): 原隐藏=\(hidden) 还原最小化窗口数=\(restoredMinimized)")
        }
    }

    /// 单向收起（供「单应用聚焦」使用）。
    public static func collapse(_ app: NSRunningApplication, mode: Preferences.CollapseMode) {
        let element = AccessibilitySupport.appElement(pid: app.processIdentifier)
        guard !AccessibilitySupport.isHidden(element) else { return }

        switch mode {
        case .hide:
            AccessibilitySupport.setHidden(element, true)
            log.info("聚焦收起(hide): \(app.localizedName ?? "?", privacy: .public)")
        case .minimize:
            let windows = AccessibilitySupport.windows(of: element)
            guard !windows.isEmpty else {
                AccessibilitySupport.setHidden(element, true)
                log.info("聚焦收起→退回hide: \(app.localizedName ?? "?", privacy: .public) 无AX窗口")
                return
            }
            let visible = windows.filter { !AccessibilitySupport.isMinimized($0) }
            visible.forEach { AccessibilitySupport.setMinimized($0, true) }
            log.info("聚焦收起(minimize): \(app.localizedName ?? "?", privacy: .public) 窗口数=\(visible.count)")
        }
    }

    /// 应用当前是否处于「已收起」状态（隐藏，或全部窗口最小化）。
    public static func isCollapsed(_ app: NSRunningApplication) -> Bool {
        let element = AccessibilitySupport.appElement(pid: app.processIdentifier)
        if AccessibilitySupport.isHidden(element) { return true }
        let windows = AccessibilitySupport.windows(of: element)
        return !windows.isEmpty && windows.allSatisfy { AccessibilitySupport.isMinimized($0) }
    }

    // MARK: - 「最小化到应用图标」系统开关

    private static let dockDefaultsDomain = "com.apple.dock"
    private static let minimizeToApplicationKey = "minimize-to-application"

    /// 是否已开启系统设置「将窗口最小化到应用程序图标」。
    /// 未开启时 genie 动画不会吸入应用图标，而是堆到 Dock 右侧，体验不符。
    public static func isMinimizeToApplicationEnabled() -> Bool {
        UserDefaults(suiteName: dockDefaultsDomain)?.bool(forKey: minimizeToApplicationKey) ?? false
    }

    /// 开启该设置并重启 Dock 使其立即生效。子进程在后台队列执行
    /// （`Process.waitUntilExit()` 在主线程会阻塞 UI），完成回调回到主线程。
    public static func enableMinimizeToApplication(completion: ((Bool) -> Void)? = nil) {
        @discardableResult
        func run(_ launchPath: String, _ args: [String]) -> Bool {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = args
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = run("/usr/bin/defaults", ["write", dockDefaultsDomain, minimizeToApplicationKey, "-bool", "true"])
            if ok { run("/usr/bin/killall", ["Dock"]) }
            DispatchQueue.main.async { completion?(ok) }
        }
    }
}
