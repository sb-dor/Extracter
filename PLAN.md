# Plan: Extracter — offline speech-to-text for any audio/video file (Flutter)
_Locked via grill — by Claude + Avaz · Revision 5 (after Codex round 5 — MAX_ROUNDS reached)_

## Pinned inputs
| Input | Pin |
|---|---|
| whisper.cpp | tag `v1.9.5` (tag object `d2a764c6…`), submodule pinned to peeled commit `d1be6fde11ac6e0407606b4e42fe72d34add8037` |
| FFmpeg | `https://ffmpeg.org/releases/ffmpeg-8.1.3.tar.xz`, SHA-256 `7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3` |
| Models | `https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/<file>` |

| Model id | File | Bytes | SHA-256 | multilingual | translate | min RAM |
|---|---|---|---|---|---|---|
| tiny | ggml-tiny-q5_1.bin | 32152673 | 818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7 | yes | yes | any |
| base | ggml-base-q5_1.bin | 59707625 | 422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898 | yes | yes | any |
| small | ggml-small-q5_1.bin | 190085487 | ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb | yes | yes | 4 GB |
| medium | ggml-medium-q5_0.bin | 539212467 | 19fea4b380c3a618ec4723c3eef2eb785ffba0d0538cf43f8f235e7b3b34220f | yes | yes | 8 GB |
| large-v3-turbo | ggml-large-v3-turbo-q5_0.bin | 574041195 | 394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2 | yes | **no** | 8 GB |
| _test fixture_ tiny.en | ggml-tiny.en-q5_1.bin | 32166155 | c77c5766f1cef09b6b7d47f21b546cbddd4157886b3b5d6d4f709e91e66c7c2b | no | no | any |

## Goal
A Flutter app for **Android, iOS, macOS, Windows and Linux** (no web) that turns audio or video files
into text **fully on-device**. A pinned, decode-only LGPL FFmpeg build demuxes/decodes every format its
built-in (non-external, non-GPL) demuxers/decoders support and resamples to 16 kHz mono float PCM;
whisper.cpp transcribes it. Users pick one or many files (plus drag-and-drop on desktop) into a
sequential queue with live progress, live segments and cancel. Results are timestamped segments,
copyable and exportable as TXT/SRT/VTT, with auto/selected language and a translate-to-English toggle
(where the model supports it). Whisper models are downloaded on demand from pinned Hugging Face
revisions and SHA-256 verified. Finished transcripts are saved in a local Drift history (FTS search,
pagination, detail, delete). Dart code follows `avera-web-flutter/docs/AI_INSTRUCTIONS.md`, except the
deviations listed in Decisions 7 and 11.

## Approach

### 0. Repo bootstrap & prerequisites
1. `git init`; `.gitignore` covers native build outputs (`packages/extracter_native/third_party/ffmpeg/`,
   `*.xcframework`, `build/`).
2. Host tools (documented in README): `brew install cmake pkg-config nasm`; Android NDK r28+
   (28.2 is installed); Xcode 26. Windows host: VS 2022 + CMake; Linux host: build-essential, nasm.
3. Dart deps: `control`, `freezed_annotation`/`freezed`, `drift`/`drift_flutter`/`drift_dev`,
   `sqlite3_flutter_libs`, `shared_preferences`, `path_provider`, `path`, `http`, `crypto`,
   `file_picker`, `desktop_drop`, `share_plus`, `file_selector`, `wakelock_plus`,
   `flutter_localizations`/`intl`/`intl_utils`, `l`, `ffigen`, `build_runner`.
4. `lib/main.dart` + `lib/src/common/` + `lib/src/feature/` as the doc requires.

### 1. Native plugin `packages/extracter_native` (`plugin_ffi` template)
**Pinned third-party code** (recorded in `THIRD_PARTY.md` with version, URL, SHA-256, licence)
- `third_party/whisper.cpp` — git submodule at the pinned commit above (MIT).
- FFmpeg — the pinned 8.1.3 tarball, SHA-256 checked by the script before extraction.
  `scripts/build_ffmpeg.sh <platform>` configures **default (LGPL) builds minus everything not needed**:
  `--disable-programs --disable-doc --disable-avdevice --disable-avfilter --disable-swscale
  --disable-encoders --disable-muxers --disable-network --disable-protocols --enable-protocol=file
  --disable-autodetect --disable-gpl --disable-nonfree --enable-shared --disable-static`
  (no `--disable-everything`, so all built-in demuxers/decoders/parsers stay enabled; no external
  libs), **plus a denylist of multi-resource / non-audio demuxers** that open other files or are
  irrelevant: `--disable-demuxer=concat,hls,dash,imf,webm_dash_manifest,image2,image2pipe,`
  `image_*_pipe,ffmetadata,mpl2,tedcaptions` (exact list audited against `ffmpeg -demuxers` of 8.1.3
  and recorded in `THIRD_PARTY.md`). The exact flags are written into `THIRD_PARTY.md` and the About screen.
  Outputs (gitignored) → `packages/extracter_native/third_party/ffmpeg/<platform>/`:
  - iOS (arm64 device, arm64 simulator) and macOS (arm64 + x86_64): dynamic `.framework`s
    assembled into `.xcframework`s.
  - Android: `.so` for `arm64-v8a` and `x86_64` only (no `armeabi-v7a`), NDK r28 (16 KB pages).
  - Linux x86_64: built from the same tarball, shipped in the bundle `lib/` with `RPATH=$ORIGIN`
    (no dependency on distro libav*).
  - Windows x64: built from the same tarball and flags with MSYS2 + MinGW-w64 (`--target-os=mingw32`),
    producing DLLs + `.lib` import libraries usable from MSVC. **No third-party prebuilt fallback** —
    every platform ships the identical configuration, so one codec matrix, SBOM and LGPL notice apply.
- `scripts/build_whisper_apple.sh` wraps whisper.cpp's `build-xcframework.sh` with Metal + embedded
  shaders and our deployment targets → `whisper.xcframework`.
- Android/Windows/Linux compile whisper.cpp via CMake `add_subdirectory` as a **single static CPU
  backend** (`GGML_NATIVE=OFF`, `GGML_BACKEND_DL=OFF`, `BUILD_SHARED_LIBS=OFF`) linked into the shim:
  - Android arm64-v8a: plain `armv8-a` baseline (no global v8.2/dotprod flags — keeps Cortex-A53-class
    devices working; slower but correct). x86_64 emulator: SSE4.2 baseline.
  - Windows/Linux x86_64: documented baseline **x86-64-v3**. Every ISA option is set explicitly:
    `GGML_SSE42=ON GGML_AVX=ON GGML_AVX2=ON GGML_FMA=ON GGML_F16C=ON GGML_BMI2=ON`, and
    `GGML_AVX_VNNI/AVX512*/AMX*=OFF` — Haswell (2013)+ / Zen+. `ex_cpu_supported()` (compiled without
    those flags, called before any ggml code) checks CPUID for SSE4.2, AVX, AVX2, FMA, F16C, BMI2, OSXSAVE
    **and** `XGETBV` that the OS saves YMM state; unsupported → explanatory error screen, no crash.

**C ABI (`src/extracter_native.h`)**
```c
#ifdef __cplusplus
extern "C" {
#endif
#if defined(_WIN32)
  #define EX_API __declspec(dllexport)
#else
  #define EX_API __attribute__((visibility("default"))) __attribute__((used))
#endif

#define EX_API_VERSION 1

typedef enum { EX_EV_PROGRESS = 0, EX_EV_SEGMENT = 1, EX_EV_DONE = 2, EX_EV_LOG = 3 } ex_event_kind;
typedef enum { EX_OK = 0, EX_CANCELLED = 1, EX_ERR_OPEN = 2, EX_ERR_DECODE = 3,
               EX_ERR_MODEL = 4, EX_ERR_NO_AUDIO = 5, EX_ERR_OOM = 6, EX_ERR_INTERNAL = 7,
               EX_ERR_TIMEOUT = 8 } ex_status;

typedef struct ex_event {          // heap-allocated by native, owned by Dart until ex_event_free
  int64_t  job_id;
  int32_t  kind;                   // ex_event_kind
  int32_t  status;                 // DONE only
  int32_t  progress_permille;      // PROGRESS: 0..999 (1000 only via DONE); -1 = indeterminate
  int64_t  t0_ms, t1_ms;           // SEGMENT
  int64_t  duration_ms;            // first PROGRESS + DONE; -1 if unknown
  char*    text;  int32_t text_len;   // SEGMENT text / DONE detected language / LOG: allowlisted JSON
  int32_t  native_code;               // DONE: numeric AVERROR / whisper return code, 0 if none
  // No native library text is ever carried; Dart maps (status, native_code) to localized messages.
} ex_event;

typedef void (*ex_event_cb)(ex_event* ev);

EX_API int32_t ex_api_version(void);
EX_API const char* ex_build_info(void);         // static string: versions + configure flags
EX_API int32_t ex_init(ex_event_cb cb);          // once; registers the single global callback
// All string arguments are deep-copied into the Job before ex_job_start returns;
// the caller may free them immediately.
EX_API int64_t ex_job_start(const char* media_path_utf8, const char* model_path_utf8,
                            const char* language /* "auto" | ISO-639-1 */, int32_t translate,
                            int32_t n_threads);  // > 0 job id; < 0 = -ex_status (sync failure)
EX_API void    ex_job_cancel(int64_t job_id);    // idempotent; unknown/finished id = no-op
EX_API void    ex_event_free(ex_event* ev);
EX_API int32_t ex_cpu_supported(void);          // x86_64: CPUID+XGETBV baseline check; else 1
EX_API int64_t ex_total_ram_bytes(void);
EX_API int64_t ex_free_disk_bytes(const char* dir_path_utf8);
EX_API void    ex_shutdown(void);                // cancels all jobs and joins worker threads
#ifdef __cplusplus
}
#endif
```
- **Callback lifetime:** Dart creates **one** `NativeCallable<ex_event_cb>.listener` at startup and
  **never closes it** — it lives for the whole process (`keepIsolateAlive = false`). So there is no
  window where native can call a closed callable, and events still queued at process exit are
  reclaimed by the OS. Every event is `malloc`ed by native, delivered asynchronously, copied by Dart,
  then released with `ex_event_free` **in a `finally` block** of the listener, so malformed UTF-8
  (decoded with `allowMalformed: true`), a missing/closed job stream or any routing exception can
  never skip the free.
- **Job lifetime:** a mutex-protected registry `job_id → shared_ptr<Job>` holding the
  `std::thread`. A job **stays registered until its thread has exited**: the worker frees its
  resources, emits `DONE` (exactly once, always the last event for that id), marks itself
  `finished`; a reaper step (run at the next `ex_job_start` and in `ex_shutdown`) joins finished
  threads and only then erases them. Cancel looks up under the lock and sets an atomic flag;
  unknown/finished ids are a no-op. `ex_shutdown` (called on `AppLifecycleState.detached` /
  desktop window close) cancels all jobs and joins every thread.
- **Model-load cancellation is delayed, not interrupting:** whisper.cpp's loader cannot be aborted
  safely mid-read, so a cancel during model load takes effect right after
  `whisper_init_from_file_with_params` returns (context freed, `DONE(CANCELLED)`). Latency is bounded
  by load time (measured and logged; target < 3 s for large-v3-turbo on a modern device); the queue
  shows `cancelling` meanwhile. No whisper.cpp patches.
- **No separate probe call:** probing happens inside the worker (`probesize`/`analyzeduration`
  limits, interrupt callback honoured), reported via `DONE(EX_ERR_OPEN|EX_ERR_NO_AUDIO)`.
- **Exceptions:** every exported function and the worker body are wrapped in `try/catch(...)` →
  `EX_ERR_INTERNAL`; nothing throws across the ABI. Paths are UTF-8 everywhere; on Windows the shim
  converts to UTF-16 only where needed (FFmpeg's `file:` protocol accepts UTF-8 on Windows).
- **Native logging:** before any FFmpeg/whisper call, `ex_init` installs `av_log_set_callback` and
  `whisper_log_set` handlers that **never forward native text** — they only count warnings/errors
  per job. Nothing goes to stderr/logcat/OSLog. Diagnostics are exclusively our own allowlisted
  structured `LOG` events (stage, elapsed ms, realtime factor, codec/container *names*, sample rate,
  channel count, numeric FFmpeg/whisper error codes, warning counts, `ex_build_info`). `DONE` carries
  only `status` + numeric `native_code`; user-facing text is a localized message chosen in Dart.
- **Input sandbox (defence in depth):** (a) the build-time demuxer denylist above removes
  concat/HLS/DASH/IMF/image-sequence inputs — the ones that create nested contexts which don't
  inherit `io_open`; (b) the worker also installs a custom `AVFormatContext.io_open` permitting only
  the exact selected path (`AVERROR(EPERM)` otherwise). Fixtures: a concat script and an HLS
  playlist referencing another local file must fail with `EX_ERR_OPEN` and never read the referenced
  file.
- **Wall-clock bound:** `AVIOInterruptCB` checks both the cancel flag and a monotonic deadline
  (open + `find_stream_info` must finish within 20 s); deadline expiry → `EX_ERR_TIMEOUT`, distinct
  from `EX_CANCELLED`. Fixture: a pathological input that would probe indefinitely.
- **Pipeline:** `avformat_open_input` (interrupt CB, `io_open` policy) →
  `avformat_find_stream_info` (`probesize` 32 MB, `analyzeduration` 30 s of media, plus the 20 s
  wall-clock deadline above)
  → `av_find_best_stream(AUDIO)` → decode →
  `swr_convert` → 16 kHz mono `float` ring buffer → **chunking**: target 180 s chunks; the cut is
  placed at the lowest-RMS 500 ms window inside the last 15 s of the chunk (no overlap; cut in silence
  so words aren't split); `whisper_full` per chunk with `new_segment_callback` → `SEGMENT` events
  stream live, timestamps offset by chunk start; previous chunk's last ~200 chars become
  `initial_prompt` (`no_context=false`). Whisper `abort_callback` reads the cancel flag.
  If no window in the last 15 s is quieter than the chunk median, the cut falls at the 180 s mark
  (**accepted limitation:** a word spoken exactly across a forced cut in continuous speech may be
  lost or garbled; overlap + dedup was rejected as too complex for v1).
- **Media clock:** the PCM timeline follows decoded-frame PTS (`best_effort_timestamp`, rescaled with
  overflow-checked `av_rescale_q_rnd` to 16 kHz samples) relative to the **container origin**
  `AVFormatContext.start_time` (if `AV_NOPTS_VALUE`, the earliest stream `start_time`, else 0), so an
  audio track starting 5 s into a video yields segments starting at 5 s. Gaps 100 ms–10 s are filled
  with silence; **gaps > 10 s are not materialised** — the current chunk is flushed/transcribed and
  the next chunk's start time jumps to the new PTS (segment time = chunk media start + whisper t).
  Backward jumps / overlaps drop samples; non-monotonic or out-of-range PTS (> 48 h, overflow) fall
  back to the running sample clock. Frames without PTS continue the running clock.
- **EOF draining:** on `AVERROR_EOF` from `av_read_frame`, send a `NULL` packet and drain
  `avcodec_receive_frame` until `AVERROR_EOF`; then `swr_convert(out, n, NULL, 0)` until it returns 0
  to flush delayed resampler samples; the final partial chunk is always transcribed.
- **Progress:** monotonic permille = (chunk_start + whisper_progress × chunk_len) / duration, clamped
  to never decrease and capped at 999 until `DONE`; `-1` (indeterminate) when duration is unknown.
- **Memory:** ≤ 180 s PCM per chunk (~12 MB) + model; one job at a time.
- **Diagnostics:** `LOG` events carry stage timings (open, first-decode, model-load, per-chunk
  inference ms, realtime factor), numeric native error codes and `ex_build_info()`; never native
  text, paths, audio or transcript text.
- Dart side: `ffigen` bindings + explicit loader (`libextracter_native.so` / `.dylib` via framework
  / `extracter_native.dll`), `ex_api_version()` checked at startup → fatal error screen on mismatch.

**Per-platform build glue**
- Android: Gradle `externalNativeBuild` → `src/CMakeLists.txt`; FFmpeg `.so` in `jniLibs`;
  `abiFilters arm64-v8a, x86_64`; NDK r28+; CI-style check script verifies 16 KB ELF alignment
  (`llvm-readelf -l`) and `zipalign -c -P 16`. Main manifest gets `INTERNET`;
  `android:allowBackup="false"` + `dataExtractionRules` excluding everything.
- iOS/macOS: podspec `vendored_frameworks` (whisper + FFmpeg xcframeworks), compiles `src/*.cpp`,
  links `Metal`, `MetalKit`, `Accelerate`. Deployment targets **iOS 16.4 / macOS 13.3** (upstream
  `build-xcframework.sh` defaults; Runner projects bumped from 15.0/12.0). macOS entitlements
  (Debug + Release): `com.apple.security.files.user-selected.read-write` (open + Save-as export),
  `com.apple.security.network.client`. On iOS/macOS the whole Application Support directory
  (database + models) is marked `isExcludedFromBackup`.
- Windows: CMake builds whisper + shim; FFmpeg DLLs listed in `extracter_native_bundled_libraries`.
- Linux: CMake builds whisper + shim, links bundled FFmpeg `.so`, installs them to bundle `lib/`.
- **Supported model matrix** (enforced in the catalogue, by `ex_total_ram_bytes()`):
  < 4 GB RAM → tiny, base; 4–8 GB → + small; ≥ 8 GB → + medium, large-v3-turbo. Free disk must
  exceed model size + 10 % before download starts.

### 2. Dart common layer (`lib/src/common/`)
- `database/` — Drift `AppDatabase` (`schemaVersion 1`):
  - `TranscriptsTable` (id, sourceName — **no source path**, durationMs, language, modelId,
    translated, createdAt, fullText); `SegmentsTable` (transcriptId FK `ON DELETE CASCADE`, idx,
    t0Ms, t1Ms, text); `TranscriptsFts` FTS5 external-content table over (sourceName, fullText)
    kept in sync by triggers.
  - `beforeOpen`: `PRAGMA foreign_keys = ON`. Save (transcript + segments) and delete run in one
    transaction.
  - **Keyset pagination:** `ORDER BY createdAt DESC, id DESC`, next page =
    `WHERE (createdAt, id) < (:lastCreatedAt, :lastId)`. The cursor (last pair) lives in the
    `completed` state (the doc's "cursor in state" rule, with a keyset cursor instead of a page int);
    `hasMore` from page fullness via `LocalPaginationUtil`. New/deleted rows can't shift pages.
  - **FTS input sanitising:** user text is split on whitespace, each token stripped of `"`, empty
    tokens discarded, the rest wrapped as `"token"*` and joined with spaces — never raw `MATCH`
    syntax. If no tokens remain (blank / whitespace / quote-only input) FTS is bypassed and the plain
    keyset list is returned. Tested with blank, whitespace-only and quote-only queries.
- `dependencies/` — `Dependencies` + `DependenciesScope`: sharedPreferences, database, http client,
  `ExtracterNative` (singleton owning the listener + an event `Stream` per job), `ModelStore`.
- `model_store/` — **single coordinator** for model files: per-model state (`absent | downloading |
  verifying | installed`), an in-use lease count taken by a running job, delete refused while
  leased/downloading, download refused while deleting. All three model features and the queue go
  through it (via their repositories).
- `localization/` (en, ru via intl_utils), `utils/` (`LocalPaginationUtil`, `screenSizeMaybeWhen`,
  `transcript_formatters.dart` pure `toTxt/toSrt/toVtt`, `whisper_languages.dart`, redacting
  `AppLogger`), `widget/` (adaptive shell, empty/error/loading, `TryAgainButton`,
  `AdaptiveDialogWidget`).

### 3. Features (`lib/src/feature/`)
| Feature | Responsibility | Handler |
|---|---|---|
| `transcription_settings/` | Load persisted model, language, translate (SharedPreferences) | Sequential |
| `transcription_settings_save/` | Persist the full settings draft | Droppable + latest-wins re-trigger |
| `transcription_queue/` | Enqueue (pick/drop), run jobs one at a time, progress/segments, save to history | Sequential runner + out-of-band cancel |
| `whisper_models/` | Catalogue + capability metadata + installed state (from `ModelStore`) | Sequential |
| `whisper_model_download/` | Download / resume / verify / cancel | Droppable start + out-of-band cancel |
| `whisper_model_deletion/` | Delete installed model (refused while leased) | Droppable |
| `transcripts/` | History list, FTS search, pagination | Sequential |
| `transcript_detail/` | By-id loader + detail (segments, copy all, export buttons) | Sequential |
| `transcript_save/` | Retry saving a `completedUnsaved` transcript | Droppable |
| `transcript_deletion/` | Delete dialog | Droppable |
| `transcript_export/` | TXT/SRT/VTT → share sheet (mobile) / Save-as (desktop) | Droppable |

- **Settings:** the `ChangeNotifier` data controller holds the in-memory draft
  `{modelId, language, translate}`. Load goes through `TranscriptionSettingsController`; persistence
  through `TranscriptionSettingsSaveController` (Droppable, saves the full draft). The config widget
  listens to the draft: on change it calls `save(draft)`; when a save completes and the draft differs
  from what was saved, it calls `save` again — so a change made during an in-flight save is never
  lost. No repository in widgets.
- **Job snapshot:** each queued job captures `{modelId, language, translate}` when enqueued; changing
  settings later never affects queued jobs.
- **Model capabilities:** catalogue entries carry `multilingual`, `supportsTranslate`
  (large-v3-turbo = false), `minRamBytes`, `sizeBytes`, `sha256`, `revisionUrl` — exactly the
  values in the **Pinned inputs** table. The translate toggle is disabled + explained for unsupported
  models. `.en` models only as a test fixture.
- **Transcription stream:** `ITranscriptionRepository.transcribe(job)` → `Stream<TranscriptionEvent>`
  using the `onListen`/`onCancel` pattern: `onListen` acquires a `ModelLease` and calls
  `ex_job_start`; `onCancel` calls `ex_job_cancel`; the stream closes on `DONE`.
- **Model reservation from enqueue to terminal:** `ITranscriptionQueueRepository.enqueue(...)`
  acquires a `ModelReservation` from `ModelStore` for the job's snapshot `modelId` **at enqueue
  time**; deletion is refused while any reservation (pending or running) exists. The repository is
  the **sole owner**: `release()` is idempotent and called exactly once when the job reaches a
  terminal state (done, completedUnsaved, failed, cancelled), is removed while pending, or
  `ex_job_start < 0` (which also adds the mapped failure and closes the stream immediately). The
  queue controller never touches reservations. Unit tests assert exactly-once release for every
  path.
- **Cancellation is out-of-band:** `TranscriptionQueueController.cancel(jobId)` and
  `ModelDownloadController.cancel()` are plain synchronous methods **not** wrapped in `handle()`;
  they flip a token / call `ex_job_cancel`, so they can never be queued behind or dropped by the
  running operation. Cancelling a pending job just removes it from the queue state.
- **Cancel acknowledgement:** cancelling a running job moves it to `cancelling`; the runner keeps
  awaiting that job's stream (the stream ends only on `DONE`, never on the cancel request itself),
  and only after `DONE(CANCELLED)` (lease already released by the repository) does it delete the
  mobile input copy, mark the job `cancelled` and start the next one. So two native workers never
  overlap.
- **Save failure never loses work:** if the Drift transaction fails after `DONE(OK)` (disk full,
  I/O), the job becomes `completedUnsaved(segments, errorCode)` — segments stay in memory with
  **Retry save**, **Copy** and **Export** actions. Retry runs through the separate
  `transcript_save/` feature (Droppable); the queue config widget listens to its `completed` state
  and moves the job to `done(transcriptId)` — so a retry is never serialized behind the next
  transcription. Tested with a failing fake repository.
- **Queue state** (freezed, immutable list): `pending | running(permille, segments) | cancelling |
  done(transcriptId) | completedUnsaved(segments, errorCode) | failed(errorCode) | cancelled`. `wakelock_plus` on while any job runs.
- **Files on mobile:** `file_picker` materialises picked items into its cache; the queue owns those
  copies, checks free space (`ex_free_disk_bytes`) before accepting, and deletes each copy when its
  job ends (done/failed/cancelled) plus `FilePicker.clearTemporaryFiles()` on queue drain and app
  start. Desktop uses real paths (macOS: user-selected read access persists for the session — the
  queue is in-memory so no bookmarks needed).
- **Download protocol:** stream to `<models>/<id>.part` (same directory → atomic rename); resume only
  if the server returns `206` with a `Content-Range` start equal to the `.part` length and matching
  total, otherwise truncate and restart; abort if total ≠ catalogue `sizeBytes`; SHA-256 of the full
  file must match before `flush`+rename; on mismatch delete and report. Release manifest has
  `INTERNET`.
- **Privacy:** no transcript text, file names or paths in logs; Android backup disabled; database
  and models excluded from iOS/macOS backup; DB uses default OS file protection (encryption out of
  scope v1).
- Desktop: NavigationRail shell, history master-detail; mobile: NavigationBar + `Navigator.push`.
  Config widgets expose static `open()` / `show()`.
- All visible strings in `intl_en.arb` + `intl_ru.arb`.

### 4. Licences & compliance
- About screen: whisper.cpp (MIT), FFmpeg (LGPL-2.1) and the Whisper model files (MIT, OpenAI
  weights converted by ggerganov/whisper.cpp — pinned HF revision, URLs, SHA-256s) notices, exact FFmpeg version + configure
  flags (`ex_build_info`), link to the pinned FFmpeg source tarball and our build scripts; FFmpeg is
  dynamically linked on every platform (iOS via embedded dynamic frameworks).
- `THIRD_PARTY.md` = lightweight SBOM (name, version, URL, SHA-256, licence) covering whisper.cpp,
  FFmpeg **and every catalogue model file**.
- Codec-patent and App Store LGPL questions are flagged for the user's legal review before any
  public release (not an engineering task).

### 5. Testing & verification
- Unit: formatters (SRT/VTT edge cases: >1 h, 0 ms, empty text), converters, download protocol
  (fake HTTP: 200 vs 206, wrong Content-Range, size mismatch, hash mismatch), `ModelStore` lease /
  delete races, controllers with fakes (queue transitions, cancel while pending/running, failure,
  snapshot settings, pagination), DB (cascade delete, FTS search, transaction rollback).
- Widget: queue screen, history list, model list (capability gating).
- Fixtures: `scripts/make_fixtures.sh` (dev-only; uses macOS `say` + a host `ffmpeg` CLI from
  Homebrew, never shipped) generates short WAV, MP3, M4A/AAC, MKV/Opus, WebM/Vorbis, MP4/H.264+AAC,
  a video with no audio, a truncated file, a non-ASCII file name, a **~7 min multi-chunk** file of
  continuous speech (no quiet window → forced 180 s cut), a ~7 min file whose known phrase sits
  next to a 1 s pause ~5 s before the 180 s mark (silence-aligned cut), a raw-stream file with
  unknown duration, an MP4 whose audio track starts 5 s after video, an audio file with a 3 s and a
  60 s PTS gap, a file with an extreme PTS jump (hours), a concat script + HLS playlist referencing
  another local file, and a pathological probe input.
- Native integration tests (`integration_test`, `ggml-tiny.en`): non-empty text per format;
  `NO_AUDIO`, `OPEN`/`DECODE` errors without crash; non-ASCII path; multi-chunk → strictly
  monotonic timestamps, known phrase present for the **silence-aligned** cut (forced cut: only
  monotonic timestamps + no crash are asserted), last segment ends within 1 s of media duration
  (EOF/resampler tail kept); unknown duration → permille `-1` until `DONE`; cancel during open /
  model load / inference → `CANCELLED`, no events after `DONE`, next queued job starts only after
  it; FFmpeg/whisper native log output never contains the fixture path; delayed-start MP4 → first
  segment ≥ 5 s; 3 s gap → timestamps shifted by 3 s; 60 s gap → no 60 s of silence transcribed
  and timestamps jump; extreme PTS → completes in bounded time; concat/HLS → `EX_ERR_OPEN` and the
  referenced file is never opened; pathological probe → `EX_ERR_TIMEOUT` within 25 s.

### 6. Acceptance gates (to be satisfied during implementation — none are met yet)
1. `flutter analyze` clean; all unit + widget tests pass.
2. Native integration tests pass on **macOS**, **iOS simulator** and **Android emulator (arm64)**
   on this Mac.
3. Android release AAB passes the 16 KB alignment check script.
4. **Windows and Linux**: CMake/scripts written; marked _unverified_ until built on those hosts.
5. Physical iOS/Android device runs: the user's step, reported separately.

## Key decisions & tradeoffs
1. **On-device Whisper only** — offline/private/free vs slower on weak phones and big downloads.
2. **FFmpeg everywhere, pinned decode-only LGPL build** (all built-in demuxers/decoders, no external
   or GPL libs) — uniform coverage vs ~5–15 MB per platform and a cross-compile script; Linux bundles
   its own FFmpeg instead of system libs.
3. **Own `plugin_ffi` plugin** with a native worker thread, single global `NativeCallable.listener`,
   heap-owned events freed by Dart.
4. **180 s silence-aligned chunks, no overlap, prompt carry-over, live `new_segment_callback`** —
   bounded memory + live output vs minor boundary-quality risk (overlap/dedup rejected as complex).
5. **Model loaded per job** — simple lifecycle vs 1–3 s reload per file for big models.
6. **Sequential in-memory queue, foreground + wakelock**; cancellation is out-of-band.
7. **Simple adaptive shell instead of Avera's `DesktopController`** — user-approved deviation (grill
   Q11) for a 3-screen app.
8. **`plugin_ffi` over `package_ffi` build hooks** — whisper.cpp+Metal xcframework, Gradle jniLibs and
   Windows bundled DLLs are first-class in the plugin template; hooks would need a third-party CMake
   toolchain for ggml. Revisit once hooks support CMake/xcframework natively.
9. **No `armeabi-v7a`**, RAM-tiered model matrix.
10. **Single static CPU backend with fixed baselines** (armv8-a; x86-64-v3) instead of
    `GGML_BACKEND_DL` variants — simpler packaging vs slower on newer CPUs and no pre-2013 x86 support.
11. **Keyset pagination** instead of the doc's page-int cursor — avoids skipped/duplicated rows while
    history changes under the list; cursor still lives in the state. **Second architecture deviation
    from AI_INSTRUCTIONS — approved by the user at sign-off (2026-10-20).**
12. **Delayed model-load cancellation** and **accepted word loss at forced chunk cuts** — both
    avoid patching whisper.cpp.

## Risks / open questions
- FFmpeg cross-compile for iOS simulator/device and Windows is the riskiest build step.
- Windows/Linux not verifiable on this Mac in this session.
- Flutter's CocoaPods → SwiftPM migration may require a `Package.swift` later.
- whisper.cpp hallucination on long silence — built-in VAD can be added later.
- Legal review of codec patents / App Store + LGPL before public release.

## Out of scope
- Web, cloud STT, diarization, word-level timestamps, JSON export, transcript editing.
- Background transcription / Android foreground service, persisted/resumable queue.
- Share-sheet / "Open with" import, GPU backends other than Metal, DB encryption, CI pipelines,
  formal SBOM tooling.
