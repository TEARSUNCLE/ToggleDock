<p align="center">
  <b>ToggleDock</b><br>
  让 macOS 程序坞像 Windows 任务栏一样：<b>点击前台应用的 Dock 图标收起，再点还原</b>（genie 动画）。
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/arch-Apple%20Silicon-lightgrey" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
</p>

---

> 中文 | [English](#english)

## 为什么需要它

从 Windows 转过来的用户几乎都会踩这个坑：在 macOS 上点击**已经在前台**的应用的 Dock 图标，什么都不会发生——窗口不会收起。而在 Windows 任务栏上，再点一次按钮窗口就收起来了。

| | Windows 任务栏 | macOS Dock（默认） | macOS Dock + ToggleDock |
|---|---|---|---|
| 点击前台应用的图标 | 收起窗口 | 无反应 | **收起（genie 动画）** ✅ |
| 再点一次 | 还原窗口 | — | **动画还原** ✅ |

ToggleDock 是一个驻留菜单栏的小工具，不占 Dock、不占屏幕，装上即用。

## 功能

- **点击收起 / 再点还原** —— 核心行为，默认「最小化」方式，窗口带 genie 动画吸入自己的 Dock 图标，再点带动画弹出，与 Windows 任务栏手感一致
- **两种收起方式** —— 最小化（带动画，默认）或 隐藏（等同 ⌘H，瞬间完成），设置窗口里随时切换
- **单应用聚焦模式**（可选） —— 切换到另一个应用时自动收起上一个，屏幕上永远只留一个应用；多显示器感知，不影响其他屏幕
- **简体中文 / English** —— 默认中文，可手动切换或跟随系统，切换即时生效
- **登录时启动** —— 使用 `SMAppService` 官方登录项 API
- **自动更新** —— 发布构建内置 [Sparkle](https://sparkle-project.org) 全自动更新；其他构建点击「检查更新」先经 GitHub Releases API 在线检测（弹窗告知新版本/最新状态），网络检测失败时回退打开 GitHub 发布页
- **轻量** —— Swift + AppKit 原生实现，无 Electron / 无解释器，开发构建整个 .app 约 0.7MB（zip 约 0.4MB；含 Sparkle 的发布构建更大）

## 安装

> 系统要求：Apple Silicon（M 系列）Mac，macOS 14 或更高。

1. 从 [Releases](../../releases) 下载 `ToggleDock-1.0.0.dmg`（或 `ToggleDock.zip`），把 `ToggleDock.app` 拖到「应用程序」文件夹
2. 打开它（首次若被 Gatekeeper 拦截：右键应用 → 打开）
3. 按提示授予 **辅助功能** 权限：系统设置 ▸ 隐私与安全性 ▸ 辅助功能 ▸ 打开 ToggleDock 开关
4. 完成。点一下当前应用的 Dock 图标试试

> 需要辅助功能权限的原因：识别「你点的哪个 Dock 图标、它对应哪个前台应用」只能通过 Accessibility API。本应用**不录屏、不联网采集任何数据**。

## 使用

- 点菜单栏图标可打开设置、检查更新、退出
- 设置窗口中可切换：收起方式、语言、单应用聚焦、登录时启动
- 用「最小化」方式时建议开启系统的「将窗口最小化到程序坞中应用图标上」（ToggleDock 会在首次使用时帮你检测并提供一键开启）

## 开发

```
ToggleDock/
├── Package.swift               # Swift Package 清单（可直接用 Xcode 打开）
├── build.sh                    # 零依赖本地构建（只需 Command Line Tools）
├── Sources/
│   ├── ToggleDockKit/          # 核心逻辑（可单测）
│   │   ├── AccessibilitySupport.swift   # AX API 封装、坐标换算
│   │   ├── DockClickDetector.swift      # 全局监听 + Dock 图标识别
│   │   ├── AppToggle.swift              # 最小化/隐藏/还原执行
│   │   ├── SingleAppFocus.swift         # 单应用聚焦（多屏感知）
│   │   ├── Preferences.swift            # 偏好（键统一 toggledock. 前缀）
│   │   ├── L10n.swift                   # 轻量本地化（.strings，即时切换）
│   │   └── Resources/*.lproj/           # zh-Hans / en 文案
│   └── ToggleDock/             # AppKit 入口层
│       ├── main.swift / AppDelegate.swift
│       ├── StatusBarController.swift    # 菜单栏
│       ├── SettingsWindow.swift         # SwiftUI 设置窗口
│       └── Updater.swift                # Sparkle 封装（可降级）
├── ToggleDockTests/            # Kit 层纯逻辑单测
└── Resources/Info.plist        # LSUIElement、Sparkle 配置等
```

两种构建方式等价：

```bash
# 方式 A：SwiftPM（需要正常的 Xcode/CLT 安装）
swift build -c release
swift test

# 方式 B：零依赖脚本（仅 Command Line Tools；产物即发布包，Apple Silicon / arm64）
./build.sh            # 全部特性
```

提交遵循 [Conventional Commits](https://www.conventionalcommits.org/zh-hans/)；版本号遵循语义化版本，更新记录见 [CHANGELOG.md](CHANGELOG.md)。

### 发布（维护者）

1. `git tag v1.0.1 && git push origin v1.0.1` → GitHub Actions 自动构建并附 zip
2. 正式分发建议购买 Apple Developer 账号后：`./build.sh --sign "Developer ID Application: …"` + `xcrun notarytool` 公证
3. 自动更新：用 Sparkle 的 `generate_keys` 生成 EdDSA 密钥对，公钥填入 `Resources/Info.plist` 的 `SUPublicEDKey`，私钥存 CI Secret，Release 工作流用 `generate_appcast` 产出 appcast.xml

## 已知限制

- 需要辅助功能权限，未授权时点击无效果（菜单栏会有橙色提示）
- 开发构建使用仓库内固定的自签证书（`Signing/dev.keychain-db`），签名合法且每次构建不变，
  **重新构建/安装无需重新授权**；若仍遇到「已授权却提示未授权」，可在系统设置中先关闭再打开，
  或 `tccutil reset Accessibility com.tears.ToggleDock` 后重新授权
- 少数非标准 Cocoa 窗口（部分 Electron 应用、游戏）的最小化可能无效
- 暂只内置简体中文与英文；繁体按简体文案回退

## 致谢

交互设计参考了 [Songhoonma/WinDock](https://github.com/Songhoonma/WinDock) 与 [barnuri/win-dock](https://github.com/barnuri/win-dock)，独立实现。

## License

[MIT](LICENSE)

---

<a name="english"></a>

# ToggleDock (English)

Make the macOS Dock behave like the Windows taskbar: **click the frontmost app's Dock icon to collapse its windows (with the genie animation), click again to restore**.

- **Why** — on macOS, re-clicking an active app's Dock icon does nothing; on Windows it minimizes. ToggleDock closes that gap from a tiny menu-bar app (≈1 MB, native Swift + AppKit, no Electron).
- **Collapse styles** — Minimize (genie animation, default) or Hide (⌘H-style, instant).
- **Single-app focus** (optional) — auto-collapses the previous app when you switch; multi-monitor aware.
- **Languages** — 简体中文 by default, switchable to English or follow-system, applied instantly.
- **Login item** via `SMAppService`, **auto updates** via [Sparkle](https://sparkle-project.org).
- **Permissions** — requires Accessibility permission to detect Dock clicks and hide windows. No screen recording, no data collection.

Build: `swift build -c release` (Xcode/SwiftPM) or `./build.sh` (Command Line Tools only, produces an Apple Silicon (arm64) bundle). See the Chinese section above for full layout and release docs.
