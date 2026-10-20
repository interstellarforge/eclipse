#!/bin/sh
# Builds dist/MovieMaker.app (ad-hoc signed). `scripts/bundle.sh dmg` also makes dist/Eclipse.dmg.
# Ad-hoc signing runs on this Mac only; other Macs need a Developer ID signature + notarization (needs Xcode/Apple account).
set -e
cd "$(dirname "$0")/.."
swift build -c release --product MovieMaker
APP=dist/Eclipse.app
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/MovieMaker" "$APP/Contents/MacOS/MovieMaker"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/AppLogo.png "$APP/Contents/Resources/AppLogo.png"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
if [ "$1" = dmg ]; then
    hdiutil create -volname "Eclipse" -srcfolder "$APP" -ov -format UDZO dist/Eclipse.dmg
fi
echo "built $APP"
