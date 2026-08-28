#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Clippet"
BUNDLE_ID="com.zhaozhanyang.Clippet"
BUILD_DIR="$ROOT/.build"
APP_DIR="$BUILD_DIR/package/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "==> Building release binary"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/${APP_NAME}"
if [[ ! -x "$BIN" ]]; then
  echo "Binary not found: $BIN" >&2
  exit 1
fi

echo "==> Assembling ${APP_NAME}.app"
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BIN" "$MACOS/${APP_NAME}"
chmod +x "$MACOS/${APP_NAME}"

cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHumanReadableCopyright</key>
  <string>© 2026 JamesZhao</string>
</dict>
</plist>
EOF

echo "==> Ad-hoc signing"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_DIR"

echo "==> Done: $APP_DIR"
echo "    Install with: cp -R \"$APP_DIR\" /Applications/"
