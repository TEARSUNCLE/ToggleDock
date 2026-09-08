import SwiftUI
import ServiceManagement
import ToggleDockKit

/// 设置窗口：NSWindow + NSHostingView 承载 SwiftUI。
/// 关闭时仅隐藏窗口，不退出应用（应用驻留在菜单栏）。
@MainActor
final class SettingsWindowController {

    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.title = L10n.string("settings.title")
            window.setContentSize(NSSize(width: 440, height: 520))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.title = L10n.string("settings.title")
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - 设置界面

struct SettingsView: View {
    @AppStorage("toggledock.collapseMode") private var collapseModeRaw = Preferences.CollapseMode.minimize.rawValue
    @AppStorage("toggledock.singleAppFocus") private var singleAppFocus = false
    @AppStorage("toggledock.language") private var languageRaw = Preferences.LanguageOption.system.rawValue

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?
    @State private var minimizeToAppEnabled = AppToggle.isMinimizeToApplicationEnabled()
    @State private var accessibilityGranted = AccessibilitySupport.isTrusted()

    private var collapseMode: Binding<Preferences.CollapseMode> {
        Binding(
            get: { Preferences.CollapseMode(rawValue: collapseModeRaw) ?? .minimize },
            set: { collapseModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            // —— 收起方式 ——
            Section {
                Picker(L10n.string("settings.collapseMode"), selection: collapseMode) {
                    Text(L10n.string("settings.mode.minimize")).tag(Preferences.CollapseMode.minimize)
                    Text(L10n.string("settings.mode.hide")).tag(Preferences.CollapseMode.hide)
                }

                if collapseMode.wrappedValue == .minimize && !minimizeToAppEnabled {
                    Label(L10n.string("settings.minimizeHint"), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                    Button(L10n.string("settings.minimizeFix")) {
                        AppToggle.enableMinimizeToApplication { _ in
                            minimizeToAppEnabled = AppToggle.isMinimizeToApplicationEnabled()
                        }
                    }
                }
            } header: {
                Text(L10n.string("settings.section.behavior"))
            }

            // —— 聚焦与登录 ——
            Section {
                Toggle(L10n.string("settings.focus"), isOn: $singleAppFocus)
                Text(L10n.string("settings.focusHint"))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Toggle(L10n.string("settings.launchAtLogin"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        applyLaunchAtLogin(newValue)
                    }
                if let launchAtLoginError {
                    Text(launchAtLoginError).font(.callout).foregroundStyle(.red)
                }
            } header: {
                Text(L10n.string("settings.section.general"))
            }

            // —— 语言 ——
            Section {
                Picker(L10n.string("settings.language"), selection: $languageRaw) {
                    Text(L10n.string("language.system")).tag(Preferences.LanguageOption.system.rawValue)
                    Text(L10n.string("language.zhHans")).tag(Preferences.LanguageOption.zhHans.rawValue)
                    Text(L10n.string("language.en")).tag(Preferences.LanguageOption.en.rawValue)
                }
                .onChange(of: languageRaw) { _, _ in
                    L10n.reload()
                }
            } header: {
                Text(L10n.string("settings.section.language"))
            }

            // —— 权限与更新 ——
            Section {
                HStack {
                    Circle()
                        .fill(accessibilityGranted ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(accessibilityGranted
                         ? L10n.string("settings.accessibility.granted")
                         : L10n.string("settings.accessibility.notGranted"))
                    Spacer()
                    if !accessibilityGranted {
                        Button(L10n.string("settings.openSystemSettings")) {
                            AccessibilitySupport.openAccessibilitySettings()
                        }
                    }
                }
                .task {
                    // 视图存续期间每秒刷新权限状态：用户在系统设置里授权后，这里会自动变绿
                    while !Task.isCancelled {
                        accessibilityGranted = AccessibilitySupport.isTrusted()
                        minimizeToAppEnabled = AppToggle.isMinimizeToApplicationEnabled()
                        try? await Task.sleep(for: .seconds(1))
                    }
                }

                // 「自动检查更新」是 Sparkle 专属能力，无 Sparkle 的构建不显示；
                // 「检查更新」按钮恒显示——无 Sparkle 时走 GitHub 在线检测
                if Updater.shared.usesSparkle {
                    Toggle(L10n.string("settings.autoUpdate"), isOn: Binding(
                        get: { Updater.shared.automaticallyChecksUpdates },
                        set: { Updater.shared.automaticallyChecksUpdates = $0 }
                    ))
                }
                Button(L10n.string("menu.checkUpdates")) {
                    Updater.shared.checkForUpdates()
                }

                HStack {
                    Text(L10n.string("settings.version"))
                    Spacer()
                    Text(appVersionString).foregroundStyle(.secondary)
                }
            } header: {
                Text(L10n.string("settings.section.about"))
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 520)
    }

    // MARK: - 辅助

    private var appVersionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = L10n.string("settings.launchAtLoginFailed")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
