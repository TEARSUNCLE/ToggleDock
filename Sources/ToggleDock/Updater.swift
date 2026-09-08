import AppKit
import ToggleDockKit

#if canImport(Sparkle)
import Sparkle
#endif

/// 自动更新封装。
///
/// - 发布构建（build.sh --sign，含 Sparkle）：SPUStandardUpdaterController 完成自动
///   检查、下载、验签与安装；appcast 地址写在 Info.plist 的 SUFeedURL。
/// - 其他构建（开发/本机调试）：点击「检查更新」先请求 GitHub Releases API 在线检测——
///   有新版本弹窗给出下载入口，已是最新明确提示；网络检测失败才回退打开 GitHub 发布页。
@MainActor
final class Updater {

    static let shared = Updater()

    /// GitHub 仓库（"owner/repo"）：在线检测与兜底跳转共用，发布后改这里即可。
    static let repo = "tears/ToggleDock"
    /// 发布页：检测失败时的兜底目标，也是弹窗「前往下载」的最终落点。
    static let releasesURL = URL(string: "https://github.com/\(repo)/releases")!
    private static let latestReleaseAPI = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!

    /// 检测请求进行中：防止连点「检查更新」弹出重复窗口。
    private var checking = false

    #if canImport(Sparkle)
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true,         // 启用 Sparkle 内置的定期自动检查
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    #endif

    /// 构建是否携带 Sparkle（决定设置窗口是否显示「自动检查更新」开关）。
    /// 不带 Sparkle 时「检查更新」同样可点——走 GitHub 在线检测。
    var usesSparkle: Bool {
        #if canImport(Sparkle)
        true
        #else
        false
        #endif
    }

    func checkForUpdates() {
        #if canImport(Sparkle)
        controller.checkForUpdates(nil as Any?)
        #else
        guard !checking else { return }
        checking = true
        Task {
            await checkGitHubForUpdates()
            checking = false
        }
        #endif
    }

    /// Sparkle 的「自动检查更新」开关（仅 Sparkle 构建有意义）。
    var automaticallyChecksUpdates: Bool {
        get {
            #if canImport(Sparkle)
            controller.updater.automaticallyChecksForUpdates
            #else
            false
            #endif
        }
        set {
            #if canImport(Sparkle)
            controller.updater.automaticallyChecksForUpdates = newValue
            #endif
        }
    }

    // MARK: - GitHub 在线检测（无 Sparkle 构建）

    private func checkGitHubForUpdates() async {
        let localText = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        guard let local = Version.triple(from: localText) else {
            openReleases() // 本地版本号读不到，无从比较：发布页兜底
            return
        }
        do {
            let release = try await Self.fetchLatestRelease()
            guard let tag = release.tagName, let remote = Version.triple(from: tag) else {
                openReleases() // 最新 tag 解析不了，不等于「没有更新」：发布页兜底
                return
            }
            if remote > local {
                presentNewVersion(release: release, localVersion: localText)
            } else {
                presentUpToDate(localVersion: localText)
            }
        } catch GitHubError.notFound {
            // 404 = 仓库从未发布过 release：同样视为没有可更新的内容
            presentUpToDate(localVersion: localText)
        } catch {
            openReleases() // 网络失败/限流/超时等：发布页兜底
        }
    }

    private func presentNewVersion(release: GitHubRelease, localVersion: String) {
        let notes = release.body.map { Self.preview($0) } ?? ""
        showAlert(
            title: String(format: L10n.string("updater.found.title"), release.tagName ?? "?"),
            message: String(format: L10n.string("updater.found.message"), localVersion, notes),
            buttons: [L10n.string("updater.found.download"), L10n.string("updater.found.later")]
        ) { choice in
            if choice == 0 {
                NSWorkspace.shared.open(release.htmlURL ?? Self.releasesURL)
            }
        }
    }

    private func presentUpToDate(localVersion: String) {
        showAlert(
            title: L10n.string("updater.upToDate.title"),
            message: String(format: L10n.string("updater.upToDate.message"), localVersion),
            buttons: [L10n.string("updater.upToDate.releasesPage"), L10n.string("updater.upToDate.close")]
        ) { choice in
            if choice == 0 { self.openReleases() }
        }
    }

    private func openReleases() {
        NSWorkspace.shared.open(Self.releasesURL)
    }

    /// 弹窗：菜单栏 accessory 应用必须先激活自己，模态弹窗才不会焦点错乱。
    /// buttons 第一个是默认高亮键；onChoice 收到被点按钮的索引（0 = 第一个）。
    private func showAlert(title: String, message: String, buttons: [String], onChoice: @escaping (Int) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        buttons.forEach { alert.addButton(withTitle: $0) }
        let response = alert.runModal()
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        onChoice(index)
    }

    // MARK: - 网络

    private static func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: latestReleaseAPI, timeoutInterval: 8)
        // GitHub API 要求提供非空 User-Agent，否则 403
        request.setValue(appVersionString, forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        switch http.statusCode {
        case 200:
            return try JSONDecoder().decode(GitHubRelease.self, from: data)
        case 404:
            throw GitHubError.notFound
        default:
            throw GitHubError.httpStatus(http.statusCode)
        }
    }

    private static var appVersionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return "ToggleDock/\(short) (+https://github.com/\(repo))"
    }

    /// release notes 摘要：取前 8 行并截断到 600 字符，避免弹窗塞满全文。
    private static func preview(_ body: String, limit: Int = 600) -> String {
        let head = body.split(separator: "\n", omittingEmptySubsequences: false).prefix(8).joined(separator: "\n")
        return head.count > limit ? String(head.prefix(limit)) + "…" : head
    }

    private enum GitHubError: Error {
        case notFound      // 404：仓库还没有发布过 release
        case httpStatus(Int)
    }

    /// GitHub Releases API「latest」响应的最小字段。
    private struct GitHubRelease: Decodable {
        let tagName: String?
        let htmlURL: URL?
        let body: String?
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body
        }
    }
}