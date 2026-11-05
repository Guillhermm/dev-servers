#!/bin/bash
# Build the Linux app and add it to the desktop's application list, for the current user only.
#
#   tools/linux/install.sh
#
# Like the macOS bundle, the binary reads ui/ and registry.json from this repo at run time.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
APP_ID="systems.zenus.DevServers"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"

cd "$REPO"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/DevServersLinux"

mkdir -p "$HOME/.local/bin" "$DATA/applications" "$DATA/icons/hicolor/256x256/apps"
ln -sfn "$BIN" "$HOME/.local/bin/dev-servers"
python3 "$REPO/tools/make_icon.py" --png "$DATA/icons/hicolor/256x256/apps/$APP_ID.png" >/dev/null
sed "s|@BIN@|$BIN|" "$REPO/tools/linux/dev-servers.desktop.in" > "$DATA/applications/$APP_ID.desktop"
update-desktop-database "$DATA/applications" 2>/dev/null || true

echo "built     $BIN"
echo "linked    $HOME/.local/bin/dev-servers"
echo "installed $DATA/applications/$APP_ID.desktop"
