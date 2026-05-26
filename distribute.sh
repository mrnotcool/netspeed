#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="NetSpeed"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
DIST_DIR="$PROJECT_DIR/dist"

# 先构建
echo "==> 构建 release 版本..."
bash "$PROJECT_DIR/build.sh"

echo ""
echo "==> 创建分发包..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# 方法1: 直接压缩 .app
echo "   打包 NetSpeed.app.zip ..."
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$DIST_DIR/$APP_NAME.zip"

# 方法2: 创建 DMG
echo "   创建 NetSpeed.dmg ..."
DMG_TMP="$DIST_DIR/tmp.dmg"
DMG_FINAL="$DIST_DIR/$APP_NAME.dmg"
hdiutil create -size 64m -fs HFS+ -volname "$APP_NAME" "$DMG_TMP" >/dev/null
DEV=$(hdiutil attach "$DMG_TMP" -nobrowse 2>/dev/null | tail -1 | awk '{print $1}')
if [ -z "$DEV" ] || [ ! -d "/Volumes/$APP_NAME" ]; then
    echo "ERROR: Failed to attach DMG"
    exit 1
fi
cp -R "$APP_BUNDLE" "/Volumes/$APP_NAME/"
hdiutil detach "$DEV" >/dev/null
hdiutil convert "$DMG_TMP" -format UDZO -o "$DMG_FINAL" >/dev/null
rm -f "$DMG_TMP"

echo ""
echo "============================================"
echo "  分发文件已生成:"
echo "    📦 $DIST_DIR/$APP_NAME.zip"
echo "    📀 $DIST_DIR/$APP_NAME.dmg"
echo "============================================"
echo ""

# 提示 Gatekeeper
echo "============================================"
echo "  ⚠️  首次在其他 Mac 运行时的注意事项"
echo "============================================"
echo ""
echo "因为应用没有用 Apple Developer 签名，"
echo "其他 Mac 打开时会提示“无法验证开发者”。"
echo ""
echo "解决方法（任选其一）："
echo ""
echo "  方案 A — 右键打开（最安全）"
echo "    1. 在 Finder 中右键 NetSpeed.app"
echo "    2. 选择“打开”"
echo "    3. 在弹出的对话框中点击“打开”即可"
echo ""
echo "  方案 B — 移除隔离属性（适合分发）"
echo "    在其他 Mac 上打开终端运行:"
echo "    xattr -dr com.apple.quarantine /Applications/NetSpeed.app"
echo ""
echo "  方案 C — 使用你的 Apple Developer 证书签名"
echo "    在 此 Mac 上运行:"
echo "    codesign --force --sign \"你的证书名称\" \\"
echo "      --options runtime \"$APP_BUNDLE\""
echo "    然后重新打包分发"
echo ""
