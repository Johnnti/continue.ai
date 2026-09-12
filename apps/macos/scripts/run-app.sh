#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PACKAGE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
REPOSITORY_ROOT="$(cd -- "$PACKAGE_ROOT/../.." && pwd)"

swift build --package-path "$PACKAGE_ROOT" --product ContinueApp
swift build --package-path "$PACKAGE_ROOT" --product ContinueControlExtension

BIN_DIR="$(swift build --package-path "$PACKAGE_ROOT" --show-bin-path)"
USER_CACHE_DIR="$(getconf DARWIN_USER_CACHE_DIR)"
BUNDLE_ROOT="${USER_CACHE_DIR%/}/continue-ai-preview"
APP_BUNDLE="$BUNDLE_ROOT/ContinuePreview.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
CONTROL_BUNDLE="$APP_CONTENTS/PlugIns/ContinueControlExtension.appex"

ensure_local_service() {
    local backend_url="${CONTINUE_BACKEND_URL:-http://localhost:3000}"
    while [[ "$backend_url" == */ ]]; do
        backend_url="${backend_url%/}"
    done
    local status_url="$backend_url/api/record/status"
    local service_host="${CONTINUE_SERVICE_HOST:-127.0.0.1}"
    local service_port="${CONTINUE_SERVICE_PORT:-3000}"
    local service_log="$BUNDLE_ROOT/local-service.log"
    local service_pid="$BUNDLE_ROOT/local-service.pid"
    local service_lock="$BUNDLE_ROOT/local-service.lock"
    local service_plist="$BUNDLE_ROOT/local-service.plist"
    local service_label="ai.continue.preview.local-service"
    local service_domain="gui/$(id -u)"

    # A configured remote backend is managed by its own owner. Do not start a
    # second local Next server that cannot satisfy the native app's URL.
    case "$backend_url" in
        http://localhost:*|http://127.0.0.1:*|http://\[::1\]:*) ;;
        *) return 0 ;;
    esac

    service_is_ready() {
        local response
        if ! response=$(/usr/bin/curl --silent --show-error --fail --location \
            --connect-timeout 1 --max-time 2 \
            --header 'Cache-Control: no-cache' \
            "$status_url" 2>/dev/null); then
            return 1
        fi
        [[ "$response" == *recording* ]]
    }

    wait_for_service() {
        for _ in {1..60}; do
            if service_is_ready; then return 0; fi
            sleep 0.25
        done
        return 1
    }

    pid_is_alive() {
        [[ "$1" == <-> ]] && kill -0 "$1" 2>/dev/null
    }

    service_is_loaded() {
        /bin/launchctl print "$service_domain/$service_label" >/dev/null 2>&1
    }

    configure_service_job() {
        local corepack_bin
        corepack_bin="$(command -v corepack)"

        /usr/bin/plutil -create xml1 "$service_plist"
        /usr/bin/plutil -insert Label -string "$service_label" "$service_plist"
        /usr/bin/plutil -insert ProgramArguments -json '[]' "$service_plist"
        /usr/bin/plutil -insert ProgramArguments.0 -string "$corepack_bin" "$service_plist"
        /usr/bin/plutil -insert ProgramArguments.1 -string pnpm "$service_plist"
        /usr/bin/plutil -insert ProgramArguments.2 -string dev:service "$service_plist"
        /usr/bin/plutil -insert WorkingDirectory -string "$REPOSITORY_ROOT" "$service_plist"
        /usr/bin/plutil -insert RunAtLoad -bool true "$service_plist"
        /usr/bin/plutil -insert KeepAlive -bool true "$service_plist"
        /usr/bin/plutil -insert ProcessType -string Background "$service_plist"
        /usr/bin/plutil -insert StandardOutPath -string "$service_log" "$service_plist"
        /usr/bin/plutil -insert StandardErrorPath -string "$service_log" "$service_plist"
        /usr/bin/plutil -insert EnvironmentVariables -dictionary "$service_plist"
        /usr/bin/plutil -insert EnvironmentVariables.PATH -string "$PATH" "$service_plist"
        /usr/bin/plutil -insert EnvironmentVariables.CONTINUE_SERVICE_HOST -string "$service_host" "$service_plist"
        /usr/bin/plutil -insert EnvironmentVariables.CONTINUE_SERVICE_PORT -string "$service_port" "$service_plist"
    }

    mkdir -p "$BUNDLE_ROOT"

    if service_is_ready; then
        return 0
    fi

    # Prevent two simultaneous launches from both deciding that the route is
    # unavailable while Next is still compiling it. A waiting launcher reuses
    # the process started by the first launcher.
    while ! mkdir "$service_lock" 2>/dev/null; do
        if wait_for_service; then return 0; fi

        # A killed launcher can leave a lock directory behind. Reclaim it only
        # when both its owner and the recorded service process are gone; this
        # avoids starting a duplicate while a detached service is still booting.
        local lock_owner=""
        local stale_service_pid=""
        [[ -f "$service_lock/owner" ]] && lock_owner="$(<"$service_lock/owner")"
        [[ -f "$service_pid" ]] && stale_service_pid="$(<"$service_pid")"
        if ! pid_is_alive "$lock_owner" && ! pid_is_alive "$stale_service_pid" && ! service_is_loaded; then
            rm -f "$service_lock/owner"
            rmdir "$service_lock" 2>/dev/null || true
            continue
        fi

        echo "Continue local service lock is held but the API did not become ready. See: $service_log" >&2
        return 1
    done
    print -r -- "$$" >"$service_lock/owner"
    release_service_lock() {
        rm -f "$service_lock/owner"
        rmdir "$service_lock" 2>/dev/null || true
    }

    if ! configure_service_job; then
        echo "Continue could not prepare the local service job. See: $service_log" >&2
        release_service_lock
        return 1
    fi
    if service_is_loaded; then
        if ! /bin/launchctl kickstart -k "$service_domain/$service_label"; then
            echo "Continue could not restart the local service job. See: $service_log" >&2
            release_service_lock
            return 1
        fi
    else
        if ! /bin/launchctl bootstrap "$service_domain" "$service_plist"; then
            echo "Continue could not register the local service job. See: $service_log" >&2
            release_service_lock
            return 1
        fi
    fi

    if wait_for_service; then
        local launched_pid
        launched_pid="$(/bin/launchctl kickstart -p "$service_domain/$service_label" 2>/dev/null || true)"
        if [[ "$launched_pid" == <-> ]]; then
            print -r -- "$launched_pid" >"$service_pid"
        fi
        release_service_lock
        return 0
    fi

    echo "Continue local service did not become ready. See: $service_log" >&2
    release_service_lock
    return 1
}

mkdir -p "$BUNDLE_ROOT" "$APP_CONTENTS/MacOS" "$CONTROL_BUNDLE/Contents/MacOS"
install -m 755 "$BIN_DIR/ContinueApp" "$APP_CONTENTS/MacOS/ContinueApp"
install -m 755 \
    "$BIN_DIR/ContinueControlExtension" \
    "$CONTROL_BUNDLE/Contents/MacOS/ContinueControlExtension"

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
    'Continue uses the microphone only when you start a voice message.' \
    "$APP_INFO"
plutil -insert NSSpeechRecognitionUsageDescription -string \
    'Continue converts your voice messages into text for the chat.' \
    "$APP_INFO"
plutil -insert NSAppTransportSecurity -dictionary "$APP_INFO"
plutil -insert NSAppTransportSecurity.NSAllowsLocalNetworking -bool true "$APP_INFO"
plutil -insert ContinueMemoryDatabasePath -string \
    "$PACKAGE_ROOT/../../data/memory.sqlite" \
    "$APP_INFO"
plutil -insert ContinueElevenLabsSpeechURL -string \
    "${CONTINUE_ELEVENLABS_SPEECH_URL:-http://localhost:3000/api/voice/speak}" \
    "$APP_INFO"
plutil -insert ContinueChatURL -string \
    "${CONTINUE_CHAT_URL:-http://localhost:3000/api/chat}" \
    "$APP_INFO"
plutil -insert ContinueBackendURL -string \
    "${CONTINUE_BACKEND_URL:-http://localhost:3000}" \
    "$APP_INFO"

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

ensure_local_service

if [[ "${1:-}" != "--no-open" ]]; then
    open "$APP_BUNDLE"
fi

echo "Continue preview: $APP_BUNDLE"
echo "Use the Xcode-signed Continue scheme to test the button in the Control Center gallery."
