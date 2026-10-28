## 1.0.1

* Android: transcriptions and model downloads keep running when you switch apps or
  turn the screen off. While Extracter is in the background, a notification shows
  the progress; on a lock screen that hides sensitive content it leaves out the
  file name.
* Export transcripts as Markdown (#6, thanks to nahuel007ng).
* Language names are shown in the app's language (#1).
* macOS and iOS builds use the real app name and bundle ID.

## 1.0.0

* First release: offline transcription of audio and video files with whisper.cpp
  and FFmpeg, a batch queue with live results and time left, timestamps, copy with
  or without timestamps, TXT, SRT and VTT export, searchable history, and an
  English and Russian interface.
