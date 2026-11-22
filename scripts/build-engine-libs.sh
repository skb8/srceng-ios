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
cc="$(xcrun --sdk "$sdk" --find clang)"
cxx="$(xcrun --sdk "$sdk" --find clang++)"
libtool="$(xcrun --sdk "$sdk" --find libtool)"
common_flags=(
  -target "$target" -isysroot "$sdk_path" -O2 -fno-strict-aliasing -fsigned-char
  -DOSX=1 -D_OSX=1 -DPOSIX=1 -D_POSIX=1 -DPLATFORM_POSIX=1 -DGNUC=1
  -DPLATFORM_64BITS=1 -DNO_HOOK_MALLOC=1 -DNDEBUG=1 -D_DLL_EXT=.dylib
  '-DWAF_CFLAGS="iOS arm64 C++11"' '-DWAF_LDFLAGS="static archive"'
  -I"$source_dir/public" -I"$source_dir/public/tier0"
  -I"$source_dir/public/mathlib" -I"$source_dir/common" -I"$source_dir"
  -I"$source_dir/public/tier1" -I"$source_dir/public/tier2" -I"$source_dir/public/tier3"
  -I"$source_dir/public/vstdlib"
)

build_library() {
  local module="$1" folder="$2"
  shift 2
  local extra_flags=()
  while [[ "$1" != -- ]]; do
    extra_flags+=("$1")
    shift
  done
  shift

  local file object compiler language
  local objects=()
  mkdir -p "$output/$module"
  for file in "$@"; do
    compiler="$cxx"
    language=c++11
    case "$file" in
      *.c) compiler="$cc"; language=c11 ;;
      *.cpp) ;;
      *) file="$folder/$file.cpp" ;;
    esac
    object="$output/$module/${file//\//_}.o"
    printf '%s\n' "$file"
    "$compiler" "-std=$language" "${common_flags[@]}" "${extra_flags[@]}" \
      -I"$source_dir/$folder" -c "$source_dir/$file" -o "$object"
    objects+=("$object")
  done
  "$libtool" -static -o "$output/lib$module.a" "${objects[@]}"
}

# Source Engine's POSIX tier0 and mathlib source lists from Waf.
build_library tier0 tier0 -DTIER0_DLL_EXPORT=1 -- \
  assert_dialog commandline cpu cpumonitoring cpu_usage dbg dynfunction fasttimer \
  mem mem_helpers memdbg memstd memvalidate minidump pch_tier0 PMELib progressbar \
  security systeminformation stacktools thread threadtools tier0_strtools tslist vprof \
  cpu_posix platform_posix pme_posix vcrmode_posix

build_library mathlib mathlib -DMATHLIB_LIB=1 -- \
  color_conversion halton lightdesc mathlib_base powsse sparse_convolution_noise \
  sseconst sse ssenoise 3dnow anorms bumpvects IceKey imagequant polyhedron quantize \
  randsse spherical simdvectormatrix vector vmatrix almostequal

build_library tier1 tier1 -DTIER1_STATIC_LIB=1 -- \
  utils/lzma/C/LzmaDec.c bitbuf byteswap characterset checksum_crc checksum_md5 \
  checksum_sha1 commandbuffer convar datamanager diff generichash ilocalize interface \
  KeyValues keyvaluesjson kvpacker lzmaDecoder lzss mempool memstack NetAdr newbitbuf \
  rangecheckedvar reliabletimer snappy-sinksource snappy-stubs-internal snappy sparsematrix \
  splitstring stringpool strtools strtools_unicode tier1 tokenreader uniqueid utlbinaryblock \
  utlbuffer utlbufferutil utlstring utlsymbol processor_detect_linux qsort_s

build_library tier2 tier2 -DNO_STEAM=1 -- \
  beamsegdraw defaultfilesystem dmconnect fileutils keybindings public/map_utils.cpp \
  public/materialsystem/MaterialSystemUtil.cpp camerautils meshutils p4helpers renderutils riff \
  soundutils tier2 util_init utlstreambuffer vconfig keyvaluesmacros

build_library vstdlib vstdlib -DVSTDLIB_DLL_EXPORT=1 -- \
  coroutine cvar jobthread KeyValuesSystem random vcover public/tier0/memoverride.cpp

build_library vpklib vpklib -DNO_STEAM=1 -- packedstore common/simplebitstring.cpp

build_library filesystem_stdio filesystem -DFILESYSTEM_STDIO_EXPORTS=1 \
  -DDONT_PROTECT_FILEIO_FUNCTIONS=1 -DSUPPORT_PACKED_STORE=1 -- \
  basefilesystem packfile filetracker filesystem_async filesystem_stdio \
  public/kevvaluescompiler.cpp public/zip_utils.cpp QueuedLoader linux_support

build_library appframework appframework -DNO_STEAM=1 -- \
  AppSystemGroup public/filesystem_init.cpp posixapp

"$cxx" -std=c++11 "${common_flags[@]}" "$repo/Engine/Upstream/FilesystemProbe.cpp" \
  -Wl,-force_load,"$output/libfilesystem_stdio.a" \
  "$output/libappframework.a" "$output/libvpklib.a" "$output/libtier2.a" \
  "$output/libvstdlib.a" "$output/libmathlib.a" "$output/libtier1.a" "$output/libtier0.a" \
  -framework CoreFoundation -liconv -lz -o "$output/source-filesystem-probe"
