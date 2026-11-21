#!/bin/sh
# Builds build/SMARTBar.app with swiftc directly (no Xcode project, no DerivedData).
set -eu
cd "$(dirname "$0")"

APP=build/SMARTBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
    -o "$APP/Contents/MacOS/SMARTBar" Sources/*.swift
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
