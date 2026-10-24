#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-run}"
case "$MODE" in
    --capture|--stream|--tune|--frontend-probe|--transport-test|--help) exec ./script/build_driver.sh "$@" ;;
esac
APP_PATTERN='(^|/)Antena[.]app/Contents/MacOS/Antena( |$)'
if pgrep -f "$APP_PATTERN" >/dev/null; then
    pkill -TERM -f "$APP_PATTERN"
    for attempt in {1..100}; do
        pgrep -f "$APP_PATTERN" >/dev/null || break
        sleep 0.1
    done
    if pgrep -f "$APP_PATTERN" >/dev/null; then
        echo 'Antena is still closing the capture. Quit it before building again.' >&2
        exit 1
    fi
fi
mkdir -p build
BUILD_SETTINGS=()
if [[ "$PWD" == /Volumes/* ]]; then
    DERIVED_DATA="${ANTENA_DERIVED_DATA:-$PWD/build/Xcode}"
    mkdir -p "$PWD/build/tmp" "$PWD/build/XcodeHome"
    export TMPDIR="$PWD/build/tmp"
    # ExFAT adds AppleDouble sidecars when signing. Sign the staged APFS copy.
    BUILD_SETTINGS+=(CODE_SIGNING_ALLOWED=NO)
    CFFIXED_USER_HOME="$PWD/build/XcodeHome" xcodebuild -project Antena.xcodeproj -scheme Antena -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED_DATA" "${BUILD_SETTINGS[@]}" build > build/antena-build.log 2>&1 || { tail -60 build/antena-build.log >&2; exit 1; }
    APP="$(./script/antena_tools.sh stage-app "$DERIVED_DATA/Build/Products/Debug/Antena.app")"
else
    DERIVED_DATA="${ANTENA_DERIVED_DATA:-${TMPDIR:-/tmp}/Antena-DerivedData}"
    xcodebuild -project Antena.xcodeproj -scheme Antena -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED_DATA" build > build/antena-build.log 2>&1 || { tail -60 build/antena-build.log >&2; exit 1; }
    APP="$DERIVED_DATA/Build/Products/Debug/Antena.app"
fi
case "$MODE" in
    run) /usr/bin/open -n "$APP" ;;
    --debug) exec lldb -- "$APP/Contents/MacOS/Antena" ;;
    --logs|--telemetry) /usr/bin/open -n "$APP"; exec /usr/bin/log stream --info --style compact --predicate 'process == "Antena"' ;;
    --verify) /usr/bin/open -n "$APP"; sleep 2; pgrep -f "$APP_PATTERN" >/dev/null ;;
    *) echo "Usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2; exit 64 ;;
esac
