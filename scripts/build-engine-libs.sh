#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$(cd "${1:?usage: build-engine-libs.sh source-checkout output-directory [iphoneos|iphonesimulator]}" && pwd)"
output="${2:?set the output directory}"
sdk="${3:-iphoneos}"
case "$sdk" in
  iphoneos) target=arm64-apple-ios17.0 ;;
  iphonesimulator) target=arm64-apple-ios17.0-simulator ;;
  *) echo "Unsupported SDK: $sdk" >&2; exit 2 ;;
esac

expected=$(cat "$repo/Engine/Upstream/revision")
actual=$(git -C "$source_dir" rev-parse HEAD)
if [[ "$actual" != "$expected" ]]; then
  echo "Expected source-engine revision $expected, found $actual" >&2
  exit 2
fi

mkdir -p "$output"
output="$(cd "$output" && pwd)"
sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
cxx="$(xcrun --sdk "$sdk" --find clang++)"
libtool="$(xcrun --sdk "$sdk" --find libtool)"
common_flags=(
  -target "$target" -isysroot "$sdk_path" -std=c++11 -O2 -fno-strict-aliasing
  -DOSX=1 -D_OSX=1 -DPOSIX=1 -D_POSIX=1 -DPLATFORM_POSIX=1 -DGNUC=1
  -DPLATFORM_64BITS=1 -DNO_HOOK_MALLOC=1 -DNDEBUG=1 -D_DLL_EXT=.dylib
  -I"$source_dir/public" -I"$source_dir/public/tier0"
  -I"$source_dir/public/mathlib" -I"$source_dir/common"
)

build_library() {
  local module="$1" define="$2"
  shift 2
  local file object
  local objects=()
  mkdir -p "$output/$module"
  for file in "$@"; do
    object="$output/$module/$file.o"
    printf '%s/%s.cpp\n' "$module" "$file"
    "$cxx" "${common_flags[@]}" "-D$define=1" -c "$source_dir/$module/$file.cpp" -o "$object"
    objects+=("$object")
  done
  "$libtool" -static -o "$output/lib$module.a" "${objects[@]}"
}

# Source Engine's POSIX tier0 and mathlib source lists from Waf.
build_library tier0 TIER0_DLL_EXPORT \
  assert_dialog commandline cpu cpumonitoring cpu_usage dbg dynfunction fasttimer \
  mem mem_helpers memdbg memstd memvalidate minidump pch_tier0 PMELib progressbar \
  security systeminformation stacktools thread threadtools tier0_strtools tslist vprof \
  cpu_posix platform_posix pme_posix vcrmode_posix

build_library mathlib MATHLIB_LIB \
  color_conversion halton lightdesc mathlib_base powsse sparse_convolution_noise \
  sseconst sse ssenoise 3dnow anorms bumpvects IceKey imagequant polyhedron quantize \
  randsse spherical simdvectormatrix vector vmatrix almostequal
