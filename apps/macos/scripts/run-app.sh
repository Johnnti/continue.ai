#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PACKAGE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

swift build --package-path "$PACKAGE_ROOT" --product ContinueApp
swift build --package-path "$PACKAGE_ROOT" --product ContinueControlExtension

BIN_DIR="$(swift build --package-path "$PACKAGE_ROOT" --show-bin-path)"
USER_CACHE_DIR="$(getconf DARWIN_USER_CACHE_DIR)"
BUNDLE_ROOT="${USER_CACHE_DIR%/}/continue-ai-preview"
APP_BUNDLE="$BUNDLE_ROOT/ContinuePreview.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
CONTROL_BUNDLE="$APP_CONTENTS/PlugIns/ContinueControlExtension.appex"
FRAMEWORKS_DIR="$APP_CONTENTS/Frameworks"

rm -rf "$APP_BUNDLE"
mkdir -p \
    "$BUNDLE_ROOT" \
    "$APP_CONTENTS/MacOS" \
    "$CONTROL_BUNDLE/Contents/MacOS" \
    "$FRAMEWORKS_DIR"
install -m 755 "$BIN_DIR/ContinueApp" "$APP_CONTENTS/MacOS/ContinueApp"
install -m 755 \
    "$BIN_DIR/ContinueControlExtension" \
    "$CONTROL_BUNDLE/Contents/MacOS/ContinueControlExtension"

for framework in "$BIN_DIR"/*.framework; do
    if [[ -d "$framework" ]]; then
        ditto "$framework" "$FRAMEWORKS_DIR/$(basename "$framework")"
    fi
done

install_name_tool \
    -add_rpath '@executable_path/../Frameworks' \
    "$APP_CONTENTS/MacOS/ContinueApp"

APP_INFO="$APP_CONTENTS/Info.plist"
plutil -create xml1 "$APP_INFO"
plutil -insert CFBundleDevelopmentRegion -string en "$APP_INFO"
plutil -insert CFBundleDisplayName -string Continue "$APP_INFO"
plutil -insert CFBundleExecutable -string ContinueApp "$APP_INFO"
plutil -insert CFBundleIdentifier -string ai.continue.preview.controlhost "$APP_INFO"
plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$APP_INFO"
plutil -insert CFBundleName -string Continue "$APP_INFO"
plutil -insert CFBundlePackageType -string APPL "$APP_INFO"
plutil -insert CFBundleShortVersionString -string 0.1.0 "$APP_INFO"
plutil -insert CFBundleSupportedPlatforms -json '["MacOSX"]' "$APP_INFO"
plutil -insert CFBundleVersion -string 1 "$APP_INFO"
plutil -insert CFBundleURLTypes -json \
    '[{"CFBundleTypeRole":"Viewer","CFBundleURLName":"ai.continue.preview.controlhost","CFBundleURLSchemes":["continue"]}]' \
    "$APP_INFO"
plutil -insert LSMinimumSystemVersion -string 14.0 "$APP_INFO"
plutil -insert LSUIElement -bool true "$APP_INFO"
plutil -insert NSHighResolutionCapable -bool true "$APP_INFO"
plutil -insert NSMicrophoneUsageDescription -string \
    'Continue uses the microphone only after you start a voice conversation.' \
    "$APP_INFO"
plutil -insert ContinueMemoryDatabasePath -string \
    "$PACKAGE_ROOT/../../data/memory.sqlite" \
    "$APP_INFO"
if [[ -n "${CONTINUE_ELEVENLABS_AGENT_ID:-}" ]]; then
    plutil -insert ContinueElevenLabsAgentID -string \
        "$CONTINUE_ELEVENLABS_AGENT_ID" \
        "$APP_INFO"
fi
if [[ -n "${CONTINUE_ELEVENLABS_TOKEN_URL:-}" ]]; then
    plutil -insert ContinueElevenLabsTokenURL -string \
        "$CONTINUE_ELEVENLABS_TOKEN_URL" \
        "$APP_INFO"
fi

CONTROL_INFO="$CONTROL_BUNDLE/Contents/Info.plist"
plutil -create xml1 "$CONTROL_INFO"
plutil -insert CFBundleDevelopmentRegion -string en "$CONTROL_INFO"
plutil -insert CFBundleDisplayName -string 'Continue Control' "$CONTROL_INFO"
plutil -insert CFBundleExecutable -string ContinueControlExtension "$CONTROL_INFO"
plutil -insert CFBundleIdentifier -string ai.continue.preview.controlhost.control "$CONTROL_INFO"
plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$CONTROL_INFO"
plutil -insert CFBundleName -string ContinueControlExtension "$CONTROL_INFO"
plutil -insert CFBundlePackageType -string XPC! "$CONTROL_INFO"
plutil -insert CFBundleShortVersionString -string 0.1.0 "$CONTROL_INFO"
plutil -insert CFBundleSupportedPlatforms -json '["MacOSX"]' "$CONTROL_INFO"
plutil -insert CFBundleVersion -string 1 "$CONTROL_INFO"
plutil -insert LSMinimumSystemVersion -string 26.0 "$CONTROL_INFO"
plutil -insert NSExtension -dictionary "$CONTROL_INFO"
plutil -insert NSExtension.NSExtensionPointIdentifier \
    -string com.apple.widgetkit-extension \
    "$CONTROL_INFO"

xattr -cr "$APP_BUNDLE"
for framework in "$FRAMEWORKS_DIR"/*.framework; do
    if [[ -d "$framework" ]]; then
        codesign --force --sign - --timestamp=none "$framework"
    fi
done
codesign \
    --force \
    --sign - \
    --timestamp=none \
    --entitlements "$PACKAGE_ROOT/Configuration/ContinueControl.entitlements" \
    "$CONTROL_BUNDLE"
codesign --force --sign - --timestamp=none "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "$APP_BUNDLE"
pluginkit -a "$CONTROL_BUNDLE"

if [[ "${1:-}" != "--no-open" ]]; then
    open "$APP_BUNDLE"
fi

echo "Continue preview: $APP_BUNDLE"
echo "Use the Xcode-signed Continue scheme to test the button in the Control Center gallery."
