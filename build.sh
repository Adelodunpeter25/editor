#!/bin/bash
# Build the Editor app via SwiftPM and bundle it. debug → "Editor Dev.app"; release → "Editor.app".
# Pass the config as $1 (default debug).
set -e
cd "$(dirname "$0")"

CONFIG="${1:-debug}"
VER="${EDITOR_VERSION:-0.1.0}"
ED_PREFIX="${ED_INSTALL_PREFIX:-$HOME/.local}"
ED_BIN_DIR="$ED_PREFIX/bin"

if [ "$CONFIG" = "debug" ]; then
  APP="Editor Dev.app"; NAME="Editor Dev"; BID="com.adelodunpeter.editor.dev"; ICNS="AppIconDev.icns"
else
  APP="Editor.app";     NAME="Editor";     BID="com.adelodunpeter.editor";     ICNS="AppIcon.icns"
fi
[ -f "$ICNS" ] || ICNS="AppIcon.icns"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/Editor"
ED_BIN=".build/$CONFIG/ed"

echo "==> installing ed launcher to $ED_BIN_DIR/ed"
mkdir -p "$ED_BIN_DIR"
cp "$ED_BIN" "$ED_BIN_DIR/ed"
chmod +x "$ED_BIN_DIR/ed"

echo "==> bundling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Editor"

# Copy SwiftPM resource bundles (e.g. Editor_Editor.bundle with the TextMate grammars) into
# Contents/Resources so they stay inside the code signature; GrammarBundle resolves them from there.
for b in ".build/$CONFIG"/*.bundle; do
  [ -e "$b" ] && cp -R -X "$b" "$APP/Contents/Resources/"
done

# Icon
[ -f "$ICNS" ] && cp "$ICNS" "$APP/Contents/Resources/icon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${NAME}</string>
  <key>CFBundleDisplayName</key><string>${NAME}</string>
  <key>CFBundleIdentifier</key><string>${BID}</string>
  <key>CFBundleExecutable</key><string>Editor</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>${VER}</string>
  <key>CFBundleShortVersionString</key><string>${VER}</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.folder</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" 2>/dev/null || echo "  (codesign unavailable; skipping ad-hoc sign)"

echo "==> done: $(pwd)/$APP"
