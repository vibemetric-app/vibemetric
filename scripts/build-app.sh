#!/bin/bash
# Builds a release Vibemetric.app into build/.
#
# Variants: VARIANT=prod (default) builds "Vibemetric.app" with bundle ID app.vibemetric.prod.
# VARIANT=dev builds "Vibemetric Dev.app" with bundle ID app.vibemetric.dev. The two have separate
# preferences, Keychain item, data folders and privacy answers, and the dev build uses the develop API.
#
# Signing: uses a "Developer ID Application" certificate from the keychain when one is
# installed (or SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"), otherwise ad-hoc.
# A Developer ID signature stays the same across builds, so macOS remembers privacy answers
# (Documents access, notifications) after updates.
#
# Also produces build/Vibemetric.dmg (or "Vibemetric Dev.dmg"): the app plus an Applications shortcut on a branded
# background (dmgbuild, installed into build/.dmgvenv on first use).
#
# Pro: the private Pro module lives in Pro/ (a clone of vibemetric-app/vibemetric-pro, ignored by git).
# PRO_ENABLED defaults to 1 when Pro/ exists and 0 when it doesn't, so builds from the public source have no Pro.
# PRO_ENABLED=1 without Pro/ stops with an error; PRO_ENABLED=0 with Pro/ builds with Pro hidden.
#
# Versions: VERSION is the version users see (default 0.1.0). BUILD is the build number that Sparkle
# compares to find updates; it defaults to the commit count plus 100, so each new commit gives a higher
# number. The 100 keeps numbers above the releases made before the open-source history restarted (up to 95).
#
# Updates (official prod builds only, that is with Pro/): the app gets Sparkle's feed URL and the public key in
# Resources/sparkle-public-key.txt, and checks https://vibemetric.app/appcast.xml for updates. Builds from
# the public source don't check, so they never replace themselves with the official app. See scripts/release.sh.
#
# Notarization (Developer ID builds only): NOTARIZE=1 ./scripts/build-app.sh
# Needs a stored notarytool profile, created once with:
#   xcrun notarytool store-credentials "vibemetric-notary" --apple-id you@example.com --team-id TEAMID
# (override the profile name with NOTARY_PROFILE). Notarizes and staples both the app and the DMG.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-$(( $(git rev-list --count HEAD) + 100 ))}"
case "${VARIANT:-prod}" in
  prod) BUNDLE_ID="app.vibemetric.prod"; APP_NAME="Vibemetric" ;;
  dev)  BUNDLE_ID="app.vibemetric.dev";  APP_NAME="Vibemetric Dev" ;;
  *)    echo "VARIANT must be prod or dev" >&2; exit 1 ;;
esac
HAS_PRO=0; [ -d Pro/Sources/VibemetricPro ] && HAS_PRO=1
PRO_ENABLED="${PRO_ENABLED:-$HAS_PRO}"
if [ "$PRO_ENABLED" = "1" ] && [ "$HAS_PRO" = "0" ]; then
  echo "PRO_ENABLED=1 needs the private Pro module. Clone it first:" >&2
  echo "  git clone https://github.com/vibemetric-app/vibemetric-pro.git Pro" >&2
  exit 1
fi
# SwiftPM caches the manifest's "does Pro/ exist" check, so evaluate it fresh on every build.
SWIFT_BUILD=(swift build --manifest-cache none -c release --product VibemetricApp --arch arm64 --arch x86_64)
"${SWIFT_BUILD[@]}"
BIN_DIR="$("${SWIFT_BUILD[@]}" --show-bin-path)"
# The binary must match the setting: Pro code exactly when Pro/ is present.
PRO_SYMBOLS="$(nm "$BIN_DIR/VibemetricApp" 2>/dev/null | grep -c 's13VibemetricPro' || true)"
if [ "$HAS_PRO" = "1" ] && [ "$PRO_SYMBOLS" = "0" ]; then
  echo "Pro/ exists but the build has no Pro code (stale SwiftPM cache?). Run: swift package reset" >&2
  exit 1
fi
if [ "$HAS_PRO" = "0" ] && [ "$PRO_SYMBOLS" != "0" ]; then
  echo "Pro/ is missing but the build has Pro code (stale build?). Run: swift package reset" >&2
  exit 1
fi
echo "Pro: module $([ "$HAS_PRO" = "1" ] && echo included || echo "not included"), $([ "$PRO_ENABLED" = "1" ] && echo shown || echo hidden)"

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/VibemetricApp" "$APP/Contents/MacOS/Vibemetric"
mkdir -p "$APP/Contents/Frameworks"
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Vibemetric"
cp -R "$BIN_DIR/Vibemetric_VibemetricCore.bundle" "$APP/Contents/Resources/"
cp -R "$BIN_DIR/Vibemetric_VibemetricAppKit.bundle" "$APP/Contents/Resources/"
# App icon. Regenerate from Resources/AppIcon.svg with: swift scripts/make-icon.swift
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>Vibemetric</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>VMProEnabled</key><$([ "$PRO_ENABLED" = "1" ] && echo true || echo false)/>
</dict>
</plist>
PLIST

SPARKLE_KEY_FILE="Resources/sparkle-public-key.txt"
if [ "${VARIANT:-prod}" = "prod" ] && [ "$HAS_PRO" = "1" ] && [ -s "$SPARKLE_KEY_FILE" ]; then
  PLIST_FILE="$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string ${SPARKLE_FEED_URL:-https://vibemetric.app/appcast.xml}" "$PLIST_FILE"
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $(tr -d '[:space:]' < "$SPARKLE_KEY_FILE")" "$PLIST_FILE"
  # Check daily without the "check automatically?" question on the second launch.
  /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool true" "$PLIST_FILE"
else
  echo "Sparkle updates are off in this build (dev variant, no Pro/, or no $SPARKLE_KEY_FILE)."
fi

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
if [ -n "$IDENTITY" ]; then
  # Hardened runtime + secure timestamp are required for notarization. Sign Sparkle's helpers from the
  # inside out (Sparkle's documented order) instead of --deep, which drops the Downloader's entitlements.
  sign() { codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"; }
  FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
  sign "$FW/XPCServices/Installer.xpc"
  sign --preserve-metadata=entitlements "$FW/XPCServices/Downloader.xpc"
  sign "$FW/Autoupdate"
  sign "$FW/Updater.app"
  sign "$APP/Contents/Frameworks/Sparkle.framework"
  sign "$APP"
  codesign --verify --strict --verbose=1 "$APP"
  echo "Signed with: $IDENTITY"
else
  codesign --force --deep --sign - "$APP"
  echo "Signed ad-hoc (no Developer ID certificate found). macOS will re-ask privacy prompts after each rebuild."
fi
echo "Built $APP ($(du -sh "$APP" | cut -f1))"

notarize() {
  xcrun notarytool submit "$1" --keychain-profile "${NOTARY_PROFILE:-vibemetric-notary}" --wait
}

if [ "${NOTARIZE:-0}" = "1" ]; then
  [ -n "$IDENTITY" ] || { echo "NOTARIZE=1 needs a Developer ID signature" >&2; exit 1; }
  # Notarize the app first so the copy inside the DMG carries its own stapled ticket.
  ditto -c -k --keepParent "$APP" build/notarize-app.zip
  notarize build/notarize-app.zip
  rm -f build/notarize-app.zip
  xcrun stapler staple "$APP"
fi

# DMG: app + Applications shortcut on the branded background.
DMG="build/$APP_NAME.dmg"
VENV="build/.dmgvenv"
[ -x "$VENV/bin/dmgbuild" ] || { python3 -m venv "$VENV" && "$VENV/bin/pip" install -q dmgbuild; }
rm -f "$DMG"
"$VENV/bin/dmgbuild" -s scripts/dmg-settings.py -D app="$APP" "$APP_NAME" "$DMG" >/dev/null
if [ -n "$IDENTITY" ]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
fi
if [ "${NOTARIZE:-0}" = "1" ]; then
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi
echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
