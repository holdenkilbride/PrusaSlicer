#!/bin/bash
# package_macos.sh - Create PrusaSlicer.app bundle

set -e

BUILD_DIR="/Users/Holden/Desktop/slicers/PrusaSlicer/build"
RESOURCES_DIR="/Users/Holden/Desktop/slicers/PrusaSlicer/resources"
APP_NAME="PrusaSlicer-FuzzySkin"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "Creating app bundle structure..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

echo "Copying executable..."
cp "$BUILD_DIR/src/PrusaSlicer" "$APP_BUNDLE/Contents/MacOS/"

echo "Copying Info.plist..."
cp "$BUILD_DIR/src/Info.plist" "$APP_BUNDLE/Contents/"

echo "Copying resources..."
cp -r "$RESOURCES_DIR"/* "$APP_BUNDLE/Contents/Resources/"

echo "Copying icon..."
if [ -f "$RESOURCES_DIR/icons/PrusaSlicer.icns" ]; then
    cp "$RESOURCES_DIR/icons/PrusaSlicer.icns" "$APP_BUNDLE/Contents/Resources/"
fi

echo "Bundling dynamic libraries..."
# This bundles all dylib dependencies into the app
if command -v dylibbundler &> /dev/null; then
    dylibbundler -od -b \
        -x "$APP_BUNDLE/Contents/MacOS/PrusaSlicer" \
        -d "$APP_BUNDLE/Contents/Frameworks/" \
        -p @executable_path/../Frameworks/
else
    echo "Warning: dylibbundler not found. Install with: brew install dylibbundler"
    echo "Skipping library bundling - app may not be portable."
fi

echo ""
echo "Done! App bundle created at: $APP_BUNDLE"
echo "To create a DMG: hdiutil create -volname '$APP_NAME' -srcfolder '$APP_BUNDLE' -ov -format UDZO '$BUILD_DIR/$APP_NAME.dmg'"
