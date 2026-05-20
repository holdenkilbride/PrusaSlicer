#!/bin/bash
# package_macos.sh - Create PrusaSlicer.app bundle

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
DEPS_DIR="$SCRIPT_DIR/deps"
DEPS_BUILD_DIR="$DEPS_DIR/build"
DEPS_PREFIX="$DEPS_BUILD_DIR/destdir/usr/local"
RESOURCES_DIR="$SCRIPT_DIR/resources"
APP_NAME="PrusaSlicer-FuzzySkin"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
JOBS="$(sysctl -n hw.ncpu)"

# PrusaSlicer's bundled Find modules declare cmake_minimum_required < 3.5;
# CMake 4.x removed compat for that. This flag makes CMake act as if policy
# version 3.5 was declared, satisfying the check without editing vendored files.
CMAKE_COMPAT_FLAGS=(-DCMAKE_POLICY_VERSION_MINIMUM=3.5)

# Discards a CMakeCache.txt whose CMAKE_HOME_DIRECTORY no longer points at the
# expected source dir (happens when the tree was copied/moved). CMake won't
# self-heal from this — make just dies with "source directory does not exist".
clear_stale_cache() {
    local build_dir="$1" expected_src="$2"
    [ -f "$build_dir/CMakeCache.txt" ] || return 0
    local cached_src
    cached_src="$(awk -F= '/^CMAKE_HOME_DIRECTORY:INTERNAL=/{print $2; exit}' "$build_dir/CMakeCache.txt")"
    if [ -n "$cached_src" ] && [ "$cached_src" != "$expected_src" ]; then
        echo "    stale cache in $build_dir (was: $cached_src) — wiping for fresh configure"
        # Selective wipe (CMakeCache + CMakeFiles only) leaves subdir Makefiles
        # with the old path baked in. Nuking the whole dir is the reliable fix.
        rm -rf "$build_dir"
    fi
}

echo "==> Building dependencies (first run: 30-90 min; subsequent runs: seconds)..."
clear_stale_cache "$DEPS_BUILD_DIR" "$DEPS_DIR"
if [ ! -f "$DEPS_BUILD_DIR/CMakeCache.txt" ]; then
    mkdir -p "$DEPS_BUILD_DIR"
    ( cd "$DEPS_BUILD_DIR" && cmake .. "${CMAKE_COMPAT_FLAGS[@]}" )
fi
( cd "$DEPS_BUILD_DIR" && make -j"$JOBS" )

echo "==> Building PrusaSlicer..."
clear_stale_cache "$BUILD_DIR" "$SCRIPT_DIR"
if [ ! -f "$BUILD_DIR/CMakeCache.txt" ]; then
    mkdir -p "$BUILD_DIR"
    ( cd "$BUILD_DIR" && cmake .. -DCMAKE_PREFIX_PATH="$DEPS_PREFIX" "${CMAKE_COMPAT_FLAGS[@]}" )
fi
( cd "$BUILD_DIR" && make -j"$JOBS" )

if [ ! -f "$BUILD_DIR/src/PrusaSlicer" ]; then
    echo "ERROR: build did not produce $BUILD_DIR/src/PrusaSlicer" >&2
    exit 1
fi

echo "==> Creating app bundle structure..."
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
