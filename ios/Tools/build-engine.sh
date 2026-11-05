#!/bin/bash
# Source builds only. Preserve the upstream engine's safe/precise math mode.
set -euo pipefail
repo=$(cd "$SRCROOT/.." && pwd)
sdk=${PLATFORM_NAME:-iphonesimulator}
case "$sdk" in
  iphoneos) suffix="" ;;
  iphonesimulator) suffix="-simulator" ;;
  *) echo "Unsupported platform: $sdk" >&2; exit 1 ;;
esac
target="air64-apple-ios${IPHONEOS_DEPLOYMENT_TARGET:-17.0}${suffix}"
work="$DERIVED_FILE_DIR/grainroom-kernels-$sdk"
resources="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/GrainroomData"
mkdir -p "$work" "$resources/engine" "$resources/Licenses"
airs=()
for source in "$repo"/engine/src/shaders/*.metal; do
  air="$work/$(basename "$source" .metal).air"
  if [[ ! -f "$air" || "$source" -nt "$air" || "$SRCROOT/Tools/build-engine.sh" -nt "$air" ]]; then
    xcrun --sdk "$sdk" metal -target "$target" -fmetal-math-mode=safe \
      -fmetal-math-fp32-functions=precise -Werror -c "$source" -o "$air"
  fi
  airs+=("$air")
done
rsync -a --delete --exclude='*.metallib' "$repo/engine/resources/" "$resources/engine/"
xcrun --sdk "$sdk" metallib "${airs[@]}" -o "$resources/engine/spektrafilm.metallib"
cp "$repo/engine/resources_product/profiles/"*.json "$resources/engine/profiles/"
cp "$repo/engine/resources_product/NOTICE.md" "$resources/Licenses/PRODUCT_PROFILES_NOTICE.md"
shared="$repo/modern_UI/Spektrafilm/Spektrafilm/Resources"
cp "$shared/StockCatalog.json" "$resources/StockCatalog.json"
cp "$shared/Licenses/"*.txt "$resources/Licenses/"
