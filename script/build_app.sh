#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Targie"
EXECUTABLE_NAME="SimilarVideoFinder"
BUNDLE_ID="local.aaronyu.SimilarVideoFinder"
APP_VERSION="${APP_VERSION:-0.0.0-dev}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
ICON_NAME="AppIcon"

cd "$ROOT_DIR"
export HOME="$ROOT_DIR/.build/home"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/swiftpm-module-cache"
export COPYFILE_DISABLE=1

# BUILD_ARCHS controls which architectures to compile.
#   unset / empty   → host architecture only (fast, used for dev)
#   "universal"     → arm64 + x86_64, merged with lipo
ARCHS="${BUILD_ARCHS:-}"

swift_build() {
  if [ "${DISABLE_SWIFTPM_SANDBOX:-0}" = "1" ]; then
    swift build --disable-sandbox "$@"
  else
    swift build "$@"
  fi
}

if [ "$ARCHS" = "universal" ]; then
  echo "▶ Building universal binary (arm64 + x86_64)..." >&2
  swift_build -c release --arch arm64 --arch x86_64
  BUILD_BINARY="$(swift_build -c release --arch arm64 --arch x86_64 --show-bin-path)/$EXECUTABLE_NAME"
else
  swift_build -c release
  BUILD_BINARY="$(swift_build -c release --show-bin-path)/$EXECUTABLE_NAME"
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BUILD_BINARY" "$CONTENTS/MacOS/$EXECUTABLE_NAME"
chmod +x "$CONTENTS/MacOS/$EXECUTABLE_NAME"

# --- Generate app icon ---------------------------------------------------
# The icon is procedurally rendered from script/generate_icon.swift on every
# build. No binary resources are checked into git; tweaking the icon means
# editing the Swift source and re-running this script.
ICON_BUILD_DIR="$ROOT_DIR/.build/icon"

mkdir -p "$ICON_BUILD_DIR"

# Apple's required iconset sizes (1x and 2x) for .icns.
declare -a ICON_SIZES=(
  "16:icon_16x16.png"
  "32:icon_16x16@2x.png"
  "32:icon_32x32.png"
  "64:icon_32x32@2x.png"
  "128:icon_128x128.png"
  "256:icon_128x128@2x.png"
  "256:icon_256x256.png"
  "512:icon_256x256@2x.png"
  "512:icon_512x512.png"
  "1024:icon_512x512@2x.png"
)

MASTER_PNG="$ICON_BUILD_DIR/icon_1024.png"
ICONSET_DIR="$ICON_BUILD_DIR/$ICON_NAME.iconset"
ICNS_OUTPUT="$CONTENTS/Resources/$ICON_NAME.icns"

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

swift "$ROOT_DIR/script/generate_icon.swift" "$MASTER_PNG" >/dev/null

for entry in "${ICON_SIZES[@]}"; do
  size="${entry%%:*}"
  name="${entry##*:}"
  /usr/bin/sips -z "$size" "$size" "$MASTER_PNG" --out "$ICONSET_DIR/$name" >/dev/null
done

/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$ICNS_OUTPUT"
# -------------------------------------------------------------------------

printf '%s\n' \
  '<?xml version="1.0" encoding="UTF-8"?>' \
  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
  '<plist version="1.0"><dict>' \
  '<key>CFBundleExecutable</key><string>SimilarVideoFinder</string>' \
  '<key>CFBundleIdentifier</key><string>local.aaronyu.SimilarVideoFinder</string>' \
  '<key>CFBundleName</key><string>Targie</string>' \
  '<key>CFBundleDisplayName</key><string>Targie</string>' \
  "<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>" \
  "<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>" \
  '<key>CFBundleIconFile</key><string>AppIcon</string>' \
  '<key>CFBundleIconName</key><string>AppIcon</string>' \
  '<key>CFBundlePackageType</key><string>APPL</string>' \
  '<key>LSMinimumSystemVersion</key><string>14.0</string>' \
  '<key>NSPrincipalClass</key><string>NSApplication</string>' \
  '</dict></plist>' > "$CONTENTS/Info.plist"

xattr -cr "$APP_BUNDLE"
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
plutil -lint "$CONTENTS/Info.plist" >/dev/null
codesign --verify --deep --strict "$APP_BUNDLE"
echo "$APP_BUNDLE"
