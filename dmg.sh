#!/usr/bin/env bash
# Packages the macOS app into a distributable DMG (drag-to-Applications layout).
# Usage: ./dmg.sh [version]   (defaults: 0.1.0, bundle id io.github.jqssun.btremote.local)

set -euo pipefail

PROJECT="BTRemote"
VERSION="${1:-0.1.0}"
BUNDLE_ID="${BUNDLE_ID:-io.github.jqssun.btremote.local}"
CONFIGURATION="Release"
DERIVED=".build/DerivedData"
APP="$DERIVED/Build/Products/$CONFIGURATION/$PROJECT.app"
VOLUME_NAME="$PROJECT"
OUT="dist/$PROJECT-$VERSION.dmg"

# 1. build (ad-hoc product id so it never collides with the App Store build)
xcodegen generate >/dev/null
xcodebuild \
    -project $PROJECT.xcodeproj \
    -scheme $PROJECT \
    -configuration $CONFIGURATION \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    MARKETING_VERSION="$VERSION" \
    build >/dev/null

# 2. sign
codesign --force --sign - --entitlements $PROJECT/entitlements.plist "$APP"
codesign --verify --strict "$APP"

# 3. stage app + Applications symlink
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE" "$STAGE.dmg"; hdiutil detach "$RW_MOUNT" -quiet >/dev/null 2>&1 || true' EXIT
cp -R "$APP" "$STAGE/$PROJECT.app"
ln -s /Applications "$STAGE/Applications"

# 4. read-write image with Finder icon layout
# the image file must live OUTSIDE the staged folder or hdiutil recurses into it
RW_IMAGE="$STAGE.dmg"
RW_MOUNT="/Volumes/$VOLUME_NAME"
rm -f "$OUT"
mkdir -p dist
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGE" -ov -format UDRW "$RW_IMAGE" >/dev/null
hdiutil attach "$RW_IMAGE" -mountpoint "$RW_MOUNT" >/dev/null
osascript <<APPLESCRIPT || echo "warn: Finder layout skipped, DMG keeps default view"
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 760, 440}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set position of item "$PROJECT.app" of container window to {160, 150}
        set position of item "Applications" of container window to {400, 150}
        update without registering applications
        close
    end tell
end tell
APPLESCRIPT
hdiutil detach "$RW_MOUNT" -quiet

# 5. compress
hdiutil convert "$RW_IMAGE" -format UDZO -imagekey zlib-level=9 -ov -o "$OUT" >/dev/null

# 6. verify what we ship
hdiutil verify "$OUT" >/dev/null
echo "$OUT"
shasum -a 256 "$OUT"
