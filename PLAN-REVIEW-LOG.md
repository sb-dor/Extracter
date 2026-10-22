# Plan Review Log: Extracter — offline speech-to-text for any audio/video file
Act 1 (grill) complete — plan locked with the user. MAX_ROUNDS=5.

## Act 1 decisions
1. STT engine: on-device whisper.cpp
2. Platforms: Android, iOS, macOS, Windows, Linux (no web)
3. Decoding: FFmpeg everywhere
4. Native layer: own FFI plugin
5. Models: download on demand
6. Output: segments + TXT/SRT/VTT, language auto/select, translate toggle
7. History: Drift
8. Input: multi-pick + desktop drag-drop, sequential queue with progress/cancel
9. Mobile background: foreground + wakelock
10. FFmpeg source: decode-only build script (Linux uses system libs)
11. Shell: simple adaptive shell (no DesktopController)

## Round 1 — Codex

The plan is not sound enough to implement. It contains a guaranteed FFI lifetime bug, contradictory platform requirements, and several races that will make cancellation and model management unreliable.

## Critical flaws

1. **Guaranteed use-after-free in FFI callbacks.** [PLAN.md:55](PLAN.md) says callback strings are valid only during the native call, but `NativeCallable.listener` delivers arguments asynchronously through a `SendPort`; pointer memory must remain valid until the Dart callback executes. The current design can read freed segment/error strings. [Dart API documentation](https://api.dart.dev/dart-ffi/NativeCallable/NativeCallable.listener.html)  
   **Fix:** Heap-allocate each callback payload, transfer ownership to Dart, include its byte length, and expose `ex_event_free()` for Dart to call after copying.

2. **The job lifetime API cannot safely cancel or shut down.** The unused `ex_job` type, integer IDs, fire-and-forget `ex_job_cancel`, and closing `NativeCallable`s from `done` do not define registry locking, stale IDs, worker joining, engine shutdown, or the guarantee that no callback can occur after `close()`—which would be undefined behavior.  
   **Fix:** Specify an opaque ref-counted job handle with synchronized lookup, idempotent cancel, completion/join acknowledgement, and `ex_shutdown()` that drains workers before Dart closes callbacks.

3. **`ex_probe` can block the Flutter UI isolate.** `avformat_open_input` and stream discovery can probe megabytes or stall on malformed files, while [PLAN.md:49](PLAN.md) exposes only a synchronous FFI call.  
   **Fix:** Make probing an asynchronous cancellable native job with byte/time limits and structured errors, or fold it into transcription startup.

4. **A path-only API does not cover mobile document pickers.** Android’s Storage Access Framework grants a `content://` URI, while Apple file providers use coordinated/security-scoped URLs; temporary paths may require copying huge media files and may disappear before a queued job runs. [Android SAF documentation](https://developer.android.com/training/data-storage/shared/documents-files), [Apple security-scoped URL documentation](https://developer.apple.com/documentation/foundation/url/startaccessingsecurityscopedresource%28%29)  
   **Fix:** Support file descriptors/custom FFmpeg AVIO plus scoped-resource lifetime management, or explicitly materialize each selection into app-private storage with capacity checks, reference counting, and cleanup.

5. **The proposed FFmpeg configuration is invalid and contradicts “any codec.”** After `--disable-everything`, FFmpeg supports singular `--enable-demuxer=`, `--enable-decoder=`, and `--enable-parser=` options—not the plural enable flags in [PLAN.md:28](PLAN.md); many formats also require external or GPL components. [FFmpeg configure options](https://github.com/FFmpeg/FFmpeg/blob/master/configure)  
   **Fix:** Pin an exact FFmpeg commit, define an explicit LGPL-compatible demuxer/decoder/parser matrix, generate flags from it, and replace “any format” with the tested supported matrix.

6. **The C ABI is not exportable as shown.** The header lacks `extern "C"`, Windows `__declspec(dllexport)`, default visibility/`used` attributes, ABI versioning, loader names, exception containment, and startup-failure semantics. Flutter warns that release link-time optimization can otherwise discard FFI symbols. [Flutter FFI documentation](https://docs.flutter.dev/platform-integration/legacy-ffi-plugin)  
   **Fix:** Add portable export/calling-convention macros, `ex_api_version`, explicit per-platform `DynamicLibrary` loading, negative start error codes, and a rule that no C++ exception crosses the ABI.

7. **Cancellation can be serialized behind the work it must cancel.** A transcription controller using one `SequentialControllerHandler` can queue `cancel()` behind the hours-long stream operation; a droppable download controller can likewise drop a cancel request while download is active.  
   **Fix:** Make cancellation an out-of-band idempotent token/handle operation and split controllers where concurrency differs, as required by `AI_INSTRUCTIONS.md:825`.

8. **Model deletion, download, selection, and transcription can race.** Separate droppable controllers can delete a model while it is being verified or loaded, especially failing unpredictably on Windows, and queued jobs do not snapshot their settings.  
   **Fix:** Introduce a shared model-store coordinator with exclusive download/delete locks, in-use leases, `.part` state, and immutable model/language/translate settings captured when each job is enqueued.

## Incorrect product and whisper.cpp assumptions

9. **Ten-minute buffering is not “live segments.”** No transcript can appear until approximately ten minutes of audio have first been decoded, and a prompt cannot recover speech split at a zero-overlap boundary.  
   **Fix:** Stream `whisper_new_segment_callback` results and use substantially shorter overlapping chunks with deterministic timestamp-aware deduplication and boundary tests.

10. **Progress will jump, stall, regress, or reach 100% too early.** Decode time can reach 100% before the last Whisper run, while the Whisper callback restarts at zero for every chunk and unknown-duration inputs have no valid denominator.  
    **Fix:** Define monotonic stage-weighted aggregate progress, cap it below 100 until `done`, and expose an indeterminate state when duration is unavailable.

11. **The model catalogue is incompatible with a universal translate toggle.** OpenAI documents that the turbo model returns the original language even when translation is requested, and `.en` models cannot provide multilingual auto-detection/translation. [OpenAI Whisper model documentation](https://github.com/openai/whisper)  
    **Fix:** Add model capability metadata and disable unsupported language/translation controls; test every catalogue entry, including the tiny.en smoke-test case.

12. **Mobile model availability is left as an open question although it controls app stability.** Upstream reports roughly 2.1 GB memory for medium and 3.9 GB for large models, making unconditional exposure unsafe on low-memory and 32-bit Android devices. [whisper.cpp memory table](https://github.com/ggml-org/whisper.cpp/blob/master/README.md)  
    **Fix:** Set a supported model matrix per architecture/RAM tier now, remove `armeabi-v7a` or restrict it to small models, and preflight disk and memory before downloading/loading.

13. **The Apple deployment targets are unsupported by the stated build procedure.** The plan promises iOS 14/macOS 11, the current project already targets iOS 15/macOS 12, and current upstream `build-xcframework.sh` defaults to iOS 16.4/macOS 13.3. [Upstream build script](https://github.com/ggml-org/whisper.cpp/blob/master/build-xcframework.sh)  
    **Fix:** Pin the exact whisper.cpp commit, choose one consistent deployment matrix, patch/build the framework for it, and run binaries on the oldest supported OS versions.

## Platform and architecture gaps

14. **The required architecture is explicitly violated.** [PLAN.md:138](PLAN.md) deliberately rejects `DesktopController`, although the governing rules say desktop navigation “must” use it at `AI_INSTRUCTIONS.md:120`; settings persistence is also ambiguous about whether a widget data controller accesses a repository, forbidden at `AI_INSTRUCTIONS.md:1439`.  
    **Fix:** Use `DesktopController.setModule` and module factories, and route settings persistence through an async controller rather than the `ChangeNotifier`.

15. **The plan chooses a legacy FFI template without justification.** This checkout uses Flutter 3.47.1, while Flutter has recommended `package_ffi` build hooks since 3.38. [Flutter’s template guidance](https://docs.flutter.dev/platform-integration/legacy-ffi-plugin)  
    **Fix:** Spike `package_ffi` first and use `plugin_ffi` only if CocoaPods/Gradle platform packaging demonstrably requires it, documenting that constraint.

16. **Android release downloads will fail and native packaging is incomplete.** `INTERNET` exists only in the debug/profile manifests, not [the main manifest](android/app/src/main/AndroidManifest.xml), and no 16 KB ELF/AAB alignment requirement is specified for the shim and FFmpeg libraries. [Android 16 KB guidance](https://developer.android.com/guide/practices/page-sizes)  
    **Fix:** Add release `INTERNET`, build all native libraries with current AGP and NDK r28+, and verify both ELF and AAB 16 KB alignment in CI.

17. **Linux is neither reproducible nor deployable as planned.** Linking whatever system `libav*` happens to be installed creates distro-dependent codecs, ABI failures, and behavior that is not “identical across five platforms.”  
    **Fix:** Either bundle pinned LGPL libraries in a Flatpak/AppImage or declare exact supported distributions/package versions and test every one.

18. **CPU “auto-detect” can produce nonportable binaries.** Build-host-native AVX flags can cause illegal-instruction crashes on older Windows/Linux CPUs.  
    **Fix:** Disable build-host-native tuning for release artifacts, choose a documented baseline ISA, retain runtime dispatch, and test on baseline hardware.

## Security, persistence, and compliance

19. **The download/resume protocol is underspecified and corruptible.** `Range` alone is unsafe when a server ignores it, changes the object, returns a mismatched `Content-Range`, disk fills, or delete/download overlap; “URLs/hashes may change” also normalizes mutable dependencies.  
    **Fix:** Use immutable revision URLs, pinned hashes, `206`/`Content-Range`/ETag validation, size and free-space limits, same-filesystem `.part` files, fsync before rename, and restart cleanly on any mismatch.

20. **The native supply chain and parser attack surface are unmanaged.** An unversioned `n7.x` BtbN artifact and fetched native dependencies have no checksum/signature/SBOM, while FFmpeg parses attacker-controlled files in-process with no patch or CVE policy.  
    **Fix:** Pin every source and binary by immutable revision and SHA-256, publish an SBOM/build provenance, restrict protocols/formats, and define a security-update cadence plus malformed-media corpus tests.

21. **“Offline/private” is misleading with plaintext history and default backups.** Transcripts and source paths are stored unencrypted, Android Auto Backup is enabled by default unless excluded, and logs are not constrained from recording sensitive content. [Android backup documentation](https://developer.android.com/identity/data/autobackup)  
    **Fix:** Remove unnecessary `sourcePath`, define OS file protection/encryption policy, exclude transcripts/models from cloud backup or obtain explicit consent, and prohibit transcript/path content in logs.

22. **Database integrity and search behavior are incomplete.** Cascade deletion needs foreign-key enforcement, transcript plus segments must be inserted atomically, offset/page pagination needs deterministic ordering, and leading-wildcard `LIKE` over unbounded multi-hour text will become a full-table scan.  
    **Fix:** Enable foreign keys in `beforeOpen`, save/delete in transactions, use `(createdAt,id)` keyset ordering, and adopt FTS5 or impose and benchmark a documented history limit.

23. **LGPL compliance is materially incomplete.** `LicenseRegistry` plus dynamic linking does not satisfy FFmpeg’s checklist, which also calls for the exact corresponding source, build configuration and changes, source download link, About/EULA notices, and reverse-engineering terms; codec patent exposure also remains a commercial-release question. [FFmpeg legal checklist](https://www.ffmpeg.org/legal.html)  
    **Fix:** Produce a per-platform compliance bundle and source archive for every shipped binary, audit BtbN’s complete configuration, and obtain distribution counsel for Apple-store and patent implications.

24. **There is no operational observability design.** A logger dependency does not provide stage timings, FFmpeg error strings, native/library versions, build flags, cancellation latency, or enough redacted diagnostics to distinguish decode, model, FFI, and packaging failures.  
    **Fix:** Define structured local diagnostics keyed by job ID with stage, native error code/string, versions/build config, timings and resource use, while redacting paths, audio, and transcript text.

25. **Testing ignores most of the risky surface.** Two smoke targets do not verify five build systems, Apple Metal, Windows DLL deployment, Linux ABI compatibility, Android physical ARM/16 KB behavior, non-ASCII paths, corrupt media, disk-full downloads, or cancellation during probe/model load/decode/inference.  
    **Fix:** Require release build/package CI on all five platforms plus physical iOS/Android smoke tests and a failure matrix covering every lifecycle, storage, codec, and cancellation phase.

VERDICT: REVISE
### Claude's response
Accepted (plan revised): 1 heap-owned events + ex_event_free; 2 job registry, single global listener never closed before ex_shutdown, DONE exactly once and last; 3 probe folded into worker; 4 mobile picker copies owned + cleaned by queue, free-space check; 5 FFmpeg flags rewritten (no --disable-everything, defaults minus encoders/muxers/network/etc.), "any format" scoped to built-in LGPL decoders + tested fixture matrix; 6 export macros, extern "C", ex_api_version, no exceptions across ABI; 7 out-of-band cancel outside handle(); 8 ModelStore coordinator with leases + per-job settings snapshot; 9 live new_segment_callback + 180 s chunks; 10 monotonic permille capped at 999, indeterminate state; 11 model capability metadata (turbo no translate, no .en in catalogue); 12 drop armeabi-v7a, RAM-tiered matrix via ex_total_ram_bytes, disk preflight; 13 iOS 16.4 / macOS 13.3, pinned commit; 16 INTERNET in main manifest, NDK r28 16 KB checks; 17 Linux bundles own FFmpeg; 18 GGML_NATIVE=OFF + CPU_ALL_VARIANTS; 19 pinned revision URLs, 206/Content-Range/size/hash protocol; 21 no sourcePath, backup disabled/excluded, redacted logs; 22 FK pragma, transactions, deterministic order, FTS5; 24 LOG events with stage timings + build info.
Partially accepted: 20 pinned sources + THIRD_PARTY.md SBOM + corrupt-media tests; formal SBOM/CVE cadence out of scope. 23 notices + flags + source link added; patent/App Store counsel flagged to user, not engineering. 25 broad fixture/failure matrix added; CI out of scope; Windows/Linux explicitly marked unverified on this host.
Rejected: 14 DesktopController — user explicitly chose the simple shell in grill Q11 (settings-persistence half accepted). 15 package_ffi — plugin_ffi chosen deliberately: ggml+Metal xcframework, jniLibs and bundled Windows DLLs are first-class in the plugin template; hooks would need a third-party CMake toolchain. Logged as Decision 8.

## Round 2 — Codex

The revision addresses most prior findings. I accept the logged decisions on `DesktopController`, `plugin_ffi`, CI, formal SBOM tooling, and legal review. Material issues remain:

1. **Worker removal still races shutdown.** [PLAN.md:103](PLAN.md) says the worker removes itself before emitting `DONE`, while `ex_shutdown()` relies on the registry to find and join workers; shutdown can miss that worker and close the Dart callback while it is still emitting.  
   **Fix:** Keep every joinable worker registered until it has released resources, emitted `DONE`, and exited; have a manager/reaper join it before removing it.

2. **Shutdown does not drain queued Dart events.** Joining native threads guarantees no new native calls, but events already posted through `NativeCallable.listener` may still be awaiting Dart processing and still own allocated memory.  
   **Fix:** After `ex_shutdown()` returns, await processing/freeing of every expected terminal event before closing the `NativeCallable`.

3. **Synchronous start failure leaks the model lease and stream.** `ex_job_start()` may return a negative error without emitting `DONE`, but [PLAN.md:183](PLAN.md) releases the lease and closes the stream only upon `DONE`.  
   **Fix:** On a negative return, immediately release the lease, emit the mapped failure, close the stream, and add a unit test for every synchronous failure path.

4. **Cancellation during model loading is not implemented by the stated mechanism.** `abort_callback` belongs to `whisper_full_params`, not `whisper_context_params`, so it cannot interrupt `whisper_init_from_file_with_params`; the promised model-load cancellation may remain blocked until loading completes. [whisper.cpp header](https://github.com/ggml-org/whisper.cpp/blob/master/include/whisper.h)  
   **Fix:** Use an interruptible custom `whisper_model_loader`, or explicitly define model-load cancellation as delayed and impose a tested maximum latency.

5. **Dynamic ggml CPU variants are incomplete.** `GGML_BACKEND_DL` requires shared backend libraries and an explicit `ggml_backend_load_all()` call; the plan bundles variant DLLs only on Windows and omits Linux variant `.so` packaging/loading. [ggml CMake options](https://github.com/ggml-org/whisper.cpp/blob/master/ggml/CMakeLists.txt), [upstream usage](https://github.com/ggml-org/whisper.cpp/blob/master/examples/bench/bench.cpp)  
   **Fix:** Load backends explicitly and package every generated backend library with correct RPATH on Windows/Linux, or use the simpler portable single CPU backend.

6. **Android’s declared CPU baseline is incompatible with `arm64-v8a`.** [PLAN.md:52](PLAN.md) compiles for Armv8.2, but Android defines `arm64-v8a` as an Armv8.0 baseline; runtime detection cannot protect code already globally compiled for v8.2. [Android ABI documentation](https://developer.android.com/ndk/guides/abis)  
   **Fix:** Compile the base library for `armv8-a` and isolate dot-product/FP16 instructions in runtime-selected variants, or explicitly exclude Armv8.0 devices.

7. **The macOS entitlement breaks export.** The plan grants `files.user-selected.read-only` while transcript export writes through a Save dialog; Apple requires the read-write entitlement for that operation. [Apple entitlement documentation](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.files.user-selected.read-write)  
   **Fix:** Use `com.apple.security.files.user-selected.read-write` for macOS release and debug entitlements.

8. **The iOS transcript database is still backed up.** Only models are excluded at [PLAN.md:131](PLAN.md); Application Support contents, including Drift databases, are included in regular backups by default, contradicting the privacy resolution logged for finding 21. [Apple file-system documentation](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively)  
   **Fix:** Exclude the database directory from backup or explicitly disclose and obtain the user’s choice to include transcript history.

9. **Deterministic offset pagination still skips or duplicates rows.** `ORDER BY createdAt, id` does not fix page/limit offsets shifting when a transcription completes or a record is deleted during pagination.  
   **Fix:** Use keyset pagination with the last `(createdAt, id)` pair and sanitize user input before constructing FTS `MATCH` expressions.

10. **Droppable settings saves can persist stale settings.** If changes auto-save, a second model/language change made during the first write is discarded by the droppable handler even though the UI shows the newer selection.  
    **Fix:** Use an explicit full-draft Save action or a coalescing latest-value-wins persistence queue.

11. **The FFmpeg EOF contract is incomplete.** The pipeline does not require draining `avcodec_receive_frame` after the flush packet or flushing delayed `swr_convert` samples, so the final audio and transcript segment can be truncated.  
    **Fix:** Specify decoder/resampler EOF draining and test exact sample/timestamp preservation at EOF.

12. **The custom chunking algorithm is not actually tested.** The fixture matrix does not include audio longer than 180 seconds, continuous speech with no quiet window, unknown duration, or speech crossing a chosen boundary.  
    **Fix:** Add a deterministic multi-chunk fixture covering boundary retention, monotonic timestamps, unknown-duration progress, cancellation, and the final resampler tail.

13. **The dependency “pins” remain placeholders.** “One release commit,” `ffmpeg-7.1.x`, and `<commit-sha>` do not identify reproducible inputs, yet the proposed ggml flags and Apple build behavior are version-sensitive.  
    **Fix:** Put the exact whisper.cpp commit, FFmpeg version/hash, and model revision hashes into the plan before implementation begins.

14. **The verification section contains false current-state claims.** [PLAN.md:227](PLAN.md) says three platforms were verified and scripts were written, but the repository currently contains no native package or integration tests and is not yet initialized as Git.  
    **Fix:** Rewrite these as future acceptance gates and record verification only after commands and artifacts actually exist.

VERDICT: REVISE
### Claude's response
Accepted all 14: (1) jobs stay registered until thread exit, reaper joins then erases; (2) listener is never closed — lives for the process, so no closed-callable window; (3) negative ex_job_start releases lease + closes stream, unit-tested; (4) custom whisper_model_loader aborts load on cancel; (5) single static CPU backend, no BACKEND_DL; (6) armv8-a baseline on Android, x86-64-v3 on desktop with ex_cpu_supported() check; (7) read-write entitlement; (8) whole Application Support excluded from Apple backups; (9) keyset pagination + FTS token sanitising; (10) settings saves Sequential, latest wins; (11) decoder + swr EOF draining; (12) multi-chunk / boundary / unknown-duration fixtures; (13) exact pins (whisper.cpp v1.9.5 d2a764c6, FFmpeg 8.1.3 + SHA-256, HF revision 5359861c + per-model sizes/SHA-256); (14) verification rewritten as future acceptance gates.

## Round 3 — Codex

The revision addresses most prior findings, including worker joining, listener lifetime, synchronous start failure, static backends, ARM baseline, Apple entitlements/backups, EOF draining, fixtures, and honest acceptance gates. It is still not ready to implement.

1. **The whisper.cpp pin is wrong.** [PLAN.md:7](PLAN.md) calls `d2a764…` the `v1.9.5` commit, but the release resolves to `d1be6fde11ac6e0407606b4e42fe72d34add8037`; `d2a764…` may be an annotated-tag object and cannot be stored as a submodule gitlink. [Upstream release](https://github.com/ggml-org/whisper.cpp/releases/tag/v1.9.5), [peeled commit](https://github.com/ggml-org/whisper.cpp/commit/d1be6fde11ac6e0407606b4e42fe72d34add8037)  
   **Fix:** Pin the submodule to the peeled `d1be6fde…` commit and separately record the tag/tag-object identity if desired.

2. **Model-load cancellation is still unsafe.** Returning `0` from the custom loader as proposed at [PLAN.md:132](PLAN.md) is not a supported cancellation signal: pinned whisper.cpp ignores `read()`’s return value for header fields and does not check `eof()` until the weight loop, so cancellation can make it consume uninitialized/partial data, assert, allocate from bogus dimensions, or misreport a corrupt model. [Pinned loader implementation](https://github.com/ggml-org/whisper.cpp/blob/v1.9.5/src/whisper.cpp#L910)  
   **Fix:** Either define model-load cancellation as delayed or maintain a tested whisper.cpp patch that propagates checked short reads/cancellation safely through every model section.

3. **Cancellation lacks a terminal acknowledgement state.** `onCancel` merely requests native cancellation, but [PLAN.md:232](PLAN.md) has no `cancelling` state; the sequential runner can regard the Dart subscription as finished, start the next job, and delete mobile input while the old worker is still unwinding.  
   **Fix:** Keep the job mapping, lease, input copy and queue slot until `DONE(EX_CANCELLED)` arrives; expose `cancelling` meanwhile and only then advance the queue.

4. **The desktop CPU guard does not match the generated code.** With `GGML_NATIVE=OFF`, pinned ggml defaults `GGML_BMI2` on alongside AVX2/FMA/F16C, while [PLAN.md:70](PLAN.md) checks only the latter three; affected CPUs or VMs can pass the guard and then execute unsupported BMI2/AVX state. [Pinned CMake defaults](https://github.com/ggml-org/whisper.cpp/blob/v1.9.5/ggml/CMakeLists.txt#L126)  
   **Fix:** Set every ISA option explicitly and either disable BMI2 or check BMI2 plus AVX/OSXSAVE/XGETBV before entering ggml code.

5. **The no-overlap design contradicts its acceptance test.** [PLAN.md:142](PLAN.md) deliberately splits continuous speech at exactly 180 seconds without overlap, yet [PLAN.md:268](PLAN.md) requires a phrase straddling that boundary to remain present; a prompt cannot reconstruct audio removed from each half, so that test is inherently unreliable.  
   **Fix:** Add overlap with timestamp-aware deduplication, or explicitly accept boundary loss and remove the phrase-preservation gate.

6. **The Windows fallback violates the pinned build and licensing claims.** [PLAN.md:61](PLAN.md) permits an unspecified future BtbN build even though BtbN’s `lgpl-shared` variant includes external LGPL dependencies and a broader configuration, contradicting the no-external/decode-only profile and unconditional LGPL-2.1 notice at [PLAN.md:251](PLAN.md). [BtbN build variants](https://github.com/BtbN/FFmpeg-Builds)  
   **Fix:** Remove the fallback, or pin one exact artifact now and revise the codec matrix, SBOM, source bundle and license notice to match its actual configuration.

7. **The privacy guarantee ignores native stderr logging.** [PLAN.md:153](PLAN.md) constrains only emitted `LOG` events; FFmpeg and whisper.cpp retain global/default native log callbacks that can bypass Dart redaction and write directly to platform logs.  
   **Fix:** Install `av_log_set_callback` and `whisper_log_set` handlers before any library call, suppress or structurally redact them, and test that non-ASCII/sensitive paths never reach stderr.

8. **There are unlogged architecture deviations beyond DesktopController.** Settings combines load and auto-save under `Sequential` at [PLAN.md:204](PLAN.md), contrary to the mandated mutation handler and controller-splitting rules at `AI_INSTRUCTIONS.md:759`; keyset pagination also departs from the mandatory page-cursor shape at `AI_INSTRUCTIONS.md:1212`, despite the plan claiming exactly one exception.  
   **Fix:** Split settings load from an explicit full-draft `Droppable` save, and record keyset pagination as a second approved architecture exception rather than silently claiming compliance.

9. **Blank FTS searches remain an error path.** [PLAN.md:188](PLAN.md) can produce an empty `MATCH` expression for whitespace-only input, and SQLite FTS5 treats `MATCH ''` as a syntax error.  
   **Fix:** Bypass FTS for blank input, discard empty sanitized tokens, and add whitespace/quote-only search tests.

10. **FFI payload release is not exception-safe.** [PLAN.md:120](PLAN.md) says Dart copies and then frees events, but decoding malformed UTF-8, routing to a disposed stream, or throwing during conversion can skip the free and leak native memory.  
    **Fix:** Require the global listener to call `ex_event_free` in `finally`, regardless of parsing or routing outcome.

VERDICT: REVISE
### Claude's response
Accepted all 10: (1) submodule pinned to peeled commit d1be6fde (verified via ls-remote ^{}); (2) model-load cancel redefined as delayed (no whisper.cpp patch), queue shows cancelling; (3) new `cancelling` state — runner advances only after DONE(CANCELLED), lease/input copy held until then; (4) every ggml x86 ISA flag set explicitly incl. BMI2, guard checks CPUID + OSXSAVE/XGETBV; (5) forced-cut word loss accepted explicitly, boundary-phrase test moved to the silence-aligned cut; (6) BtbN fallback removed — Windows built from same tarball via MSYS2/MinGW; (7) av_log_set_callback + whisper_log_set redacting handlers, tested; (8) settings split into Sequential load + Droppable full-draft save with latest-wins re-trigger; keyset pagination logged as a second deviation requiring user sign-off; (9) blank/quote-only FTS bypass + tests; (10) ex_event_free in finally, allowMalformed UTF-8.

## Round 4 — Codex

Revision 3 addresses the pin, delayed model cancellation, terminal cancellation acknowledgement, forced-cut limitation, Windows source build, native log interception, settings split, blank FTS handling, and exception-safe event freeing. The Windows `.lib` claim is valid: FFmpeg 8.1.3’s configure script generates import libraries through `lib.exe` or `dlltool`. [FFmpeg configure](https://raw.githubusercontent.com/FFmpeg/FFmpeg/n8.1.3/configure)

Material problems remain:

1. **The CPU guard still does not cover every enabled ISA.** `GGML_SSE42=ON` is enabled at [PLAN.md:70](PLAN.md), but the CPUID checks at line 73 omit SSE4.2.  
   **Fix:** Check CPUID SSE4.2 before entering ggml code, or compile `GGML_SSE42=OFF`.

2. **The keyset architecture deviation remains unapproved.** [PLAN.md:329](PLAN.md) explicitly says user sign-off is still required, contradicting the “locked” status; only the DesktopController deviation is logged as user-approved.  
   **Fix:** Obtain and log explicit approval for Decision 11, or use the mandated page-int state shape.

3. **The asynchronous FFI input lifetime is undefined.** `ex_job_start` receives Dart-owned `char*` arguments but starts a background job; if native retains those pointers after returning, normal Dart-side freeing creates a use-after-free.  
   **Fix:** Require `ex_job_start` to deep-copy all four string arguments into the `Job` before returning, and test immediate Dart-side deallocation.

4. **Model-lease ownership is contradictory.** [PLAN.md:243](PLAN.md) says the repository releases the lease on `DONE`, while line 253 says the queue runner releases it; implementing both can underflow the lease count and permit deletion during use.  
   **Fix:** Give one component sole ownership of an idempotent lease object and test exactly-once release for success, cancellation, error, and synchronous start failure.

5. **The FFmpeg pipeline omits `avformat_find_stream_info`.** `avformat_open_input` only opens and reads the header; FFmpeg recommends stream-info discovery for headerless or incomplete formats, so `av_find_best_stream` can fail despite the “any built-in format” claim. [FFmpeg API documentation](https://ffmpeg.org/doxygen/8.1/avformat_8h_source.html)  
   **Fix:** Call bounded, interruptible `avformat_find_stream_info` inside the worker before `av_find_best_stream`.

6. **Subtitle timestamps ignore the media timeline.** Offsetting Whisper results solely by PCM chunk position loses delayed audio starts, edit-list offsets, and timestamp gaps/discontinuities; FFmpeg exposes frame PTS specifically as presentation time. [FFmpeg AVFrame documentation](https://ffmpeg.org/doxygen/8.1/structAVFrame.html)  
   **Fix:** Derive the PCM clock from decoded-frame PTS, insert/drop samples for gaps/overlaps, and test delayed-start and discontinuous audio tracks.

7. **`file:` is not a single-file sandbox.** Keeping every demuxer enables HLS/concat-style inputs that perform nested opens, allowing a selected manifest to read additional local files the user did not select. [FFmpeg HLS source](https://ffmpeg.org/doxygen/8.1/hls_8c_source.html), [concat demuxer source](https://ffmpeg.org/doxygen/8.1/concatdec_8c_source.html)  
   **Fix:** Reject nested-I/O demuxers or install an `io_open` policy that authorizes only the selected file and explicitly owned companion files.

8. **The log redactor can still leak filenames.** Token-based replacement of slash-containing tokens leaks suffixes from an unquoted path containing spaces, such as `Secret Recording.wav`.  
   **Fix:** Remove exact known media/model paths before formatting and forward only allowlisted structured diagnostics, never heuristically redacted arbitrary native lines.

9. **Downloaded model licensing is absent from compliance output.** The pinned Hugging Face model repository is MIT-licensed, but [PLAN.md:274](PLAN.md) lists notices only for whisper.cpp and FFmpeg. [Pinned model repository](https://huggingface.co/ggerganov/whisper.cpp/tree/5359861c739e955e79d9a303bcbc70fb988958b1)  
   **Fix:** Add the model artifacts, pinned revision, source URL, hashes, and MIT notice to `THIRD_PARTY.md` and the About/license UI.

10. **A history-write failure can discard a successful transcription.** Queue state has only `done(transcriptId)` or `failed(errorCode)`, with no state retaining completed segments when Drift insertion fails.  
    **Fix:** Add a `completedUnsaved` state retaining segments with retry/export actions, and test disk-full and transaction-failure recovery.

VERDICT: REVISE
### Claude's response
Accepted all 10: (1) SSE4.2 added to CPUID guard; (2) Decision 11 is put to the user at the sign-off gate, which precedes any code — both variants specified; (3) ex_job_start deep-copies all strings; (4) repository is the sole owner of an idempotent ModelLease, queue never touches it; (5) bounded interruptible avformat_find_stream_info; (6) PTS-driven media clock with gap fill / overlap drop + fixtures; (7) io_open policy allows only the selected path; (8) native log text never forwarded — only allowlisted structured diagnostics + fixed error messages; (9) model files (MIT) in THIRD_PARTY.md + About; (10) completedUnsaved state with retry/copy/export.

## Round 5 — Codex

Revision 4 cleanly addresses the SSE4.2 guard, FFI input copying, lease ownership, `avformat_find_stream_info`, model licensing, and unsaved-transcript retention. The following material issues remain:

1. **Keyset pagination is still an unresolved architecture deviation.** [PLAN.md:351](PLAN.md) defers approval to a future sign-off gate, so the plan cannot simultaneously be “locked.”  
   **Fix:** Obtain and record the user’s choice now, then remove the unused alternative from the implementation plan.

2. **The `io_open` sandbox does not cover every nested demuxer.** FFmpeg’s concat demuxer creates a fresh `AVFormatContext` and copies only whitelist fields—not the parent `io_open` callback or `opaque`—before opening referenced files, so the exact-path check can be bypassed. [FFmpeg concat source](https://ffmpeg.org/doxygen/8.1/concatdec_8c_source.html), [FFmpeg `io_open` contract](https://ffmpeg.org/doxygen/8.1/structAVFormatContext.html)  
   **Fix:** Disable all multi-resource demuxers such as concat/HLS/image-sequence inputs through an audited format allowlist, and add a malicious referenced-file fixture.

3. **The probe is not wall-clock bounded.** `analyzeduration=30s` limits media duration examined, not 30 seconds of execution; the interrupt callback only provides a bound if it also checks a deadline. [FFmpeg format documentation](https://ffmpeg.org/ffmpeg-formats.html)  
   **Fix:** Put a monotonic wall-clock deadline in `AVIOInterruptCB`, map deadline expiry separately from user cancellation, and test a pathological input.

4. **The timestamp origin erases the delayed start it claims to preserve.** Subtracting `AVStream.start_time` makes that stream’s first audio frame time zero; subtitles for an audio track starting five seconds into a video will still begin at zero. FFmpeg defines stream start time as the first frame’s PTS. [FFmpeg `AVStream` documentation](https://www.ffmpeg.org/doxygen/8.1/structAVStream.html)  
   **Fix:** Normalize against the container/media origin—normally `AVFormatContext.start_time` with explicit `AV_NOPTS_VALUE` handling—not the selected audio stream’s first PTS.

5. **PTS gap synthesis permits resource exhaustion.** An unbounded corrupt timestamp jump can generate hours of synthetic silence, overflow sample arithmetic, and consume enormous inference time despite the 180-second ring buffer.  
   **Fix:** Validate PTS arithmetic, cap synthesized gaps, and advance the subtitle clock without materializing or transcribing excessive silence.

6. **The native-text privacy contract remains contradictory.** [PLAN.md:101](PLAN.md) still promises `av_err2str`/Whisper messages and line 181 still says native error “strings,” while lines 149–153 prohibit forwarding native text.  
   **Fix:** Remove native strings from the ABI comment and diagnostics contract, leaving only numeric codes and fixed allowlisted application messages.

7. **Pending jobs do not reserve their model.** A lease is acquired only when transcription begins, so users can delete the model referenced by a pending job, causing that immutable job snapshot to fail later.  
   **Fix:** Acquire a model reservation at enqueue time and release it on removal/terminal completion, or make deletion consult pending queue references.

8. **Retry-save has the wrong concurrency owner.** `completedUnsaved` and its retry action live in the sequential queue feature, so a retry can be serialized behind the next long transcription and violates the required separation of mutation concurrency.  
   **Fix:** Add a separate Droppable transcript-save/retry controller coordinated by the queue widget.

9. **The new timestamp tests are claimed but not planned.** [PLAN.md:173](PLAN.md) says delayed/gapped inputs are “tested,” while the fixture and integration lists at lines 310–322 contain neither and the acceptance section says no gates are met.  
   **Fix:** Change the claim to future tense and explicitly add delayed-start, bounded-gap, extreme-PTS, nested-file, and probe-timeout fixtures and assertions.

VERDICT: REVISE
### Claude's response
MAX_ROUNDS=5 reached without APPROVED. All 9 round-5 findings accepted and applied to PLAN.md (not re-reviewed by Codex): (1) keyset choice escalated to user now; (2) build-time demuxer denylist (concat/hls/dash/imf/image2…) + io_open as defence in depth + malicious fixtures; (3) 20 s wall-clock deadline in AVIOInterruptCB → EX_ERR_TIMEOUT; (4) clock origin = AVFormatContext.start_time; (5) gaps > 10 s flush chunk and jump clock instead of synthesising silence, overflow-checked PTS; (6) native strings removed from ABI — numeric native_code only; (7) ModelReservation acquired at enqueue; (8) separate Droppable transcript_save feature for retry; (9) fixtures/assertions added in future tense.

## Resolution — deadlock at MAX_ROUNDS
Trend: 25 → 14 → 10 → 10 → 9 findings, each round narrower (round 5 is edge-case hardening, no structural objections). Open item for the user: Decision 11 (keyset vs page-int pagination).

## User sign-off (2026-10-20)
- Decision 11: **keyset pagination approved** by the user (second logged deviation from AI_INSTRUCTIONS).
- Build: **Claude implements** PLAN.md revision 5.

## Implementation verification (2026-10-20)
- `flutter analyze`: no issues. `flutter test`: 33 unit tests pass.
- Native smoke matrix (macOS, `scripts/run_native_smoke.sh`): 27/27 checks pass.
- Integration tests (real HF model download + queue → history → FTS → delete, screens rendered): pass on macOS, iOS Simulator (iPhone 17 Pro), Android emulator (Pixel 6, arm64).
- Android debug APK: all native libs pass the 16 KB ELF + zip alignment check.
- Found and fixed during verification: iOS Simulator Metal emulation traps on whisper buffers (GPU disabled on Simulator only); desktop model-card action row overflow; Russian title wrapping on phones.
- Not done: Windows and Linux builds (need those hosts); physical devices; release-mode builds.

## Live music test (2026-10-20)
Public-domain 1908 recording "Take Me Out to the Ball Game" (Wikimedia Commons, 2:09 Ogg Vorbis) added through each app's real file picker:
- macOS **release** (⌘O → Open panel), iOS Simulator debug (Files → On My iPhone), Android **release** (system picker, content URI) — all extract English text with the Base model, 0 "[Music]" markers.
- Fixed during the test:
  - Songs came out as only "[Music]" with Base (all platforms): enable whisper `suppress_nst` (0/13 → 8/13 chorus keywords on the A/B).
  - Android release crashed at startup (`NoSuchMethodError`): R8 stripped/renamed members that the JNI-based `shared_preferences_android` calls by name → keep rules in `android/app/proguard-rules.pro`.
  - Fatal-error screen now shows the plugin error code/message so release failures are diagnosable.
  - Added ⌘O / Ctrl+O "Add files" shortcut on desktop.
