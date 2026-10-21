// C ABI of extracter_native: decode any audio/video with FFmpeg and transcribe
// it with whisper.cpp on a native worker thread.
//
// Threading and ownership contract:
// - ex_init() registers where events go: a Dart native port plus Dart's
//   Dart_PostCObject (NativeApi.postCObject). Each event is posted as an int64
//   holding its address. Posting to a port whose isolate has died just fails,
//   so a job that outlives its isolate (e.g. the Android activity was closed)
//   is safe; its events are freed by native instead.
// - Every ex_event is heap-allocated by native code and owned by the receiver
//   until it calls ex_event_free(). No pointer is read by native after posting.
// - All string arguments are copied before the call returns.
// - For each job id returned by ex_job_start (> 0) exactly one EX_EV_DONE event
//   is posted, and it is always the last event for that id.
// - No native library text (FFmpeg / whisper logs or error strings) is ever
//   forwarded: only numeric codes and allowlisted structured diagnostics.
#ifndef EXTRACTER_NATIVE_H
#define EXTRACTER_NATIVE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define EX_API __declspec(dllexport)
#else
#define EX_API __attribute__((visibility("default"))) __attribute__((used))
#endif

#define EX_API_VERSION 2

typedef enum ex_event_kind {
  EX_EV_PROGRESS = 0,
  EX_EV_SEGMENT = 1,
  EX_EV_DONE = 2,
  EX_EV_LOG = 3,
} ex_event_kind;

typedef enum ex_status {
  EX_OK = 0,
  EX_CANCELLED = 1,
  EX_ERR_OPEN = 2,
  EX_ERR_DECODE = 3,
  EX_ERR_MODEL = 4,
  EX_ERR_NO_AUDIO = 5,
  EX_ERR_OOM = 6,
  EX_ERR_INTERNAL = 7,
  EX_ERR_TIMEOUT = 8,
} ex_status;

typedef struct ex_event {
  int64_t job_id;
  int32_t kind;               // ex_event_kind
  int32_t status;             // DONE: ex_status
  int32_t progress_permille;  // PROGRESS: 0..999 (1000 only via DONE); -1 = indeterminate
  int32_t native_code;        // DONE: numeric AVERROR / whisper return code, 0 if none
  int64_t t0_ms;              // SEGMENT start, media time
  int64_t t1_ms;              // SEGMENT end, media time
  int64_t duration_ms;        // PROGRESS and DONE; -1 if unknown
  char* text;                 // SEGMENT text / DONE detected language / LOG JSON (UTF-8)
  int32_t text_len;           // bytes, without the terminating NUL
} ex_event;

// Layout-compatible prefix of Dart_CObject; native only sends type kInt64 (3).
typedef struct ex_cobject {
  int32_t type;
  union {
    int64_t as_int64;
    uint8_t reserved[48];  // Dart_CObject's union is at most 40 bytes
  } value;
} ex_cobject;

// Signature of Dart_PostCObject: false when the port is closed.
typedef bool (*ex_post_fn)(int64_t port, ex_cobject* message);

EX_API int32_t ex_api_version(void);
// Static string: library versions and the decode-only build profile.
EX_API const char* ex_build_info(void);
// Sends events of jobs started from now on to `port` and installs silent
// native log handlers. Call once per isolate: a new port means the previous
// isolate is gone, so its still-running jobs are cancelled. Returns 0, or -1
// if `post` is null.
EX_API int32_t ex_init(ex_post_fn post, int64_t port);
// Starts a job. language: "auto" or an ISO-639-1 code. Returns a job id > 0,
// or -ex_status when the job could not be started (no DONE follows then).
EX_API int64_t ex_job_start(const char* media_path_utf8, const char* model_path_utf8,
                            const char* language, int32_t translate, int32_t n_threads);
// Idempotent; an unknown or finished id is a no-op.
EX_API void ex_job_cancel(int64_t job_id);
EX_API void ex_event_free(ex_event* ev);
// x86_64: 1 when CPUID + XGETBV report the x86-64-v3 baseline (SSE4.2, AVX,
// AVX2, FMA, F16C, BMI2, OS-saved YMM state). Always 1 on other CPUs.
EX_API int32_t ex_cpu_supported(void);
EX_API int64_t ex_total_ram_bytes(void);
EX_API int64_t ex_free_disk_bytes(const char* dir_path_utf8);
// iOS/macOS: marks a directory as excluded from iCloud/iTunes/Time Machine-style
// app backups. Returns 0 on success, -1 on failure, 1 where not applicable.
EX_API int32_t ex_exclude_from_backup(const char* dir_path_utf8);
// Cancels every job and joins every worker thread.
EX_API void ex_shutdown(void);

#ifdef __cplusplus
}
#endif

#endif  // EXTRACTER_NATIVE_H
