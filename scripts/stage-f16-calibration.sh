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

# Stage 020 yaw-control correction.
#
# The upstream XML feeds rudder-cmd-norm into the yaw feedback error and then
# adds the same pilot command again in yaw-scheduler. Our older patch compounded
# that with another 28% feed-forward. Stage 020 removes that extra feed-forward
# and separates the pilot pedal from SAS feedback. Yaw-rate/lateral-acceleration
# feedback damps the aircraft; the pilot command enters the scheduler once.
python3 - "$RESOURCE_ROOT/aircraft/f16/f16.xml" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old_error = '''   <!--
     - Calculate the difference between the current yaw-rate
     - and the one requiested for.
     -->
   <summer name="fcs/yaw-trim-error">
    <input>fcs/rudder-cmd-norm</input>
    <input>fcs/yaw-rate-norm</input>
    <input>fcs/yaw-load-norm</input>
   </summer>'''
new_error = '''   <!-- Full Authority Stage 020: SAS feedback only. Pilot pedal
     command is summed once in yaw-scheduler below. -->
   <summer name="fcs/yaw-trim-error">
    <input>fcs/yaw-rate-norm</input>
    <input>fcs/yaw-load-norm</input>
   </summer>'''
if text.count(old_error) != 1:
    raise SystemExit(f"expected one upstream yaw feedback block, found {text.count(old_error)}")
text = text.replace(old_error, new_error, 1)
old_rate = '''      80.0  0.0
      100.0    15.0
      150.0    100.0'''
new_rate = '''      80.0  0.0
      100.0    15.0
      150.0    112.0'''
if text.count(old_rate) != 1:
    raise SystemExit(f"expected one yaw-rate schedule, found {text.count(old_rate)}")
text = text.replace(old_rate, new_rate, 1)
scheduler = '''   <summer name="fcs/yaw-scheduler">
     <input>fcs/rudder-cmd-norm</input>
     <input>fcs/yaw-trim-cmd-norm</input>
     <input>fcs/yaw-load-pid</input>'''
if text.count(scheduler) != 1:
    raise SystemExit(f"expected one direct pilot yaw scheduler, found {text.count(scheduler)}")
path.write_text(text, encoding="utf-8")
PY

grep -q 'Full Authority Stage 020: SAS feedback only' "$RESOURCE_ROOT/aircraft/f16/f16.xml"
grep -q '150.0    112.0' "$RESOURCE_ROOT/aircraft/f16/f16.xml"
test "$(grep -c '<input>fcs/rudder-cmd-norm</input>' "$RESOURCE_ROOT/aircraft/f16/f16.xml")" -eq 1
grep -q '<pid name="fcs/yaw-load-pid">' "$RESOURCE_ROOT/aircraft/f16/f16.xml"

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

echo "Staged JSBSim F-16 calibration data, Stage 020 yaw SAS correction and terrain texture"
