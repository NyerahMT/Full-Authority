#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/FullAuthority.app" >&2
  exit 64
fi

APP_PATH="$1"
SOURCE_ROOT="${GITHUB_WORKSPACE:-$PWD}/ThirdParty/jsbsim"
RESOURCE_ROOT="$APP_PATH/JSBSim"
MODEL_ROOT="$APP_PATH/Models"

F16_VISUAL_COMMIT="e0757b1473736d5b2a64351cba4be46a20abf53e"
F16_VISUAL_BASE="https://raw.githubusercontent.com/srdanrasic/R4/${F16_VISUAL_COMMIT}"
F16_VISUAL_PATH="demo/R4%20iOS%20Demo/Resources/Meshes/f16.obj"

[[ -d "$APP_PATH" ]] || { echo "app bundle not found: $APP_PATH" >&2; exit 1; }
[[ -f "$SOURCE_ROOT/aircraft/f16/f16.xml" ]] || { echo "JSBSim F-16 source is missing" >&2; exit 1; }
[[ -f "$SOURCE_ROOT/engine/F100-PW-229.xml" ]] || { echo "JSBSim F100 engine source is missing" >&2; exit 1; }
[[ -f "$SOURCE_ROOT/engine/direct.xml" ]] || { echo "JSBSim direct thruster source is missing" >&2; exit 1; }

rm -rf "$RESOURCE_ROOT/aircraft/f16"
mkdir -p "$RESOURCE_ROOT/aircraft" "$RESOURCE_ROOT/engine" "$RESOURCE_ROOT/licenses" "$MODEL_ROOT"

# Preserve the complete upstream aircraft directory. That includes reset files,
# local systems and every other resource the FDM expects beside f16.xml.
cp -R "$SOURCE_ROOT/aircraft/f16" "$RESOURCE_ROOT/aircraft/f16"
cp "$SOURCE_ROOT/engine/F100-PW-229.xml" "$RESOURCE_ROOT/engine/F100-PW-229.xml"
cp "$SOURCE_ROOT/engine/direct.xml" "$RESOURCE_ROOT/engine/direct.xml"
cp "$SOURCE_ROOT/COPYING" "$RESOURCE_ROOT/licenses/JSBSim-COPYING.txt"

# JSBSim intentionally does not ship render art. Stage a pinned, MIT-licensed
# F-16 OBJ rather than fabricating an aircraft from RealityKit primitives.
curl --fail --location --retry 3 --silent --show-error \
  "$F16_VISUAL_BASE/$F16_VISUAL_PATH" \
  -o "$MODEL_ROOT/f16.obj"
curl --fail --location --retry 3 --silent --show-error \
  "$F16_VISUAL_BASE/LICENSE" \
  -o "$RESOURCE_ROOT/licenses/R4-F16-MIT-LICENSE.txt"

for required in \
  "$RESOURCE_ROOT/aircraft/f16/f16.xml" \
  "$RESOURCE_ROOT/engine/F100-PW-229.xml" \
  "$RESOURCE_ROOT/engine/direct.xml" \
  "$MODEL_ROOT/f16.obj"; do
  test -s "$required"
done

grep -q '^o f16' "$MODEL_ROOT/f16.obj"
grep -q '^f ' "$MODEL_ROOT/f16.obj"

echo "Staged complete JSBSim F-16 model and pinned F-16 render mesh"
