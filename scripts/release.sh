#!/bin/bash
# Makes a public release: a notarized build, the website download, and the Sparkle update feed.
#
#   VERSION=0.2.0 ./scripts/release.sh
#
# Run it on the release Mac. That Mac needs the Developer ID certificate, the "vibemetric-notary"
# profile (see build-app.sh), and the Sparkle private key in the login Keychain. Create the key once:
#   .build/artifacts/sparkle/Sparkle/bin/generate_keys
# and save the public key it prints in Resources/sparkle-public-key.txt (commit that file).
# Back up the private key (generate_keys -x <file>). Without it, installed apps cannot accept updates.
#
# Writes into ../vibemetric-web (override with WEB_DIR):
#   public/download/Vibemetric.dmg      the website's download button
#   public/updates/Vibemetric-<v>.dmg   the copy that Sparkle downloads
#   public/appcast.xml                  the feed that installed apps check
# Optional release notes: public/updates/Vibemetric-<v>.html, written before you run this script.
# Then commit and deploy vibemetric-web.
#
# Releases always include Pro: Pro/ must be a clone of vibemetric-app/vibemetric-pro with no local
# changes and the same commit as its origin/main.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${VERSION:?Set VERSION, for example: VERSION=0.2.0 ./scripts/release.sh}"
[ -s Resources/sparkle-public-key.txt ] || { echo "Missing Resources/sparkle-public-key.txt (see the comment at the top)" >&2; exit 1; }
# The build number comes from the commit count, so a release must be a committed state.
[ -z "$(git status --porcelain)" ] || { echo "Commit or stash your changes first." >&2; exit 1; }

[ -d Pro/Sources/VibemetricPro ] || { echo "Missing Pro/. Clone it: git clone https://github.com/vibemetric-app/vibemetric-pro.git Pro" >&2; exit 1; }
[ -z "$(git -C Pro status --porcelain)" ] || { echo "Pro/ has local changes. Commit and push them first." >&2; exit 1; }
git -C Pro fetch -q origin
[ "$(git -C Pro rev-parse HEAD)" = "$(git -C Pro rev-parse origin/main)" ] || {
  echo "Pro/ is not at origin/main. Run: git -C Pro checkout main && git -C Pro pull" >&2; exit 1; }
echo "Pro: $(git -C Pro log -1 --format='%h %s')"

VARIANT=prod NOTARIZE=1 PRO_ENABLED=1 ./scripts/build-app.sh

WEB="${WEB_DIR:-../vibemetric-web}"
mkdir -p "$WEB/public/updates" "$WEB/public/download"
cp build/Vibemetric.dmg "$WEB/public/updates/Vibemetric-$VERSION.dmg"
cp build/Vibemetric.dmg "$WEB/public/download/Vibemetric.dmg"

# Signs each update with the private key from the Keychain and lists every DMG in public/updates.
.build/artifacts/sparkle/Sparkle/bin/generate_appcast \
  --download-url-prefix "https://vibemetric.app/updates/" \
  -o "$WEB/public/appcast.xml" \
  "$WEB/public/updates"

# The version and size that the website shows.
SIZE="$(du -m build/Vibemetric.dmg | cut -f1)"
sed -i '' -E "s/version: \"[^\"]*\"/version: \"$VERSION\"/; s/size: \"[^\"]*\"/size: \"$SIZE MB download\"/" "$WEB/app/lib/site.ts"

echo "Released $VERSION (build $(( $(git rev-list --count HEAD) + 100 ))). Now commit and deploy $WEB."
