#!/bin/zsh
# Writes build/appcast.xml, the feed Sparkle reads for in-app updates, for a packaged and published release.
#   scripts/appcast.sh               the version in build/App.noindex (run after package.sh and gh release create)
#   VERSION=1.4.0 scripts/appcast.sh
#   UPLOAD=1 scripts/appcast.sh      also attaches appcast.xml to the GitHub release. The app reads
#                                    releases/latest/download/appcast.xml, so the newest release's copy is the feed.
#   NOTES=notes.md scripts/appcast.sh
#                                    release notes from a Markdown file instead of the GitHub release's text
#   DOWNLOAD_URL=http://… scripts/appcast.sh
#                                    another download location for the zip, to try an update locally
# The zip is signed with the EdDSA key in the login keychain (Sparkle's generate_keys made it; its public half is
# SUPublicEDKey in Info.plist). Keep a backup: generate_keys -x <file> exports it, -f <file> imports it again.
set -euo pipefail

ROOT=${0:A:h:h}
REPO=rolottr/bambu-bar
SPARKLE_BIN="$ROOT/build/DerivedData.noindex/SourcePackages/artifacts/sparkle/Sparkle/bin"
[[ -x "$SPARKLE_BIN/sign_update" ]] || { echo "Sparkle's tools are missing: run scripts/build.sh first" >&2; exit 2; }

VERSION=${VERSION:-$(plutil -extract CFBundleShortVersionString raw "$ROOT/build/App.noindex/Bambu Bar.app/Contents/Info.plist")}
ZIP="$ROOT/build/Bambu-Bar-$VERSION-macos.zip"
[[ -f "$ZIP" ]] || { echo "$ZIP is missing: run scripts/package.sh first" >&2; exit 2; }
URL=${DOWNLOAD_URL:-https://github.com/$REPO/releases/download/v$VERSION/${ZIP:t}}

# Sparkle compares CFBundleVersion (the build timestamp), so read it from the zip that ships.
INFO=$(unzip -p "$ZIP" "Bambu Bar.app/Contents/Info.plist")
BUILD=$(plutil -extract CFBundleVersion raw -o - - <<< "$INFO")
MINIMUM_SYSTEM=$(plutil -extract LSMinimumSystemVersion raw -o - - <<< "$INFO")
SIGNATURE=$("$SPARKLE_BIN/sign_update" "$ZIP")

# The release text minus its install instructions, rendered by GitHub the way the release page shows it.
if [[ -n "${NOTES:-}" ]]; then
  MARKDOWN=$(<"$NOTES")
else
  MARKDOWN=$(gh release view "v$VERSION" --repo "$REPO" --json body --jq .body)
fi
MARKDOWN=$(print -r -- "$MARKDOWN" | sed '/^\*\*Install:\*\*/,$d')
HTML=$(gh api markdown -f mode=gfm -f context="$REPO" -f text="$MARKDOWN")

cat > "$ROOT/build/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Bambu Bar</title>
    <link>https://github.com/$REPO</link>
    <item>
      <title>Bambu Bar $VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINIMUM_SYSTEM</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/$REPO/releases</sparkle:fullReleaseNotesLink>
      <description><![CDATA[
<style>
  :root { color-scheme: light dark; }
  body { font: 13px/1.45 -apple-system, sans-serif; margin: 10px 14px; }
  ul { padding-left: 1.2em; } li { margin: 0.35em 0; }
  code { font: 12px ui-monospace, monospace; }
  a { color: #2fae66; }
</style>
$HTML
      ]]></description>
      <enclosure url="$URL" type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
EOF
xmllint --noout "$ROOT/build/appcast.xml"
echo "==> Wrote $ROOT/build/appcast.xml ($VERSION, build $BUILD)"

if [[ -n "${UPLOAD:-}" ]]; then
  gh release upload "v$VERSION" "$ROOT/build/appcast.xml" --repo "$REPO" --clobber
  echo "==> Attached appcast.xml to v$VERSION"
fi
