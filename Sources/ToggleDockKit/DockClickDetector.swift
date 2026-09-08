import AppKit
import os

/// 全局监听鼠标按下事件，识别「点击了当前前台应用的 Dock 图标」这一动作。
///
/// 实现要点：
/// - `NSEvent.addGlobalMonitorForEvents` 只观察不拦截，不改变系统正常行为；
/// - **主线程只做零成本快照**（鼠标位置换算、前台应用信息）；所有 AX 同步 IPC
///   都在专用后台串行队列执行——在每次点击的回调里做同步 AX 调用，一旦目标
///   （Dock/前台应用）暂时无响应就会挂死主线程，导致菜单栏失灵、无法退出；
/// - 需要辅助功能权限才能收到其他进程（Dock）的事件；
/// - **身份判定 = 「点击的是应用图标」+「点击前后台应用一致」**，而不是比对
///   Dock 图标的 URL/标题/pid：少数应用（如小红书）的 Dock 图标由与主进程不同
///   的 bundle 提供（图标名 rednote.app / 前台进程 discover.app），其 AXPID 也
///   拿不到，URL/标题/pid 匹配会全部落空。替代判断：点击 Dock 图标后系统会把
///   该应用带到前台；若点击延迟后前台仍是点击前的应用，说明用户点的是「自己
///   （已在前台）的图标」——收起/还原；若前台被切换成别的应用，则是普通切换。
/// - 匹配成功后延迟 `clickPropagationDelay` 再执行收起——等点击事件先传导给系统，
///   避免与系统的激活逻辑产生竞态；延迟后仍需校验目标应用仍在前台；
/// - **收起/还原的意图在点击瞬间采样**（`AppToggle.dockClickIntent`），而不是在
///   延迟后的现场推断：微信等应用点击 Dock 图标会自行还原主窗口，等到 150ms 后
///   现场已「有可见窗口」，若据现场推断会把用户的还原误判成收起（窗口刚出来又被收起）。
public final class DockClickDetector {

    private static let log = Logger(subsystem: "com.tears.ToggleDock", category: "dock")

    /// 收到点击事件后的主回调（已在主线程）。参数为被点击的前台应用与点击瞬间的意图。
    public var onDockReClick: ((NSRunningApplication, AppToggle.DockClickIntent) -> Void)?

    /// 点击传导延迟（秒）。过小会读到尚未稳定的前台状态，过大则手感拖沓，0.15 为验证过的平衡值。
    static let clickPropagationDelay: TimeInterval = 0.15

    private var globalMonitor: Any?
    private let probeQueue = DispatchQueue(label: "toggledock.dock-probe", qos: .userInteractive)
    /// 同一时刻只允许一个探测在途（探针卡住时避免回调堆积）。主线程访问。
    private var probeInFlight = false

    public init() {}

    public func start() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            self?.handleGlobalMouseDown()
        }
    }

    public func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }

    // MARK: - 检测流程

    private func handleGlobalMouseDown() {
        guard !probeInFlight else { return }
        // 主线程快照：坐标换算 + 前台应用信息（均为本地调用，无 IPC）
        guard let axPoint = AccessibilitySupport.axPoint(fromCocoa: NSEvent.mouseLocation),
              let frontmost = NSWorkspace.shared.frontmostApplication, !frontmost.isTerminated
        else { return }
        let target = TargetInfo(
            name: frontmost.localizedName,
            pid: frontmost.processIdentifier,
            // 主线程快照 Dock 区判定线：避免后台查询 NSScreen
            dockAreaMinY: (NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height ?? 0) - 140
        )
        let mouse = NSEvent.mouseLocation
        Self.log.info("鼠标按下 ax=(\(Int(axPoint.x)),\(Int(axPoint.y))) cocoa=(\(Int(mouse.x)),\(Int(mouse.y))) 前台=\(target.name ?? "?", privacy: .public)")

        probeInFlight = true
        probeQueue.async { [weak self] in
            guard let self else { return }
            defer { DispatchQueue.main.async { self.probeInFlight = false } }

            // 1. 取鼠标处的元素，确认是 Dock 中的应用图标（同步 IPC，已在后台）
            guard let element = AccessibilitySupport.elementAtAXPosition(axPoint) else {
                Self.log.info("未命中: 坐标处无元素")
                return
            }
            guard AccessibilitySupport.subrole(element) == AccessibilitySupport.applicationDockItemSubrole else {
                // 点击落在 Dock 区域却拿不到「应用图标」元素时记录原因（普通窗口点击不刷屏）
                if Self.isInDockArea(axPoint, minY: target.dockAreaMinY) {
                    let subrole = AccessibilitySupport.subrole(element)
                    let role = AccessibilitySupport.copyString(element, "AXRole")
                    Self.log.info("Dock区未识别: 元素 subrole=\(subrole ?? "nil", privacy: .public) role=\(role ?? "nil", privacy: .public)")
                }
                return
            }

            // 2. 命中：立即采样「点击瞬间」的应用状态推断意图（趁系统/应用自身的
            //    恢复动作还没发生），随后回主线程等点击传导完成。
            //    身份判定不比对 dock 图标的 URL/标题/pid（见类注释）：点到应用图标
            //    + 传导后前台仍是该应用，即为「点击自己图标」。
            guard let app = NSRunningApplication(processIdentifier: target.pid), !app.isTerminated else { return }
            let intent = AppToggle.dockClickIntent(of: app)

            // 3. 回主线程：等点击传导完成后二次校验，前台依旧才触发动作
            DispatchQueue.main.async {
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.clickPropagationDelay) { [weak self] in
                    guard self != nil,
                          let frontmostNow = NSWorkspace.shared.frontmostApplication,
                          frontmostNow.processIdentifier == target.pid,
                          let app = NSRunningApplication(processIdentifier: target.pid),
                          !app.isTerminated
                    else {
                        // 前台已被切换（点击的是其他应用图标做普通切换）→ 放弃
                        Self.log.info("放弃触发: \(target.name ?? "?", privacy: .public) 点击后前台已切换")
                        return
                    }
                    Self.log.info("命中 Dock=\(target.name ?? "?", privacy: .public) 意图=\(intent == .collapse ? "收起" : "还原", privacy: .public)")
                    Self.log.info("触发动作: \(target.name ?? "?", privacy: .public)")
                    self?.onDockReClick?(app, intent)
                }
            }
        }
    }

    private struct TargetInfo {
        let name: String?
        let pid: pid_t
        /// 屏幕底部 Dock 区域判定线（AX 坐标系，y ≥ 该值视为 Dock 区）
        let dockAreaMinY: CGFloat
    }

    // MARK: - 诊断辅助

    /// 点击点是否落在屏幕底部 Dock 区域（用于决定失败路径是否打日志，避免点窗口时刷屏）。
    private static func isInDockArea(_ axPoint: CGPoint, minY: CGFloat) -> Bool {
        axPoint.y >= minY
    }
}
