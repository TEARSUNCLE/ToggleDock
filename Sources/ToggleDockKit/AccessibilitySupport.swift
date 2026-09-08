import AppKit
import ApplicationServices

/// Accessibility API 统一封装：属性读写、坐标换算、元素识别。
/// 这是本应用的核心底层能力——需要用户在「系统设置 ▸ 隐私与安全性 ▸ 辅助功能」中授权。
public enum AccessibilitySupport {

    // MARK: - 权限

    /// 是否已获得辅助功能权限；prompt=true 时触发系统授权弹窗。
    public static func isTrusted(prompt: Bool = false) -> Bool {
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    /// 直接打开「辅助功能」设置面板。
    public static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - 属性读写

    /// 统一的消息超时（秒）。系统默认约 6s：目标应用无响应时同步调用会把调用方长时间挂起，
    /// 对「每次点击都要查询」的路径是灾难。1s 足够覆盖正常响应，又保证最坏情况有界。
    static let messagingTimeout: Float = 1.0

    static func copyAttribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return error == .success ? value : nil
    }

    static func copyString(_ element: AXUIElement, _ name: String) -> String? {
        copyAttribute(element, name) as? String
    }

    static func copyBool(_ element: AXUIElement, _ name: String) -> Bool? {
        guard let value = copyAttribute(element, name), CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    @discardableResult
    static func setBool(_ element: AXUIElement, _ name: String, _ value: Bool) -> Bool {
        AXUIElementSetAttributeValue(element, name as CFString, value ? kCFBooleanTrue : kCFBooleanFalse) == .success
    }

    static func copyElementArray(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        guard let value = copyAttribute(element, name) else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    // MARK: - 元素与坐标

    /// Dock 图标的 AX subrole 标识。
    public static let applicationDockItemSubrole = "AXApplicationDockItem"

    /// 屏幕坐标换算：Cocoa 为左下原点，Accessibility 以主屏左上为原点。
    /// 注意：必须用主屏（origin == .zero 的那块），`NSScreen.main` 在多显示器下可能是副屏。
    static func cocoaPointToAX(_ cocoa: CGPoint) -> CGPoint? {
        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) else { return nil }
        return CGPoint(x: cocoa.x, y: primary.frame.maxY - cocoa.y)
    }

    /// AX 全局坐标（左上原点）→ Cocoa 全局坐标（左下原点）。
    static func axPointToCocoa(_ ax: CGPoint) -> CGPoint? {
        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) else { return nil }
        return CGPoint(x: ax.x, y: primary.frame.maxY - ax.y)
    }

    /// Cocoa 全局坐标 → AX 全局坐标（纯计算，可安全在主线程调用）。
    public static func axPoint(fromCocoa cocoaPoint: CGPoint) -> CGPoint? {
        cocoaPointToAX(cocoaPoint)
    }

    /// 按 AX 全局坐标取元素（含同步 IPC，须在后台队列调用）。
    public static func elementAtAXPosition(_ axPoint: CGPoint) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(systemWide, Float(axPoint.x), Float(axPoint.y), &element)
        return error == .success ? element : nil
    }

    /// 应用（进程）的 AX 元素。
    public static func appElement(pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    static func subrole(_ element: AXUIElement) -> String? {
        copyString(element, "AXSubrole")
    }

    // MARK: - 窗口状态

    public static func windows(of appElement: AXUIElement) -> [AXUIElement] {
        let result = copyElementArray(appElement, "AXWindows")
        // 子元素继承连接但超时设置按元素计：统一补齐，防止对无响应窗口卡住
        result.forEach { AXUIElementSetMessagingTimeout($0, messagingTimeout) }
        return result
    }

    static func isMinimized(_ window: AXUIElement) -> Bool {
        copyBool(window, "AXMinimized") ?? false
    }

    static func setMinimized(_ window: AXUIElement, _ value: Bool) {
        setBool(window, "AXMinimized", value)
    }

    static func isHidden(_ appElement: AXUIElement) -> Bool {
        copyBool(appElement, "AXHidden") ?? false
    }

    static func setHidden(_ appElement: AXUIElement, _ value: Bool) {
        setBool(appElement, "AXHidden", value)
    }

    /// 窗口左上角在 Cocoa 全局坐标系中的位置。
    static func cocoaPosition(of window: AXUIElement) -> CGPoint? {
        guard let value = copyAttribute(window, "AXPosition"), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue((value as! AXValue), .cgPoint, &point) else { return nil }
        return axPointToCocoa(point)
    }
}
