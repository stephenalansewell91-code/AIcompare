#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
[[ "$(uname -s)" == Darwin ]] || { echo 'A macOS build host is required.'; exit 1; }
app_dir="$PWD/dist/AI Compare.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos13.0 Sources/main.swift -framework Cocoa -o "$app_dir/Contents/MacOS/AICompare"
cp Sources/adapter.js Sources/send.js "$app_dir/Contents/Resources/"
cp Info.plist "$app_dir/Contents/Info.plist"
codesign --force --sign - --identifier com.aicompare.desktop "$app_dir"
codesign --verify --deep --strict "$app_dir"
file "$app_dir/Contents/MacOS/AICompare" | tee dist/architecture.txt
grep -q arm64 dist/architecture.txt
mkdir -p dist/dmg-root
cp -R "$app_dir" dist/dmg-root/
ln -s /Applications dist/dmg-root/Applications
hdiutil create -volname 'AI Compare' -srcfolder dist/dmg-root -ov -format UDZO dist/AICompare-AppleSilicon.dmg
ditto -c -k --sequesterRsrc --keepParent "$app_dir" dist/AICompare-AppleSilicon.zip
