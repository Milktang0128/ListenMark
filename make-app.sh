#!/bin/bash
# Build a release binary and wrap it in a proper .app bundle so macOS can
# attribute the Accessibility permission to a stable app identity.
set -e
cd "$(dirname "$0")"

swift build -c release

FLAVOR="${FLAVOR:-zh}"
VERSION="${VERSION:-0.3.3}"
BUILD="${BUILD:-33}"
if [ "$FLAVOR" = "en" ] || [ "$FLAVOR" = "international" ]; then
  APP="Dob International.app"
  BUNDLE_NAME="Dob International"
  BUNDLE_DISPLAY_NAME="Dob International"
  BUNDLE_ID="com.listenmark.international"
  APP_FLAVOR="international"
else
  APP="Dob.app"
  BUNDLE_NAME="Dob"
  BUNDLE_DISPLAY_NAME="Dob"
  BUNDLE_ID="com.listenmark.app"
  APP_FLAVOR="zh"
fi
BIN=".build/release/ListenMark"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ListenMark"
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "Resources/DobStatusIcon.png" "$APP/Contents/Resources/DobStatusIcon.png"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$BUNDLE_NAME</string>
  <key>CFBundleDisplayName</key><string>$BUNDLE_DISPLAY_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>ListenMark</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LMAppFlavor</key><string>$APP_FLAVOR</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP"
else
  # Ad-hoc sign so the bundle has a stable code identity for TCC in local dev.
  codesign --force --deep --sign - "$APP" 2>/dev/null || true
fi

echo "✅ Built $APP"
