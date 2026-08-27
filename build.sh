#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="NetSpeed"
BUILD_DIR="$PROJECT_DIR/.build"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"

echo "==> Building $APP_NAME (release)..."
swift build -c release --disable-sandbox

BINARY="$BUILD_DIR/release/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

echo "==> Creating app bundle at $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

FONT_FILE="$PROJECT_DIR/Sources/NetSpeed/SF-Compact-Display-Medium.otf"
[ -f "$FONT_FILE" ] || { echo "ERROR: Font file not found at $FONT_FILE"; exit 1; }
cp "$FONT_FILE" "$APP_BUNDLE/Contents/Resources/"

ICON_FILE="$PROJECT_DIR/AppIcon.icns"
[ -f "$ICON_FILE" ] || { echo "ERROR: AppIcon.icns not found at $ICON_FILE"; exit 1; }
cp "$ICON_FILE" "$APP_BUNDLE/Contents/Resources/"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>NetSpeed</string>
    <key>CFBundleIdentifier</key>
    <string>com.claude.netspeed</string>
    <key>CFBundleName</key>
    <string>NetSpeed</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
PLIST

echo "==> Done! App bundle created at $APP_BUNDLE"
echo "==> Drag NetSpeed.app to your Applications folder or run it from here."
if [ "${1:-}" != "--no-open" ]; then
    open "$APP_BUNDLE"
fi
