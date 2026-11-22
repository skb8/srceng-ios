#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd "${1:?usage: build-hl2-client-host.sh source-checkout SDL-checkout output-directory SDK}" && pwd)"
sdl_source="$(cd "${2:?set the SDL source directory}" && pwd)"
output="${3:?set the output directory}"
sdk="${4:?set the iOS SDK}"

case "$sdk" in
  iphoneos) target=arm64-apple-ios17.0 ;;
  iphonesimulator) target=arm64-apple-ios17.0-simulator ;;
  *) echo "Unsupported SDK: $sdk" >&2; exit 2 ;;
esac

mkdir -p "$output"
output="$(cd "$output" && pwd)"
sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
jobs="$(sysctl -n hw.logicalcpu)"

cmake -S "$sdl_source" -B "$output/sdl-build" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
  -DCMAKE_OSX_SYSROOT="$sdk_path" -DCMAKE_INSTALL_PREFIX="$output/sdl" \
  -DCMAKE_INSTALL_NAME_DIR=@rpath -DSDL_SHARED=ON -DSDL_STATIC=OFF \
  -DSDL_TEST=OFF -DSDL_TESTS=OFF -DSDL_INSTALL_TESTS=OFF
cmake --build "$output/sdl-build" --parallel "$jobs"
cmake --install "$output/sdl-build"

export CC="$(xcrun --sdk "$sdk" --find clang)"
export CXX="$(xcrun --sdk "$sdk" --find clang++)"
export CFLAGS="-target $target -isysroot $sdk_path"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="$CFLAGS"
export PKG_CONFIG_LIBDIR="$output/sdl/lib/pkgconfig"
unset PKG_CONFIG_PATH

cd "$source_dir"
if ! python3 waf configure -T release --ios-client-host --build-games hl2 --disable-warns \
  --out="$output/objects" --prefix="$output/runtime"; then
  tail -n 80 "$output/objects/config.log" >&2
  exit 1
fi

log="$output/build.log"
if ! python3 waf install -kk --targets=engine -j "$jobs" > "$log" 2>&1; then
  sed -E '/^\[[[:space:]0-9]+\/[[:space:]0-9]+\]/d; /^\+ install /d' "$log" >&2
  exit 1
fi
tail -n 2 "$log"
cp -P "$output/sdl/lib/"libSDL2*.dylib "$output/runtime/bin/"
