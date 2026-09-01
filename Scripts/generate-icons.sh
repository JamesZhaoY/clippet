#!/usr/bin/env bash
# Renders Assets/AppIcon.svg into an .icns and the 1024px master PNG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SVG="Assets/AppIcon.svg"
BASE="$(mktemp -d /tmp/clippet.XXXXXX)"
ICONSET_DIR="${BASE}.iconset"
mv "$BASE" "$ICONSET_DIR"
trap 'rm -rf "$ICONSET_DIR"' EXIT

# iconutil expects exactly these names in the iconset.
render() {
  local name="$1" size="$2" scale="$3"
  local px=$((size * scale))
  rsvg-convert -w "$px" -h "$px" "$SVG" -o "$ICONSET_DIR/${name}.png"
}
render icon_16x16 16 1
render icon_16x16@2x 16 2
render icon_32x32 32 1
render icon_32x32@2x 32 2
render icon_128x128 128 1
render icon_128x128@2x 128 2
render icon_256x256 256 1
render icon_256x256@2x 256 2
render icon_512x512 512 1
render icon_512x512@2x 512 2

mkdir -p Assets
iconutil -c icns "$ICONSET_DIR" -o Assets/Clippet.icns
# Master 1024px PNG saved next to the source for web/README use.
rsvg-convert -w 1024 -h 1024 "$SVG" -o Assets/AppIcon-1024.png

echo "==> Assets/Clippet.icns"
ls -la Assets/Clippet.icns Assets/AppIcon-1024.png
