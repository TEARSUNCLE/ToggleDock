import AppKit
import os
import ToggleDockKit

/// 菜单栏图标与下拉菜单。语言/偏好变化时整个菜单重建（比逐项改状态更可靠）。
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    /// 菜单弹出期间不重建（见 buildMenu 注释中的崩溃坑），关闭时若有待办刷新再补做。
    private var menuOpen = false
    /// 授权状态轮询：系统设置里授权/撤销不会发通知，只有定期比对才知道变了。
    /// 授权后 ⚠️ 提示无需重启即消失（「未授权仍提示」的老毛病）。
    private var trustTimer: Timer?
    private var lastTrusted: Bool?

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = Self.makeIcon()
            button.toolTip = "ToggleDock"
        }
        // 直接挂一份完整构建好的菜单。不要再写 NSMenuDelegate.menuNeedsUpdate 重建：
        // 该回调在菜单弹出期间被 AppKit 多次调用，removeAllItems + addItem 与 AppKit 的
        // 填充流程竞争，偶发抛 NSInternalInconsistencyException（"Item to be inserted
        // into menu already is in another menu"）直接 abort。需要更新内容时整体替换菜单。
        item.menu = buildMenu()
        statusItem = item
        lastTrusted = AccessibilitySupport.isTrusted()

        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIfTrustChanged() }
        }
        RunLoop.main.add(timer, forMode: .common)
        trustTimer = timer
    }

    /// 授权状态变化 → 整体替换菜单（菜单处于弹出状态时挂起，关闭后立即补做）。
    private func refreshIfTrustChanged() {
        guard !menuOpen else { return }
        let trusted = AccessibilitySupport.isTrusted()
        guard trusted != lastTrusted else { return }
        lastTrusted = trusted
        let was = trusted ? "已授权" : "未授权"
        Logger(subsystem: "com.tears.ToggleDock", category: "dock")
            .info("授权状态变化→\(was, privacy: .public)，重建菜单")
        refresh()
    }

    // MARK: - NSMenuDelegate（仅用于记录弹出状态，防止弹出中重建）

    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
        refreshIfTrustChanged() // 弹出期间漏掉的变化，关闭后补刷新
    }

    func refresh() {
        // 语言/偏好变化时整体替换菜单（旧菜单此刻已被关闭：偏好只能通过菜单/设置改，
        // 而菜单项点击后菜单即收起，设置窗口与菜单互斥，不会出现替换一个正在弹出的菜单）
        guard let item = statusItem else { return }
        item.menu = buildMenu()
    }

    // MARK: - 图标

    /// SF Symbol 矢量模板图标：自动适配深浅色菜单栏，不用位图资源、体积小。
    private static func makeIcon() -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "ToggleDock")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    // MARK: - 菜单

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self // 记录弹出状态：弹出期间禁止整体替换（见 install 注释）

        if !AccessibilitySupport.isTrusted() {
            // 未授权时给出醒目提示，点击直达系统设置
            let warn = NSMenuItem(title: L10n.string("menu.needPermission"),
                                  action: #selector(openAccessibilitySettings(_:)),
                                  keyEquivalent: "")
            warn.target = self
            warn.attributedTitle = NSAttributedString(
                string: "⚠️ " + L10n.string("menu.needPermission"),
                attributes: [.foregroundColor: NSColor.systemOrange]
            )
            menu.addItem(warn)
        }

        if Preferences.collapseMode == .minimize, !AppToggle.isMinimizeToApplicationEnabled() {
            // 「最小化到应用图标」未开启时给出一键开启入口（取代原模态弹窗，避免焦点黑洞）
            let hint = NSMenuItem(title: L10n.string("minimizeHint.title"),
                                  action: #selector(enableMinimizeToApp(_:)),
                                  keyEquivalent: "")
            hint.target = self
            hint.attributedTitle = NSAttributedString(
                string: "💡 " + L10n.string("minimizeHint.title"),
                attributes: [.foregroundColor: NSColor.systemOrange]
            )
            menu.addItem(hint)
        }

        // ⚠️/💡 条目都是条件出现；一条都没有时（已授权且已开启最小化到图标），
        // 分隔线不能当菜单首项，此时跳过，让「设置」直接开头
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }

        let settings = NSMenuItem(title: L10n.string("menu.settings"),
                                  action: #selector(openSettings(_:)),
                                  keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let checkUpdates = NSMenuItem(title: L10n.string("menu.checkUpdates"),
                                      action: #selector(checkForUpdates(_:)),
                                      keyEquivalent: "")
        checkUpdates.target = self
        // 恒可点：无 Sparkle 的开发构建走 GitHub 在线检测（有新版弹窗，失败才跳发布页）
        menu.addItem(checkUpdates)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: L10n.string("menu.quit"),
                              action: #selector(quit(_:)),
                              keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    // MARK: - 动作

    @objc private func openSettings(_ sender: NSMenuItem) {
        NSApp.activate(ignoringOtherApps: true)
        SettingsWindowController.shared.show()
    }

    @objc private func checkForUpdates(_ sender: NSMenuItem) {
        NSApp.activate(ignoringOtherApps: true)
        Updater.shared.checkForUpdates()
    }

    @objc private func openAccessibilitySettings(_ sender: NSMenuItem) {
        AccessibilitySupport.openAccessibilitySettings()
    }

    @objc private func enableMinimizeToApp(_ sender: NSMenuItem) {
        AppToggle.enableMinimizeToApplication { [weak self] _ in self?.refresh() }
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}
