#!/bin/bash
# Builds a signed, custom designed installer disk image.
set -e
APP="$1"; OUT="$2"; BG="build/dmg-bg.png"
VOL="Sill"
STAGE="build/dmg-stage"

rm -rf "$STAGE" "$OUT"; mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/Sill.app"
cp "$BG" "$STAGE/.background/bg.png"
ln -s /Applications "$STAGE/Applications"

hdiutil create -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ \
  -format UDRW -ov build/rw.dmg >/dev/null
DEV=$(hdiutil attach -readwrite -noverify -noautoopen build/rw.dmg | egrep '^/dev/' | head -1 | awk '{print $1}')
sleep 2

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 540}
    set vopts to the icon view options of container window
    set arrangement of vopts to not arranged
    set icon size of vopts to 116
    set background picture of vopts to file ".background:bg.png"
    set position of item "Sill.app" of container window to {186, 250}
    set position of item "Applications" of container window to {474, 250}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
APPLESCRIPT

chmod -Rf go-w "/Volumes/$VOL" || true
sync
hdiutil detach "$DEV" >/dev/null
hdiutil convert build/rw.dmg -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
rm -f build/rw.dmg
echo "built $OUT"
