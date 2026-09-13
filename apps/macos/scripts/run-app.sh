#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PACKAGE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
REPOSITORY_ROOT="$(cd -- "$PACKAGE_ROOT/../.." && pwd)"
APP_BUNDLE="$PACKAGE_ROOT/.build/Continue.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/ContinueApp"
APP_INFO="$APP_CONTENTS/Info.plist"
BACKEND_URL="${CONTINUE_BACKEND_URL:-http://127.0.0.1:3000}"
AGENT_ID="${ELEVENLABS_AGENT_ID:-}"

if [[ -z "$AGENT_ID" && -f "$REPOSITORY_ROOT/.env" ]]; then
    agent_line="$(/usr/bin/grep -E '^ELEVENLABS_AGENT_ID=' "$REPOSITORY_ROOT/.env" | /usr/bin/tail -n 1 || true)"
    AGENT_ID="${agent_line#ELEVENLABS_AGENT_ID=}"
    AGENT_ID="${AGENT_ID#\"}"
    AGENT_ID="${AGENT_ID%\"}"
    AGENT_ID="${AGENT_ID#\'}"
    AGENT_ID="${AGENT_ID%\'}"
fi

swift build --package-path "$PACKAGE_ROOT" --product ContinueApp
BIN_DIR="$(swift build --package-path "$PACKAGE_ROOT" --show-bin-path)"

mkdir -p "$APP_MACOS" "$APP_FRAMEWORKS" "$APP_RESOURCES"
install -m 755 "$BIN_DIR/ContinueApp" "$APP_BINARY"

for framework_name in RustLiveKitUniFFI LiveKitWebRTC; do
    /usr/bin/ditto \
        "$BIN_DIR/$framework_name.framework" \
        "$APP_FRAMEWORKS/$framework_name.framework"
done

for resource_bundle in \
    ContinueMac_ContinueCore.bundle \
    ElevenLabs_ElevenLabs.bundle \
    LiveKit_LiveKit.bundle \
    SwiftProtobuf_SwiftProtobuf.bundle; do
    if [[ -d "$BIN_DIR/$resource_bundle" ]]; then
        /usr/bin/ditto "$BIN_DIR/$resource_bundle" "$APP_RESOURCES/$resource_bundle"
    fi
done

/usr/bin/install_name_tool -add_rpath @executable_path/../Frameworks "$APP_BINARY"

if [[ ! -f "$APP_INFO" ]]; then
    /usr/bin/plutil -create xml1 "$APP_INFO"
fi

/usr/bin/plutil -replace CFBundleDevelopmentRegion -string en "$APP_INFO"
/usr/bin/plutil -replace CFBundleDisplayName -string Continue "$APP_INFO"
/usr/bin/plutil -replace CFBundleExecutable -string ContinueApp "$APP_INFO"
/usr/bin/plutil -replace CFBundleIdentifier -string ai.continue.preview "$APP_INFO"
/usr/bin/plutil -replace CFBundleInfoDictionaryVersion -string 6.0 "$APP_INFO"
/usr/bin/plutil -replace CFBundleName -string Continue "$APP_INFO"
/usr/bin/plutil -replace CFBundlePackageType -string APPL "$APP_INFO"
/usr/bin/plutil -replace CFBundleShortVersionString -string 0.1.0 "$APP_INFO"
/usr/bin/plutil -replace CFBundleSupportedPlatforms -json '["MacOSX"]' "$APP_INFO"
/usr/bin/plutil -replace CFBundleVersion -string 1 "$APP_INFO"
/usr/bin/plutil -replace LSMinimumSystemVersion -string 14.0 "$APP_INFO"
/usr/bin/plutil -replace NSHighResolutionCapable -bool true "$APP_INFO"
/usr/bin/plutil -replace NSMicrophoneUsageDescription -string "Continue uses the microphone only while you choose to talk with your voice assistant." "$APP_INFO"
/usr/bin/plutil -replace ContinueBackendURL -string "$BACKEND_URL" "$APP_INFO"
/usr/bin/plutil -replace ContinueElevenLabsAgentID -string "$AGENT_ID" "$APP_INFO"
# SwiftPM resource privacy manifests are intentionally read-only. Make the
# copied app bundle owner-writable before removing inherited provenance data;
# otherwise xattr cannot update those files and aborts the launcher.
/bin/chmod -R u+w "$APP_BUNDLE"
/usr/bin/xattr -cr "$APP_BUNDLE"
for framework_name in RustLiveKitUniFFI LiveKitWebRTC; do
    /usr/bin/codesign \
        --force \
        --sign - \
        --timestamp=none \
        "$APP_FRAMEWORKS/$framework_name.framework" >/dev/null
done
/usr/bin/codesign --force --sign - --timestamp=none "$APP_BUNDLE" >/dev/null

existing_pids=()
while read -r pid command; do
    [[ "$command" == "$APP_BINARY" || "$command" == "$APP_BINARY "* ]] || continue
    [[ "$pid" == "$$" ]] && continue
    existing_pids+=("$pid")
    kill "$pid" 2>/dev/null || true
done < <(/bin/ps -axo pid=,command=)

for pid in $existing_pids; do
    for _ in {1..40}; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.05
    done
done

opened=0
for _ in {1..20}; do
    if /usr/bin/open "$APP_BUNDLE" >/dev/null 2>&1; then
        opened=1
        break
    fi
    sleep 0.25
done

if (( ! opened )); then
    print -u2 -- "Continue could not open $APP_BUNDLE"
    exit 1
fi

echo "Continue preview: $APP_BUNDLE"
