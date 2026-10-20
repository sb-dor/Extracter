import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'extracter_native_bindings_generated.dart';
import 'native_job_event.dart';

/// The native transcription engine: FFmpeg decode + whisper.cpp, one worker
/// thread per job, events delivered on [events].
abstract interface class IExtracterNative {
  /// ABI version of the loaded library; must equal [ExtracterNative.expectedApiVersion].
  int get apiVersion;

  /// Library versions and the FFmpeg build profile.
  String get buildInfo;

  /// False on x86_64 CPUs below the x86-64-v3 baseline.
  bool get cpuSupported;

  /// Physical memory in bytes, or null when unknown.
  int? get totalRamBytes;

  /// Free bytes on the volume holding [directory], or null when unknown.
  int? freeDiskBytes(String directory);

  /// iOS/macOS: excludes [directory] from device backups. No-op elsewhere.
  void excludeFromBackup(String directory);

  /// Every event of every job, in the order native posted them.
  Stream<NativeJobEvent> get events;

  /// Starts a job and returns its id (> 0). A negative value is `-status`: the
  /// job did not start and no [NativeDone] will follow.
  int startJob({
    required String mediaPath,
    required String modelPath,
    required String language,
    required bool translate,
    required int threads,
  });

  /// Idempotent; unknown or finished ids are ignored.
  void cancelJob(int jobId);

  /// Cancels every job and joins the worker threads. Call on app exit.
  void shutdown();
}

final class ExtracterNative implements IExtracterNative {
  ExtracterNative._(this._bindings) {
    // One listener for the whole process, never closed: native may post until
    // ex_shutdown returns, and a closed callable would be undefined behaviour.
    _listener = ffi.NativeCallable<ffi.Void Function(ffi.Pointer<ex_event>)>.listener(_onEvent)
      ..keepIsolateAlive = false;
    _bindings.ex_init(_listener.nativeFunction);
  }

  /// The process-wide engine. Throws [UnsupportedError] if the library is missing.
  factory ExtracterNative() => _instance ??= ExtracterNative._(ExtracterNativeBindings(_open()));

  static const int expectedApiVersion = EX_API_VERSION;
  static ExtracterNative? _instance;

  final ExtracterNativeBindings _bindings;
  late final ffi.NativeCallable<ffi.Void Function(ffi.Pointer<ex_event>)> _listener;
  final StreamController<NativeJobEvent> _events = StreamController<NativeJobEvent>.broadcast();

  static ffi.DynamicLibrary _open() {
    const name = 'extracter_native';
    if (Platform.isMacOS || Platform.isIOS) return ffi.DynamicLibrary.open('$name.framework/$name');
    if (Platform.isAndroid || Platform.isLinux) return ffi.DynamicLibrary.open('lib$name.so');
    if (Platform.isWindows) return ffi.DynamicLibrary.open('$name.dll');
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  void _onEvent(ffi.Pointer<ex_event> pointer) {
    try {
      final ev = pointer.ref;
      final text = ev.text == ffi.nullptr || ev.text_len <= 0
          ? null
          : utf8.decode(ev.text.cast<ffi.Uint8>().asTypedList(ev.text_len), allowMalformed: true);
      final durationMs = ev.duration_ms >= 0 ? ev.duration_ms : null;
      final event = switch (ev.kind) {
        0 => NativeProgress(ev.job_id, permille: ev.progress_permille, durationMs: durationMs),
        1 => NativeSegment(ev.job_id, startMs: ev.t0_ms, endMs: ev.t1_ms, text: text ?? ''),
        2 => NativeDone(
          ev.job_id,
          status: NativeJobStatus.fromCode(ev.status),
          nativeCode: ev.native_code,
          detectedLanguage: text,
          durationMs: durationMs,
        ),
        _ => NativeLog(ev.job_id, text ?? '{}'),
      };
      _events.add(event);
    } finally {
      _bindings.ex_event_free(pointer);
    }
  }

  @override
  int get apiVersion => _bindings.ex_api_version();

  @override
  String get buildInfo => _bindings.ex_build_info().cast<Utf8>().toDartString();

  @override
  bool get cpuSupported => _bindings.ex_cpu_supported() == 1;

  @override
  int? get totalRamBytes {
    final bytes = _bindings.ex_total_ram_bytes();
    return bytes > 0 ? bytes : null;
  }

  @override
  int? freeDiskBytes(String directory) {
    final path = directory.toNativeUtf8();
    try {
      final bytes = _bindings.ex_free_disk_bytes(path.cast());
      return bytes >= 0 ? bytes : null;
    } finally {
      calloc.free(path);
    }
  }

  @override
  void excludeFromBackup(String directory) {
    final path = directory.toNativeUtf8();
    try {
      _bindings.ex_exclude_from_backup(path.cast());
    } finally {
      calloc.free(path);
    }
  }

  @override
  Stream<NativeJobEvent> get events => _events.stream;

  @override
  int startJob({
    required String mediaPath,
    required String modelPath,
    required String language,
    required bool translate,
    required int threads,
  }) {
    final media = mediaPath.toNativeUtf8();
    final model = modelPath.toNativeUtf8();
    final lang = language.toNativeUtf8();
    try {
      // Native copies every string before returning.
      return _bindings.ex_job_start(media.cast(), model.cast(), lang.cast(), translate ? 1 : 0, threads);
    } finally {
      calloc
        ..free(media)
        ..free(model)
        ..free(lang);
    }
  }

  @override
  void cancelJob(int jobId) => _bindings.ex_job_cancel(jobId);

  @override
  void shutdown() => _bindings.ex_shutdown();
}
