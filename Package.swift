// swift-tools-version:5.9
import PackageDescription

// ToggleDock —— 让 macOS 程序坞像 Windows 任务栏一样：
// 点击前台应用的 Dock 图标即收起（genie 动画），再次点击还原。
//
// 结构约定（符合 Swift 社区规范）：
//   ToggleDockKit —— 平台无关的核心逻辑（偏好、本地化、AX 收起/还原、点击判定），可单测
//   ToggleDock    —— AppKit/SwiftUI 可执行入口（菜单栏、设置窗口、生命周期）
//
// 本仓库是标准 Swift Package，可直接用 Xcode 打开（File ▸ Open…），
// 也可在仅安装 Command Line Tools 的机器上用 `swift build` 编译；
// 发布产物（.app / Apple Silicon arm64）由根目录 build.sh 组装。
//
// 语言模式：Swift 5（AppKit 尚未全面 Sendable），UI 代码统一标注 @MainActor。
let package = Package(
    name: "ToggleDock",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // Sparkle 自动更新。若网络受限可临时删除此行及下方产品依赖，
        // 代码通过 #if canImport(Sparkle) 自动降级为「打开 Releases 页面」。
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "ToggleDockKit",
            path: "Sources/ToggleDockKit",
            resources: [
                .copy("Resources")
            ]
        ),
        .executableTarget(
            name: "ToggleDock",
            dependencies: [
                "ToggleDockKit",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/ToggleDock"
        ),
        .testTarget(
            name: "ToggleDockTests",
            dependencies: ["ToggleDockKit"],
            path: "ToggleDockTests"
        ),
    ]
)
