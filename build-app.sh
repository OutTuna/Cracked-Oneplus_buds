#!/bin/sh
set -eu
project=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build_root=${ENCO_BUILD_PATH:-"$project/.build"}
configuration=${ENCO_CONFIGURATION:-release}
destination=${ENCO_APP_OUTPUT:-"$project/../Enco.app"}
swift build --package-path "$project" --scratch-path "$build_root" -c "$configuration" --product enco-menu
bin_path=$(swift build --package-path "$project" --scratch-path "$build_root" -c "$configuration" --show-bin-path)
app_bundle="$build_root/Enco.app"
rm -rf "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources" "$app_bundle/Contents/Frameworks"
cp "$bin_path/enco-menu" "$app_bundle/Contents/MacOS/Enco"
ditto "$bin_path/EncoAir5Pro_EncoMenu.bundle" "$app_bundle/Contents/Resources/EncoAir5Pro_EncoMenu.bundle"
cp "$project/Support/App-Info.plist" "$app_bundle/Contents/Info.plist"
ditto "$bin_path/Sparkle.framework" "$app_bundle/Contents/Frameworks/Sparkle.framework"
cp "$build_root/artifacts/encoair5pro/Sparkle/LICENSE" "$app_bundle/Contents/Resources/Sparkle-LICENSE.txt"
install_name_tool -add_rpath '@executable_path/../Frameworks' "$app_bundle/Contents/MacOS/Enco"
"$bin_path/enco-menu" --export-icon "$build_root/Enco-icon.png"
iconset="$build_root/Enco.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$build_root/Enco-icon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$build_root/Enco-icon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app_bundle/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$app_bundle/Contents/PkgInfo"
codesign --force --sign - "$app_bundle"
codesign --verify --deep --strict "$app_bundle"
ditto "$app_bundle" "$destination"
echo "$destination"
