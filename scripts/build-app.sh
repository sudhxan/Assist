#!/usr/bin/env bash
# Builds build/Assist.app and code-signs it.
# Uses xcodebuild rather than `swift build`: SwiftPM on the command line can't compile
# MLX's Metal kernels. The first build compiles MLX and takes a few minutes.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-Release}"
DERIVED=".build/xcode"
xcodebuild -scheme Assist -destination 'platform=macOS,arch=arm64' -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" -skipPackagePluginValidation -skipMacroValidation -quiet build
BIN_DIR="$DERIVED/Build/Products/$CONFIG"

APP="build/Assist.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Assist" "$APP/Contents/MacOS/Assist"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"; fi
# SwiftPM resource bundles, including MLX's compiled Metal kernels (mlx-swift_Cmlx.bundle).
for bundle in "$BIN_DIR"/*.bundle; do cp -R "$bundle" "$APP/Contents/Resources/"; done

# A stable Apple Development identity keeps microphone / screen-recording grants and the
# Keychain entry valid across rebuilds. Falls back to ad-hoc signing ("-").
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')}"
codesign --force --options runtime --entitlements Resources/Assist.entitlements --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed with ${IDENTITY:-ad-hoc})"
