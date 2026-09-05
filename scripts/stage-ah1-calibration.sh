#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/FullAuthority.app" >&2
  exit 64
fi

APP_PATH="$1"
SOURCE_ROOT="${GITHUB_WORKSPACE:-$PWD}/ThirdParty/jsbsim"
RESOURCE_ROOT="$APP_PATH/JSBSim"

[[ -d "$APP_PATH" ]] || { echo "app bundle not found: $APP_PATH" >&2; exit 1; }
[[ -d "$SOURCE_ROOT/aircraft/ah1s" ]] || { echo "JSBSim AH-1S source is missing" >&2; exit 1; }

mkdir -p "$RESOURCE_ROOT/aircraft/ah1s" "$RESOURCE_ROOT/engine" "$RESOURCE_ROOT/systems" "$RESOURCE_ROOT/licenses"

cp "$SOURCE_ROOT/aircraft/ah1s/ah1s.xml" "$RESOURCE_ROOT/aircraft/ah1s/ah1s.xml"
cp "$SOURCE_ROOT/aircraft/ah1s/reset00.xml" "$RESOURCE_ROOT/aircraft/ah1s/reset00.xml"

cp "$SOURCE_ROOT/aircraft/ah1s/Engines/ah1s_rotor.xml" "$RESOURCE_ROOT/engine/ah1s_rotor.xml"
cp "$SOURCE_ROOT/aircraft/ah1s/Engines/ah1s_tail_rotor.xml" "$RESOURCE_ROOT/engine/ah1s_tail_rotor.xml"
cp "$SOURCE_ROOT/aircraft/ah1s/Engines/electric_1500hp.xml" "$RESOURCE_ROOT/engine/electric_1500hp.xml"
cp "$SOURCE_ROOT/aircraft/ah1s/Engines/electric_1hp_dummy.xml" "$RESOURCE_ROOT/engine/electric_1hp_dummy.xml"

cp "$SOURCE_ROOT/aircraft/ah1s/Systems/rotor_control.xml" "$RESOURCE_ROOT/systems/rotor_control.xml"
cp "$SOURCE_ROOT/aircraft/ah1s/Systems/steady_flight_data.xml" "$RESOURCE_ROOT/systems/steady_flight_data.xml"
cp "$SOURCE_ROOT/aircraft/ah1s/Systems/trim_control.xml" "$RESOURCE_ROOT/systems/trim_control.xml"
cp "$SOURCE_ROOT/systems/rpm_governor.xml" "$RESOURCE_ROOT/systems/rpm_governor.xml"
cp "$SOURCE_ROOT/systems/afcs.xml" "$RESOURCE_ROOT/systems/afcs.xml"

# Keep the upstream notices alongside the calibration data. The AH-1S XML also
# contains its own explicit model license notice. This aircraft is a development
# calibration reference, not a Full Authority shipping aircraft.
cp "$SOURCE_ROOT/COPYING" "$RESOURCE_ROOT/licenses/JSBSim-COPYING.txt"

for required in \
  "$RESOURCE_ROOT/aircraft/ah1s/ah1s.xml" \
  "$RESOURCE_ROOT/engine/ah1s_rotor.xml" \
  "$RESOURCE_ROOT/systems/rotor_control.xml" \
  "$RESOURCE_ROOT/systems/rpm_governor.xml" \
  "$RESOURCE_ROOT/systems/afcs.xml"; do
  test -s "$required"
done

echo "Staged JSBSim AH-1S calibration model into $RESOURCE_ROOT"
