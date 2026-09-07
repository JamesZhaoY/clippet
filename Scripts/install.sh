#!/usr/bin/env bash
# Installs the packaged app: quits the running copy, replaces the old bundle wholesale
# (never merges into it), refreshes the icon cache and relaunches.
#
#   bash Scripts/install.sh              # into /Applications
#   bash Scripts/install.sh ~/Applications
#   bash Scripts/install.sh -n           # dry run: print what would happen
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Clippet"
SRC="$ROOT/.build/package/${APP_NAME}.app"

DRY_RUN=0
DEST_DIR="/Applications"
for arg in "$@"; do
  case "$arg" in
    -n|--dry-run) DRY_RUN=1 ;;
    *) DEST_DIR="$arg" ;;
  esac
done
DEST="$DEST_DIR/${APP_NAME}.app"

run() {
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "    [dry-run] $*"
  else
    "$@"
  fi
}

if [[ ! -d "$SRC" ]]; then
  echo "==> No packaged app at $SRC, packaging first"
  bash "$ROOT/Scripts/package-app.sh"
fi

if pgrep -xq "$APP_NAME"; then
  echo "==> Quitting running ${APP_NAME}"
  # A regular quit lets the app checkpoint its database; fall back to a signal if the
  # Apple Event is refused (e.g. Automation permission denied for this terminal).
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "    [dry-run] osascript -e 'tell application \"${APP_NAME}\" to quit'  (fallback: pkill -x ${APP_NAME})"
  else
    osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || pkill -x "$APP_NAME" || true
    for _ in $(seq 1 50); do
      pgrep -xq "$APP_NAME" || break
      sleep 0.1
    done
    if pgrep -xq "$APP_NAME"; then
      echo "    still running, sending SIGKILL"
      pkill -9 -x "$APP_NAME" || true
      sleep 0.3
    fi
  fi
fi

echo "==> Installing to $DEST"
# Copying over an existing bundle merges the trees and leaves the running Dock entry with
# a stale icon; replacing the bundle avoids both.
if [[ -d "$DEST" ]]; then
  run rm -rf "$DEST"
fi
run mkdir -p "$DEST_DIR"
run cp -R "$SRC" "$DEST"
# A new bundle mtime makes Finder and the Dock drop their cached icon.
run touch "$DEST"
run /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"

echo "==> Launching"
run open "$DEST"

cat <<EOF
==> Installed $DEST
    If ↩ stops pasting, re-enable ${APP_NAME} once under
    System Settings → Privacy & Security → Accessibility. With a stable signing
    identity (see package-app.sh) that only happens the first time the identity changes.
EOF
