#!/bin/sh
# Builds a universal smartctl from the unmodified smartmontools release tarball, for
# bundling inside SMARTBar.app. Output goes to build/vendor/:
#   smartctl                      universal binary (arm64 + x86_64, macOS 13+)
#   COPYING                       smartmontools' licence (GPL-2.0-or-later)
#   smartmontools-<version>.tar.gz  the exact source, shipped alongside each release
# The result is cached; delete build/vendor to rebuild.
set -eu
cd "$(dirname "$0")"

VERSION=7.5
URL=https://downloads.sourceforge.net/project/smartmontools/smartmontools/$VERSION/smartmontools-$VERSION.tar.gz
SHA256=690b83ca331378da9ea0d9d61008c4b22dde391387b9bbad7f29387f2595f76e

VENDOR=$PWD/build/vendor
TARBALL=$VENDOR/smartmontools-$VERSION.tar.gz
[ -x "$VENDOR/smartctl" ] && [ -f "$TARBALL" ] && exit 0

mkdir -p "$VENDOR"
[ -f "$TARBALL" ] || curl -fsSL -o "$TARBALL" "$URL"
if [ "$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)" != "$SHA256" ]; then
    echo "Checksum mismatch for $TARBALL" >&2
    rm -f "$TARBALL"
    exit 1
fi

SRC=$VENDOR/src
rm -rf "$SRC"
mkdir "$SRC"
tar -xzf "$TARBALL" -C "$SRC" --strip-components 1

for arch in arm64 x86_64; do
    mkdir "$SRC/build-$arch"
    (
        cd "$SRC/build-$arch"
        # No external drive database or updater: the bundled copy uses the one compiled in.
        ../configure --quiet --host="$arch-apple-darwin" \
            --with-drivedbdir=no --with-update-smart-drivedb=no --without-gnupg \
            CXX="clang++ -arch $arch" CXXFLAGS="-O2 -mmacosx-version-min=13.0" \
            LDFLAGS="-mmacosx-version-min=13.0"
        make -s -j"$(sysctl -n hw.ncpu)" smartctl
    )
done

lipo -create "$SRC/build-arm64/smartctl" "$SRC/build-x86_64/smartctl" -output "$VENDOR/smartctl"
strip -x "$VENDOR/smartctl"
cp "$SRC/COPYING" "$VENDOR/COPYING"
rm -rf "$SRC"
echo "Built $VENDOR/smartctl (smartmontools $VERSION)"
