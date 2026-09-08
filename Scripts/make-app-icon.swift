#!/usr/bin/env swift
//
// ToggleDock App 图标生成器
//
// 程序化绘制 macOS 风格 App 图标（深蓝→靛蓝渐变圆角方块 + 白色 Dock 栏与三个应用方块，
// 呼应菜单栏使用的 SF Symbol "dock.rectangle"），并导出 .iconset 所需的全部尺寸 PNG。
//
// 用法：
//   swift Scripts/make-app-icon.swift <输出目录>
//   输出：<输出目录>/AppIcon.iconset/*.png + <输出目录>/AppIcon-preview.png（1024 预览）
//   随后用 iconutil 生成最终 icns：
//     iconutil -c icns <输出目录>/AppIcon.iconset -o Resources/AppIcon.icns
//
// 修改样式后重跑本脚本再重生成 icns 即可（构建产物无需入库）。
//
import AppKit
import Foundation

// MARK: - 调色板（sRGB）

let topBlue = NSColor(srgbRed: 0.039, green: 0.518, blue: 1.0, alpha: 1)     // #0A84FF
let bottomIndigo = NSColor(srgbRed: 0.345, green: 0.337, blue: 0.839, alpha: 1) // #5856D6
let windowBlue = NSColor(srgbRed: 0.0, green: 0.478, blue: 1.0, alpha: 1)    // #007AFF
let white = NSColor.white

// MARK: - 画布上的构图（以 1024 为基准，坐标原点在左下、y 向上）

/// 构图参照微信等主流 App 图标：底板外圈留 ~10% 透明边（避免贴满画布的压迫感），
/// 主体块整体放大加厚、居中偏下，像「站在 Dock 栏上的一组窗口」。
let artInset: CGFloat = 100                          // 底板四边留白 → 实际图形 824×824
let baseRadius: CGFloat = 205                        // 底板圆角半径
/// Dock 栏（白色圆角横条，比两侧方块略宽）
let barRect = NSRect(x: 172, y: 350, width: 680, height: 180)   // y 350…530
let barRadius: CGFloat = 90
/// 三个应用方块（站在 Dock 栏上，中间一块是「带窗口的应用」）
let tileSize: CGFloat = 200
let tileRadius: CGFloat = 40
let tileCenters: [CGFloat] = [292, 512, 732]         // 间距 220，均居中于 512
let tileBottomY: CGFloat = 505                       // 方块底边压入 Dock 栏 25
/// 中间方块的「窗口」内芯
let windowInset: CGFloat = 30
let windowRadius: CGFloat = 32

/// 按画布边长缩放的圆角矩形填充
func fill(_ s: CGFloat, _ rect: NSRect, radius: CGFloat, color: NSColor) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    color.setFill()
    path.fill()
}

/// 渲染一幅指定边长的图标
func render(_ side: Int) -> NSBitmapImageRep? {
    let s = CGFloat(side)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }
    NSGraphicsContext.current = ctx

    let k = s / 1024
    let R = { (v: CGFloat) -> CGFloat in v * k }  // 基准构图按比例缩放

    // 1) 底板：透明圆角外的渐变方块（四边留 artInset 空气，不贴满画布）
    let base = NSBezierPath(roundedRect: NSRect(x: R(artInset), y: R(artInset),
                                                width: s - R(artInset * 2),
                                                height: s - R(artInset * 2)),
                            xRadius: R(baseRadius), yRadius: R(baseRadius))
    let gradient = NSGradient(starting: bottomIndigo, ending: topBlue)!
    gradient.draw(in: base, angle: 90)

    // 2) Dock 栏 + 三个方块（小于 256 时省略细节，避免糊成一团）
    if s >= 256 {
        fill(s, NSRect(x: R(barRect.minX), y: R(barRect.minY),
                       width: R(barRect.width), height: R(barRect.height)),
             radius: R(barRadius), color: white)
    }
    for (index, cx) in tileCenters.enumerated() {
        let tile = NSRect(x: R(cx - tileSize / 2), y: R(tileBottomY),
                          width: R(tileSize), height: R(tileSize))
        fill(s, tile, radius: R(tileRadius), color: white)
        // 中间一块：内嵌蓝色「窗口」，暗示收起/还原的对象
        if index == 1 && s >= 256 {
            let win = NSRect(x: R(cx - tileSize / 2 + windowInset),
                             y: R(tileBottomY + windowInset),
                             width: R(tileSize - windowInset * 2),
                             height: R(tileSize - windowInset * 2))
            fill(s, win, radius: R(windowRadius), color: windowBlue)
        }
    }

    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - 导出

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let fm = FileManager.default
let iconset = "\(outDir)/AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

/// iconset 命名约定：icon_<边长>[_@2x].png
let sizes: [(side: Int, name: String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]

for size in sizes {
    guard let rep = render(size.side),
          let data = rep.representation(using: .png, properties: [:]) else {
        fputs("✗ 渲染失败: \(size.name)\n", stderr)
        exit(1)
    }
    let url = URL(fileURLWithPath: "\(iconset)/\(size.name)")
    do { try data.write(to: url) } catch {
        fputs("✗ 写入失败: \(url.path) \(error)\n", stderr)
        exit(1)
    }
    print("✓ \(size.name) (\(size.side)px)")
}

// 1024 预览图（供人眼校对，不入库）
if let preview = render(1024),
   let data = preview.representation(using: .png, properties: [:]) {
    try? data.write(to: URL(fileURLWithPath: "\(outDir)/AppIcon-preview.png"))
    print("✓ AppIcon-preview.png")
}
print("完成：\(iconset)")
