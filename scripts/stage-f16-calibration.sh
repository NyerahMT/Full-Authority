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
[[ -f "$SOURCE_ROOT/aircraft/f16/f16.xml" ]] || { echo "JSBSim F-16 source is missing" >&2; exit 1; }
[[ -f "$SOURCE_ROOT/engine/F100-PW-229.xml" ]] || { echo "JSBSim F100 engine source is missing" >&2; exit 1; }
[[ -f "$SOURCE_ROOT/engine/direct.xml" ]] || { echo "JSBSim direct thruster source is missing" >&2; exit 1; }

rm -rf "$RESOURCE_ROOT/aircraft/f16"
mkdir -p "$RESOURCE_ROOT/aircraft" "$RESOURCE_ROOT/engine" "$RESOURCE_ROOT/licenses"

# Preserve the complete upstream aircraft directory. This deliberately restores
# the stock JSBSim F-16 yaw-rate / lateral-load controller. Full Authority does
# not replace that stability logic anymore.
cp -R "$SOURCE_ROOT/aircraft/f16" "$RESOURCE_ROOT/aircraft/f16"
cp "$SOURCE_ROOT/engine/F100-PW-229.xml" "$RESOURCE_ROOT/engine/F100-PW-229.xml"
cp "$SOURCE_ROOT/engine/direct.xml" "$RESOURCE_ROOT/engine/direct.xml"
cp "$SOURCE_ROOT/COPYING" "$RESOURCE_ROOT/licenses/JSBSim-COPYING.txt"

# Keep the upstream yaw controller intact and add only a small feed-forward term
# in the final rudder scheduler. The stock yaw PID still owns yaw-rate and
# lateral-load damping; this adds 28% of pedal command after that loop so touch
# input has meaningfully more authority without creating another feedback system.
python3 - "$RESOURCE_ROOT/aircraft/f16/f16.xml" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
needle = '''   <summer name="fcs/yaw-scheduler">\n     <input>fcs/rudder-cmd-norm</input>'''
replacement = '''   <!-- Full Authority: stock JSBSim yaw controller + stronger pedal feed-forward. -->\n   <pure_gain name="fcs/fa-pedal-feedforward">\n    <input>fcs/rudder-cmd-norm</input>\n    <gain>0.28</gain>\n   </pure_gain>\n\n   <summer name="fcs/yaw-scheduler">\n     <input>fcs/rudder-cmd-norm</input>\n     <input>fcs/fa-pedal-feedforward</input>'''
if text.count(needle) != 1:
    raise SystemExit(f"expected one upstream F-16 yaw scheduler, found {text.count(needle)}")
text = text.replace(needle, replacement, 1)
path.write_text(text, encoding="utf-8")
PY

grep -q 'stock JSBSim yaw controller + stronger pedal feed-forward' "$RESOURCE_ROOT/aircraft/f16/f16.xml"
grep -q '<pid name="fcs/yaw-load-pid">' "$RESOURCE_ROOT/aircraft/f16/f16.xml"
grep -q '<gain>0.28</gain>' "$RESOURCE_ROOT/aircraft/f16/f16.xml"

# Render art is now bundled from the authored, MIT-licensed vazgriz/FlightSim_F16
# import under JSBSim/visuals/f16. Do not download or stage the retired R4 OBJ here.

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
  "$APP_PATH/terrain_albedo.png"; do
  test -s "$required"
done

echo "Staged JSBSim F-16 calibration data, yaw damping, pedal feed-forward and terrain texture"
