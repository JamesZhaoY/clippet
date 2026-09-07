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

# Application icon (render from SVG if the .icns is missing)
if [[ ! -f "$ROOT/Assets/Clippet.icns" ]]; then
  echo "==> Clippet.icns not found, generating from SVG"
  bash "$ROOT/Scripts/generate-icons.sh"
fi
cp "$ROOT/Assets/Clippet.icns" "$RESOURCES/Clippet.icns"

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
  <key>CFBundleIconFile</key>
  <string>Clippet</string>
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

# Signing identity. Accessibility permission is bound to the app's designated requirement:
# with an ad-hoc signature that is the binary's hash, so every rebuild loses the grant.
# Any real certificate (Apple Development from Xcode, or a self-signed "Code Signing"
# certificate from Keychain Access) keeps it stable across rebuilds.
pick_identity() {
  if [[ -n "${CLIPPET_SIGN_IDENTITY:-}" ]]; then
    echo "$CLIPPET_SIGN_IDENTITY"
    return
  fi
  local identities
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  local kind
  for kind in "Developer ID Application" "Apple Development" "Mac Developer" "Clippet"; do
    local hash
    hash="$(printf '%s\n' "$identities" | grep -F "\"$kind" | head -n1 | awk '{print $2}')"
    if [[ -n "$hash" ]]; then
      echo "$hash"
      return
    fi
  done
}

IDENTITY="$(pick_identity)"
if [[ -n "$IDENTITY" ]]; then
  echo "==> Signing with identity $IDENTITY"
  codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP_DIR"
else
  echo "==> No code-signing identity found, signing ad-hoc"
  echo "    (Accessibility permission will need re-granting after every rebuild;"
  echo "     create a Code Signing certificate in Keychain Access to avoid that)"
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_DIR"
fi
codesign --verify --deep --strict "$APP_DIR"
echo "    $(codesign -d -r- "$APP_DIR" 2>&1 | grep designated)"

echo "==> Done: $APP_DIR"
echo "    Install with: bash Scripts/install.sh"
