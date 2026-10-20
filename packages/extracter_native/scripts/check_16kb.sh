#!/usr/bin/env bash
# Verifies Android 16 KB page-size compatibility of every native library in an
# APK or AAB: ELF LOAD segments aligned to >= 16 KB, and (APK) zip alignment.
# Usage: scripts/check_16kb.sh <app.apk|app.aab>
set -euo pipefail

ARCHIVE="${1:?usage: check_16kb.sh <apk-or-aab>}"
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
NDK="${ANDROID_NDK_HOME:-$(ls -d "$SDK"/ndk/28.* 2>/dev/null | sort -V | tail -1)}"
READELF="$(ls "$NDK"/toolchains/llvm/prebuilt/*/bin/llvm-readelf | head -1)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

unzip -q "$ARCHIVE" '*.so' -d "$TMP"
fail=0
while IFS= read -r so; do
  # Every LOAD segment's alignment (last column) must be 2**14 or more.
  bad=""
  for align in $("$READELF" -lW "$so" | awk '$1=="LOAD" { print $NF }'); do
    (( $(printf '%d' "$align") < 16384 )) && bad="$bad $align"
  done
  if [[ -n "$bad" ]]; then
    echo "FAIL ${so#"$TMP"/}: LOAD alignment $bad"
    fail=1
  else
    echo "ok   ${so#"$TMP"/}"
  fi
done < <(find "$TMP" -name '*.so' | sort)

if [[ "$ARCHIVE" == *.apk ]]; then
  ZIPALIGN="$(ls -d "$SDK"/build-tools/* | sort -V | tail -1)/zipalign"
  if "$ZIPALIGN" -c -P 16 -v 4 "$ARCHIVE" > /dev/null; then
    echo "ok   zip alignment (16 KB for .so)"
  else
    echo "FAIL zip alignment"
    fail=1
  fi
fi
exit $fail
