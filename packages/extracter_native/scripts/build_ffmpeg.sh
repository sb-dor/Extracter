#!/usr/bin/env bash
# Builds the pinned, decode-only LGPL FFmpeg used by extracter_native.
#
# Usage: scripts/build_ffmpeg.sh <target>
#   targets: macos-arm64 macos-x86_64 ios-arm64 iossim-arm64
#            android-arm64-v8a android-x86_64 linux-x86_64 windows-x86_64
#
# Every target uses the same configure flags (see FFMPEG_FLAGS below). FFmpeg is
# built as static archives, then linked into ONE shared library per target
# (FFmpeg.framework / libffmpeg.so / ffmpeg.dll) so the app links it dynamically.
set -euo pipefail

FFMPEG_VERSION="8.1.3"
FFMPEG_SHA256="7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3"
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"

IOS_MIN="16.4"
MACOS_MIN="13.3"
ANDROID_API="24"

TARGET="${1:?usage: build_ffmpeg.sh <target>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$ROOT/third_party/src"
SRC="$SRC_DIR/ffmpeg-$FFMPEG_VERSION"
BUILD="$ROOT/third_party/build/ffmpeg-$TARGET"
PREFIX="$BUILD/prefix"
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"

fetch_source() {
  mkdir -p "$SRC_DIR"
  local tarball="$SRC_DIR/ffmpeg-$FFMPEG_VERSION.tar.xz"
  if [[ ! -f "$tarball" ]]; then
    curl -fsSL "$FFMPEG_URL" -o "$tarball"
  fi
  local actual
  actual="$(shasum -a 256 "$tarball" | cut -d' ' -f1)"
  if [[ "$actual" != "$FFMPEG_SHA256" ]]; then
    echo "SHA-256 mismatch for $tarball: $actual" >&2
    exit 1
  fi
  if [[ ! -d "$SRC" ]]; then
    tar -xf "$tarball" -C "$SRC_DIR"
  fi
}

# Audio decoders only: the app never decodes video frames. The list is derived
# from the audio / PCM / DPCM / ADPCM sections of libavcodec/allcodecs.c so it
# tracks the pinned source exactly.
audio_decoders() {
  awk '/\/\* audio codecs \*\//{on=1} /\/\* subtitles \*\//{on=0} on' "$SRC/libavcodec/allcodecs.c" |
    grep -oE 'ff_[a-z0-9_]+_decoder' | sed -E 's/^ff_//; s/_decoder$//' | sort -u | paste -sd, -
}

# Demuxers that open other files (playlists, sequences, manifests) or carry no
# audio. Removing them is the first layer of the input sandbox.
denied_demuxers() {
  local images
  images="$("$SRC/configure" --list-demuxers | tr -s ' \t' '\n' | grep -E '^image' | paste -sd, -)"
  echo "concat,hls,dash,imf,webm_dash_manifest,ffmetadata,mpl2,tedcaptions,${images}"
}

fetch_source

FFMPEG_FLAGS=(
  --disable-programs --disable-doc --disable-debug
  --disable-avdevice --disable-avfilter --disable-swscale
  --disable-encoders --disable-muxers
  --disable-network --disable-protocols --enable-protocol=file
  --disable-autodetect --enable-zlib
  --disable-gpl --disable-nonfree
  --disable-hwaccels
  --disable-decoders "--enable-decoder=$(audio_decoders)"
  "--disable-demuxer=$(denied_demuxers)"
  --enable-pic --enable-static --disable-shared
)

CROSS=()
EXTRA_CFLAGS=""
EXTRA_LDFLAGS=""
case "$TARGET" in
  macos-arm64|macos-x86_64)
    arch="${TARGET#macos-}"
    sdk="$(xcrun -sdk macosx --show-sdk-path)"
    CROSS=(--target-os=darwin --arch="$arch" --enable-cross-compile
      --cc="xcrun -sdk macosx clang" --sysroot="$sdk")
    EXTRA_CFLAGS="-arch $arch -mmacosx-version-min=$MACOS_MIN"
    EXTRA_LDFLAGS="$EXTRA_CFLAGS"
    ;;
  ios-arm64)
    sdk="$(xcrun -sdk iphoneos --show-sdk-path)"
    CROSS=(--target-os=darwin --arch=arm64 --enable-cross-compile
      --cc="xcrun -sdk iphoneos clang" --sysroot="$sdk")
    EXTRA_CFLAGS="-target arm64-apple-ios$IOS_MIN"
    EXTRA_LDFLAGS="$EXTRA_CFLAGS"
    ;;
  iossim-arm64)
    sdk="$(xcrun -sdk iphonesimulator --show-sdk-path)"
    CROSS=(--target-os=darwin --arch=arm64 --enable-cross-compile
      --cc="xcrun -sdk iphonesimulator clang" --sysroot="$sdk")
    EXTRA_CFLAGS="-target arm64-apple-ios$IOS_MIN-simulator"
    EXTRA_LDFLAGS="$EXTRA_CFLAGS"
    ;;
  android-arm64-v8a|android-x86_64)
    ndk="${ANDROID_NDK_HOME:-$(ls -d "$HOME"/Library/Android/sdk/ndk/28.* 2>/dev/null | sort -V | tail -1)}"
    [[ -d "$ndk" ]] || { echo "Android NDK r28+ not found; set ANDROID_NDK_HOME" >&2; exit 1; }
    host="$(ls "$ndk/toolchains/llvm/prebuilt" | head -1)"
    tc="$ndk/toolchains/llvm/prebuilt/$host/bin"
    if [[ "$TARGET" == android-arm64-v8a ]]; then
      triple="aarch64-linux-android"; arch="aarch64"
    else
      triple="x86_64-linux-android"; arch="x86_64"
    fi
    CROSS=(--target-os=android --arch="$arch" --enable-cross-compile
      --cc="$tc/${triple}${ANDROID_API}-clang" --cxx="$tc/${triple}${ANDROID_API}-clang++"
      --ar="$tc/llvm-ar" --nm="$tc/llvm-nm" --ranlib="$tc/llvm-ranlib" --strip="$tc/llvm-strip")
    # arm64-v8a baseline is Armv8.0; FFmpeg's NEON paths are runtime-safe on it.
    [[ "$arch" == aarch64 ]] && EXTRA_CFLAGS="-march=armv8-a"
    # The emulator ABI only; NASM text relocations are rejected by Android's linker.
    [[ "$arch" == x86_64 ]] && CROSS+=(--disable-x86asm)
    ;;
  linux-x86_64)
    CROSS=(--target-os=linux --arch=x86_64)
    ;;
  windows-x86_64)
    CROSS=(--target-os=mingw32 --arch=x86_64 --cross-prefix="${MINGW_PREFIX:-x86_64-w64-mingw32-}")
    ;;
  *)
    echo "unknown target: $TARGET" >&2; exit 1 ;;
esac

rm -rf "$BUILD"
mkdir -p "$BUILD/obj"
cd "$BUILD/obj"
"$SRC/configure" --prefix="$PREFIX" "${FFMPEG_FLAGS[@]}" "${CROSS[@]}" \
  --extra-cflags="$EXTRA_CFLAGS" --extra-ldflags="$EXTRA_LDFLAGS" > "$BUILD/configure.log" 2>&1 \
  || { tail -40 "$BUILD/configure.log"; tail -40 ffbuild/config.log 2>/dev/null; exit 1; }
make -j"$JOBS" > "$BUILD/make.log" 2>&1 || { tail -60 "$BUILD/make.log"; exit 1; }
make install > /dev/null

LIBS=(libavformat.a libavcodec.a libswresample.a libavutil.a)
cd "$PREFIX/lib"
OUT="$BUILD/out"
mkdir -p "$OUT"

case "$TARGET" in
  macos-*|ios-*|iossim-*)
    xcrun -sdk "$( [[ $TARGET == macos-* ]] && echo macosx || ([[ $TARGET == ios-* ]] && echo iphoneos || echo iphonesimulator))" \
      clang $EXTRA_LDFLAGS -dynamiclib -o "$OUT/FFmpeg" \
      -Wl,-all_load "${LIBS[@]}" -lz -framework CoreFoundation \
      -install_name @rpath/FFmpeg.framework/FFmpeg \
      -compatibility_version 1 -current_version 1
    ;;
  android-*)
    cc="$(printf '%s\n' "${CROSS[@]}" | sed -n 's/^--cc=//p')"
    "$cc" -shared -o "$OUT/libffmpeg.so" -Wl,-soname,libffmpeg.so \
      -Wl,--whole-archive "${LIBS[@]}" -Wl,--no-whole-archive \
      -Wl,-Bsymbolic -Wl,-z,max-page-size=16384 -lz -lm
    ;;
  linux-*)
    cc -shared -o "$OUT/libffmpeg.so" -Wl,-soname,libffmpeg.so \
      -Wl,--whole-archive "${LIBS[@]}" -Wl,--no-whole-archive -Wl,-Bsymbolic -lz -lm -lpthread
    ;;
  windows-*)
    "${MINGW_PREFIX:-x86_64-w64-mingw32-}gcc" -shared -o "$OUT/ffmpeg.dll" \
      -Wl,--whole-archive "${LIBS[@]}" -Wl,--no-whole-archive \
      -Wl,--output-def,"$OUT/ffmpeg.def" -Wl,--out-implib,"$OUT/libffmpeg.dll.a" -lz -lbcrypt -lws2_32
    # MSVC import library for the Flutter (MSVC) build of the plugin.
    if command -v lib.exe > /dev/null; then
      lib.exe /nologo /def:"$(cygpath -w "$OUT/ffmpeg.def")" /machine:x64 /out:"$(cygpath -w "$OUT/ffmpeg.lib")"
    else
      echo "lib.exe not on PATH: run 'lib /def:ffmpeg.def /machine:x64 /out:ffmpeg.lib' in $OUT from a VS prompt" >&2
    fi
    ;;
esac

rm -rf "$OUT/include"
cp -R "$PREFIX/include" "$OUT/include"
# Configure flags with the local build prefix stripped, for THIRD_PARTY.md / About.
grep -E '#define (FFMPEG_CONFIGURATION|FFMPEG_LICENSE)' "$BUILD/obj/config.h" |
  sed -E "s#--prefix=[^ ]+ ##; s#--sysroot=[^ ]+ ##g; s#--(cc|cxx|ar|nm|ranlib|strip)=[^ ]+ ##g" > "$OUT/configuration.txt"
echo "FFmpeg $FFMPEG_VERSION for $TARGET → $OUT"
