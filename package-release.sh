#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

VERSION="${VERSION:-0.3.2}"
BUILD="${BUILD:-32}"
ARCH="${ARCH:-arm64}"
IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Zhi Tang (LB8ZBRDP63)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-myskills-notary}"
NOTARY_KEYCHAIN="${NOTARY_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

package_one() {
  local flavor="$1"
  local app_name app_path prefix dmg zip checksum root note_prefix app_notary dmg_notary label

  if [ "$flavor" = "international" ]; then
    app_name="Dob International"
    app_path="Dob International.app"
    prefix="Dob-International"
    checksum="release/checksums-international-${VERSION}-${ARCH}.txt"
    root="release/dmg-root-international"
    note_prefix="international-"
    label="Dob International"
  else
    app_name="Dob"
    app_path="Dob.app"
    prefix="Dob"
    checksum="release/checksums-${VERSION}-${ARCH}.txt"
    root="release/dmg-root"
    note_prefix=""
    label="Dob"
  fi

  dmg="release/${prefix}-${VERSION}-${ARCH}.dmg"
  zip="release/${prefix}-${VERSION}-${ARCH}.zip"
  app_notary="release/notary-${note_prefix}app-${VERSION}-${ARCH}.json"
  dmg_notary="release/notary-${note_prefix}dmg-${VERSION}-${ARCH}.json"
  local tmp_notary

  echo "==> Building ${label} ${VERSION}"
  FLAVOR="$flavor" VERSION="$VERSION" BUILD="$BUILD" CODESIGN_IDENTITY="$IDENTITY" ./make-app.sh

  codesign --verify --deep --strict --verbose=2 "$app_path"
  spctl -a -vvv -t exec "$app_path" || true

  rm -f "$zip" "$dmg"
  /usr/bin/ditto -c -k --keepParent "$app_path" "$zip"

  echo "==> Notarizing ${zip}"
  tmp_notary="$(mktemp)"
  xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --keychain "$NOTARY_KEYCHAIN" --wait --output-format json | tee "$tmp_notary"
  mv "$tmp_notary" "$app_notary"
  xcrun stapler staple "$app_path"
  xcrun stapler validate "$app_path"

  rm -f "$zip"
  /usr/bin/ditto -c -k --keepParent "$app_path" "$zip"

  rm -rf "$root"
  mkdir -p "$root"
  cp -R "$app_path" "$root/"
  ln -s /Applications "$root/Applications"
  hdiutil create -volname "$app_name $VERSION" -srcfolder "$root" -ov -format UDZO "$dmg"
  codesign --force --timestamp --sign "$IDENTITY" "$dmg"

  echo "==> Notarizing ${dmg}"
  tmp_notary="$(mktemp)"
  xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --keychain "$NOTARY_KEYCHAIN" --wait --output-format json | tee "$tmp_notary"
  mv "$tmp_notary" "$dmg_notary"
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"

  shasum -a 256 "$dmg" "$zip" > "$checksum"
  echo "==> Wrote ${checksum}"
}

mkdir -p release
package_one zh
package_one international

echo "✅ Packaged ${VERSION}"
