#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd "${1:?usage: build-hl2-dedicated.sh source-checkout output-directory SDK}" && pwd)"
output="${2:?set the output directory}"
sdk="${3:?set the iOS SDK}"

case "$sdk" in
  iphoneos) target=arm64-apple-ios17.0 ;;
  iphonesimulator) target=arm64-apple-ios17.0-simulator ;;
  *) echo "Unsupported SDK: $sdk" >&2; exit 2 ;;
esac

mkdir -p "$output"
output="$(cd "$output" && pwd)"
sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
export CC="$(xcrun --sdk "$sdk" --find clang)"
export CXX="$(xcrun --sdk "$sdk" --find clang++)"
export CFLAGS="-target $target -isysroot $sdk_path"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="$CFLAGS"

cd "$source_dir"
if ! python3 waf configure -T release --dedicated --ios-dedicated --ios-hl2-client --build-games hl2 --disable-warns \
  --out="$output/objects" --prefix="$output/runtime"; then
  tail -n 70 "$output/objects/config.log" >&2
  exit 1
fi
log="$output/build.log"
if ! python3 waf install -kk -j "$(sysctl -n hw.logicalcpu)" > "$log" 2>&1; then
  sed -E '/^\[[[:space:]0-9]+\/[[:space:]0-9]+\]/d; /^\+ install /d' "$log" >&2
  exit 1
fi
tail -n 2 "$log"
