#!/bin/bash
# Build "Dev Servers.app" into build/ and link it into ~/Applications.
#
#   tools/macos/build_app.sh
#
# The bundle holds only the binary and the icon. The page and the registry are read
# from the repo at run time, found by resolving the bundle's location.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
APP="$REPO/build/Dev Servers.app"
NAME="Dev Servers"

cd "$REPO"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/DevServersMac" "$APP/Contents/MacOS/$NAME"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>Dev Servers</string>
  <key>CFBundleDisplayName</key>     <string>Dev Servers</string>
  <key>CFBundleIdentifier</key>      <string>systems.zenus.dev-servers</string>
  <key>CFBundleExecutable</key>      <string>Dev Servers</string>
  <key>CFBundleIconFile</key>        <string>icon</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleVersion</key>         <string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key>  <string>13.0</string>
  <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

python3 "$REPO/tools/make_icon.py" >/dev/null

codesign --force --deep -s - "$APP"
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true

mkdir -p "$HOME/Applications"
ln -sfn "$APP" "$HOME/Applications/$NAME.app"

echo "built  $APP"
echo "linked $HOME/Applications/$NAME.app"
