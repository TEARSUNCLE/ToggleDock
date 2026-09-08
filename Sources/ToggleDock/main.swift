import AppKit

// 不使用 @main：SPM 可执行目标中带顶层代码的 main.swift 是最直接的启动方式，
// 显式调用 NSApplication.run() 保证 AppKit 生命周期正常启动。
// 顶层代码运行于主线程，但默认非隔离，故用 assumeIsolated 进入 MainActor 上下文。
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
