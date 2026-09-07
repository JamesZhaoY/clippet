#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Clippet"
BUNDLE_ID="com.zhaozhanyang.Clippet"
BUILD_DIR="$ROOT/.build"

# Version: marketing version from the latest tag (v1.2.3 → 1.2.3, 0.1.0 when untagged),
# build number from the commit count, so every build is identifiable in About.
LATEST_TAG="$(git -C "$ROOT" describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
SHORT_VERSION="${LATEST_TAG#v}"
SHORT_VERSION="${SHORT_VERSION:-0.1.0}"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
GIT_DESCRIBE="$(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null || echo unknown)"
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

echo "==> Assembling ${APP_NAME}.app ${SHORT_VERSION} (${BUILD_NUMBER}, ${GIT_DESCRIBE})"
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
  <string>${SHORT_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>ClippetGitDescribe</key>
  <string>${GIT_DESCRIBE}</string>
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
