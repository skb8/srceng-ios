#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
sdk="${1:-iphoneos}"
case "$sdk" in
  iphoneos) destination="generic/platform=iOS" ;;
  iphonesimulator) destination="generic/platform=iOS Simulator" ;;
  *) echo "Unsupported SDK: $sdk" >&2; exit 2 ;;
esac
if (( $# > 0 )); then shift; fi

shader_dir="$repo/build/$sdk/shaders"
scripts/compile-shaders.sh "$shader_dir" "$sdk"
mkdir -p App/Generated
cp "$shader_dir/LightmappedPreview.metallib" App/Generated/
xcodegen generate --spec project.yml
xcodebuild -project SourceIOS.xcodeproj -scheme SourceIOS -configuration Release \
  -sdk "$sdk" -destination "$destination" -derivedDataPath "$repo/build/$sdk" \
  CODE_SIGNING_ALLOWED=NO "$@" build
