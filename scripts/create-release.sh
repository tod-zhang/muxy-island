#!/bin/bash
# Cut a new Muxy Island release end-to-end:
#   1. Build Release (ad-hoc signed, no notarization)
#   2. Package as a DMG via hdiutil
#   3. Sign the DMG with the Sparkle EdDSA private key
#   4. Prepend a new <item> to docs/appcast.xml
#   5. Create the git tag and GitHub release, upload the DMG
#   6. Commit + push the updated appcast
#
# Usage:
#   ./scripts/create-release.sh 0.2.0            # prompts for notes
#   ./scripts/create-release.sh 0.2.0 "Short release notes"
#
# Prerequisites:
#   - gh CLI installed and authenticated
#   - .sparkle-keys/eddsa_private_key present (generate-keys.sh once)
#   - Clean working tree (pending commits are OK; we commit appcast ourselves)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
RELEASE_DIR="$PROJECT_DIR/releases"
APPCAST="$PROJECT_DIR/docs/appcast.xml"
KEY_FILE="$PROJECT_DIR/.sparkle-keys/eddsa_private_key"

REPO="tod-zhang/muxy-island"
DMG_NAME_PREFIX="MuxyIsland"

# ------------------------------------------------------------------------
# Arg parsing
# ------------------------------------------------------------------------
if [ "${1:-}" = "" ]; then
    echo "Usage: $0 <version> [release-notes]"
    echo "Example: $0 0.2.0 'Adds global hotkey and provider badges'"
    exit 1
fi
VERSION="$1"
NOTES="${2:-}"

if [ -z "$NOTES" ]; then
    echo "Enter release notes for v$VERSION (end with Ctrl-D):"
    NOTES="$(cat)"
fi

# ------------------------------------------------------------------------
# Locate Sparkle tools
# ------------------------------------------------------------------------
SIGN_UPDATE=""
for candidate in "$HOME/Library/Developer/Xcode/DerivedData"/ClaudeIsland-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update; do
    if [ -x "$candidate" ]; then
        SIGN_UPDATE="$candidate"
        break
    fi
done
if [ -z "$SIGN_UPDATE" ]; then
    echo "ERROR: Sparkle sign_update not found. Open the project in Xcode once"
    echo "to fetch the Sparkle SPM package, then re-run this script."
    exit 1
fi

if [ ! -f "$KEY_FILE" ]; then
    echo "ERROR: Private key not found at $KEY_FILE"
    echo "Run scripts/generate-keys.sh first."
    exit 1
fi

# ------------------------------------------------------------------------
# Bump MARKETING_VERSION in pbxproj if it doesn't already match
# ------------------------------------------------------------------------
PBXPROJ="$PROJECT_DIR/ClaudeIsland.xcodeproj/project.pbxproj"
CURRENT_VERSION=$(grep -m1 "MARKETING_VERSION" "$PBXPROJ" | sed -E 's/.*MARKETING_VERSION = ([^;]+);.*/\1/')
if [ "$CURRENT_VERSION" != "$VERSION" ]; then
    echo "Bumping MARKETING_VERSION: $CURRENT_VERSION -> $VERSION"
    sed -i '' "s/MARKETING_VERSION = $CURRENT_VERSION;/MARKETING_VERSION = $VERSION;/g" "$PBXPROJ"
fi

# ------------------------------------------------------------------------
# Build Release (ad-hoc signed)
# ------------------------------------------------------------------------
echo "=== Building Release ==="
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$RELEASE_DIR"
cd "$PROJECT_DIR"
xcodebuild -scheme ClaudeIsland -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    ENABLE_HARDENED_RUNTIME=NO \
    build \
    | grep -E "error:|BUILD (SUCC|FAIL)" || true

APP_PATH="$BUILD_DIR/Build/Products/Release/Vibe Notch.app"
if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: Build did not produce $APP_PATH"
    exit 1
fi

APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist")
if [ "$APP_VERSION" != "$VERSION" ]; then
    echo "ERROR: Built app reports $APP_VERSION but releasing $VERSION"
    exit 1
fi

# ------------------------------------------------------------------------
# DMG
# ------------------------------------------------------------------------
DMG_NAME="$DMG_NAME_PREFIX-$VERSION.dmg"
DMG_PATH="$RELEASE_DIR/$DMG_NAME"
echo "=== Creating DMG ==="
rm -f "$DMG_PATH"
hdiutil create -quiet -volname "Muxy Island" -srcfolder "$APP_PATH" \
    -ov -format UDZO "$DMG_PATH"
DMG_SIZE=$(stat -f %z "$DMG_PATH")
echo "DMG: $DMG_PATH ($DMG_SIZE bytes)"

# ------------------------------------------------------------------------
# Sparkle signature
# ------------------------------------------------------------------------
echo "=== Signing DMG ==="
SIG_LINE=$("$SIGN_UPDATE" --ed-key-file "$KEY_FILE" "$DMG_PATH")
SIGNATURE=$(echo "$SIG_LINE" | sed -E 's/.*sparkle:edSignature="([^"]+)".*/\1/')
LENGTH=$(echo "$SIG_LINE" | sed -E 's/.*length="([^"]+)".*/\1/')
if [ -z "$SIGNATURE" ] || [ -z "$LENGTH" ]; then
    echo "ERROR: Failed to parse signature from: $SIG_LINE"
    exit 1
fi

# ------------------------------------------------------------------------
# Prepend new <item> to appcast.xml
# ------------------------------------------------------------------------
echo "=== Updating appcast.xml ==="
PUB_DATE=$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S +0000")
NOTES_HTML=$(printf '%s' "$NOTES" | sed -E 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
ENCL_URL="https://github.com/$REPO/releases/download/v$VERSION/$DMG_NAME"

NEW_ITEM="    <item>
      <title>Version $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.6</sparkle:minimumSystemVersion>
      <description><![CDATA[$NOTES_HTML]]></description>
      <enclosure url=\"$ENCL_URL\"
                 sparkle:edSignature=\"$SIGNATURE\"
                 length=\"$LENGTH\"
                 type=\"application/octet-stream\" />
    </item>"

# Insert just after the opening <channel>...description/language block.
# Matches the first <item> line and prepends our new item on top.
python3 <<PY
from pathlib import Path
p = Path("$APPCAST")
text = p.read_text()
marker = text.find("<item>")
if marker == -1:
    # Empty channel — insert before </channel>
    marker = text.find("</channel>")
new = text[:marker] + """$NEW_ITEM
""" + text[marker:]
p.write_text(new)
PY

# ------------------------------------------------------------------------
# GitHub release
# ------------------------------------------------------------------------
echo "=== Creating GitHub release v$VERSION ==="
if gh release view "v$VERSION" --repo "$REPO" &>/dev/null; then
    echo "Release v$VERSION already exists — uploading DMG only."
    gh release upload "v$VERSION" "$DMG_PATH" --repo "$REPO" --clobber
else
    gh release create "v$VERSION" "$DMG_PATH" \
        --repo "$REPO" \
        --title "Muxy Island $VERSION" \
        --notes "$NOTES"
fi

# ------------------------------------------------------------------------
# Commit + push appcast + pbxproj bump
# ------------------------------------------------------------------------
echo "=== Commit + push appcast ==="
git add "$APPCAST" "$PBXPROJ"
git commit -m "Release v$VERSION — bump MARKETING_VERSION, append appcast item

$NOTES" || echo "(nothing to commit)"
git push

echo ""
echo "=== Done ==="
echo "Release: https://github.com/$REPO/releases/tag/v$VERSION"
echo "DMG:     $DMG_PATH"
echo "Appcast: $APPCAST"
