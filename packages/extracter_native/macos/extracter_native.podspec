#
# extracter_native for macOS. Run scripts/build_apple.sh first: it installs
# Frameworks/ (FFmpeg.xcframework, whisper.xcframework, include/).
#
Pod::Spec.new do |s|
  s.name             = 'extracter_native'
  s.version          = '1.0.0'
  s.summary          = 'On-device transcription: FFmpeg decoding + whisper.cpp.'
  s.description      = 'Decodes audio/video with a decode-only LGPL FFmpeg and transcribes it with whisper.cpp.'
  s.homepage         = 'https://github.com/ggml-org/whisper.cpp'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Extracter' => 'extracter@localhost' }

  # Podspec does not support relative paths, so Classes contains a forwarder
  # that includes ../src/extracter_native.cpp, shared with every platform.
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.vendored_frameworks = 'Frameworks/FFmpeg.xcframework', 'Frameworks/whisper.xcframework'
  s.preserve_paths   = 'Frameworks/include/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '13.3'
  s.frameworks = 'Metal', 'MetalKit', 'Accelerate', 'Foundation'
  s.libraries = 'c++', 'z'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/Frameworks/include"',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    # CocoaPods embeds the dynamic FFmpeg framework in the app but does not
    # link it into this pod's own binary.
    'OTHER_LDFLAGS' => '$(inherited) -framework FFmpeg',
  }
  s.swift_version = '5.0'
end
