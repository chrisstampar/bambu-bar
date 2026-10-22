#!/bin/zsh
# Makes the Mac App Store screenshots (1440×900 PNG, no alpha) from demo runs of the built app.
#   scripts/appstore-screenshots.sh            into build/AppStore/Screenshots (build the app first: scripts/build.sh)
# With the mock fleet running (scripts/fleet/run.sh), the "every printer" shot shows its 12 printers instead of
# the demo's 6. Opens the app's windows for a few seconds per scene; needs Screen Recording permission.
set -euo pipefail

ROOT=${0:A:h:h}
OUT="$ROOT/build/AppStore/Screenshots"
C="$ROOT/build/AppStore/Captures"
BIN="$ROOT/build/App.noindex/Bambu Bar.app/Contents/MacOS/Bambu Bar"
FLEET_CONF="$ROOT/scripts/fleet/out/BambuStudio.conf"
rm -rf "$OUT" "$C"
mkdir -p "$OUT"

"$ROOT/scripts/showcase.sh" "$C" printing failed >/dev/null
PAGE=filament "$ROOT/scripts/showcase.sh" "$C" printing >/dev/null
if [[ -f "$FLEET_CONF" ]] && nc -z 127.0.0.1 18801 2>/dev/null; then
  rm -f "$C/windows.txt"
  "$BIN" --emulator "$FLEET_CONF" --add-all --showcase "$C" --page fleet >/dev/null 2>&1 &
  APP_PID=$!
  for _ in {1..40}; do [[ -f "$C/windows.txt" ]] && break; sleep 0.25; done
  sleep 12  # "Add All" runs once the settings file is read, then every printer connects and reports
  # Front again, so the window is drawn active.
  osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $APP_PID) to true" >/dev/null 2>&1 || true
  sleep 0.5
  screencapture -x -o -l "$(awk '$1 == "main" {print $2}' "$C/windows.txt")" "$C/fleet-main.png"
  pkill -f "$BIN" 2>/dev/null || true
else
  FLEET=1 PAGE=fleet "$ROOT/scripts/showcase.sh" "$C" printing >/dev/null
  cp "$C/printing-main-fleet.png" "$C/fleet-main.png"
fi

# The widget gallery sits on a wallpaper; cut the three widgets out of it.
crop() { sips -c "$4" "$3" --cropOffset "$2" "$1" "$C/printing-widgets.png" --out "$C/widget-$5.png" >/dev/null; }
crop 25 25 168 168 small
crop 213 25 362 168 medium
crop 595 25 362 380 large

compose() { swift "$ROOT/scripts/compose-screenshot.swift" "$@"; }
compose "$OUT/1-menu-bar.png" "Your printer, one click away" \
  "Progress, temperatures and filament live in the menu bar, straight from the printer." \
  "$C/printing-main.png@0.84" "$C/printing-panel.png@1"
compose "$OUT/2-fleet.png" "Every printer at a glance" \
  "Watch a whole print farm at once, and see which printer needs you." \
  "$C/fleet-main.png@0.88"
GAP=30 compose "$OUT/3-widgets.png" "Desktop widgets" \
  "Small, medium and large widgets keep the print in view." \
  "$C/widget-small.png@1.25@22" "$C/widget-medium.png@1.25@22" "$C/widget-large.png@1.25@22"
compose "$OUT/4-filament.png" "Know what's loaded" \
  "AMS trays, colours, remaining filament and humidity for every unit." \
  "$C/printing-main-filament.png@0.88"
compose "$OUT/5-alerts.png" "Catch problems early" \
  "Clear error messages and notifications when a print fails, pauses or finishes." \
  "$C/failed-main.png@0.84" "$C/failed-panel.png@1"
echo "==> Screenshots in $OUT"
ls "$OUT"
