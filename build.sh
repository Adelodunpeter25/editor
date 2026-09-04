#!/bin/bash
# Build the Editor app via SwiftPM and bundle it. debug → "Editor Dev.app"; release → "Editor.app".
# Pass the config as $1 (default debug).
set -e
cd "$(dirname "$0")"

CONFIG="${1:-debug}"
VER="${EDITOR_VERSION:-0.1.0}"
ED_PREFIX="${ED_INSTALL_PREFIX:-$HOME/.local}"
ED_BIN_DIR="$ED_PREFIX/bin"
# Optional arch override (e.g. ED_ARCH=x86_64 on an arm64 CI host). Defaults to host arch.
ARCH_FLAGS=""
if [ -n "$ED_ARCH" ]; then ARCH_FLAGS="--arch $ED_ARCH"; fi

if [ "$CONFIG" = "debug" ]; then
  APP="Editor Dev.app"; NAME="Editor Dev"; BID="com.adelodunpeter.editor.dev"; ICNS="AppIconDev.icns"
else
  APP="Editor.app";     NAME="Editor";     BID="com.adelodunpeter.editor";     ICNS="AppIcon.icns"
fi
[ -f "$ICNS" ] || ICNS="AppIcon.icns"

echo "==> swift build ($CONFIG) ${ARCH_FLAGS}"
swift build -c "$CONFIG" $ARCH_FLAGS

# Resolve the actual build output dir (swift build --arch puts it under a triple-named dir).
BIN="$(swift build -c "$CONFIG" $ARCH_FLAGS --show-bin-path)/Editor"
ED_BIN="$(swift build -c "$CONFIG" $ARCH_FLAGS --show-bin-path)/ed"

echo "==> installing ed launcher to $ED_BIN_DIR/ed"
mkdir -p "$ED_BIN_DIR"
cp "$ED_BIN" "$ED_BIN_DIR/ed"
chmod +x "$ED_BIN_DIR/ed"

echo "==> bundling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Editor"
# Bundle the fff dylib next to the executable so @rpath/libfff_c.dylib resolves at runtime
# (LC_ID is @rpath/libfff_c.dylib, LC_RPATH is @loader_path). Without this the .app dylds
# at launch on arm64 because Sources/Cfff isn't inside the bundle.
if [ -f "Sources/Cfff/libfff_c.dylib" ]; then
  cp "Sources/Cfff/libfff_c.dylib" "$APP/Contents/MacOS/"
fi

# Copy SwiftPM resource bundles (e.g. Editor_Editor.bundle with the TextMate grammars) into
# Contents/Resources so they stay inside the code signature; GrammarBundle and
# LanguageRegistry resolve them from there. Also copy to the .app root
# (`Bundle.main.bundleURL`) for third-party SPM bundles (e.g. SwiftTerm) whose
# generated `Bundle.module` only checks the app root + baked build path and would
# otherwise `fatalError` in a distributed app (see LanguageRegistry crash fix).
BUILD_DIR="$(swift build -c "$CONFIG" $ARCH_FLAGS --show-bin-path)"
for b in "$BUILD_DIR"/*.bundle; do
  [ -e "$b" ] && cp -R -X "$b" "$APP/Contents/Resources/"
done
for b in "$BUILD_DIR"/*.bundle; do
  [ -e "$b" ] && cp -R -X "$b" "$APP/"
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
  <!-- Register common source, markup, config, script, and data files for Finder's Open With menu. -->
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Source Code and Text</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>CFBundleTypeExtensions</key>
      <array>
        <string>md</string><string>markdown</string><string>txt</string><string>text</string>
        <string>swift</string><string>m</string><string>mm</string><string>h</string><string>c</string><string>cc</string><string>cpp</string><string>cxx</string><string>hpp</string><string>rs</string><string>go</string><string>java</string><string>kt</string><string>kts</string>
        <string>js</string><string>jsx</string><string>ts</string><string>tsx</string><string>mjs</string><string>cjs</string><string>vue</string><string>svelte</string>
        <string>py</string><string>rb</string><string>php</string><string>pl</string><string>lua</string><string>sh</string><string>bash</string><string>zsh</string><string>fish</string><string>sql</string>
        <string>html</string><string>htm</string><string>css</string><string>scss</string><string>sass</string><string>less</string><string>xml</string><string>yaml</string><string>yml</string><string>json</string><string>toml</string><string>ini</string><string>conf</string><string>env</string><string>gitignore</string>
        <string>db</string><string>sqlite</string><string>sqlite3</string>
      </array>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.plain-text</string>
        <string>public.source-code</string>
        <string>public.shell-script</string>
        <string>public.data</string>
      </array>
    </dict>
    <dict>
      <key>CFBundleTypeName</key><string>Folder</string>
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
