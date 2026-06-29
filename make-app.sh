#!/bin/bash
# Build a release binary and wrap it in a proper .app bundle so macOS can
# attribute the Accessibility permission to a stable app identity.
set -e
cd "$(dirname "$0")"

swift build -c release

VERSION="${VERSION:-0.3.10}"
BUILD="${BUILD:-40}"
TIMESTAMP_URL="${TIMESTAMP_URL:-http://timestamp.apple.com/ts01}"
# Single unified build. LMAppFlavor stays "zh" so the in-app updater's
# bundle-flavor self-check keeps matching for already-shipped users.
APP="Dob.app"
BUNDLE_NAME="Dob"
BUNDLE_DISPLAY_NAME="Dob"
BUNDLE_ID="com.listenmark.app"
APP_FLAVOR="zh"
BIN=".build/release/ListenMark"

codesign_with_timestamp() {
  local target="$1"
  local attempt
  for attempt in 1 2 3; do
    if codesign --force --deep --options runtime --timestamp="$TIMESTAMP_URL" --sign "$CODESIGN_IDENTITY" "$target"; then
      return 0
    fi
    echo "codesign timestamp failed for $target; retrying ($attempt/3)..." >&2
    sleep $((attempt * 2))
  done
  codesign --force --deep --options runtime --timestamp="$TIMESTAMP_URL" --sign "$CODESIGN_IDENTITY" "$target"
}

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
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>Dob URL</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>dob</string>
      </array>
    </dict>
  </array>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  codesign_with_timestamp "$APP"
else
  # Ad-hoc sign so the bundle has a stable code identity for TCC in local dev.
  codesign --force --deep --sign - "$APP" 2>/dev/null || true
fi

echo "✅ Built $APP"
