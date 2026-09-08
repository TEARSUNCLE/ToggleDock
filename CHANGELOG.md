# 更新日志

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)；
提交信息遵循 [Conventional Commits](https://www.conventionalcommits.org/zh-hans/)。

## [Unreleased]

### Added
- 「检查更新」新增在线版本检测（无 Sparkle 的开发构建）：通过 GitHub Releases API 查询最新发布，
  有新版本弹窗提示并提供下载入口，已是最新则明确告知；网络检测失败自动回退打开 GitHub 发布页

### Changed
- 仅支持 Apple Silicon（arm64），不再构建 x86_64；最低系统仍为 macOS 14

### Removed
- 移除「暂停 ToggleDock」总开关（菜单栏与设置里的开关项）：功能恒生效，
  需要停用直接退出应用即可

### Fixed
- 修复小红书等「Dock 图标与主进程分属不同 bundle」的应用无法收起（图标注册名 rednote.app、
  前台进程 discover.app、AXPID 也不可用，URL/标题/pid 匹配全部落空）：
  点击识别不再比对 Dock 图标的身份，改为「点击到应用图标 + 点击传导后前台仍是原应用」
  ——即用户点击的是自己（已在前台）的图标；从其他应用切换过来的点击自动放行，不会误收起
- 修复界面语言为「跟随系统」（默认）时 L10n 无限递归导致的启动即崩溃
- 修复点击无响应应用后主线程被同步 Accessibility 调用挂起（表现为键盘输入失效、菜单栏无法退出）：
  点击探测、收起执行、子进程调用全部移出主线程，并为所有 AX 元素统一设置 1 秒消息超时
- 启动权限引导与「最小化到应用图标」提示不再使用模态弹窗（accessory 应用自激活受限，
  模态窗口会吞掉键盘焦点并阻塞主线程），改为系统授权弹窗 + 菜单栏常驻提示项
- 修复点击菜单栏图标打开菜单时偶发崩溃：原 `menuNeedsUpdate` 中 `removeAllItems` +
  `addItem` 与 AppKit 菜单填充流程竞争，抛 `NSInternalInconsistencyException`
  （"Item to be inserted into menu already is in another menu"）直接 abort。
  现改为预构建完整菜单、需要更新时整体替换 `statusItem.menu`（状态/语言变化只发生在
  菜单已收起的时机，可安全替换）

## [1.0.0] - 2026-09-07

### Added
- 核心：点击前台应用的 Dock 图标收起（最小化 genie 动画 / 隐藏两种方式），再点还原
- 单应用聚焦模式：切换应用时自动收起上一个（多显示器感知）
- 菜单栏应用：启用/暂停、设置、检查更新、退出
- 设置窗口：收起方式、界面语言（默认中文，可切英文/跟随系统）、登录时启动、权限状态
- Sparkle 自动更新（缺失依赖时自动降级为打开 Releases 页面）
- Apple Silicon（arm64）构建脚本，最低支持 macOS 14
- Kit 层纯逻辑单元测试；GitHub Actions CI 与 Release 工作流
