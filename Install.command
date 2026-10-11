#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo 'This installer requires an Apple Silicon Mac.'; exit 1
fi
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo 'Install Apple Command Line Tools in the dialog, then run this installer again.'
  xcode-select --install || true
  read -r -p 'Press Return to close.'; exit 1
fi
if [[ ! -d '/Applications/Google Chrome.app' && ! -d "$HOME/Applications/Google Chrome.app" ]]; then
  echo 'Install Google Chrome from https://www.google.com/chrome/ first.'
  read -r -p 'Press Return to close.'; exit 1
fi
app_dir="$HOME/Applications/AI Compare.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos13.0 Sources/main.swift -framework Cocoa -o "$app_dir/Contents/MacOS/AICompare"
cp Sources/adapter.js Sources/send.js "$app_dir/Contents/Resources/"
cp Info.plist "$app_dir/Contents/Info.plist"
codesign --force --sign - --identifier com.aicompare.desktop "$app_dir"
open "$app_dir"
echo "Installed: $app_dir"
