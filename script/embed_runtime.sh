#!/bin/bash
set -euo pipefail
cd "${SRCROOT:?}"
: "${TARGET_BUILD_DIR:?}" "${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}" "${EXECUTABLE_FOLDER_PATH:?}" "${FRAMEWORKS_FOLDER_PATH:?}"
RUNTIME_SOURCE="${VLC_ROOT:-$SRCROOT/Vendor/VLC}"
if [[ ! -f "$RUNTIME_SOURCE/lib/libvlc.dylib" || ! -f firmware/xc3028-v27.fw ]]; then
    echo 'error: Faltan las dependencias locales. Consulta docs/APP.md.' >&2
    exit 1
fi
RUNTIME_DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/VLC"
# Remove the previous development layout, which was not a framework bundle.
rm -rf "$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH/VLC"
RESOURCE_DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
HELPER_DEST="$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH"
mkdir -p "$RUNTIME_DEST" "$RESOURCE_DEST/firmware" "$HELPER_DEST"
for folder in lib plugins share; do
    /usr/bin/ditto --noextattr --norsrc --noacl "$RUNTIME_SOURCE/$folder" "$RUNTIME_DEST/$folder"
done
cp "$RUNTIME_SOURCE/README-VideoLAN.txt" "$RUNTIME_DEST/README-VideoLAN.txt"
cp LICENSE "$RESOURCE_DEST/LICENSE-GPL-2.0.txt"
cp firmware/PROVENANCE.md "$RESOURCE_DEST/firmware/PROVENANCE.md"
cp firmware/xc3028-v27.fw "$RESOURCE_DEST/firmware/xc3028-v27.fw"
xcrun clang -std=c11 -O2 -Wall -Wextra -Werror -arch arm64 -mmacosx-version-min=27.0 \
    Sources/probe.c Sources/frontend.c Sources/capture.c Sources/transport_stream.c \
    -framework IOKit -framework CoreFoundation -o "$HELPER_DEST/kworld-tv"
/usr/bin/codesign --force --sign - "$HELPER_DEST/kworld-tv"
APP_DEST="$TARGET_BUILD_DIR/$WRAPPER_NAME"
# Strip only presentation metadata rejected by codesign from generated output.
/usr/bin/xattr -dr com.apple.FinderInfo "$APP_DEST" 2>/dev/null || true
/usr/bin/xattr -dr com.apple.ResourceFork "$APP_DEST" 2>/dev/null || true
