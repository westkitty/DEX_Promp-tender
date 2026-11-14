#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="DexPromptender.app"
APP_DIR="$DIST_DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
RUNTIME_SRC=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --runtime-dir)
            RUNTIME_SRC="${2:-}"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

echo "[build_app] Building release binary..."
cd "$ROOT_DIR"
swift build -c release

BIN_PATH="$ROOT_DIR/.build/release/DexPromptender"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "Release binary missing at $BIN_PATH" >&2
    exit 1
fi

echo "[build_app] Assembling $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/DexPromptender"
chmod +x "$MACOS_DIR/DexPromptender"

cp "$ROOT_DIR/DexPromptender/Info.plist" "$CONTENTS_DIR/Info.plist"
plutil -lint "$CONTENTS_DIR/Info.plist"

cp "$ROOT_DIR/DexPromptender/Resources/DefaultTemplates.json" "$RESOURCES_DIR/DefaultTemplates.json"
cp "$ROOT_DIR/DexPromptender/Resources/PromptingPlaybooks.md" "$RESOURCES_DIR/PromptingPlaybooks.md"
cp "$ROOT_DIR/DexPromptender/Resources/Assets.xcassets/DexCraftWatermark.imageset/DexCraftWatermark.png" "$RESOURCES_DIR/DexCraftWatermark.png"

# Copy SwiftPM resource bundle(s) if built
for bundle_path in "$ROOT_DIR/.build/release"/*.bundle; do
    if [[ -d "$bundle_path" ]]; then
        cp -R "$bundle_path" "$RESOURCES_DIR/"
    fi
done

# Compile Assets.xcassets with actool when full Xcode is active; otherwise build AppIcon.icns with iconutil
ASSET_DIR="$ROOT_DIR/DexPromptender/Resources/Assets.xcassets"
if xcode-select -p 2>/dev/null | grep -q "Xcode.app"; then
    echo "[build_app] Compiling asset catalog via actool..."
    actool "$ASSET_DIR" \
        --compile "$RESOURCES_DIR" \
        --platform macosx \
        --minimum-deployment-target 13.0 \
        --app-icon AppIcon \
        --output-partial-info-plist "$DIST_DIR/assetcatalog-partial.plist" >/dev/null
    rm -f "$DIST_DIR/assetcatalog-partial.plist"
else
    echo "[build_app] Xcode.app not selected; generating AppIcon.icns via iconutil..."
    TMP_ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$TMP_ICONSET"
    cp "$ASSET_DIR/AppIcon.appiconset"/icon_*.png "$TMP_ICONSET/"
    iconutil -c icns "$TMP_ICONSET" -o "$RESOURCES_DIR/AppIcon.icns"
    rm -rf "$(dirname "$TMP_ICONSET")"
fi

if [[ -n "$RUNTIME_SRC" ]]; then
    if [[ ! -d "$RUNTIME_SRC" ]]; then
        echo "Provided --runtime-dir does not exist: $RUNTIME_SRC" >&2
        exit 1
    fi
    echo "[build_app] Embedding optional local runtime from $RUNTIME_SRC..."
    mkdir -p "$RESOURCES_DIR/EmbeddedTinyRuntime"
    cp -R "$RUNTIME_SRC/." "$RESOURCES_DIR/EmbeddedTinyRuntime/"
fi

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

echo "[build_app] Applying adhoc signature..."
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "[build_app] Built and verified: $APP_DIR"
