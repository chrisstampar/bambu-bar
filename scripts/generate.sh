#!/bin/zsh
# Draws the app icon into Resources/Assets.xcassets and generates BambuBar.xcodeproj from project.yml (neither
# is checked in). build.sh and appstore.sh run it; run it by hand before opening the project in Xcode.
#   scripts/generate.sh && open BambuBar.xcodeproj
set -euo pipefail

ROOT=${0:A:h:h}
BUILD="$ROOT/build"
ICONSET="$BUILD/AppIcon.iconset"
APPICON="$ROOT/Resources/Assets.xcassets/AppIcon.appiconset"
cd "$ROOT"
command -v xcodegen >/dev/null || { echo "xcodegen is required: brew install xcodegen" >&2; exit 2; }

echo "==> App icon"
rm -rf "$ICONSET" "$APPICON"
mkdir -p "$BUILD" "$APPICON"
swift "$ROOT/scripts/generate-icon.swift" "$ICONSET" >/dev/null
cp "$ICONSET"/*.png "$APPICON/"
print '{ "info" : { "author" : "xcode", "version" : 1 } }' > "${APPICON:h}/Contents.json"
{
  print '{\n  "images" : ['
  sep=""
  for size in 16 32 128 256 512; do
    for scale in 1 2; do
      file="icon_${size}x${size}${${scale:#1}:+@2x}.png"
      print -n "$sep    { \"idiom\" : \"mac\", \"size\" : \"${size}x${size}\", \"scale\" : \"${scale}x\", \"filename\" : \"$file\" }"
      sep=$',\n'
    done
  done
  print '\n  ],\n  "info" : { "author" : "xcode", "version" : 1 }\n}'
} > "$APPICON/Contents.json"

echo "==> Generating Xcode project"
xcodegen generate --quiet --spec "$ROOT/project.yml" --project "$ROOT"
