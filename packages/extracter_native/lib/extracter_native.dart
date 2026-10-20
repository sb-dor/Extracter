/// On-device transcription engine for Extracter: FFmpeg (decode-only, LGPL)
/// + whisper.cpp behind a small C ABI.
library;

export 'src/extracter_native_impl.dart' show ExtracterNative, IExtracterNative;
export 'src/native_job_event.dart';
