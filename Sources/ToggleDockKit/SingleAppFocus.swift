import AppKit
import os

/// 「单应用聚焦」判定：切换到应用 B 时，是否应自动收起上一个应用 A。
///
/// 多显示器规则：A、B 在不同屏幕时**不**收起——副屏上的应用不应被主屏的操作打扰。
public enum SingleAppFocusLogic {

    /// - Parameters:
    ///   - sameScreenCount: 总屏幕数；≤1 时视为同屏
    ///   - previousOnScreen / currentOnScreen: 各自窗口所在屏幕；任一为 nil（无窗口/取不到位置）则不收起
    public static func shouldCollapsePrevious(
        previousPID: pid_t,
        currentPID: pid_t,
        previousOnScreen: NSScreen?,
        currentOnScreen: NSScreen?,
        screenCount: Int
    ) -> Bool {
        guard previousPID != currentPID else { return false }
        guard screenCount > 1 else { return true } // 单屏：直接收起
        // 多屏：无法定位窗口的应用没有可见内容需要收起，跳过
        guard let a = previousOnScreen, let b = currentOnScreen else { return false }
        return a === b || a.frame == b.frame
    }

    /// 找到包含指定 Cocoa 全局坐标点的屏幕。
    public static func screen(containing point: CGPoint, in screens: [NSScreen]) -> NSScreen? {
        screens.first { NSPointInRect(point, $0.frame) }
    }
}

/// 聚焦协调器：监听应用切换通知，收起前一个应用。
/// 收起动作仅针对**有可见窗口**的应用（无窗口则无事可做）。
public final class SingleAppFocusCoordinator {

    private static let log = Logger(subsystem: "com.tears.ToggleDock", category: "focus")

    private var workspaceObserver: Any?
    private var previousPID: pid_t?

    public init() {}

    public func start() {
        guard workspaceObserver == nil else { return }
        previousPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self.handleActivation(activated)
        }
    }

    public func stop() {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
    }

    private func handleActivation(_ activated: NSRunningApplication) {
        defer { previousPID = activated.processIdentifier }
        guard Preferences.singleAppFocusEnabled,
              let previousPID,
              let previous = NSRunningApplication(processIdentifier: previousPID),
              !previous.isTerminated,
              previous.activationPolicy == .regular
        else { return }
        Self.log.info("激活切换: →\(activated.localizedName ?? "?", privacy: .public)，尝试收起前一个 \(previous.localizedName ?? "?", privacy: .public)")

        let screens = NSScreen.screens // 主线程快照，后台计算用
        // screenOf/collapse 都含同步 AX IPC：放后台执行，主线程（菜单栏响应）不受目标应用状态影响
        DispatchQueue.global(qos: .userInitiated).async {
            let a = Self.screenOf(previous, screens: screens)
            let b = Self.screenOf(activated, screens: screens)
            guard SingleAppFocusLogic.shouldCollapsePrevious(
                previousPID: previous.processIdentifier,
                currentPID: activated.processIdentifier,
                previousOnScreen: a,
                currentOnScreen: b,
                screenCount: screens.count
            ) else { return }
            AppToggle.collapse(previous, mode: Preferences.collapseMode)
        }
    }

    /// 应用首个可见窗口所在屏幕。含同步 AX IPC，须在后台队列调用；screens 为主线程快照。
    static func screenOf(_ app: NSRunningApplication, screens: [NSScreen]) -> NSScreen? {
        let element = AccessibilitySupport.appElement(pid: app.processIdentifier)
        for window in AccessibilitySupport.windows(of: element) {
            if let point = AccessibilitySupport.cocoaPosition(of: window) {
                return SingleAppFocusLogic.screen(containing: point, in: screens)
            }
        }
        return nil
    }
}
