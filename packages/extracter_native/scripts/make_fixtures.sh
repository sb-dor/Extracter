#!/usr/bin/env bash
# Dev-only: generates the media fixtures and fetches the tiny.en test model.
# Needs macOS `say` and a host `ffmpeg` CLI (Homebrew). Nothing here ships.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/test_fixtures"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-tiny.en-q5_1.bin"
MODEL_SHA="c77c5766f1cef09b6b7d47f21b546cbddd4157886b3b5d6d4f709e91e66c7c2b"
FF=(ffmpeg -hide_banner -loglevel error -y)

mkdir -p "$OUT"
cd "$OUT"

if [[ ! -f ggml-tiny.en-q5_1.bin ]] || [[ "$(shasum -a 256 ggml-tiny.en-q5_1.bin | cut -d' ' -f1)" != "$MODEL_SHA" ]]; then
  curl -fsSL "$MODEL_URL" -o ggml-tiny.en-q5_1.bin
  [[ "$(shasum -a 256 ggml-tiny.en-q5_1.bin | cut -d' ' -f1)" == "$MODEL_SHA" ]] || { echo "model hash mismatch" >&2; exit 1; }
fi

SPEECH="The quick brown fox jumps over the lazy dog. Offline transcription keeps every recording on this device."
PHRASE="The purple elephant dances at midnight."
FILLER="Weather reports describe clouds, rain and sunshine across the northern hills while farmers check their fields and the river keeps flowing toward the sea."

say -o speech.aiff "$SPEECH"
say -o phrase.aiff "$PHRASE"
say -o filler.aiff "$FILLER"

"${FF[@]}" -i speech.aiff -ar 44100 -ac 2 speech.wav
"${FF[@]}" -i speech.aiff -c:a libmp3lame -b:a 128k speech.mp3
"${FF[@]}" -i speech.aiff -c:a aac -b:a 96k speech.m4a
"${FF[@]}" -i speech.aiff -c:a libopus -b:a 48k speech.mkv
"${FF[@]}" -i speech.aiff -ac 2 -c:a vorbis -strict experimental speech.webm
"${FF[@]}" -f lavfi -i testsrc=size=320x240:rate=25 -i speech.aiff -shortest -c:v libx264 -pix_fmt yuv420p -c:a aac speech_video.mp4
"${FF[@]}" -f lavfi -i testsrc=size=320x240:rate=25:duration=4 -c:v libx264 -pix_fmt yuv420p no_audio.mp4
cp speech.m4a "Тест запись ü.m4a"
size=$(stat -f%z speech.mp3); head -c $((size / 2)) speech.mp3 > truncated.mp3
head -c 4096 /dev/urandom > corrupt.mp3

# Audio starts 5 s after the video.
"${FF[@]}" -f lavfi -i testsrc=size=320x240:rate=25:duration=14 -itsoffset 5 -i speech.aiff \
  -c:v libx264 -pix_fmt yuv420p -c:a aac delayed_audio.mp4

# PTS gaps inside one audio stream: +3 s after 4 s, and +60 s after 4 s.
"${FF[@]}" -i speech.aiff -af "asetpts='PTS+if(gte(T,4),3/TB,0)'" -c:a pcm_s16le gap3s.mkv
"${FF[@]}" -i speech.aiff -af "asetpts='PTS+if(gte(T,4),60/TB,0)'" -c:a pcm_s16le gap60s.mkv
"${FF[@]}" -i speech.aiff -af "asetpts='PTS+if(gte(T,4),36000/TB,0)'" -c:a pcm_s16le pts_jump.mkv

# Unknown duration: live WebM has no Duration element and no cues.
"${FF[@]}" -i speech.aiff -c:a libopus -f webm -live 1 unknown_duration.webm

# ~7 min continuous speech over constant noise → no quiet window → forced 180 s cut.
"${FF[@]}" -stream_loop 60 -i filler.aiff -f lavfi -i "anoisesrc=color=pink:amplitude=0.08:duration=420" \
  -filter_complex "[0:a]aresample=16000,atrim=0:420[s];[1:a]aresample=16000[n];[s][n]amix=inputs=2:duration=shortest" \
  -ac 1 -c:a aac long_continuous.m4a

# A perfectly steady 500 Hz tone at 16 kHz: every 500 ms window has the same RMS,
# so no window is quieter than the median and the cut is forced at exactly 180 s.
"${FF[@]}" -f lavfi -i "sine=frequency=500:sample_rate=16000:duration=200" -ac 1 -c:a pcm_s16le steady_tone.wav

# ~7 min with a known phrase followed by a 1 s pause ending ~5 s before 180 s.
"${FF[@]}" -stream_loop 30 -i filler.aiff -af "aresample=16000,atrim=0:170" -ac 1 part_a.wav
"${FF[@]}" -i phrase.aiff -af "aresample=16000" -ac 1 part_phrase.wav
"${FF[@]}" -f lavfi -i "anullsrc=r=16000:cl=mono" -t 1.2 part_pause.wav
"${FF[@]}" -stream_loop 30 -i filler.aiff -af "aresample=16000,atrim=0:240" -ac 1 part_b.wav
printf "file 'part_a.wav'\nfile 'part_phrase.wav'\nfile 'part_pause.wav'\nfile 'part_b.wav'\n" > parts.txt
"${FF[@]}" -f concat -safe 0 -i parts.txt -c:a aac long_boundary.m4a
rm -f part_*.wav parts.txt

# Inputs that try to open other local files: must fail without reading them.
printf "ffconcat version 1.0\nfile 'speech.wav'\n" > playlist.ffconcat
printf "#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\nspeech.wav\n#EXT-X-ENDLIST\n" > playlist.m3u8

ls -la "$OUT"
