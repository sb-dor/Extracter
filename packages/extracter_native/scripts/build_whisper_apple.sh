#!/usr/bin/env bash
# Builds whisper.cpp (pinned submodule) as a static library per Apple slice and
# wraps it in whisper.xcframework. Metal is on with the shader library embedded;
# Accelerate provides BLAS.
#
# Usage: scripts/build_whisper_apple.sh [macos] [ios] [iossim]   (default: all)
set -euo pipefail

IOS_MIN="16.4"
MACOS_MIN="13.3"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WHISPER="$ROOT/third_party/whisper.cpp"
BUILD="$ROOT/third_party/build/whisper-apple"
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
SLICES=("$@")
[[ ${#SLICES[@]} -eq 0 ]] && SLICES=(macos ios iossim)

COMMON=(
  -DCMAKE_BUILD_TYPE=Release
  -DBUILD_SHARED_LIBS=OFF
  -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF
  -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON
  -DGGML_BLAS=ON -DGGML_ACCELERATE=ON
  -DGGML_OPENMP=OFF -DGGML_NATIVE=OFF
)

build_slice() {
  local name="$1"; shift
  local dir="$BUILD/$name"
  cmake -S "$WHISPER" -B "$dir/cmake" -G "Unix Makefiles" "${COMMON[@]}" "$@" > "$dir.configure.log" 2>&1 \
    || { tail -40 "$dir.configure.log"; exit 1; }
  cmake --build "$dir/cmake" --config Release -j"$JOBS" > "$dir.build.log" 2>&1 \
    || { tail -60 "$dir.build.log"; exit 1; }
  mkdir -p "$dir/lib"
  # One archive per slice: whisper + every ggml backend it was built with.
  libtool -static -o "$dir/lib/libwhisper.a" $(find "$dir/cmake" -name '*.a' | sort) 2> /dev/null
  echo "whisper.cpp slice $name → $dir/lib/libwhisper.a"
}

mkdir -p "$BUILD"
for slice in "${SLICES[@]}"; do
  mkdir -p "$BUILD/$slice"
  case "$slice" in
    macos)
      build_slice macos -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_MIN" \
        -DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON -DGGML_BMI2=ON ;;
    ios)
      build_slice ios -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos \
        -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_MIN" ;;
    iossim)
      build_slice iossim -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphonesimulator \
        -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_MIN" ;;
    *) echo "unknown slice: $slice" >&2; exit 1 ;;
  esac
done

HEADERS="$BUILD/headers"
rm -rf "$HEADERS"; mkdir -p "$HEADERS"
cp "$WHISPER/include/whisper.h" "$WHISPER"/ggml/include/*.h "$HEADERS/"

ARGS=()
for slice in macos ios iossim; do
  [[ -f "$BUILD/$slice/lib/libwhisper.a" ]] && ARGS+=(-library "$BUILD/$slice/lib/libwhisper.a" -headers "$HEADERS")
done
rm -rf "$BUILD/whisper.xcframework"
xcodebuild -create-xcframework "${ARGS[@]}" -output "$BUILD/whisper.xcframework" > /dev/null
echo "→ $BUILD/whisper.xcframework"
