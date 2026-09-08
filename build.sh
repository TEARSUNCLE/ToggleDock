#!/usr/bin/env bash
#
# ToggleDock 本地构建脚本（零依赖：只需 Command Line Tools，不需要 Xcode/SPM）
#
#   ./build.sh            默认：Apple Silicon（arm64）→ 自签开发证书签名 → 组装 .app → zip
#   ./build.sh --sign "-" 显式退回 ad-hoc
#   ./build.sh --sign "Developer ID Application: XXX (TEAMID)"   正式签名（需配合 notarytool 公证）
#
# Sparkle：仅显式 --sign 的发布构建启用（自动更新）；开发构建菜单「检查更新」置灰。
#
set -euo pipefail
cd "$(dirname "$0")"

APP="ToggleDock"
OUT="build"
BUNDLE="$OUT/$APP.app"
MACOS_MIN="14.0"
SDK="$(xcrun --show-sdk-path)"
# —— 签名身份 ——
# 默认(不传 --sign):使用 Signing/dev.keychain-db 里的自签开发证书。
# 证书身份稳定 → 每次重编译产出的代码签名(designated requirement)相同 →
# 系统授权(TCC)只需做一次,之后重编译/重装无需再重新授权。
# 旧的 ad-hoc("-")签名每次编译哈希都变,所以每次都要重新授权。
# 钥匙串密码内嵌仅供本机开发:钥匙串文件放 Signing/(已 gitignore),别把该目录拷给别人。
SIGN_IDENTITY=""                   # 空 = 自动选择开发证书;--sign 显式覆盖
SIGNING_KEYCHAIN="$PWD/Signing/dev.keychain-db"   # security 只认绝对路径
SIGNING_KEYCHAIN_PASS="toggledock-dev"
RELEASE_BUILD=0                    # 仅显式 --sign(发布身份)才编译/嵌入 Sparkle

resolve_signing_identity() {
    if [[ -n "$SIGN_IDENTITY" ]]; then echo "$SIGN_IDENTITY"; return; fi  # --sign 显式指定
    if [[ -f "$SIGNING_KEYCHAIN" ]]; then
        # 构建前解锁(重启后钥匙串会重新锁定,不加这一步 codesign 会卡在密码弹窗)
        security unlock-keychain -p "$SIGNING_KEYCHAIN_PASS" "$SIGNING_KEYCHAIN" >/dev/null 2>&1 || true
        # find-identity 输出形如: 1) 0C93…0210 "ToggleDock Development" → 取第 2 列指纹
        local ident
        ident="$(security find-identity -v -p codesigning "$SIGNING_KEYCHAIN" 2>/dev/null |
                 awk '/^[[:space:]]*[0-9]+\)/ {print $2; exit}')"
        if [[ -n "$ident" ]]; then
            echo "▸ 签名身份: 自签开发证书 ${ident:0:10}…(稳定签名,授权只需一次)" >&2
            echo "$ident"
            return
        fi
        echo "▸ 警告: Signing/ 钥匙串里没有可用证书,退回 ad-hoc" >&2
    fi
    echo "-"
}
SIGN_IDENTITY="$(resolve_signing_identity)"

ARCHS=(arm64)   # 仅支持 Apple Silicon;最低 macOS 14
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign)   SIGN_IDENTITY="$2"; RELEASE_BUILD=1; shift ;;
        *) echo "未知参数: $1" >&2; exit 1 ;;
    esac
    shift
done

SOURCES_KIT=(Sources/ToggleDockKit/*.swift)
SOURCES_APP=(Sources/ToggleDock/*.swift)

rm -rf "$OUT"
mkdir -p "$OUT"

# —— Sparkle 准备 ——
SPARKLE_FRAMEWORK_DIR=""   # 内含 Sparkle.framework 的目录，空 = 不启用
prepare_sparkle() {
    # 只有显式 --sign(发布构建)才编译/嵌入 Sparkle:
    # 开发构建(默认自签证书或 ad-hoc)的 appcast 尚未就绪,点「检查更新」只会请求
    # 不存在的 feed 报错,此时 Updater.isAvailable=false,菜单项自动置灰。
    # Vendor 缓存由脚本自动下载,用完即弃,不入库。
    if [[ "$RELEASE_BUILD" -eq 0 ]]; then
        echo "▸ 开发构建:跳过 Sparkle(「检查更新」置灰;发布请用 --sign 带 Developer ID)"
        return
    fi
    local xc="Vendor/Sparkle.xcframework"
    if [[ ! -d "$xc" ]]; then
        echo "▸ 未发现 Vendor/Sparkle.xcframework，尝试下载…"
        local url="https://github.com/sparkle-project/Sparkle/releases/download/2.9.6/Sparkle-for-Swift-Package-Manager.zip"
        if curl -sfL "$url" -o "$OUT/sparkle.zip" && ditto -x -k "$OUT/sparkle.zip" Vendor/ 2>/dev/null; then
            rm -f "$OUT/sparkle.zip"
            echo "  已下载至 Vendor/"
        else
            rm -f "$OUT/sparkle.zip"
            echo "  ⚠️ 下载失败：本次构建不含自动更新（功能自动降级为打开 Releases 页面）"
            return
        fi
    fi
    local fw
    fw="$(find "$xc" -maxdepth 2 -name Sparkle.framework -type d 2>/dev/null | head -1 || true)"
    if [[ -n "$fw" ]]; then
        SPARKLE_FRAMEWORK_DIR="$(dirname "$fw")"
        echo "▸ Sparkle 已启用: $fw"
    fi
}
prepare_sparkle

# 用普通字符串而非数组：macOS 自带 bash 3.2 下空数组的 ${arr[@]} 展开配合 set -u
# 会报 "unbound variable"。依赖库路径不含空格（仓库内相对路径），直接内插安全。
SPARKLE_CFLAGS=""
if [[ -n "$SPARKLE_FRAMEWORK_DIR" ]]; then
    SPARKLE_CFLAGS="-F $SPARKLE_FRAMEWORK_DIR -framework Sparkle"
fi

BINARIES=()
for arch in "${ARCHS[@]}"; do
    MODDIR="$OUT/$arch"
    mkdir -p "$MODDIR"

    # —— 第一步：Kit 层 → 静态库 + 模块接口 ——
    echo "▸ 编译 ToggleDockKit [$arch]"
    swiftc -O \
        -target "${arch}-apple-macos${MACOS_MIN}" \
        -sdk "$SDK" \
        -module-name "${APP}Kit" -parse-as-library \
        -emit-library -static -o "$MODDIR/lib${APP}Kit.a" \
        -emit-module -emit-module-path "$MODDIR/${APP}Kit.swiftmodule" \
        "${SOURCES_KIT[@]}"

    # —— 第二步：App 层链接 Kit，并把 Info.plist 嵌入 __TEXT,__info_plist ——
    echo "▸ 编译 $APP [$arch]"
    swiftc -O \
        -target "${arch}-apple-macos${MACOS_MIN}" \
        -sdk "$SDK" \
        -I "$MODDIR" -L "$MODDIR" -l"${APP}Kit" \
        -framework Cocoa -framework SwiftUI -framework ServiceManagement \
        ${SPARKLE_CFLAGS} \
        -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
        -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Resources/Info.plist \
        -o "$OUT/$APP-$arch" \
        "${SOURCES_APP[@]}"
    BINARIES+=("$OUT/$APP-$arch")
done

# —— 第三步：lipo 产出最终二进制（当前仅 arm64，保留多架构拼装结构）——
echo "▸ lipo 合并: ${ARCHS[*]}"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
lipo -create "${BINARIES[@]}" -output "$BUNDLE/Contents/MacOS/$APP"

# —— 第四步：组装 bundle 资源 ——
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"
cp -R Sources/ToggleDockKit/Resources/*.lproj "$BUNDLE/Contents/Resources/"
# App 图标（由 Scripts/make-app-icon.swift 生成，改动样式后重新运行 + iconutil 更新）
cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/"

# —— 第五步：嵌入 Sparkle.framework ——
if [[ -n "$SPARKLE_FRAMEWORK_DIR" ]]; then
    mkdir -p "$BUNDLE/Contents/Frameworks"
    ditto "$SPARKLE_FRAMEWORK_DIR/Sparkle.framework" "$BUNDLE/Contents/Frameworks/Sparkle.framework"
fi

# —— 第六步：签名（本地 ad-hoc；正式发布请改用 --sign 并加 --options runtime + entitlements，随后 notarytool 公证）——
echo "▸ codesign（身份: ${SIGN_IDENTITY}）"
if [[ -n "$SPARKLE_FRAMEWORK_DIR" ]]; then
    # 由内向外签：先 XPC/辅助工具，再 framework，最后主程序
    find "$BUNDLE/Contents/Frameworks/Sparkle.framework" \( -name "*.xpc" -o -name "Autoupdate" -o -name "Installer Tool" \) -print0 |
        xargs -0 -I{} codesign --force --options runtime --sign "$SIGN_IDENTITY" {}
    codesign --force --options runtime --sign "$SIGN_IDENTITY" "$BUNDLE/Contents/Frameworks/Sparkle.framework"
fi
codesign --force --sign "$SIGN_IDENTITY" "$BUNDLE"

# —— 第七步：打包 zip ——
# --noextattr：排除 com.apple.provenance 等系统扩展属性（受保护、xattr -c 删不掉），
# 否则 ditto 会把它们编码成 ._* AppleDouble 条目，用 unzip 解压后残留文件会导致
# codesign 校验失败。xattr 不属于签名内容，排除无副作用。
echo "▸ 打包 zip"
( cd "$OUT" && rm -f "$APP.zip" && ditto -c -k --keepParent --norsrc --noextattr --noacl "$APP.app" "$APP.zip" )

echo
echo "✅ 完成：$BUNDLE"
echo "   app 体积: $(du -sh "$BUNDLE" | cut -f1) · zip: $OUT/$APP.zip（$(du -sh "$OUT/$APP.zip" | cut -f1)）"
lipo -info "$BUNDLE/Contents/MacOS/$APP"
