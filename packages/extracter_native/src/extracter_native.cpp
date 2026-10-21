// extracter_native: FFmpeg decode → 16 kHz mono float PCM → chunked whisper.cpp
// transcription, one native worker thread per job. See extracter_native.h for
// the threading and ownership contract.
#include "extracter_native.h"

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/channel_layout.h>
#include <libavutil/opt.h>
#include <libswresample/swresample.h>
}
#include "whisper.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <map>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <thread>
#include <vector>

#if defined(_WIN32)
#include <windows.h>
#else
#include <sys/statvfs.h>
#include <unistd.h>
#endif
#if defined(__APPLE__)
#include <CoreFoundation/CoreFoundation.h>
#include <TargetConditionals.h>
#include <sys/sysctl.h>
#endif
#if defined(__x86_64__) || defined(_M_X64)
#define EX_X86_64 1
#if defined(_MSC_VER)
#include <immintrin.h>
#include <intrin.h>
#else
#include <cpuid.h>
#endif
#endif

namespace {

constexpr int kSampleRate = 16000;
constexpr int64_t kChunkSamples = 180LL * kSampleRate;      // target chunk length
constexpr int64_t kCutSearchSamples = 15LL * kSampleRate;   // cut search window at chunk end
constexpr int64_t kRmsWindow = kSampleRate / 2;             // 500 ms
constexpr int64_t kRmsStep = kSampleRate / 10;              // 100 ms
constexpr int64_t kSmallGap = kSampleRate / 10;             // gaps/overlaps below are ignored
constexpr int64_t kMaxSilenceFill = 10LL * kSampleRate;     // larger gaps jump the clock
constexpr int64_t kMaxPtsSamples = 48LL * 3600 * kSampleRate;
constexpr int64_t kMinChunkSamples = kSampleRate / 10;
constexpr int64_t kNoPts = std::numeric_limits<int64_t>::min();
constexpr auto kProbeTimeout = std::chrono::seconds(20);

using Clock = std::chrono::steady_clock;

int64_t now_ns() {
  return std::chrono::duration_cast<std::chrono::nanoseconds>(Clock::now().time_since_epoch()).count();
}

int64_t elapsed_ms(Clock::time_point since) {
  return std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - since).count();
}

struct Job {
  int64_t id = 0;
  int64_t port = 0;  // Dart port of the isolate that started the job
  std::string media_path;
  std::string model_path;
  std::string language;
  std::string allowed_url;
  bool translate = false;
  int n_threads = 4;
  std::atomic<bool> cancel{false};
  std::atomic<bool> finished{false};
  std::atomic<bool> timed_out{false};
  std::atomic<int64_t> deadline_ns{0};
  int warnings = 0;  // touched only by the worker thread
  std::thread thread;
};

std::mutex g_mutex;
std::map<int64_t, std::shared_ptr<Job>> g_jobs;
std::atomic<ex_post_fn> g_post{nullptr};
std::atomic<int64_t> g_port{0};
std::atomic<int64_t> g_next_id{1};
thread_local Job* t_job = nullptr;

// ---------------------------------------------------------------- events

ex_event* new_event(int64_t job_id, ex_event_kind kind) {
  auto* ev = static_cast<ex_event*>(std::calloc(1, sizeof(ex_event)));
  if (ev == nullptr) return nullptr;
  ev->job_id = job_id;
  ev->kind = kind;
  ev->progress_permille = -1;
  ev->duration_ms = -1;
  return ev;
}

bool set_text(ex_event* ev, const std::string& text) {
  if (text.empty()) return true;
  auto* buf = static_cast<char*>(std::malloc(text.size() + 1));
  if (buf == nullptr) return false;
  std::memcpy(buf, text.data(), text.size());
  buf[text.size()] = '\0';
  ev->text = buf;
  ev->text_len = static_cast<int32_t>(text.size());
  return true;
}

constexpr int32_t kDartCObjectInt64 = 3;  // Dart_CObject_kInt64

// The receiver owns the event once the post succeeds; a closed port (dead
// isolate) leaves it with us.
void post(const Job& job, ex_event* ev) {
  if (ev == nullptr) return;
  ex_post_fn fn = g_post.load();
  ex_cobject message{};
  message.type = kDartCObjectInt64;
  message.value.as_int64 = static_cast<int64_t>(reinterpret_cast<intptr_t>(ev));
  if (fn == nullptr || !fn(job.port, &message)) ex_event_free(ev);
}

void post_progress(const Job& job, int32_t permille, int64_t duration_ms) {
  ex_event* ev = new_event(job.id, EX_EV_PROGRESS);
  if (ev == nullptr) return;
  ev->progress_permille = permille;
  ev->duration_ms = duration_ms;
  post(job, ev);
}

void post_segment(const Job& job, int64_t t0_ms, int64_t t1_ms, const std::string& text) {
  ex_event* ev = new_event(job.id, EX_EV_SEGMENT);
  if (ev == nullptr) return;
  ev->t0_ms = t0_ms;
  ev->t1_ms = t1_ms;
  if (!set_text(ev, text)) {
    ex_event_free(ev);
    return;
  }
  post(job, ev);
}

// LOG payloads are built only from numbers and FFmpeg component names, never
// from paths, native messages or transcript text.
void post_log(const Job& job, const std::string& json) {
  ex_event* ev = new_event(job.id, EX_EV_LOG);
  if (ev == nullptr) return;
  if (!set_text(ev, json)) {
    ex_event_free(ev);
    return;
  }
  post(job, ev);
}

std::string json_name(const char* name) {
  std::string out;
  for (const char* c = name ? name : ""; *c != '\0'; ++c) {
    const char ch = *c;
    if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_' ||
        ch == ',' || ch == '-' || ch == '.') {
      out.push_back(ch);
    }
  }
  return "\"" + out + "\"";
}

// ---------------------------------------------------------------- logging

void av_log_silent(void*, int level, const char*, va_list) {
  if (level <= AV_LOG_WARNING && t_job != nullptr) t_job->warnings++;
}

void ggml_log_silent(enum ggml_log_level level, const char*, void*) {
  if ((level == GGML_LOG_LEVEL_WARN || level == GGML_LOG_LEVEL_ERROR) && t_job != nullptr) t_job->warnings++;
}

// Installed before the first call into FFmpeg or whisper.cpp from any entry point.
void ensure_silent_logging() {
  static std::once_flag once;
  std::call_once(once, [] {
    av_log_set_callback(&av_log_silent);
    whisper_log_set(&ggml_log_silent, nullptr);
  });
}

// ---------------------------------------------------------------- files

#if defined(_WIN32)
std::wstring widen(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int n = MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring out(static_cast<size_t>(n), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), out.data(), n);
  return out;
}
#endif

FILE* open_read(const std::string& path) {
#if defined(_WIN32)
  return _wfopen(widen(path).c_str(), L"rb");
#else
  return std::fopen(path.c_str(), "rb");
#endif
}

size_t loader_read(void* ctx, void* output, size_t size) { return std::fread(output, 1, size, static_cast<FILE*>(ctx)); }
bool loader_eof(void* ctx) { return std::feof(static_cast<FILE*>(ctx)) != 0; }
void loader_close(void* ctx) { std::fclose(static_cast<FILE*>(ctx)); }

// ---------------------------------------------------------------- FFmpeg hooks

int interrupt_cb(void* opaque) {
  auto* job = static_cast<Job*>(opaque);
  if (job->cancel.load()) return 1;
  const int64_t deadline = job->deadline_ns.load();
  if (deadline != 0 && now_ns() > deadline) {
    job->timed_out = true;
    return 1;
  }
  return 0;
}

// Second layer of the input sandbox: only the selected file may be opened.
int io_open_cb(AVFormatContext* s, AVIOContext** pb, const char* url, int flags, AVDictionary** options) {
  auto* job = static_cast<Job*>(s->opaque);
  if (job == nullptr || url == nullptr || (flags & AVIO_FLAG_WRITE) != 0 || job->allowed_url != url) {
    return AVERROR(EPERM);
  }
  return avio_open2(pb, url, flags, &s->interrupt_callback, options);
}

// ---------------------------------------------------------------- pipeline

struct Pipeline {
  AVFormatContext* fmt = nullptr;
  AVCodecContext* dec = nullptr;
  SwrContext* swr = nullptr;
  AVPacket* pkt = nullptr;
  AVFrame* frame = nullptr;
  whisper_context* wctx = nullptr;

  ~Pipeline() {
    if (wctx != nullptr) whisper_free(wctx);
    av_frame_free(&frame);
    av_packet_free(&pkt);
    swr_free(&swr);
    avcodec_free_context(&dec);
    avformat_close_input(&fmt);
  }
};

struct Result {
  int32_t status = EX_ERR_INTERNAL;
  int32_t native_code = 0;
  int64_t duration_ms = -1;
  std::string language;
};

class Transcriber {
 public:
  // run() has already posted progress 0 (or indeterminate) before this exists.
  Transcriber(Job& job, Pipeline& p, int64_t duration_samples)
      : job_(job),
        p_(p),
        duration_samples_(duration_samples),
        language_(job.language),
        last_permille_(0),
        indeterminate_sent_(duration_samples <= 0) {}

  // Appends decoded samples whose first sample sits at media time `pts`
  // (16 kHz samples, kNoPts when unknown). Returns false on cancel/failure.
  bool push(const float* samples, int64_t n, int64_t pts) {
    if (n <= 0) return true;
    any_audio_ = true;
    if (pts != kNoPts) {
      if (pcm_.empty()) {
        chunk_start_ = pts;
      } else {
        const int64_t gap = pts - (chunk_start_ + static_cast<int64_t>(pcm_.size()));
        if (gap > kMaxSilenceFill) {
          if (!transcribe(static_cast<int64_t>(pcm_.size()))) return false;
          pcm_.clear();
          chunk_start_ = pts;
        } else if (gap > kSmallGap) {
          pcm_.insert(pcm_.end(), static_cast<size_t>(gap), 0.0f);
        } else if (gap < -kSmallGap) {
          const int64_t drop = std::min(-gap, n);
          samples += drop;
          n -= drop;
        }
      }
    }
    pcm_.insert(pcm_.end(), samples, samples + n);
    while (static_cast<int64_t>(pcm_.size()) >= kChunkSamples) {
      const int64_t cut = find_cut();
      if (!transcribe(cut)) return false;
      pcm_.erase(pcm_.begin(), pcm_.begin() + cut);
      chunk_start_ += cut;
    }
    return true;
  }

  bool finish() {
    const bool ok = transcribe(static_cast<int64_t>(pcm_.size()));
    pcm_.clear();
    return ok;
  }

  bool any_audio() const { return any_audio_; }
  const std::string& detected_language() const { return detected_; }
  int32_t whisper_code() const { return whisper_code_; }

 private:
  struct Callback {
    Transcriber* self;
    int64_t chunk_start;
    int64_t chunk_len;
  };

  double rms(int64_t start, int64_t len) const {
    double sum = 0.0;
    for (int64_t i = start; i < start + len; ++i) sum += static_cast<double>(pcm_[i]) * pcm_[i];
    return std::sqrt(sum / static_cast<double>(len));
  }

  // Cut at the quietest 500 ms window in the last 15 s of the chunk, if it is
  // quieter than the chunk's median; otherwise at exactly 180 s.
  int64_t find_cut() const {
    std::vector<double> windows;
    for (int64_t i = 0; i + kRmsWindow <= kChunkSamples; i += kRmsWindow) windows.push_back(rms(i, kRmsWindow));
    std::nth_element(windows.begin(), windows.begin() + windows.size() / 2, windows.end());
    const double median = windows[windows.size() / 2];
    int64_t best = -1;
    double best_rms = std::numeric_limits<double>::max();
    for (int64_t start = kChunkSamples - kCutSearchSamples; start + kRmsWindow <= kChunkSamples; start += kRmsStep) {
      const double r = rms(start, kRmsWindow);
      if (r < best_rms) {
        best_rms = r;
        best = start;
      }
    }
    if (best >= 0 && best_rms < median) return best + kRmsWindow / 2;
    return kChunkSamples;
  }

  void report_progress(int64_t done_samples) {
    if (duration_samples_ <= 0) {
      if (!indeterminate_sent_) {
        indeterminate_sent_ = true;
        post_progress(job_, -1, -1);
      }
      return;
    }
    int64_t permille = done_samples * 1000 / duration_samples_;
    permille = std::clamp<int64_t>(permille, 0, 999);
    if (permille > last_permille_) {
      last_permille_ = static_cast<int32_t>(permille);
      post_progress(job_, last_permille_, duration_samples_ * 1000 / kSampleRate);
    }
  }

  static void on_segment(whisper_context* ctx, whisper_state*, int n_new, void* user) {
    auto* cb = static_cast<Callback*>(user);
    const int n = whisper_full_n_segments(ctx);
    const int64_t offset_ms = cb->chunk_start * 1000 / kSampleRate;
    for (int i = std::max(0, n - n_new); i < n; ++i) {
      const char* raw = whisper_full_get_segment_text(ctx, i);
      std::string text = raw != nullptr ? raw : "";
      const size_t first = text.find_first_not_of(" \t\n");
      if (first == std::string::npos) continue;
      text = text.substr(first, text.find_last_not_of(" \t\n") - first + 1);
      if (text == "[BLANK_AUDIO]") continue;
      const int64_t t0 = offset_ms + whisper_full_get_segment_t0(ctx, i) * 10;
      const int64_t t1 = offset_ms + whisper_full_get_segment_t1(ctx, i) * 10;
      post_segment(cb->self->job_, t0, t1, text);
    }
  }

  static void on_progress(whisper_context*, whisper_state*, int progress, void* user) {
    auto* cb = static_cast<Callback*>(user);
    cb->self->report_progress(cb->chunk_start + cb->chunk_len * progress / 100);
  }

  static bool on_abort(void* user) { return static_cast<Job*>(user)->cancel.load(); }

  bool transcribe(int64_t n) {
    if (n < kMinChunkSamples) return true;
    const auto started = Clock::now();
    Callback cb{this, chunk_start_, n};

    whisper_full_params wp = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    wp.n_threads = job_.n_threads;
    wp.translate = job_.translate;
    wp.language = language_.c_str();
    wp.detect_language = false;
    wp.no_context = false;  // whisper keeps the previous chunk's text as prompt
    // Never emit "[Music]"-style markers instead of words: on songs Base would
    // otherwise label every window as music and drop the lyrics entirely.
    wp.suppress_nst = true;
    wp.print_progress = false;
    wp.print_realtime = false;
    wp.print_timestamps = false;
    wp.print_special = false;
    wp.new_segment_callback = &Transcriber::on_segment;
    wp.new_segment_callback_user_data = &cb;
    wp.progress_callback = &Transcriber::on_progress;
    wp.progress_callback_user_data = &cb;
    wp.abort_callback = &Transcriber::on_abort;
    wp.abort_callback_user_data = &job_;

    const int rc = whisper_full(p_.wctx, wp, pcm_.data(), static_cast<int>(n));
    if (job_.cancel.load()) return false;
    if (rc != 0) {
      whisper_code_ = rc;
      return false;
    }
    if (detected_.empty()) {
      if (!whisper_is_multilingual(p_.wctx)) {
        detected_ = "en";
      } else if (language_ != "auto") {
        detected_ = language_;
      } else {
        const int id = whisper_full_lang_id(p_.wctx);
        const char* lang = id >= 0 ? whisper_lang_str(id) : nullptr;
        if (lang != nullptr) detected_ = lang;
      }
      // Keep one language across chunks once auto-detection has decided.
      if (language_ == "auto" && !detected_.empty()) language_ = detected_;
    }
    const int64_t audio_ms = n * 1000 / kSampleRate;
    const int64_t took = std::max<int64_t>(1, elapsed_ms(started));
    post_log(job_, "{\"stage\":\"chunk\",\"index\":" + std::to_string(chunk_index_++) +
                       ",\"audio_ms\":" + std::to_string(audio_ms) + ",\"ms\":" + std::to_string(took) +
                       ",\"realtime_x100\":" + std::to_string(audio_ms * 100 / took) + "}");
    report_progress(chunk_start_ + n);
    return true;
  }

  Job& job_;
  Pipeline& p_;
  std::vector<float> pcm_;
  int64_t chunk_start_ = 0;
  int64_t duration_samples_;
  std::string language_;
  std::string detected_;
  int32_t last_permille_;
  int32_t whisper_code_ = 0;
  int chunk_index_ = 0;
  bool indeterminate_sent_;
  bool any_audio_ = false;
};

Result fail(int32_t status, int32_t native_code = 0) {
  Result r;
  r.status = status;
  r.native_code = native_code;
  return r;
}

bool configure_resampler(Pipeline& p, const AVFrame* f) {
  swr_free(&p.swr);
  AVChannelLayout mono = AV_CHANNEL_LAYOUT_MONO;
  AVChannelLayout in_layout;
  if (f->ch_layout.nb_channels > 0) {
    if (av_channel_layout_copy(&in_layout, &f->ch_layout) < 0) return false;
  } else {
    av_channel_layout_default(&in_layout, 1);
  }
  const int rc = swr_alloc_set_opts2(&p.swr, &mono, AV_SAMPLE_FMT_FLT, kSampleRate, &in_layout,
                                     static_cast<AVSampleFormat>(f->format), f->sample_rate, 0, nullptr);
  av_channel_layout_uninit(&in_layout);
  return rc >= 0 && swr_init(p.swr) >= 0;
}

Result run(Job& job) {
  Pipeline p;
  const auto t_open = Clock::now();

  // ---- open + probe, bounded by the wall-clock deadline
  p.fmt = avformat_alloc_context();
  if (p.fmt == nullptr) return fail(EX_ERR_OOM);
  p.fmt->interrupt_callback.callback = &interrupt_cb;
  p.fmt->interrupt_callback.opaque = &job;
  p.fmt->opaque = &job;
  p.fmt->io_open = &io_open_cb;
  p.fmt->probesize = 32LL * 1024 * 1024;
  p.fmt->max_analyze_duration = 30LL * AV_TIME_BASE;
  job.allowed_url = "file:" + job.media_path;
  job.deadline_ns = now_ns() + std::chrono::duration_cast<std::chrono::nanoseconds>(kProbeTimeout).count();

  AVDictionary* opts = nullptr;
  av_dict_set(&opts, "protocol_whitelist", "file", 0);
  int rc = avformat_open_input(&p.fmt, job.allowed_url.c_str(), nullptr, &opts);
  av_dict_free(&opts);
  if (rc < 0) {
    if (job.timed_out) return fail(EX_ERR_TIMEOUT, rc);
    if (job.cancel) return fail(EX_CANCELLED, rc);
    return fail(EX_ERR_OPEN, rc);
  }
  rc = avformat_find_stream_info(p.fmt, nullptr);
  if (rc < 0 && (job.timed_out || job.cancel)) return fail(job.timed_out ? EX_ERR_TIMEOUT : EX_CANCELLED, rc);
  job.deadline_ns = 0;

  const AVCodec* codec = nullptr;
  const int audio_index = av_find_best_stream(p.fmt, AVMEDIA_TYPE_AUDIO, -1, -1, &codec, 0);
  if (audio_index == AVERROR_STREAM_NOT_FOUND) return fail(EX_ERR_NO_AUDIO, audio_index);
  if (audio_index < 0 || codec == nullptr) return fail(EX_ERR_DECODE, audio_index);
  AVStream* st = p.fmt->streams[audio_index];
  for (unsigned i = 0; i < p.fmt->nb_streams; ++i) {
    if (static_cast<int>(i) != audio_index) p.fmt->streams[i]->discard = AVDISCARD_ALL;
  }

  p.dec = avcodec_alloc_context3(codec);
  if (p.dec == nullptr) return fail(EX_ERR_OOM);
  if ((rc = avcodec_parameters_to_context(p.dec, st->codecpar)) < 0) return fail(EX_ERR_DECODE, rc);
  p.dec->pkt_timebase = st->time_base;
  if ((rc = avcodec_open2(p.dec, codec, nullptr)) < 0) return fail(EX_ERR_DECODE, rc);

  int64_t duration_samples = -1;
  if (p.fmt->duration != AV_NOPTS_VALUE && p.fmt->duration > 0) {
    duration_samples = av_rescale(p.fmt->duration, kSampleRate, AV_TIME_BASE);
  } else if (st->duration != AV_NOPTS_VALUE && st->duration > 0) {
    duration_samples = av_rescale_q(st->duration, st->time_base, AVRational{1, kSampleRate});
  }
  Result result;
  result.duration_ms = duration_samples > 0 ? duration_samples * 1000 / kSampleRate : -1;

  // Media clock origin: the container start, so a delayed audio track keeps its offset.
  int64_t origin = 0;
  if (p.fmt->start_time != AV_NOPTS_VALUE) {
    origin = av_rescale_q(p.fmt->start_time, AV_TIME_BASE_Q, st->time_base);
  } else if (st->start_time != AV_NOPTS_VALUE) {
    origin = st->start_time;
  }

  post_log(job, "{\"stage\":\"open\",\"ms\":" + std::to_string(elapsed_ms(t_open)) +
                    ",\"container\":" + json_name(p.fmt->iformat->name) +
                    ",\"codec\":" + json_name(avcodec_get_name(st->codecpar->codec_id)) +
                    ",\"sample_rate\":" + std::to_string(st->codecpar->sample_rate) +
                    ",\"channels\":" + std::to_string(st->codecpar->ch_layout.nb_channels) +
                    ",\"duration_ms\":" + std::to_string(result.duration_ms) + "}");
  post_progress(job, duration_samples > 0 ? 0 : -1, result.duration_ms);

  // ---- model (cancellation takes effect once loading returns)
  const auto t_model = Clock::now();
  FILE* model_file = open_read(job.model_path);
  if (model_file == nullptr) return fail(EX_ERR_MODEL);
  whisper_model_loader loader{model_file, &loader_read, &loader_eof, &loader_close};
  whisper_context_params cparams = whisper_context_default_params();
#if defined(TARGET_OS_SIMULATOR) && TARGET_OS_SIMULATOR
  // The iOS Simulator's Metal emulation traps on whisper's large buffers.
  cparams.use_gpu = false;
#else
  cparams.use_gpu = true;
#endif
  p.wctx = whisper_init_with_params(&loader, cparams);  // closes the file
  if (job.cancel) return fail(EX_CANCELLED);
  if (p.wctx == nullptr) return fail(EX_ERR_MODEL);
  post_log(job, "{\"stage\":\"model_load\",\"ms\":" + std::to_string(elapsed_ms(t_model)) + "}");

  // ---- decode → resample → transcribe
  p.pkt = av_packet_alloc();
  p.frame = av_frame_alloc();
  if (p.pkt == nullptr || p.frame == nullptr) return fail(EX_ERR_OOM);

  Transcriber tr(job, p, duration_samples);
  std::vector<float> out;
  int swr_rate = 0, swr_format = -1;
  AVChannelLayout swr_layout{};

  auto convert = [&](const AVFrame* f) -> bool {
    if (p.swr == nullptr || f->sample_rate != swr_rate || f->format != swr_format ||
        av_channel_layout_compare(&f->ch_layout, &swr_layout) != 0) {
      if (!configure_resampler(p, f)) return false;
      swr_rate = f->sample_rate;
      swr_format = f->format;
      av_channel_layout_uninit(&swr_layout);
      av_channel_layout_copy(&swr_layout, &f->ch_layout);
    }
    int64_t pts = kNoPts;
    if (f->best_effort_timestamp != AV_NOPTS_VALUE) {
      pts = av_rescale_q_rnd(f->best_effort_timestamp - origin, st->time_base, AVRational{1, kSampleRate},
                             static_cast<AVRounding>(AV_ROUND_NEAR_INF | AV_ROUND_PASS_MINMAX));
      pts -= swr_get_delay(p.swr, kSampleRate);
      if (pts < 0 || pts > kMaxPtsSamples) pts = kNoPts;
    }
    const int cap = swr_get_out_samples(p.swr, f->nb_samples);
    if (cap <= 0) return true;
    out.resize(static_cast<size_t>(cap));
    auto* dst = reinterpret_cast<uint8_t*>(out.data());
    const int got = swr_convert(p.swr, &dst, cap, const_cast<const uint8_t**>(f->extended_data), f->nb_samples);
    if (got < 0) {
      job.warnings++;
      return true;
    }
    return tr.push(out.data(), got, pts);
  };

  auto drain = [&]() -> bool {
    while (true) {
      const int r = avcodec_receive_frame(p.dec, p.frame);
      if (r == AVERROR(EAGAIN) || r == AVERROR_EOF) return true;
      if (r < 0) {
        job.warnings++;
        return true;
      }
      const bool ok = convert(p.frame);
      av_frame_unref(p.frame);
      if (!ok) return false;
    }
  };

  auto stopped = [&](int32_t fallback) -> Result {
    av_channel_layout_uninit(&swr_layout);
    if (job.cancel) return fail(EX_CANCELLED);
    if (tr.whisper_code() != 0) return fail(EX_ERR_INTERNAL, tr.whisper_code());
    return fail(fallback);
  };

  while (true) {
    if (job.cancel) return stopped(EX_CANCELLED);
    rc = av_read_frame(p.fmt, p.pkt);
    if (rc == AVERROR_EOF) break;
    if (rc < 0) {
      if (job.cancel) return stopped(EX_CANCELLED);
      if (rc == AVERROR(EAGAIN)) continue;
      // A truncated or damaged tail: keep what was decoded so far.
      if (tr.any_audio()) break;
      av_channel_layout_uninit(&swr_layout);
      return fail(EX_ERR_DECODE, rc);
    }
    if (p.pkt->stream_index != audio_index) {
      av_packet_unref(p.pkt);
      continue;
    }
    rc = avcodec_send_packet(p.dec, p.pkt);
    av_packet_unref(p.pkt);
    if (rc < 0 && rc != AVERROR(EAGAIN)) {
      job.warnings++;
      continue;
    }
    if (!drain()) return stopped(EX_ERR_DECODE);
  }

  // ---- EOF: drain the decoder, then the resampler's delayed samples
  avcodec_send_packet(p.dec, nullptr);
  if (!drain()) return stopped(EX_ERR_DECODE);
  if (p.swr != nullptr) {
    while (true) {
      const int cap = std::max(4096, swr_get_out_samples(p.swr, 0));
      out.resize(static_cast<size_t>(cap));
      auto* dst = reinterpret_cast<uint8_t*>(out.data());
      const int got = swr_convert(p.swr, &dst, cap, nullptr, 0);
      if (got <= 0) break;
      if (!tr.push(out.data(), got, kNoPts)) return stopped(EX_ERR_DECODE);
    }
  }
  if (!tr.finish()) return stopped(EX_ERR_DECODE);
  av_channel_layout_uninit(&swr_layout);
  if (!tr.any_audio()) return fail(EX_ERR_DECODE);

  result.status = EX_OK;
  result.language = tr.detected_language();
  return result;
}

void worker(std::shared_ptr<Job> job) {
  t_job = job.get();
  const auto started = Clock::now();
  Result r;
  try {
    r = run(*job);
  } catch (const std::bad_alloc&) {
    r = fail(EX_ERR_OOM);
  } catch (...) {
    r = fail(EX_ERR_INTERNAL);
  }
  if (r.status != EX_OK && job->cancel.load() && r.status != EX_ERR_TIMEOUT) r.status = EX_CANCELLED;

  post_log(*job, "{\"stage\":\"done\",\"status\":" + std::to_string(r.status) +
                     ",\"ms\":" + std::to_string(elapsed_ms(started)) +
                     ",\"warnings\":" + std::to_string(job->warnings) + "}");
  ex_event* ev = new_event(job->id, EX_EV_DONE);
  if (ev != nullptr) {
    ev->status = r.status;
    ev->native_code = r.native_code;
    ev->duration_ms = r.duration_ms;
    ev->progress_permille = r.status == EX_OK ? 1000 : -1;
    set_text(ev, r.language);
    post(*job, ev);
  }
  t_job = nullptr;
  job->finished = true;
}

// Joins and forgets workers that have posted DONE. Caller holds g_mutex.
void reap_locked() {
  for (auto it = g_jobs.begin(); it != g_jobs.end();) {
    if (it->second->finished.load() && it->second->thread.joinable()) {
      it->second->thread.join();
      it = g_jobs.erase(it);
    } else {
      ++it;
    }
  }
}

#if defined(EX_X86_64)
void cpuid(unsigned leaf, unsigned sub, unsigned regs[4]) {
#if defined(_MSC_VER)
  int r[4];
  __cpuidex(r, static_cast<int>(leaf), static_cast<int>(sub));
  for (int i = 0; i < 4; ++i) regs[i] = static_cast<unsigned>(r[i]);
#else
  __cpuid_count(leaf, sub, regs[0], regs[1], regs[2], regs[3]);
#endif
}

uint64_t xgetbv0() {
#if defined(_MSC_VER)
  return _xgetbv(0);
#else
  uint32_t eax = 0, edx = 0;
  __asm__ volatile("xgetbv" : "=a"(eax), "=d"(edx) : "c"(0));
  return (static_cast<uint64_t>(edx) << 32) | eax;
#endif
}
#endif

}  // namespace

extern "C" {

EX_API int32_t ex_api_version(void) { return EX_API_VERSION; }

EX_API const char* ex_build_info(void) {
  ensure_silent_logging();
  static const std::string info = std::string("extracter_native/") + std::to_string(EX_API_VERSION) +
                                  "; whisper.cpp 1.9.5 (d1be6fde); FFmpeg " + av_version_info() +
                                  " decode-only LGPL-2.1; " + whisper_print_system_info();
  return info.c_str();
}

EX_API int32_t ex_init(ex_post_fn post, int64_t port) {
  if (post == nullptr) return -1;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_post = post;
    g_port = port;
    // Jobs of an earlier isolate (closed activity, hot restart) have nobody
    // left to report to.
    for (auto& entry : g_jobs) {
      if (entry.second->port != port) entry.second->cancel = true;
    }
  }
  ensure_silent_logging();
  return 0;
}

EX_API int64_t ex_job_start(const char* media_path_utf8, const char* model_path_utf8, const char* language,
                            int32_t translate, int32_t n_threads) {
  if (g_post.load() == nullptr) return -EX_ERR_INTERNAL;
  if (media_path_utf8 == nullptr || model_path_utf8 == nullptr || language == nullptr) return -EX_ERR_INTERNAL;
  try {
    auto job = std::make_shared<Job>();
    job->media_path = media_path_utf8;
    job->model_path = model_path_utf8;
    job->language = language;
    job->translate = translate != 0;
    job->n_threads = std::clamp(n_threads, 1, 16);
    job->id = g_next_id.fetch_add(1);

    std::lock_guard<std::mutex> lock(g_mutex);
    reap_locked();
    job->port = g_port.load();  // under g_mutex, so ex_init sees every job
    g_jobs[job->id] = job;
    try {
      job->thread = std::thread(worker, job);
    } catch (...) {
      g_jobs.erase(job->id);
      return -EX_ERR_INTERNAL;
    }
    return job->id;
  } catch (const std::bad_alloc&) {
    return -EX_ERR_OOM;
  } catch (...) {
    return -EX_ERR_INTERNAL;
  }
}

EX_API void ex_job_cancel(int64_t job_id) {
  std::lock_guard<std::mutex> lock(g_mutex);
  auto it = g_jobs.find(job_id);
  if (it != g_jobs.end()) it->second->cancel = true;
}

EX_API void ex_event_free(ex_event* ev) {
  if (ev == nullptr) return;
  std::free(ev->text);
  std::free(ev);
}

EX_API int32_t ex_cpu_supported(void) {
#if defined(EX_X86_64)
  unsigned r[4] = {0, 0, 0, 0};
  cpuid(0, 0, r);
  if (r[0] < 7) return 0;
  cpuid(1, 0, r);
  const unsigned ecx = r[2];
  const bool sse42 = (ecx >> 20) & 1u, fma = (ecx >> 12) & 1u, osxsave = (ecx >> 27) & 1u;
  const bool avx = (ecx >> 28) & 1u, f16c = (ecx >> 29) & 1u;
  if (!(sse42 && fma && osxsave && avx && f16c)) return 0;
  if ((xgetbv0() & 0x6) != 0x6) return 0;  // OS saves XMM + YMM state
  cpuid(7, 0, r);
  const bool avx2 = (r[1] >> 5) & 1u, bmi2 = (r[1] >> 8) & 1u;
  return (avx2 && bmi2) ? 1 : 0;
#else
  return 1;
#endif
}

EX_API int64_t ex_total_ram_bytes(void) {
#if defined(_WIN32)
  MEMORYSTATUSEX status;
  status.dwLength = sizeof(status);
  return GlobalMemoryStatusEx(&status) ? static_cast<int64_t>(status.ullTotalPhys) : -1;
#elif defined(__APPLE__)
  int64_t mem = 0;
  size_t len = sizeof(mem);
  return sysctlbyname("hw.memsize", &mem, &len, nullptr, 0) == 0 ? mem : -1;
#else
  const long pages = sysconf(_SC_PHYS_PAGES);
  const long page = sysconf(_SC_PAGE_SIZE);
  return (pages > 0 && page > 0) ? static_cast<int64_t>(pages) * page : -1;
#endif
}

EX_API int64_t ex_free_disk_bytes(const char* dir_path_utf8) {
  if (dir_path_utf8 == nullptr) return -1;
#if defined(_WIN32)
  ULARGE_INTEGER free_bytes;
  return GetDiskFreeSpaceExW(widen(dir_path_utf8).c_str(), &free_bytes, nullptr, nullptr)
             ? static_cast<int64_t>(free_bytes.QuadPart)
             : -1;
#else
  struct statvfs s;
  if (statvfs(dir_path_utf8, &s) != 0) return -1;
  return static_cast<int64_t>(s.f_bavail) * static_cast<int64_t>(s.f_frsize);
#endif
}

EX_API int32_t ex_exclude_from_backup(const char* dir_path_utf8) {
  if (dir_path_utf8 == nullptr) return -1;
#if defined(__APPLE__)
  CFURLRef url = CFURLCreateFromFileSystemRepresentation(
      nullptr, reinterpret_cast<const UInt8*>(dir_path_utf8), static_cast<CFIndex>(std::strlen(dir_path_utf8)), true);
  if (url == nullptr) return -1;
  const Boolean ok = CFURLSetResourcePropertyForKey(url, kCFURLIsExcludedFromBackupKey, kCFBooleanTrue, nullptr);
  CFRelease(url);
  return ok ? 0 : -1;
#else
  return 1;
#endif
}

EX_API void ex_shutdown(void) {
  std::lock_guard<std::mutex> lock(g_mutex);
  for (auto& entry : g_jobs) entry.second->cancel = true;
  for (auto& entry : g_jobs) {
    if (entry.second->thread.joinable()) entry.second->thread.join();
  }
  g_jobs.clear();
}

}  // extern "C"
