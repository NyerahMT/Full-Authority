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

# Stage 010.3 keeps the upstream aerodynamic coefficient tables intact but uses
# a conservative yaw command path. The previous experimental PID multiplied
# yaw-rate feedback by up to 100 before a delayed rudder actuator, which caused
# the on-device hunting/oscillation. Pedal authority is now direct, with only a
# small proportional yaw-rate and lateral-load damper. No I/D terms are used.
# Full Authority currently sends the airborne command with the opposite sign,
# so the leading '-' converts it back to the model's positive rudder convention.
python3 - "$RESOURCE_ROOT/aircraft/f16/f16.xml" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
pattern = re.compile(
    r'  <channel name="Yaw">\n.*?\n  </channel>\n\n  <channel name="Landing Gear">',
    re.S,
)
replacement = '''  <channel name="Yaw">
   <!-- Full Authority Stage 010.3b: direct pedal + gentle proportional damper. -->
   <scheduled_gain name="fcs/yaw-rate-damper">
    <input>velocities/r-aero-rad_sec</input>
    <table>
     <independentVar>velocities/vg-fps</independentVar>
     <tableData>
       0.0    0.00
      80.0    0.00
     120.0   -0.30
     250.0   -0.65
     700.0   -0.55
    1800.0   -0.40
     </tableData>
    </table>
   </scheduled_gain>

   <pure_gain name="fcs/yaw-load-damper">
    <input>accelerations/n-pilot-y-norm</input>
    <gain>-0.06</gain>
   </pure_gain>

   <summer name="fcs/yaw-scheduler">
    <input>-fcs/rudder-cmd-norm</input>
    <input>fcs/yaw-trim-cmd-norm</input>
    <input>fcs/yaw-rate-damper</input>
    <input>fcs/yaw-load-damper</input>
    <clipto>
     <min>-1</min>
     <max>1</max>
    </clipto>
   </summer>

   <kinematic name="fcs/rudder-position">
    <input>fcs/yaw-scheduler</input>
    <traverse>
     <setting>
      <position>-1</position>
      <time>0.32</time>
     </setting>
     <setting>
      <position>1</position>
      <time>0.32</time>
     </setting>
    </traverse>
    <output>fcs/rudder-pos-norm</output>
   </kinematic>

   <aerosurface_scale name="fcs/rudder-control">
    <input>fcs/rudder-pos-norm</input>
    <range>
     <min>-0.524</min>
     <max>0.524</max>
    </range>
    <output>fcs/rudder-pos-rad</output>
   </aerosurface_scale>
  </channel>

  <channel name="Landing Gear">'''
updated, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise SystemExit(f"expected one F-16 yaw channel, replaced {count}")
path.write_text(updated, encoding="utf-8")
PY

grep -q 'Full Authority Stage 010.3b' "$RESOURCE_ROOT/aircraft/f16/f16.xml"

# JSBSim intentionally does not ship render art. Stage a pinned, MIT-licensed
# F-16 OBJ rather than fabricating an aircraft from RealityKit primitives.
curl --fail --location --retry 3 --silent --show-error \
  "$F16_VISUAL_BASE/$F16_VISUAL_PATH" \
  -o "$MODEL_ROOT/f16.obj"
curl --fail --location --retry 3 --silent --show-error \
  "$F16_VISUAL_BASE/LICENSE" \
  -o "$RESOURCE_ROOT/licenses/R4-F16-MIT-LICENSE.txt"

# Generate a deterministic terrain albedo directly into the app bundle. It is
# intentionally low-frequency and earthy: RealityKit supplies lighting while
# the material's very high roughness prevents the old plastic/shiny terrain.
python3 - "$APP_PATH/terrain_albedo.png" <<'PY'
from pathlib import Path
import math
import random
import struct
import sys
import zlib

out = Path(sys.argv[1])
w = h = 256
rng = random.Random(90421)
rows = []
for y in range(h):
    row = bytearray([0])
    for x in range(w):
        n = (
            0.46
            + 0.15 * math.sin(x / 17.0 + math.sin(y / 43.0) * 1.4)
            + 0.11 * math.cos((x + y) / 29.0)
            + 0.08 * math.sin((x * 0.72 - y) / 13.0)
            + 0.05 * math.cos(y / 8.5)
            + rng.uniform(-0.055, 0.055)
        )
        n = max(0.0, min(1.0, n))
        dry = max(0.0, min(1.0, (n - 0.52) / 0.48))
        soil = max(0.0, math.sin(x / 8.0 + y / 21.0) * math.cos(y / 15.0) - 0.55)
        dark = (48, 68, 35)
        green = (82, 104, 52)
        tan = (119, 108, 67)
        dirt = (91, 75, 52)
        rgb = []
        for i in range(3):
            base = dark[i] * (1 - n) + green[i] * n
            base = base * (1 - dry * 0.55) + tan[i] * (dry * 0.55)
            base = base * (1 - soil * 0.28) + dirt[i] * (soil * 0.28)
            rgb.append(max(0, min(255, int(base))))
        row.extend(rgb)
    rows.append(bytes(row))
raw = b''.join(rows)

def chunk(kind, payload):
    return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload) & 0xffffffff)

png = b'\x89PNG\r\n\x1a\n'
png += chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(raw, 9))
png += chunk(b'IEND', b'')
out.write_bytes(png)
PY

for required in \
  "$RESOURCE_ROOT/aircraft/f16/f16.xml" \
  "$RESOURCE_ROOT/engine/F100-PW-229.xml" \
  "$RESOURCE_ROOT/engine/direct.xml" \
  "$MODEL_ROOT/f16.obj" \
  "$APP_PATH/terrain_albedo.png"; do
  test -s "$required"
done

grep -q '^o f16' "$MODEL_ROOT/f16.obj"
grep -q '^f ' "$MODEL_ROOT/f16.obj"

echo "Staged JSBSim F-16, stable yaw control law, terrain texture and pinned F-16 render mesh"
