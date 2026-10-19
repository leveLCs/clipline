#!/bin/bash
# Package a local build without publishing, notarizing, or editing a Homebrew tap.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build-app.sh release
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/Clipline.app/Contents/Info.plist)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R build/Clipline.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -ov -srcfolder "$STAGE" -volname Clipline -format UDZO "build/Clipline-$VERSION.dmg"
