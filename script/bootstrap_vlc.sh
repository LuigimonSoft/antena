#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -m)" != arm64 ]]; then echo 'Este proyecto incluye el motor para Apple Silicon.' >&2; exit 1; fi
ARCHIVE="${TMPDIR:-/tmp}/antena-vlc-3.0.24-arm64.dmg"
MOUNT="${TMPDIR:-/tmp}/antena-vlc-bootstrap-$$"
URL="https://download.videolan.org/pub/videolan/vlc/3.0.24/macosx/vlc-3.0.24-arm64.dmg"
curl --fail --location --show-error "$URL" -o "$ARCHIVE"
echo "64a89d93cdd30b0e97131743e246373db82d6826ea882d265d46d74b136da2b7  $ARCHIVE" | shasum -a 256 -c -
mkdir -p "$MOUNT" Vendor/VLC
hdiutil attach "$ARCHIVE" -nobrowse -readonly -mountpoint "$MOUNT"
trap 'hdiutil detach "$MOUNT" >/dev/null || true' EXIT
for folder in lib plugins include share; do
    ditto "$MOUNT/VLC.app/Contents/MacOS/$folder" "Vendor/VLC/$folder"
done
cp "$MOUNT/VLC.app/Contents/Resources/README" Vendor/VLC/README-VideoLAN.txt
echo 'Motor VideoLAN preparado. Abre Antena.xcodeproj y ejecuta Antena.'
