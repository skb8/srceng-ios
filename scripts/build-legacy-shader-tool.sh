#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source="$(cd "${1:?usage: build-legacy-shader-tool.sh mojoshader-checkout output-directory}" && pwd)"
output="${2:?set the output directory}"
tools="$repo/Engine/Upstream/LegacyShaders"
expected="$(cat "$tools/mojoshader-revision")"
[[ "$(git -C "$source" rev-parse HEAD)" == "$expected" ]] || {
  echo "Expected MojoShader revision $expected" >&2
  exit 2
}

mkdir -p "$output"
printf '#define MOJOSHADER_VERSION (-1)\n#define MOJOSHADER_CHANGESET "git-%s"\n' \
  "$expected" > "$output/mojoshader_version.h"
"${CC:-cc}" -std=gnu11 -include alloca.h -O2 -I"$output" -I"$source" \
  -DSUPPORT_PROFILE_D3D=0 -DSUPPORT_PROFILE_BYTECODE=0 -DSUPPORT_PROFILE_HLSL=0 \
  -DSUPPORT_PROFILE_ARB1=0 -DSUPPORT_PROFILE_ARB1_NV=0 \
  -DSUPPORT_PROFILE_GLSL=0 -DSUPPORT_PROFILE_GLSL120=0 \
  -DSUPPORT_PROFILE_GLSLES=0 -DSUPPORT_PROFILE_GLSLES3=0 \
  -DSUPPORT_PROFILE_SPIRV=0 -DSUPPORT_PROFILE_GLSPIRV=0 \
  "$tools/translate.c" "$source/mojoshader.c" "$source/mojoshader_common.c" \
  "$source/profiles/mojoshader_profile_common.c" "$source/profiles/mojoshader_profile_metal.c" \
  -lm -o "$output/d3d9-to-msl"
