#!/bin/bash
# Build a release binary and wrap it in a proper .app bundle so macOS can
# attribute the Accessibility permission to a stable app identity.
set -e
cd "$(dirname "$0")"

swift build -c release

APP="ListenMark.app"
BIN=".build/release/ListenMark"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ListenMark"
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ListenMark</string>
  <key>CFBundleDisplayName</key><string>ListenMark</string>
  <key>CFBundleIdentifier</key><string>com.listenmark.app</string>
  <key>CFBundleExecutable</key><string>ListenMark</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so the bundle has a stable code identity for TCC.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "✅ Built $APP"
