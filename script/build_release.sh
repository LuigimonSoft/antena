#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -m)" == arm64 ]] || { echo 'Release builds require Apple Silicon.' >&2; exit 1; }
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
[[ "${SDK_VERSION%%.*}" -ge 27 ]] || { echo 'Xcode with the macOS 27 SDK is required.' >&2; exit 1; }
VERSION="${APP_VERSION:-$(tr -d '[:space:]' < VERSION)}"
if [[ "${GITHUB_REF_TYPE:-}" == tag && -z "${APP_VERSION:-}" ]]; then VERSION="${GITHUB_REF_NAME#v}"; fi
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Version must be major.minor.patch (tags: v1.2.3).' >&2; exit 1; }
BUILD_NUMBER="${APP_BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo 'Build number must be numeric.' >&2; exit 1; }
./script/antena_tools.sh verify-firmware
[[ -f Vendor/VLC/lib/libvlc.dylib ]] || { echo 'Run ./script/bootstrap_vlc.sh first.' >&2; exit 1; }
./script/antena_tools.sh generate-project
DERIVED_DATA="${ANTENA_DERIVED_DATA:-$PWD/build/ReleaseDerivedData}"
mkdir -p build dist
xcodebuild -project Antena.xcodeproj -scheme Antena -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO ENABLE_DEBUG_DYLIB=NO \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    build > build/release-build.log 2>&1 || { tail -60 build/release-build.log >&2; exit 1; }
./script/antena_tools.sh package-dmg "$DERIVED_DATA/Build/Products/Release/Antena.app" \
    > build/release-package.log 2>&1 || { tail -60 build/release-package.log >&2; exit 1; }
(cd dist && shasum -a 256 "Antena-$VERSION-arm64.dmg" > "Antena-$VERSION-arm64.dmg.sha256")
printf 'Release ready: dist/Antena-%s-arm64.dmg\n' "$VERSION"
printf 'Signing: %s\n' "${SIGNING_IDENTITY:-- (ad hoc; not notarized)}"
