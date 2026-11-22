#!/usr/bin/env bash
set -euo pipefail

sim="${1:?set a booted Simulator UDID}"
runtime="$(cd "${2:?set the client runtime directory}" && pwd)"
source_dir="$(cd "${3:?set the Source checkout directory}" && pwd)"
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$runtime/SourceMetalWindowProbe.app"
bundle_id=io.github.skb8.srceng.metal-window-probe

mkdir -p "$app/bin"
cp -P "$runtime/bin/"*.dylib "$app/bin/"
cat > "$app/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>SourceMetalWindowProbe</string>
  <key>CFBundleIdentifier</key><string>$bundle_id</string>
  <key>CFBundleName</key><string>SourceMetalWindowProbe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
  <key>MinimumOSVersion</key><string>17.0</string>
  <key>UILaunchScreen</key><dict/>
</dict>
</plist>
PLIST

xcrun --sdk iphonesimulator clang++ -std=c++11 -fobjc-arc \
  -target arm64-apple-ios17.0-simulator \
  -isysroot "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -DOSX=1 -D_OSX=1 -DPOSIX=1 -D_POSIX=1 -DPLATFORM_POSIX=1 \
  -DGNUC=1 -DPLATFORM_64BITS=1 -DNDEBUG=1 -DUSE_SDL=1 -DDONT_DEFINE_BOOL=1 \
  -I"$source_dir/public" "$repo/Engine/Upstream/MetalWindowProbe.mm" \
  -L"$runtime/bin" -ltier0 -Wl,-rpath,@executable_path/bin \
  -framework UIKit -framework Metal -framework QuartzCore -o "$app/SourceMetalWindowProbe"
codesign --force --sign - "$app"
xcrun simctl install "$sim" "$app"
xcrun simctl launch --console "$sim" "$bundle_id" 2>&1 | tee "$runtime/metal-window-probe.log"
grep -Fx 'Presented a Metal drawable from the Source window manager' "$runtime/metal-window-probe.log"
