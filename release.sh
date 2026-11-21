#!/bin/sh
# Builds a universal SMARTBar.app with smartctl bundled, signs it with a Developer ID,
# packs it in a DMG, notarises and staples the DMG, and optionally publishes it as a
# GitHub release.
#
#   ./release.sh 1.0.0             build build/SMARTBar-1.0.0.dmg
#   ./release.sh 1.0.0 --publish   also tag v1.0.0 and create the GitHub release
#
# One-time setup:
#   1. A "Developer ID Application" certificate in the login keychain
#      (Xcode > Settings > Accounts > Manage Certificates).
#   2. Notary credentials saved under the profile name "SMARTBar":
#        xcrun notarytool store-credentials SMARTBar \
#            --apple-id <apple id> --team-id <team id> --password <app-specific password>
#
# SMARTBAR_IDENTITY=- ./release.sh 0.0.0 makes an ad hoc signed, un-notarised DMG for
# checking the packaging. Don't distribute that one: Gatekeeper will block it.
set -eu
cd "$(dirname "$0")"

VERSION=${1:?usage: ./release.sh <version> [--publish]}
PUBLISH=${2:-}
IDENTITY=${SMARTBAR_IDENTITY:-Developer ID Application}
PROFILE=${SMARTBAR_NOTARY_PROFILE:-SMARTBar}

if [ "$IDENTITY" != "-" ] && ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "No \"$IDENTITY\" certificate in the keychain. See the setup notes at the top of this script." >&2
    exit 1
fi
if [ "$PUBLISH" = "--publish" ] && [ -n "$(git status --porcelain)" ]; then
    echo "Working tree has uncommitted changes; commit them before publishing." >&2
    exit 1
fi

OUT=build/release
APP=$OUT/SMARTBar.app
DMG=build/SMARTBar-$VERSION.dmg
rm -rf "$OUT" "$DMG"
mkdir -p "$APP/Contents/MacOS"

for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" -o "$OUT/SMARTBar-$arch" Sources/*.swift
done
lipo -create "$OUT/SMARTBar-arm64" "$OUT/SMARTBar-x86_64" -output "$APP/Contents/MacOS/SMARTBar"
rm "$OUT/SMARTBar-arm64" "$OUT/SMARTBar-x86_64"

cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
    -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "$APP/Contents/Info.plist"

# Bundle smartctl with its licence. It stays a separate GPL program that the app runs.
./vendor-smartctl.sh
SOURCE=$(ls build/vendor/smartmontools-*.tar.gz)
cp build/vendor/smartctl "$APP/Contents/MacOS/smartctl"
mkdir -p "$APP/Contents/Resources/smartmontools"
cp build/vendor/COPYING "$APP/Contents/Resources/smartmontools/COPYING"
cat > "$APP/Contents/Resources/smartmontools/README.txt" <<EOF
SMARTBar.app/Contents/MacOS/smartctl is smartctl from smartmontools
(https://www.smartmontools.org), built without modification from
$(basename "$SOURCE").

smartmontools is licensed under the GNU General Public License, version 2 or
later; see COPYING in this folder. The exact source archive is published with
every SMARTBar release at https://github.com/jameshmcvay/SMARTBar/releases
and the build recipe is vendor-smartctl.sh in the SMARTBar repository.
EOF

# Nested executable first, then the app around it
if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP/Contents/MacOS/smartctl"
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/MacOS/smartctl"
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi

# DMG with the app next to an Applications shortcut, for drag-to-install
mkdir "$OUT/dmg"
cp -R "$APP" "$OUT/dmg/"
ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -quiet -volname "SMARTBar $VERSION" -srcfolder "$OUT/dmg" -format UDZO "$DMG"
rm -rf "$OUT/dmg"

if [ "$IDENTITY" = "-" ]; then
    echo "Built $DMG (ad hoc signed, not notarised)"
    exit 0
fi

codesign --force --timestamp --sign "$IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
echo "Built $DMG (signed, notarised and stapled)"

if [ "$PUBLISH" = "--publish" ]; then
    git tag "v$VERSION"
    git push origin "v$VERSION"
    # The smartmontools source goes up next to the DMG that contains its binary (GPL).
    gh release create "v$VERSION" "$DMG" "$SOURCE" --title "SMARTBar $VERSION" --generate-notes
fi
