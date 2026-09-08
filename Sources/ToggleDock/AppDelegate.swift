import AppKit
import os
import ToggleDockKit

/// 应用装配层：把「点击检测 → 收起/还原」与菜单栏、设置窗口、聚焦模式连起来。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBarController: StatusBarController!
    private var clickDetector: DockClickDetector!
    private var focusCoordinator: SingleAppFocusCoordinator!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 纯菜单栏应用：不在 Dock 中显示自己的图标
        NSApp.setActivationPolicy(.accessory)

        statusBarController = StatusBarController()
        statusBarController.install()

        clickDetector = DockClickDetector()
        clickDetector.onDockReClick = { app, intent in
            let mode = Preferences.collapseMode
            // AX 写操作可能触达无响应的目标应用：放后台队列执行（统一 1s 消息超时兜底），
            // 主线程（菜单栏响应/退出）不受影响
            DispatchQueue.global(qos: .userInteractive).async {
                AppToggle.toggle(app, mode: mode, intent: intent)
                // 复核（仅诊断）：动作后 0.6s 再看一眼现场，
                // 若目标应用自己把窗口恢复了/又收起了，日志能看出来
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    let name = app.localizedName ?? "?"
                    let logger = Logger(subsystem: "com.tears.ToggleDock", category: "toggle")
                    if AppToggle.isCollapsed(app) {
                        logger.info("复核0.6s: \(name, privacy: .public) 已收起")
                    } else {
                        logger.info("复核0.6s: \(name, privacy: .public) 有可见窗口")
                    }
                }
            }
        }
        clickDetector.start()

        focusCoordinator = SingleAppFocusCoordinator()
        focusCoordinator.start()

        // 偏好 / 语言变化 → 重建菜单与设置 UI（selector 方式，terminate 时统一移除）
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(interfaceStateChanged),
                           name: Preferences.didChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(interfaceStateChanged),
                           name: L10n.didChangeNotification, object: nil)

        guideAccessibilityIfNeeded()
    }

    @objc private func interfaceStateChanged() {
        statusBarController.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        clickDetector.stop()
        focusCoordinator.stop()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 辅助功能权限引导（首次启动）

    private func guideAccessibilityIfNeeded() {
        guard !AccessibilitySupport.isTrusted() else { return }
        guard !Preferences.seenAccessibilityPrompt else { return }
        Preferences.seenAccessibilityPrompt = true
        // 只触发系统自带的授权弹窗（系统 UI，非阻塞）。
        // 不用 NSAlert.runModal：macOS 14 下 accessory 应用无法可靠自激活，模态窗口
        // 若出现在后台会吞掉键鼠焦点并阻塞主线程（表现为键盘失效、应用无法退出）。
        // 未授权时菜单栏会常驻「需要权限」条目直达系统设置，设置窗口也有状态指示。
        _ = AccessibilitySupport.isTrusted(prompt: true)
    }
}
