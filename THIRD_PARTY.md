# Third-party components

Lightweight SBOM for Extracter. Every input is pinned; build scripts verify hashes.

| Component | Version / pin | Source | SHA-256 | Licence | How it ships |
|---|---|---|---|---|---|
| whisper.cpp + ggml | v1.9.5, commit `d1be6fde11ac6e0407606b4e42fe72d34add8037` (tag object `d2a764c6…`) | git submodule `packages/extracter_native/third_party/whisper.cpp` | (git commit) | MIT | Static library linked into `extracter_native` |
| FFmpeg | 8.1.3 | https://ffmpeg.org/releases/ffmpeg-8.1.3.tar.xz | `7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3` | LGPL-2.1-or-later | **Dynamically linked**: `FFmpeg.framework` (Apple), `libffmpeg.so` (Android/Linux), `ffmpeg.dll` (Windows) |
| zlib | OS-provided | system SDK / NDK | — | zlib | System library |

## Whisper models (downloaded at runtime, never bundled)

From https://huggingface.co/ggerganov/whisper.cpp at the immutable revision
`5359861c739e955e79d9a303bcbc70fb988958b1`. Licence: MIT (OpenAI Whisper weights,
ggml conversion by the whisper.cpp project). Each file is verified by size and SHA-256
before it is installed.

| Model | File | Bytes | SHA-256 |
|---|---|---|---|
| tiny | ggml-tiny-q5_1.bin | 32152673 | `818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7` |
| base | ggml-base-q5_1.bin | 59707625 | `422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898` |
| small | ggml-small-q5_1.bin | 190085487 | `ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb` |
| medium | ggml-medium-q5_0.bin | 539212467 | `19fea4b380c3a618ec4723c3eef2eb785ffba0d0538cf43f8f235e7b3b34220f` |
| large-v3-turbo | ggml-large-v3-turbo-q5_0.bin | 574041195 | `394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2` |
| tiny.en (tests only) | ggml-tiny.en-q5_1.bin | 32166155 | `c77c5766f1cef09b6b7d47f21b546cbddd4157886b3b5d6d4f709e91e66c7c2b` |

## FFmpeg build profile

Built unmodified from the tarball above by `packages/extracter_native/scripts/build_ffmpeg.sh`,
with the same flags on every platform (plus per-target cross-compile flags):

```
--disable-programs --disable-doc --disable-debug
--disable-avdevice --disable-avfilter --disable-swscale
--disable-encoders --disable-muxers
--disable-network --disable-protocols --enable-protocol=file
--disable-autodetect --enable-zlib
--disable-gpl --disable-nonfree --disable-hwaccels
--disable-decoders --enable-decoder=<all 213 audio/PCM/DPCM/ADPCM decoders in libavcodec/allcodecs.c>
--disable-demuxer=concat,hls,dash,imf,webm_dash_manifest,ffmetadata,mpl2,tedcaptions,<all image* demuxers>
--enable-pic --enable-static --disable-shared
```

The static archives are then linked into one shared library per target, so FFmpeg stays
replaceable by the user (LGPL §6). The exact `FFMPEG_CONFIGURATION` string of a build is
written to `third_party/ffmpeg-configuration.txt` and shown in the app's licence page.

**Not legal advice:** codec patents and App Store distribution of LGPL code should be
reviewed before a public release.
