// Dev-only CLI: runs one job through the real C ABI and prints every event.
// Usage: smoke <media> <model> [language] [translate] [cancel_after_ms]
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <mutex>
#include <string>
#include <thread>

#include "../src/extracter_native.h"

namespace {
std::mutex g_mutex;
std::condition_variable g_cv;
bool g_done = false;
int g_status = -1;

void on_event(ex_event* ev) {
  std::lock_guard<std::mutex> lock(g_mutex);
  const std::string text = ev->text != nullptr ? std::string(ev->text, ev->text_len) : "";
  switch (ev->kind) {
    case EX_EV_PROGRESS:
      std::printf("PROGRESS %d duration=%lld\n", ev->progress_permille, static_cast<long long>(ev->duration_ms));
      break;
    case EX_EV_SEGMENT:
      std::printf("SEGMENT %lld %lld %s\n", static_cast<long long>(ev->t0_ms), static_cast<long long>(ev->t1_ms),
                  text.c_str());
      break;
    case EX_EV_LOG:
      std::printf("LOG %s\n", text.c_str());
      break;
    case EX_EV_DONE:
      std::printf("DONE status=%d native=%d lang=%s duration=%lld\n", ev->status, ev->native_code, text.c_str(),
                  static_cast<long long>(ev->duration_ms));
      g_done = true;
      g_status = ev->status;
      g_cv.notify_all();
      break;
  }
  std::fflush(stdout);
  ex_event_free(ev);
}
}  // namespace

int main(int argc, char** argv) {
  if (argc < 3) {
    std::fprintf(stderr, "usage: smoke <media> <model> [language] [translate] [cancel_after_ms]\n");
    return 2;
  }
  std::printf("INFO %s cpu_supported=%d ram=%lld free=%lld\n", ex_build_info(), ex_cpu_supported(),
              static_cast<long long>(ex_total_ram_bytes()), static_cast<long long>(ex_free_disk_bytes(".")));
  ex_init(&on_event);
  const char* language = argc > 3 ? argv[3] : "auto";
  const int translate = argc > 4 ? std::atoi(argv[4]) : 0;
  const int cancel_after = argc > 5 ? std::atoi(argv[5]) : -1;
  const int64_t id = ex_job_start(argv[1], argv[2], language, translate, 4);
  if (id <= 0) {
    std::printf("START_FAILED %lld\n", static_cast<long long>(id));
    return 1;
  }
  if (cancel_after >= 0) {
    std::this_thread::sleep_for(std::chrono::milliseconds(cancel_after));
    ex_job_cancel(id);
    ex_job_cancel(id);  // idempotent
  }
  std::unique_lock<std::mutex> lock(g_mutex);
  g_cv.wait(lock, [] { return g_done; });
  lock.unlock();
  ex_shutdown();
  return g_status;
}
