#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds Everything.app (adapted from Vorssaint's build.sh).
#
#   scripts/build-app.sh check      fast debug type-check/compile, no bundle
#   scripts/build-app.sh            release build + bundle in build/stage
#   scripts/build-app.sh --install  release build, replace /Applications/EVERYTHING.app, relaunch
#   scripts/build-app.sh --dmg      release build, then build/EVERYTHING.dmg for a GitHub release
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="release"; INSTALL=0; DMG=0
for arg in "$@"; do
    case "$arg" in
        check) MODE="check" ;;
        --install) INSTALL=1 ;;
        --dmg) DMG=1 ;;
    esac
done

APP_NAME="EVERYTHING"
EXECUTABLE="Everything"
BUNDLE_ID="com.shvmane.everything"
NOW_PLAYING_ADAPTER="libEverythingNowPlaying.dylib"
TARGET="arm64-apple-macosx14.0"
ENTITLEMENTS="Resources/Everything.entitlements"
JOBS="$(sysctl -n hw.logicalcpu)"

# The macOS 27 SDK turns SwiftUI property wrappers into macros whose plugin the
# Command Line Tools lack; the 26 SDK compiles cleanly with Swift 6.4.
PINNED_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
SDK_COMPAT_FLAGS=()
if [[ -d "$PINNED_SDK" ]]; then
    SDK="$PINNED_SDK"
    SDK_COMPAT_FLAGS=(-Xfrontend -interface-compiler-version -Xfrontend 6.3.2)
else
    SDK="$(xcrun --show-sdk-path)"
    SDK_COMPAT_FLAGS=(-plugin-path /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins)
fi
INCLUDE_FLAGS=(-enable-bare-slash-regex -I Sources/VMStatisticsCompat -I Sources/HIDEventSystem -I Sources/ISS/include)

write_output_file_map() {
    local out="$1" dir="$2"; shift 2
    {
        print -r -- "{"
        print -r -- "  \"\": { \"swift-dependencies\": \"$dir/master.swiftdeps\" }"
        local s a
        for s in "$@"; do
            a="${s//\//__}"; a="${a%.swift}"
            print -r -- ", \"$s\": { \"object\": \"$dir/$a.o\", \"swift-dependencies\": \"$dir/$a.swiftdeps\" }"
        done
        print -r -- "}"
    } > "$out"
}

# --- C target: InstantSpaceSwitcher core -----------------------------------
ISS_OBJECTS=()
if [[ -d Sources/ISS ]]; then
    mkdir -p build/objects/ISS
    for c in Sources/ISS/*.c; do
        o="build/objects/ISS/$(basename "${c%.c}").o"
        if [[ ! -f "$o" || "$c" -nt "$o" ]] || [[ -n "$(find Sources/ISS -name '*.h' -newer "$o" 2>/dev/null)" ]]; then
            clang -c -O2 -target "$TARGET" -isysroot "$SDK" -I Sources/ISS/include -I Sources/ISS "$c" -o "$o"
        fi
        ISS_OBJECTS+=("$o")
    done
fi
ISS_LINK_FLAGS=()
(( ${#ISS_OBJECTS} )) && ISS_LINK_FLAGS=(-Xlinker -F/System/Library/PrivateFrameworks -Xlinker -framework -Xlinker SkyLight)

APP_SOURCES=(Sources/Everything/**/*.swift)

if [[ "$MODE" == "check" ]]; then
    DIR="build/objects/check"; mkdir -p "$DIR"
    write_output_file_map "$DIR/map.json" "$DIR" "${APP_SOURCES[@]}"
    echo "▸ Debug compile…"
    swiftc -Onone -incremental -enable-batch-mode -j "$JOBS" -output-file-map "$DIR/map.json" \
        -target "$TARGET" -sdk "$SDK" "${SDK_COMPAT_FLAGS[@]}" "${INCLUDE_FLAGS[@]}" \
        "${APP_SOURCES[@]}" "${ISS_OBJECTS[@]}" "${ISS_LINK_FLAGS[@]}" -o build/Everything-debug
    echo "✓ check passed"
    exit 0
fi

DIR="build/objects/release"; mkdir -p "$DIR"
write_output_file_map "$DIR/map.json" "$DIR" "${APP_SOURCES[@]}"
echo "▸ Release compile…"
swiftc -O -incremental -enable-batch-mode -j "$JOBS" -output-file-map "$DIR/map.json" \
    -target "$TARGET" -sdk "$SDK" "${SDK_COMPAT_FLAGS[@]}" "${INCLUDE_FLAGS[@]}" \
    -Xlinker -dead_strip \
    "${APP_SOURCES[@]}" "${ISS_OBJECTS[@]}" "${ISS_LINK_FLAGS[@]}" -o "build/$EXECUTABLE"

echo "▸ Now Playing adapter…"
swiftc -O -target "$TARGET" -sdk "$SDK" "${SDK_COMPAT_FLAGS[@]}" -emit-library \
    -module-name EverythingNowPlaying \
    Sources/NowPlayingAdapter/*.swift \
    Sources/Everything/Services/Notch/NotchPlaybackSource.swift \
    Sources/Everything/Services/Notch/NotchPlaybackCommand.swift \
    -o "build/$NOW_PLAYING_ADAPTER"

# The app icon (regenerate with scripts/MakeAppIcon.swift).
cp Resources/AppIcon.icns build/AppIcon.icns

echo "▸ Bundle…"
STAGE="build/stage/$APP_NAME.app"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources" "$STAGE/Contents/Frameworks"
cp "build/$EXECUTABLE" "$STAGE/Contents/MacOS/"
cp "build/$NOW_PLAYING_ADAPTER" "$STAGE/Contents/Frameworks/"
cp Resources/now-playing.pl Resources/agent-prices.json Resources/ClaudeThinking.gif "$STAGE/Contents/Resources/"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
printf 'APPL????' > "$STAGE/Contents/PkgInfo"
cp build/AppIcon.icns "$STAGE/Contents/Resources/"
xattr -c -r "$STAGE" 2>/dev/null || true

# Sign with a stable identity so Accessibility grants survive rebuilds.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -E 'Apple Development|Developer ID Application' | head -1 | sed -E 's/.*"(.*)".*/\1/' || true)"
[[ -z "$IDENTITY" ]] && IDENTITY="-"
echo "▸ Signing with: $IDENTITY"
codesign --force --strip-disallowed-xattrs --identifier "$BUNDLE_ID.now-playing" --sign "$IDENTITY" \
    "$STAGE/Contents/Frameworks/$NOW_PLAYING_ADAPTER"
codesign --force --strip-disallowed-xattrs --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$STAGE"
codesign --verify --deep --strict "$STAGE"
echo "✓ Built $STAGE ($(du -sh "$STAGE" | cut -f1))"

if (( INSTALL )); then
    pkill -x "$EXECUTABLE" 2>/dev/null || true
    for _ in {1..50}; do pgrep -x "$EXECUTABLE" >/dev/null || break; sleep 0.1; done
    rm -rf "/Applications/$APP_NAME.app"
    ditto --noextattr --noqtn "$STAGE" "/Applications/$APP_NAME.app"
    codesign --verify --deep --strict "/Applications/$APP_NAME.app"
    # Refresh the Dock/Finder icon cache for the new icon.
    touch "/Applications/$APP_NAME.app"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/$APP_NAME.app" >/dev/null 2>&1 || true
    open "/Applications/$APP_NAME.app"
    echo "✓ Installed and launched /Applications/$APP_NAME.app"
fi

if (( DMG )); then
    # A drag-to-Applications disk image for a GitHub release.
    DMG_DIR="build/dmg"
    rm -rf "$DMG_DIR" "build/$APP_NAME.dmg"
    mkdir -p "$DMG_DIR"
    ditto --noextattr --noqtn "$STAGE" "$DMG_DIR/$APP_NAME.app"
    ln -s /Applications "$DMG_DIR/Applications"
    hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$DMG_DIR" -ov -format UDZO "build/$APP_NAME.dmg"
    rm -rf "$DMG_DIR"
    echo "✓ Built build/$APP_NAME.dmg"
fi
