#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TOOLS="$PWD/build/tools"
BINARY="$TOOLS/antena-tools"
mkdir -p "$TOOLS/module-cache"
REBUILD=0
[[ -x "$BINARY" ]] || REBUILD=1
for SOURCE in script/Tools/*.swift; do
    [[ "$SOURCE" -nt "$BINARY" ]] && REBUILD=1
done
if [[ "$REBUILD" == 1 ]]; then
    xcrun swiftc -O -module-cache-path "$TOOLS/module-cache" script/Tools/*.swift -o "$BINARY.new"
    mv -f "$BINARY.new" "$BINARY"
fi
exec "$BINARY" "$@"
