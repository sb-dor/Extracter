#!/usr/bin/env bash
# Dev-only (macOS): builds test_native/smoke.cpp against the Apple frameworks
# and runs the fixture matrix from PLAN.md §5 with assertions.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FW="$ROOT/macos/Frameworks"
FX="$ROOT/test_fixtures"
BIN="$ROOT/build_smoke/smoke"
MODEL="$FX/ggml-tiny.en-q5_1.bin"
mkdir -p "$ROOT/build_smoke"

clang++ -std=c++17 -O2 -Wall -Wextra -I "$FW/include" "$ROOT/src/extracter_native.cpp" "$ROOT/test_native/smoke.cpp" \
  -F "$FW/FFmpeg.xcframework/macos-arm64_x86_64" -framework FFmpeg \
  "$FW/whisper.xcframework/macos-arm64_x86_64/libwhisper.a" \
  -framework Metal -framework MetalKit -framework Accelerate -framework Foundation -lz \
  -Wl,-rpath,"$FW/FFmpeg.xcframework/macos-arm64_x86_64" -mmacosx-version-min=13.3 -o "$BIN" || exit 1

PASS=0; FAIL=0
check() { # <name> <condition-result 0/1> <detail>
  if [[ "$2" == 0 ]]; then PASS=$((PASS + 1)); echo "  ok   $1"; else FAIL=$((FAIL + 1)); echo "  FAIL $1 — $3"; fi
}
run() { "$BIN" "$@" 2> "$ROOT/build_smoke/stderr.txt"; }

echo "native smoke matrix"
for f in speech.wav speech.mp3 speech.m4a speech.mkv speech.webm speech_video.mp4 "Тест запись ü.m4a"; do
  out="$(run "$FX/$f" "$MODEL")"
  echo "$out" | grep -q "DONE status=0 " && echo "$out" | grep -qi "fox"
  check "transcribes $f" $? "$(echo "$out" | grep -E 'DONE|SEGMENT' | head -3)"
done

out="$(run "$FX/no_audio.mp4" "$MODEL")"; echo "$out" | grep -q "DONE status=5 "; check "no_audio.mp4 → NO_AUDIO" $? "$(echo "$out" | grep DONE)"
out="$(run "$FX/corrupt.mp3" "$MODEL")"; echo "$out" | grep -qE "DONE status=(2|3) "; check "corrupt.mp3 → OPEN/DECODE" $? "$(echo "$out" | grep DONE)"
out="$(run "$FX/truncated.mp3" "$MODEL")"; echo "$out" | grep -q "DONE status=0 "; check "truncated.mp3 keeps decoded part" $? "$(echo "$out" | grep DONE)"
out="$(run "$FX/missing-file.wav" "$MODEL")"; echo "$out" | grep -q "DONE status=2 "; check "missing file → OPEN" $? "$(echo "$out" | grep DONE)"
out="$(run "$FX/speech.wav" "$FX/speech.wav")"; echo "$out" | grep -q "DONE status=4 "; check "bad model → MODEL" $? "$(echo "$out" | grep DONE)"

for f in playlist.ffconcat playlist.m3u8; do
  out="$(run "$FX/$f" "$MODEL")"
  echo "$out" | grep -qE "DONE status=(2|5) " && ! echo "$out" | grep -q "SEGMENT"
  check "$f refused (no nested open)" $? "$(echo "$out" | grep -E 'DONE|SEGMENT' | head -2)"
done

out="$(run "$FX/delayed_audio.mp4" "$MODEL")"
first="$(echo "$out" | awk '/^SEGMENT/{print $2; exit}')"
[[ -n "$first" && "$first" -ge 4500 ]]; check "delayed audio → first segment ≥ 5 s (got ${first:-none})" $? ""

out="$(run "$FX/gap3s.mkv" "$MODEL")"
last="$(echo "$out" | awk '/^SEGMENT/{v=$3} END{print v}')"
[[ -n "$last" && "$last" -ge 9000 ]]; check "3 s gap shifts timestamps (last end ${last:-none} ms)" $? ""

out="$(run "$FX/gap60s.mkv" "$MODEL")"
last="$(echo "$out" | awk '/^SEGMENT/{v=$3} END{print v}')"
chunks="$(echo "$out" | grep -c '"stage":"chunk"')"
[[ -n "$last" && "$last" -ge 60000 && "$chunks" -ge 2 ]]; check "60 s gap jumps clock without transcribing silence (last ${last:-none} ms, $chunks chunks)" $? ""

start=$(date +%s)
out="$(run "$FX/pts_jump.mkv" "$MODEL")"
took=$(( $(date +%s) - start ))
echo "$out" | grep -q "DONE status=0 " && [[ $took -lt 60 ]]; check "extreme PTS jump completes in bounded time (${took}s)" $? "$(echo "$out" | grep DONE)"

out="$(run "$FX/unknown_duration.webm" "$MODEL")"
echo "$out" | grep -q "DONE status=0 " && ! echo "$out" | grep -E "^PROGRESS" | grep -vq "PROGRESS -1"
check "unknown duration → only indeterminate progress" $? "$(echo "$out" | grep -E 'PROGRESS|DONE' | head -4)"

out="$(run "$FX/long_continuous.m4a" "$MODEL")"
echo "$out" | grep -q "DONE status=0 " &&
  echo "$out" | awk '/^SEGMENT/{ if ($2 < prev) bad=1; prev=$2 } END{exit bad}' &&
  [[ "$(echo "$out" | grep -c '"stage":"chunk"')" -ge 3 ]]
check "long continuous: 3 chunks, monotonic timestamps" $? "$(echo "$out" | grep -E 'DONE|chunk')"
last="$(echo "$out" | awk '/^SEGMENT/{v=$3} END{print v}')"
dur="$(echo "$out" | sed -n 's/^DONE.*duration=\([0-9]*\).*/\1/p')"
[[ -n "$last" && -n "$dur" && $((dur - last)) -lt 3000 ]]; check "EOF tail kept (last end $last of $dur ms)" $? ""
echo "$out" | awk '/^PROGRESS/{ if ($2 < prev) bad=1; prev=$2 } END{exit bad}'; check "progress monotonic" $? ""

out="$(run "$FX/steady_tone.wav" "$MODEL")"
echo "$out" | grep -q '"index":0,"audio_ms":180000,'
check "steady signal → forced cut at exactly 180 s" $? "$(echo "$out" | grep '"stage":"chunk"' | head -1)"

out="$(run "$FX/long_boundary.m4a" "$MODEL")"
echo "$out" | grep -q "DONE status=0 " && echo "$out" | grep -qi "purple elephant"
check "phrase before silence-aligned cut survives" $? "$(echo "$out" | grep -iE 'purple|elephant|DONE')"

out="$(run "$FX/long_continuous.m4a" "$MODEL" auto 0 1500)"
echo "$out" | grep -q "DONE status=1 " && [[ "$(echo "$out" | tail -1 | cut -c1-4)" == "DONE" ]]
check "cancel during inference → CANCELLED, DONE last" $? "$(echo "$out" | tail -2)"
out="$(run "$FX/speech.wav" "$MODEL" auto 0 0)"
echo "$out" | grep -q "DONE status=1 " && [[ "$(echo "$out" | tail -1 | cut -c1-4)" == "DONE" ]]
check "cancel during open/model load → CANCELLED" $? "$(echo "$out" | tail -2)"

! grep -q "$FX" "$ROOT/build_smoke/stderr.txt" && [[ ! -s "$ROOT/build_smoke/stderr.txt" ]]
check "native libraries print nothing (no paths in logs)" $? "$(head -3 "$ROOT/build_smoke/stderr.txt")"

echo "passed $PASS, failed $FAIL"
[[ $FAIL -eq 0 ]]
