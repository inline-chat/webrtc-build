#!/bin/bash

set -e

if [[ -z "$1" ]]; then
  echo "Usage: $0 'debug' | 'release' 'source_dir' 'out_dir' ['framework_prefix'] ['symbol_prefix']"
  exit 0
fi

MODE="$1"
SOURCE_DIR="$(realpath "$2")"
OUT_DIR="$(realpath "$3")"
PREFIX="${4:-""}"
SYMBOL_PREFIX="${5:-""}"

if [ -z "$PREFIX" ]; then
  FRAMEWORK_NAME="WebRTC"
  SYMBOL_PREFIX="${SYMBOL_PREFIX:-RTC}"
else
  FRAMEWORK_NAME="${PREFIX}WebRTC"
  SYMBOL_PREFIX="${SYMBOL_PREFIX:-${PREFIX}RTC}"
fi

DEBUG="false"
if [[ "$MODE" == "debug" ]]; then
  DEBUG="true"
fi

PARALLEL_BUILDS=6

echo "xcframework.sh: MODE=$MODE, DEBUG=$DEBUG, SOURCE_DIR=$SOURCE_DIR, OUT_DIR=$OUT_DIR, PREFIX=$PREFIX, FRAMEWORK_NAME=$FRAMEWORK_NAME, SYMBOL_PREFIX=$SYMBOL_PREFIX"

start_group() {
  if [[ "$CI" == "true" ]]; then
    echo "::group::$1"
  else
    echo "=== $1 ==="
  fi
}

end_group() {
  if [[ "$CI" == "true" ]]; then
    echo "::endgroup::"
  fi
}

require_exported_symbol() {
  local binary_path="$1"
  local symbol="$2"

  if ! nm -gU "$binary_path" | grep -Fq "$symbol"; then
    echo "error: $binary_path does not export required symbol $symbol" >&2
    exit 1
  fi
}

require_header_text() {
  local header_path="$1"
  local text="$2"

  if ! grep -Fq "$text" "$header_path"; then
    echo "error: $header_path does not declare required SDK API $text" >&2
    exit 1
  fi
}

require_exact_archs() {
  local binary_path="$1"
  shift
  local actual_archs
  local actual_arch
  local expected_arch
  local found

  if ! actual_archs="$(lipo -archs "$binary_path")"; then
    echo "error: unable to read architectures from $binary_path" >&2
    exit 1
  fi

  for expected_arch in "$@"; do
    if [[ " $actual_archs " != *" $expected_arch "* ]]; then
      echo "error: $binary_path is missing required architecture $expected_arch ($actual_archs)" >&2
      exit 1
    fi
  done

  for actual_arch in $actual_archs; do
    found="false"
    for expected_arch in "$@"; do
      if [[ "$actual_arch" == "$expected_arch" ]]; then
        found="true"
        break
      fi
    done
    if [[ "$found" != "true" ]]; then
      echo "error: $binary_path contains unexpected architecture $actual_arch ($actual_archs)" >&2
      exit 1
    fi
  done
}

validate_framework_sdk() {
  local framework_path="$1"
  local binary_path="$framework_path/$FRAMEWORK_NAME"
  local headers_path="$framework_path/Headers"

  require_exported_symbol "$binary_path" "_${SYMBOL_PREFIX}InitializeSSL"
  require_exported_symbol "$binary_path" "_OBJC_CLASS_\$_${SYMBOL_PREFIX}AudioDeviceModule"
  require_exported_symbol "$binary_path" "_OBJC_CLASS_\$_${SYMBOL_PREFIX}AudioSource"
  require_exported_symbol "$binary_path" "_OBJC_CLASS_\$_${SYMBOL_PREFIX}AudioProcessingState"
  require_exported_symbol "$binary_path" "_OBJC_CLASS_\$_${SYMBOL_PREFIX}PlatformAudioProcessingState"
  require_exported_symbol "$binary_path" "_k${SYMBOL_PREFIX}AudioEngineInputMixerNodeKey"
  require_header_text \
    "$headers_path/RTCAudioDeviceModule.h" \
    "RTCAudioEngineRuntimeDiagnostics"
  require_header_text \
    "$headers_path/RTCAudioDeviceModule.h" \
    "audioEngineRuntimeDiagnostics"
  require_header_text \
    "$headers_path/RTCAudioDeviceModule.h" \
    "configuredPlayoutSampleRate"
  require_header_text \
    "$headers_path/RTCAudioDeviceModule.h" \
    "configuredRecordingSampleRate"
  require_header_text \
    "$headers_path/RTCAudioDeviceModule.h" \
    "configuredPlayoutChannels"
  require_header_text \
    "$headers_path/RTCAudioDeviceModule.h" \
    "configuredRecordingChannels"
  require_header_text \
    "$headers_path/RTCAudioProcessingState.h" \
    "RTCAudioProcessingState"
}

COMMON_ARGS="
      enable_dsyms = $DEBUG
      enable_libaom = true
      enable_stripping = true
      fatal_linker_warnings = false
      ios_enable_code_signing = false
      is_component_build = false
      is_debug = $DEBUG
      rtc_build_examples = false
      rtc_enable_protobuf = false
      rtc_enable_symbol_export = true
      rtc_include_dav1d_in_internal_decoder_factory = true
      rtc_include_tests = false
      rtc_libvpx_build_vp9 = true
      rtc_use_h264 = false
      treat_warnings_as_errors = false
      use_clang_modules = false
      use_custom_libcxx = false
      use_lld = false
      use_rtti = true
      use_siso = false"

PLATFORMS=(
  "iOS-arm64-device:target_os=\"ios\" target_environment=\"device\" target_cpu=\"arm64\" ios_deployment_target=\"13.0\""
  "iOS-arm64-simulator:target_os=\"ios\" target_environment=\"simulator\" target_cpu=\"arm64\" ios_deployment_target=\"13.0\""
  "iOS-x64-simulator:target_os=\"ios\" target_environment=\"simulator\" target_cpu=\"x64\" ios_deployment_target=\"13.0\""
  "macOS-arm64:target_os=\"mac\" target_cpu=\"arm64\" mac_deployment_target=\"10.15\""
  "catalyst-arm64:target_os=\"ios\" target_environment=\"catalyst\" target_cpu=\"arm64\" ios_deployment_target=\"14.0\""
  "catalyst-x64:target_os=\"ios\" target_environment=\"catalyst\" target_cpu=\"x64\" ios_deployment_target=\"14.0\""
  "tvOS-arm64-device:target_os=\"ios\" target_environment=\"appletv\" target_cpu=\"arm64\" ios_deployment_target=\"17.0\""
  "tvOS-arm64-simulator:target_os=\"ios\" target_environment=\"appletvsimulator\" target_cpu=\"arm64\" ios_deployment_target=\"17.0\""
  "xrOS-arm64-device:target_os=\"ios\" target_environment=\"xrdevice\" target_cpu=\"arm64\" ios_deployment_target=\"26.0\""
  "xrOS-arm64-simulator:target_os=\"ios\" target_environment=\"xrsimulator\" target_cpu=\"arm64\" ios_deployment_target=\"26.0\""
)

cd "$SOURCE_DIR"

end_group

for platform_config in "${PLATFORMS[@]}"; do
  platform="${platform_config%%:*}"
  config="${platform_config#*:}"
  
  start_group "Building $platform"
  
  gn gen "$OUT_DIR/$platform" --args="$COMMON_ARGS $config" --ide=xcode
  
  if [[ $platform == *"macOS"* ]]; then
    build_target="mac_framework_bundle"
  else
    build_target="ios_framework_bundle"
  fi
  
  ninja -C "$OUT_DIR/$platform" "$build_target" -j $PARALLEL_BUILDS --quiet || exit 1
  validate_framework_sdk "$OUT_DIR/$platform/$FRAMEWORK_NAME.framework"
  end_group
done

start_group "Creating combined Apple binaries"

mkdir -p "$OUT_DIR/catalyst-lib"
cp -R "$OUT_DIR/catalyst-arm64/$FRAMEWORK_NAME.framework" "$OUT_DIR/catalyst-lib/$FRAMEWORK_NAME.framework"
lipo -create -output "$OUT_DIR/catalyst-lib/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME" "$OUT_DIR/catalyst-arm64/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME" "$OUT_DIR/catalyst-x64/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME"
if [ -d "$OUT_DIR/catalyst-arm64/$FRAMEWORK_NAME.dSYM" ]; then
  cp -R "$OUT_DIR/catalyst-arm64/$FRAMEWORK_NAME.dSYM" "$OUT_DIR/catalyst-lib/$FRAMEWORK_NAME.dSYM"
  lipo -create -output "$OUT_DIR/catalyst-lib/$FRAMEWORK_NAME.dSYM/Contents/Resources/DWARF/$FRAMEWORK_NAME" "$OUT_DIR/catalyst-arm64/$FRAMEWORK_NAME.dSYM/Contents/Resources/DWARF/$FRAMEWORK_NAME" "$OUT_DIR/catalyst-x64/$FRAMEWORK_NAME.dSYM/Contents/Resources/DWARF/$FRAMEWORK_NAME"
fi

mkdir -p "$OUT_DIR/iOS-device-lib"
cp -R "$OUT_DIR/iOS-arm64-device/$FRAMEWORK_NAME.framework" "$OUT_DIR/iOS-device-lib/$FRAMEWORK_NAME.framework"
lipo -create -output "$OUT_DIR/iOS-device-lib/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME" "$OUT_DIR/iOS-arm64-device/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME"
if [ -d "$OUT_DIR/iOS-arm64-device/$FRAMEWORK_NAME.dSYM" ]; then
  cp -R "$OUT_DIR/iOS-arm64-device/$FRAMEWORK_NAME.dSYM" "$OUT_DIR/iOS-device-lib/$FRAMEWORK_NAME.dSYM"
  lipo -create -output "$OUT_DIR/iOS-device-lib/$FRAMEWORK_NAME.dSYM/Contents/Resources/DWARF/$FRAMEWORK_NAME" "$OUT_DIR/iOS-arm64-device/$FRAMEWORK_NAME.dSYM/Contents/Resources/DWARF/$FRAMEWORK_NAME"
fi

mkdir -p "$OUT_DIR/iOS-simulator-lib"
cp -R "$OUT_DIR/iOS-arm64-simulator/$FRAMEWORK_NAME.framework" "$OUT_DIR/iOS-simulator-lib/$FRAMEWORK_NAME.framework"
lipo -create -output "$OUT_DIR/iOS-simulator-lib/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME" "$OUT_DIR/iOS-arm64-simulator/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME" "$OUT_DIR/iOS-x64-simulator/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME"
if [ -d "$OUT_DIR/iOS-arm64-simulator/$FRAMEWORK_NAME.dSYM" ]; then
  cp -R "$OUT_DIR/iOS-arm64-simulator/$FRAMEWORK_NAME.dSYM" "$OUT_DIR/iOS-simulator-lib/$FRAMEWORK_NAME.dSYM"
  lipo -create -output "$OUT_DIR/iOS-simulator-lib/$FRAMEWORK_NAME.dSYM/Contents/Resources/DWARF/$FRAMEWORK_NAME" "$OUT_DIR/iOS-arm64-simulator/$FRAMEWORK_NAME.dSYM/Contents/Resources/DWARF/$FRAMEWORK_NAME" "$OUT_DIR/iOS-x64-simulator/$FRAMEWORK_NAME.dSYM/Contents/Resources/DWARF/$FRAMEWORK_NAME"
fi

end_group

start_group "Creating XCFramework"

XCFRAMEWORK_ARGS=(-create-xcframework)

FRAMEWORK_PATHS=(
  "$OUT_DIR/iOS-device-lib/$FRAMEWORK_NAME.framework"
  "$OUT_DIR/iOS-simulator-lib/$FRAMEWORK_NAME.framework"
  "$OUT_DIR/macOS-arm64/$FRAMEWORK_NAME.framework"
  "$OUT_DIR/catalyst-lib/$FRAMEWORK_NAME.framework"
  "$OUT_DIR/tvOS-arm64-device/$FRAMEWORK_NAME.framework"
  "$OUT_DIR/tvOS-arm64-simulator/$FRAMEWORK_NAME.framework"
  "$OUT_DIR/xrOS-arm64-device/$FRAMEWORK_NAME.framework"
  "$OUT_DIR/xrOS-arm64-simulator/$FRAMEWORK_NAME.framework"
)

DSYM_PATHS=(
  "$OUT_DIR/iOS-device-lib/$FRAMEWORK_NAME.dSYM"
  "$OUT_DIR/iOS-simulator-lib/$FRAMEWORK_NAME.dSYM"
  "$OUT_DIR/macOS-arm64/$FRAMEWORK_NAME.dSYM"
  "$OUT_DIR/catalyst-lib/$FRAMEWORK_NAME.dSYM"
  "$OUT_DIR/tvOS-arm64-device/$FRAMEWORK_NAME.dSYM"
  "$OUT_DIR/tvOS-arm64-simulator/$FRAMEWORK_NAME.dSYM"
  "$OUT_DIR/xrOS-arm64-device/$FRAMEWORK_NAME.dSYM"
  "$OUT_DIR/xrOS-arm64-simulator/$FRAMEWORK_NAME.dSYM"
)

for i in "${!FRAMEWORK_PATHS[@]}"; do
  XCFRAMEWORK_ARGS+=(-framework "${FRAMEWORK_PATHS[$i]}")

  if [[ "$DEBUG" == "true" ]] && [[ -d "${DSYM_PATHS[$i]}" ]]; then
    XCFRAMEWORK_ARGS+=(-debug-symbols "${DSYM_PATHS[$i]}")
  fi
done

XCFRAMEWORK_ARGS+=(-output "$OUT_DIR/$FRAMEWORK_NAME.xcframework")

xcodebuild "${XCFRAMEWORK_ARGS[@]}"

end_group

start_group "Post-processing XCFramework"

cp LICENSE "$OUT_DIR/$FRAMEWORK_NAME.xcframework/"

cd "$OUT_DIR/$FRAMEWORK_NAME.xcframework/macos-arm64/$FRAMEWORK_NAME.framework/"
mv "$FRAMEWORK_NAME" "Versions/A/$FRAMEWORK_NAME"
ln -s "Versions/Current/$FRAMEWORK_NAME" "$FRAMEWORK_NAME"

cd "$OUT_DIR/$FRAMEWORK_NAME.xcframework/ios-arm64_x86_64-maccatalyst/$FRAMEWORK_NAME.framework/"
mv "$FRAMEWORK_NAME" "Versions/A/$FRAMEWORK_NAME"
ln -s "Versions/Current/$FRAMEWORK_NAME" "$FRAMEWORK_NAME"

XCFRAMEWORK_PATH="$OUT_DIR/$FRAMEWORK_NAME.xcframework"
XCFRAMEWORK_SLICE_PATHS=(
  "$XCFRAMEWORK_PATH/ios-arm64/$FRAMEWORK_NAME.framework"
  "$XCFRAMEWORK_PATH/ios-arm64_x86_64-simulator/$FRAMEWORK_NAME.framework"
  "$XCFRAMEWORK_PATH/macos-arm64/$FRAMEWORK_NAME.framework"
  "$XCFRAMEWORK_PATH/ios-arm64_x86_64-maccatalyst/$FRAMEWORK_NAME.framework"
  "$XCFRAMEWORK_PATH/tvos-arm64/$FRAMEWORK_NAME.framework"
  "$XCFRAMEWORK_PATH/tvos-arm64-simulator/$FRAMEWORK_NAME.framework"
  "$XCFRAMEWORK_PATH/xros-arm64/$FRAMEWORK_NAME.framework"
  "$XCFRAMEWORK_PATH/xros-arm64-simulator/$FRAMEWORK_NAME.framework"
)

for framework_path in "${XCFRAMEWORK_SLICE_PATHS[@]}"; do
  validate_framework_sdk "$framework_path"
done

require_exact_archs "${XCFRAMEWORK_SLICE_PATHS[0]}/$FRAMEWORK_NAME" arm64
require_exact_archs "${XCFRAMEWORK_SLICE_PATHS[1]}/$FRAMEWORK_NAME" arm64 x86_64
require_exact_archs "${XCFRAMEWORK_SLICE_PATHS[2]}/$FRAMEWORK_NAME" arm64
require_exact_archs "${XCFRAMEWORK_SLICE_PATHS[3]}/$FRAMEWORK_NAME" arm64 x86_64
require_exact_archs "${XCFRAMEWORK_SLICE_PATHS[4]}/$FRAMEWORK_NAME" arm64
require_exact_archs "${XCFRAMEWORK_SLICE_PATHS[5]}/$FRAMEWORK_NAME" arm64
require_exact_archs "${XCFRAMEWORK_SLICE_PATHS[6]}/$FRAMEWORK_NAME" arm64
require_exact_archs "${XCFRAMEWORK_SLICE_PATHS[7]}/$FRAMEWORK_NAME" arm64

cd "$OUT_DIR"
zip --symlinks -9 -r "$FRAMEWORK_NAME.xcframework.zip" "$FRAMEWORK_NAME.xcframework"

end_group

if [[ "$CI" == "true" ]]; then
  echo "framework_name=$FRAMEWORK_NAME" >> "$GITHUB_OUTPUT"
fi
