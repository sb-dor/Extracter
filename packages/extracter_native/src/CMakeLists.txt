# Shared native build for Android, Linux and Windows (iOS/macOS use the
# podspecs with prebuilt xcframeworks from scripts/build_apple.sh).
#
# Needs the FFmpeg build for the target from scripts/build_ffmpeg.sh:
#   third_party/build/ffmpeg-<target>/out/{libffmpeg.so|ffmpeg.dll, include/}
cmake_minimum_required(VERSION 3.14)

project(extracter_native_library VERSION 1.0.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(EX_ROOT "${CMAKE_CURRENT_LIST_DIR}/..")

# ---- whisper.cpp: one static CPU backend with a fixed ISA baseline
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)
set(GGML_CPU_ALL_VARIANTS OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)

if(ANDROID)
  set(EX_FFMPEG_TARGET "android-${ANDROID_ABI}")
  if(ANDROID_ABI STREQUAL "arm64-v8a")
    # Armv8.0 baseline: Cortex-A53-class devices must not hit illegal instructions.
    set(GGML_CPU_ARM_ARCH "armv8-a" CACHE STRING "" FORCE)
  else()
    set(GGML_AVX OFF CACHE BOOL "" FORCE)
    set(GGML_AVX2 OFF CACHE BOOL "" FORCE)
    set(GGML_FMA OFF CACHE BOOL "" FORCE)
    set(GGML_F16C OFF CACHE BOOL "" FORCE)
    set(GGML_BMI2 OFF CACHE BOOL "" FORCE)
  endif()
else()
  if(WIN32)
    set(EX_FFMPEG_TARGET "windows-x86_64")
  else()
    set(EX_FFMPEG_TARGET "linux-x86_64")
  endif()
  # x86-64-v3 baseline, guarded at runtime by ex_cpu_supported().
  foreach(opt SSE42 AVX AVX2 FMA F16C BMI2)
    set(GGML_${opt} ON CACHE BOOL "" FORCE)
  endforeach()
  foreach(opt AVX_VNNI AVX512 AVX512_VBMI AVX512_VNNI AVX512_BF16 AMX_TILE AMX_INT8 AMX_BF16)
    set(GGML_${opt} OFF CACHE BOOL "" FORCE)
  endforeach()
endif()

add_subdirectory("${EX_ROOT}/third_party/whisper.cpp" whisper EXCLUDE_FROM_ALL)

# ---- FFmpeg: one shared library, linked dynamically (LGPL)
set(EX_FFMPEG_DIR "${EX_ROOT}/third_party/build/ffmpeg-${EX_FFMPEG_TARGET}/out")
if(WIN32)
  set(EX_FFMPEG_LIBRARY "${EX_FFMPEG_DIR}/ffmpeg.dll")
  set(EX_FFMPEG_IMPLIB "${EX_FFMPEG_DIR}/ffmpeg.lib")
else()
  set(EX_FFMPEG_LIBRARY "${EX_FFMPEG_DIR}/libffmpeg.so")
endif()
if(NOT EXISTS "${EX_FFMPEG_LIBRARY}")
  message(FATAL_ERROR "FFmpeg for ${EX_FFMPEG_TARGET} not built: run scripts/build_ffmpeg.sh ${EX_FFMPEG_TARGET}")
endif()
# Read by linux/ and windows/CMakeLists.txt to bundle the library.
set(EXTRACTER_FFMPEG_LIBRARY "${EX_FFMPEG_LIBRARY}" CACHE INTERNAL "")

add_library(ffmpeg SHARED IMPORTED)
set_target_properties(ffmpeg PROPERTIES
  IMPORTED_LOCATION "${EX_FFMPEG_LIBRARY}"
  INTERFACE_INCLUDE_DIRECTORIES "${EX_FFMPEG_DIR}/include")
if(WIN32)
  set_target_properties(ffmpeg PROPERTIES IMPORTED_IMPLIB "${EX_FFMPEG_IMPLIB}")
endif()

# ---- the shim
add_library(extracter_native SHARED "extracter_native.cpp")
target_link_libraries(extracter_native PRIVATE whisper ffmpeg)
target_compile_definitions(extracter_native PUBLIC DART_SHARED_LIB)
set_target_properties(extracter_native PROPERTIES
  PUBLIC_HEADER extracter_native.h
  OUTPUT_NAME "extracter_native"
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON)

if(ANDROID)
  # 16 KB page alignment (Android 15+).
  target_link_options(extracter_native PRIVATE "-Wl,-z,max-page-size=16384")
elseif(UNIX)
  # libffmpeg.so sits next to libextracter_native.so in the bundle's lib/.
  set_target_properties(extracter_native PROPERTIES BUILD_RPATH "$ORIGIN" INSTALL_RPATH "$ORIGIN")
endif()
