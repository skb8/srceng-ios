#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:?usage: compile-shaders.sh output-directory}"
mkdir -p "$output"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
source_file="$repo/Shaders/PreviewMaterials.hlsl"

convert_stage() {
  local stage="$1" hlsl_entry="$2" metal_entry="$3" file="$4"
  glslangValidator -D -V -S "$stage" -e "$hlsl_entry" --hlsl-offsets \
    --auto-map-locations -o "$work/$metal_entry.spv" "$source_file"
  spirv-val "$work/$metal_entry.spv"
  spirv-cross "$work/$metal_entry.spv" --msl --msl-ios --msl-version 20300 \
    --msl-decoration-binding --rename-entry-point "$hlsl_entry" "$metal_entry" "$stage" \
    --output "$work/$file"
}

convert_stage vert vertexMain lightmappedVertex LightmappedVertex.metal
convert_stage frag fragmentMain lightmappedFragment LightmappedFragment.metal
convert_stage frag unlitMain unlitFragment UnlitFragment.metal
cp "$work/"*.metal "$output/"
