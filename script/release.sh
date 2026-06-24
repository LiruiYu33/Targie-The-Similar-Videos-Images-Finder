#!/usr/bin/env bash
# Targie release packager.
#
# Usage:
#   ./script/release.sh <version>      e.g. ./script/release.sh 1.0.0
#
# Produces:
#   dist/release/Targie-v<version>-macos-universal.zip
#   dist/release/Targie-v<version>-macos-universal.zip.sha256
#
# What it does:
#   1. Refuses to run if the working tree is dirty (uncommitted changes).
#   2. Runs the test suite.
#   3. Builds a universal (arm64 + x86_64) release bundle via build_app.sh.
#   4. Verifies the bundle's binary contains both architectures.
#   5. Compresses the .app into a zip with `ditto` (preserves resource forks
#      and macOS metadata, unlike plain `zip`).
#   6. Writes a SHA-256 checksum next to the zip.
#
# After this script finishes, upload the .zip + .sha256 to the GitHub
# Releases page for the matching tag (`v<version>`).
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <version>   (e.g. $0 1.0.0)" >&2
  exit 2
fi

VERSION="$1"
TAG="v$VERSION"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.+-]+)?$ ]]; then
  echo "error: version must look like 1.0.0 or 1.0.0-rc1, got '$VERSION'" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# --- Sanity checks -----------------------------------------------------------

if [ -n "$(git status --porcelain)" ]; then
  echo "error: working tree is dirty. Commit or stash changes first:" >&2
  git status --short >&2
  exit 1
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
echo "▶ Releasing Targie $TAG from branch '$CURRENT_BRANCH' (commit $(git rev-parse --short HEAD))"

# --- Test --------------------------------------------------------------------

echo "▶ Running tests..."
# Unset the sandbox-injected safe.bareRepository=explicit env so SwiftPM can
# reuse its bare-cache repo for GRDB instead of re-fetching (~30s) each run.
env -u GIT_CONFIG_COUNT -u GIT_CONFIG_KEY_0 -u GIT_CONFIG_VALUE_0 swift test

# --- Build -------------------------------------------------------------------

echo "▶ Building universal app bundle..."
APP_BUNDLE="$(APP_VERSION="$VERSION" BUILD_ARCHS=universal "$ROOT_DIR/script/build_app.sh" | tail -1)"

if [ ! -d "$APP_BUNDLE" ]; then
  echo "error: build_app.sh did not produce an .app bundle (got '$APP_BUNDLE')" >&2
  exit 1
fi

# Verify both slices are present in the binary.
EXECUTABLE="$APP_BUNDLE/Contents/MacOS/SimilarVideoFinder"
PLIST="$APP_BUNDLE/Contents/Info.plist"
ARCH_OUT="$(/usr/bin/lipo -archs "$EXECUTABLE")"
echo "▶ Bundle architectures: $ARCH_OUT"
if ! echo "$ARCH_OUT" | grep -q arm64 || ! echo "$ARCH_OUT" | grep -q x86_64; then
  echo "error: expected arm64 + x86_64, got '$ARCH_OUT'" >&2
  exit 1
fi

PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
if [ "$PLIST_VERSION" != "$VERSION" ]; then
  echo "error: expected bundle version '$VERSION', got '$PLIST_VERSION'" >&2
  exit 1
fi

# --- Package -----------------------------------------------------------------

RELEASE_DIR="$ROOT_DIR/dist/release"
mkdir -p "$RELEASE_DIR"

ZIP_NAME="Targie-$TAG-macos-universal.zip"
ZIP_PATH="$RELEASE_DIR/$ZIP_NAME"

rm -f "$ZIP_PATH" "$ZIP_PATH.sha256"

# `ditto` preserves the bundle's HFS+ metadata, signature, and resource
# layout — `zip -r` would corrupt the code signature.
echo "▶ Packaging into $ZIP_NAME..."
/usr/bin/ditto -c -k --keepParent --sequesterRsrc "$APP_BUNDLE" "$ZIP_PATH"

# Re-verify after packaging by extracting to a temp dir.
TMP_VERIFY="$(mktemp -d)"
trap 'rm -rf "$TMP_VERIFY"' EXIT
/usr/bin/ditto -x -k "$ZIP_PATH" "$TMP_VERIFY"
codesign --verify --strict "$TMP_VERIFY/$(basename "$APP_BUNDLE")/Contents/MacOS/SimilarVideoFinder"

# Checksum.
( cd "$RELEASE_DIR" && /usr/bin/shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256" )

ZIP_BYTES=$(stat -f%z "$ZIP_PATH")
ZIP_MB=$(awk "BEGIN { printf \"%.1f\", $ZIP_BYTES / 1024 / 1024 }")

echo ""
echo "✓ Release artifact ready:"
echo "    $ZIP_PATH  (${ZIP_MB} MB)"
echo "    $ZIP_PATH.sha256"
echo ""
echo "Next steps:"
echo "  1. Tag the release commit:    git tag -a $TAG -m 'Targie $TAG'"
echo "  2. Push the tag:              git push origin $TAG"
echo "  3. Open https://github.com/<your-user>/<your-repo>/releases/new"
echo "  4. Pick tag $TAG, attach the .zip and .sha256 above, publish."
