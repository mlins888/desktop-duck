#!/bin/sh
# Builds DesktopDuck.app in ./build so it can be double-clicked, added to
# /Applications, or set as a login item (System Settings → General → Login Items).
set -e
cd "$(dirname "$0")"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift build -c release

APP=build/DesktopDuck.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/DesktopDuck "$APP/Contents/MacOS/DesktopDuck"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Desktop Duck</string>
    <key>CFBundleIdentifier</key><string>local.desktopduck</string>
    <key>CFBundleExecutable</key><string>DesktopDuck</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
