#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:?usage: compile-shaders.sh output-directory [iphoneos|iphonesimulator|msl]}"
sdk="${2:-iphoneos}"
case "$sdk" in
  iphoneos|iphonesimulator|msl) ;;
  *) echo "Unsupported shader target: $sdk" >&2; exit 2 ;;
esac
mkdir -p "$output"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
source_file="$repo/Shaders/LightmappedPreview.hlsl"

convert_stage() {
  local stage="$1" hlsl_entry="$2" metal_entry="$3"
  glslangValidator -D -V -S "$stage" -e "$hlsl_entry" --hlsl-offsets \
    --auto-map-locations -o "$work/$stage.spv" "$source_file"
  spirv-val "$work/$stage.spv"
  spirv-cross "$work/$stage.spv" --msl --msl-ios --msl-version 20300 \
    --msl-decoration-binding --rename-entry-point "$hlsl_entry" "$metal_entry" "$stage" \
    --output "$work/$stage.metal"
}

convert_stage vert vertexMain lightmappedVertex
convert_stage frag fragmentMain lightmappedFragment

if [[ "$sdk" == msl ]]; then
  cp "$work/vert.metal" "$output/LightmappedVertex.metal"
  cp "$work/frag.metal" "$output/LightmappedFragment.metal"
else
  xcrun -sdk "$sdk" metal -c "$work/vert.metal" -o "$work/vert.air"
  xcrun -sdk "$sdk" metal -c "$work/frag.metal" -o "$work/frag.air"
  xcrun -sdk "$sdk" metallib "$work/vert.air" "$work/frag.air" -o "$work/LightmappedPreview.metallib"
  cp "$work/LightmappedPreview.metallib" "$output/"
fi
