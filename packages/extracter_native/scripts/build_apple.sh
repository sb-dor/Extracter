#!/usr/bin/env bash
# Builds every Apple slice of FFmpeg and whisper.cpp and installs
#   ios/Frameworks/   and   macos/Frameworks/
# with FFmpeg.xcframework (dynamic), whisper.xcframework (static) and include/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
B="$ROOT/third_party/build"
APPLE="$B/apple"

if [[ "${SKIP_BUILD:-0}" != 1 ]]; then
  for t in macos-arm64 macos-x86_64 ios-arm64 iossim-arm64; do
    [[ -f "$B/ffmpeg-$t/out/FFmpeg" ]] || "$ROOT/scripts/build_ffmpeg.sh" "$t" &
  done
  wait
  "$ROOT/scripts/build_whisper_apple.sh" macos ios iossim
fi

plist() { # <path> <min-os-key> <min-os> <platform>
  cat > "$1" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>FFmpeg</string>
  <key>CFBundleIdentifier</key><string>org.ffmpeg.FFmpeg</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>FFmpeg</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>8.1.3</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleSupportedPlatforms</key><array><string>$4</string></array>
  <key>$2</key><string>$3</string>
</dict>
</plist>
EOF
}

rm -rf "$APPLE"; mkdir -p "$APPLE"

# macOS: versioned bundle, universal binary.
mac="$APPLE/macos/FFmpeg.framework"
mkdir -p "$mac/Versions/A/Resources"
lipo -create "$B/ffmpeg-macos-arm64/out/FFmpeg" "$B/ffmpeg-macos-x86_64/out/FFmpeg" -output "$mac/Versions/A/FFmpeg"
plist "$mac/Versions/A/Resources/Info.plist" LSMinimumSystemVersion 13.3 MacOSX
ln -s A "$mac/Versions/Current"
ln -s Versions/Current/FFmpeg "$mac/FFmpeg"
ln -s Versions/Current/Resources "$mac/Resources"

# iOS device + simulator: flat bundles.
for t in ios-arm64:iPhoneOS iossim-arm64:iPhoneSimulator; do
  name="${t%%:*}"; platform="${t##*:}"
  fw="$APPLE/$name/FFmpeg.framework"
  mkdir -p "$fw"
  cp "$B/ffmpeg-$name/out/FFmpeg" "$fw/FFmpeg"
  plist "$fw/Info.plist" MinimumOSVersion 16.4 "$platform"
done

xcodebuild -create-xcframework \
  -framework "$APPLE/macos/FFmpeg.framework" \
  -framework "$APPLE/ios-arm64/FFmpeg.framework" \
  -framework "$APPLE/iossim-arm64/FFmpeg.framework" \
  -output "$APPLE/FFmpeg.xcframework" > /dev/null

mkdir -p "$APPLE/include"
cp -R "$B/ffmpeg-macos-arm64/out/include/." "$APPLE/include/"
cp "$B/whisper-apple/headers/"*.h "$APPLE/include/"

for platform in ios macos; do
  dest="$ROOT/$platform/Frameworks"
  rm -rf "$dest"; mkdir -p "$dest"
  cp -R "$APPLE/FFmpeg.xcframework" "$B/whisper-apple/whisper.xcframework" "$APPLE/include" "$dest/"
done
cp "$B/ffmpeg-macos-arm64/out/configuration.txt" "$ROOT/third_party/ffmpeg-configuration.txt"
echo "Apple frameworks installed into ios/Frameworks and macos/Frameworks"
