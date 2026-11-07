#!/bin/sh
set -eu

device=${1:-booted}
bundle_id=org.angelauramc.amethyst.jitflagstests
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/amethyst-jitflags.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
cd "$(dirname "$0")/.."

app="$test_dir/JITFlagsTests.app"
mkdir -p "$app"
cat > "$app/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$bundle_id</string>
  <key>CFBundleExecutable</key><string>JITFlagsTests</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>14.0</string>
  <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
</dict></plist>
EOF

sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator clang -target arm64-apple-ios14.0-simulator -isysroot "$sdk" \
    -fobjc-arc -fcommon -I Natives -I Natives/ctxbridges -I Natives/external/mesa \
    -Dmmap=JITFlagsTestMmap -c Natives/utils.m -o "$test_dir/utils.o"
xcrun --sdk iphonesimulator clang -target arm64-apple-ios14.0-simulator -isysroot "$sdk" \
    -fobjc-arc -fcommon -I Natives -I Natives/ctxbridges -I Natives/external/mesa \
    -framework Foundation -framework UIKit -framework SafariServices -framework Security -framework CoreImage \
    Tests/JITFlagsTests.m "$test_dir/utils.o" -o "$app/JITFlagsTests"
codesign --force --sign - "$app"
xcrun simctl install "$device" "$app"
trap 'xcrun simctl uninstall "$device" "$bundle_id" || :; rm -rf "$test_dir"' EXIT
installed=$(xcrun simctl get_app_container "$device" "$bundle_id" app)
xcrun simctl spawn "$device" "$installed/JITFlagsTests"
