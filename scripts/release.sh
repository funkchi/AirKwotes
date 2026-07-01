#!/bin/bash
# Cut a GitHub Release for AirKwotes with a packaged .dmg.
#
# Usage: scripts/release.sh 0.2.0
#
# Requires: Xcode command-line tools, `gh` authenticated, and (for notarized
# builds) an Apple Developer ID. The 0.1.x line ships unsigned by default.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:?usage: scripts/release.sh <version, e.g. 0.2.0>}"
APP=AirKwotes
PLIST=Resources/Info.plist
CASK=Casks/airkwotes.rb

echo "==> AirKwotes $VERSION"

# 1) Bump the app version.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 1" "$PLIST"

# 2) Build the .dmg (+ sha256). Override SIGN_IDENTITY once you have a Developer ID.
make release

# 3) Stamp the Homebrew cask with the version + real sha256.
SHA="$(awk '{print $1}' "dist/$APP-$VERSION.dmg.sha256")"
perl -0pi -e "s/^  version .*$/  version \"$VERSION\"/m; s/^  sha256 .*$/  sha256 \"$SHA\"/m" "$CASK"

echo "==> cask $CASK now references v$VERSION ($SHA)"

# 4) Commit, tag, and upload the release.
git add "$PLIST" "$CASK" CHANGELOG.md
git commit -m "Release v$VERSION" || true
git tag -f "v$VERSION"

gh release create "v$VERSION" "dist/$APP-$VERSION.dmg" \
  --title "v$VERSION" --generate-notes

echo "==> Published v$VERSION"
