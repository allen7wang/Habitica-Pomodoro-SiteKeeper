#!/bin/bash
set -e

BASE="/Users/allenwang/Library/Mobile Documents/com~apple~CloudDocs/codex_working_space/pomoApp/HabiticaPomodoro"
SRC="$BASE/HabiticaPomodoro"
SDK=$(xcrun --show-sdk-path)

# Build in /tmp to avoid iCloud Drive xattr issues (com.apple.provenance)
OUT="/tmp/hp-release"
rm -rf "$OUT"
mkdir -p "$OUT/HabiticaPomodoro.app/Contents/MacOS"
mkdir -p "$OUT/HabiticaPomodoro.app/Contents/Resources/audio"

cd "$SRC"

# ── 1. Compile universal binary ──
echo "1/5  Compiling universal binary (arm64 + x86_64)..."
swiftc -sdk "$SDK" -target arm64-apple-macos13.0 \
    -emit-executable -o "$OUT/arm64" *.swift 2>&1 | grep -v "Sendable\|warning:" || true
swiftc -sdk "$SDK" -target x86_64-apple-macos13.0 \
    -emit-executable -o "$OUT/x86_64" *.swift 2>&1 | grep -v "Sendable\|warning:" || true
lipo -create -output "$OUT/HabiticaPomodoro" "$OUT/arm64" "$OUT/x86_64"
rm "$OUT/arm64" "$OUT/x86_64"
echo "      ✅ Universal: $(lipo -archs "$OUT/HabiticaPomodoro")"

# ── 2. Assemble .app bundle ──
echo "2/5  Building .app bundle..."
mv "$OUT/HabiticaPomodoro" "$OUT/HabiticaPomodoro.app/Contents/MacOS/HabiticaPomodoro"
cp Info.plist "$OUT/HabiticaPomodoro.app/Contents/Info.plist"
cp audio/* "$OUT/HabiticaPomodoro.app/Contents/Resources/audio/"

# Verify CFBundleExecutable is correct (not $(EXECUTABLE_NAME))
EXEC_VAL=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$OUT/HabiticaPomodoro.app/Contents/Info.plist")
if [ "$EXEC_VAL" != "HabiticaPomodoro" ]; then
    echo "      ⚠️  Fixing CFBundleExecutable: '$EXEC_VAL' → 'HabiticaPomodoro'"
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable HabiticaPomodoro" "$OUT/HabiticaPomodoro.app/Contents/Info.plist"
fi

# ── 3. App icon ──
echo "3/5  Creating app icon..."
ICON_SRC="/Users/allenwang/Library/Mobile Documents/com~apple~CloudDocs/codex_working_space/pomoApp/app/img/icon128.png"
ICONSET="$OUT/HabiticaPomodoro.app/Contents/Resources/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" "512:icon_256x256@2x"; do
    size="${spec%%:*}"; name="${spec##*:}"
    sips -z "$size" "$size" "$ICON_SRC" --out "$ICONSET/$name.png" >/dev/null 2>&1
done
iconutil -c icns "$ICONSET" -o "$OUT/HabiticaPomodoro.app/Contents/Resources/AppIcon.icns" 2>/dev/null || true
rm -rf "$ICONSET"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$OUT/HabiticaPomodoro.app/Contents/Info.plist" 2>/dev/null || true
chmod +x "$OUT/HabiticaPomodoro.app/Contents/MacOS/HabiticaPomodoro"

# ── 4. Ad-hoc code signing ──
# macOS 26+ attaches com.apple.provenance to all files; signing the executable
# first, then the bundle, works around the "detritus not allowed" error.
echo "4/5  Ad-hoc code signing..."
codesign --force --sign - "$OUT/HabiticaPomodoro.app/Contents/MacOS/HabiticaPomodoro" 2>/dev/null
codesign --force --sign - "$OUT/HabiticaPomodoro.app" 2>/dev/null
codesign -dv "$OUT/HabiticaPomodoro.app" 2>&1 | grep -E "Format|Signature"

# ── 5. Build DMG installer ──
echo "5/5  Building DMG installer..."
DMG="$BASE/HabiticaPomodoro-Installer.dmg"
STAGING="/tmp/habitica-pomodoro-dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$OUT/HabiticaPomodoro.app" "$STAGING/HabiticaPomodoro.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "Habitica Pomodoro" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG" 2>&1 | tail -1

rm -rf "$STAGING"

# Also copy app back to iCloud folder for convenience
ditto "$OUT/HabiticaPomodoro.app" "$BASE/HabiticaPomodoro.app"
rm -rf "$OUT"

echo ""
echo "════════════════════════════════════════════"
echo "✅ ALL DONE"
echo ""
echo "  App:  $BASE/HabiticaPomodoro.app"
echo "  DMG:  $DMG"
echo "  Size: $(du -sh "$DMG" | cut -f1)"
echo "  Arch: Universal (arm64 + x86_64)"
echo "════════════════════════════════════════════"
