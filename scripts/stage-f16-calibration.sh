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

# Preserve the complete upstream aircraft directory. Full Authority keeps the
# published JSBSim F-16 aerodynamic model and only corrects the directional
# control-law plumbing around pilot pedal authority and stability augmentation.
cp -R "$SOURCE_ROOT/aircraft/f16" "$RESOURCE_ROOT/aircraft/f16"
cp "$SOURCE_ROOT/engine/F100-PW-229.xml" "$RESOURCE_ROOT/engine/F100-PW-229.xml"
cp "$SOURCE_ROOT/engine/direct.xml" "$RESOURCE_ROOT/engine/direct.xml"
cp "$SOURCE_ROOT/COPYING" "$RESOURCE_ROOT/licenses/JSBSim-COPYING.txt"

# Stage 021 directional-control correction.
#
# NASA F-16 control-law documentation describes an air-data scheduled rudder-
# pedal forward path that reduces sensitivity in high dynamic pressure, plus
# yaw-rate/lateral-acceleration feedback for directional damping/coordination.
# JSBSim's stock F-16 yaw loop severely suppresses deliberate pedal commands in
# our dynamic test (70% pedal at 300 KCAS produced only ~4 degrees rudder).
#
# Full Authority therefore keeps the stock/strengthened SAS when the pedals are
# centered, but deliberately displaced pedals use an air-data-scheduled forward
# path. Releasing the pedal immediately hands control back to the SAS.
#
# The upstream model also binds BOTH yaw-load-pid and rudder-position to the
# physical fcs/rudder-pos-norm property. FGKinemat reads its current output at
# the beginning of every frame, so the PID overwrites actuator history before
# the kinematic can accumulate its 0.4-second travel. That creates a hard
# one-frame rudder ceiling. Stage 021 keeps the PID on its own component property
# and gives physical rudder position exclusively to the actuator kinematic.
python3 - "$RESOURCE_ROOT/aircraft/f16/f16.xml" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

# Modestly stronger feet-off-pedals yaw-rate normalization than upstream.
old_rate = '''      80.0  0.0
      100.0    15.0
      150.0    100.0'''
new_rate = '''      80.0  0.0
      100.0    15.0
      150.0    125.0'''
if text.count(old_rate) != 1:
    raise SystemExit(f"expected one yaw-rate schedule, found {text.count(old_rate)}")
text = text.replace(old_rate, new_rate, 1)

# JSBSim FCS components automatically publish their component name as an output.
# The explicit rudder-pos-norm output on yaw-load-pid is therefore unnecessary
# and, because the downstream FGKinemat uses that same property as actuator
# history, actively breaks rudder travel. Remove only that exact PID side effect.
old_pid = '''   <pid name="fcs/yaw-load-pid">
     <trigger>fcs/rudder-pid-trigger</trigger>
     <input>fcs/yaw-trim-error</input>
     <kp> 0.105500 </kp>
     <ki> 0.000010 </ki>
     <kd> 0.00005 </kd>
     <clipto>
    <min>-1</min>
    <max>1</max>
     </clipto>
     <output>fcs/rudder-pos-norm</output>
   </pid>'''
new_pid = '''   <!-- Full Authority Stage 021: PID output remains fcs/yaw-load-pid.
        Do not bind it to physical rudder position; the actuator kinematic owns
        fcs/rudder-pos-norm so its rate-limited state persists frame to frame. -->
   <pid name="fcs/yaw-load-pid">
     <trigger>fcs/rudder-pid-trigger</trigger>
     <input>fcs/yaw-trim-error</input>
     <kp> 0.105500 </kp>
     <ki> 0.000010 </ki>
     <kd> 0.00005 </kd>
     <clipto>
    <min>-1</min>
    <max>1</max>
     </clipto>
   </pid>'''
if text.count(old_pid) != 1:
    raise SystemExit(f"expected one upstream yaw PID block, found {text.count(old_pid)}")
text = text.replace(old_pid, new_pid, 1)

start = text.index('   <summer name="fcs/yaw-scheduler">')
end = text.index('   <kinematic name="fcs/rudder-position">', start)
old_scheduler_region = text[start:end]
if old_scheduler_region.count('<summer name="fcs/yaw-scheduler">') != 1:
    raise SystemExit('unexpected yaw scheduler region')

new_scheduler_region = '''   <!-- Full Authority Stage 021: centered-pedal SAS branch. -->
   <summer name="fcs/fa-yaw-sas">
     <input>fcs/rudder-cmd-norm</input>
     <input>fcs/yaw-trim-cmd-norm</input>
     <input>fcs/yaw-load-pid</input>
     <clipto>
      <min>-1</min>
      <max>1</max>
     </clipto>
   </summer>

   <!-- Rudder-pedal forward-loop authority scheduled by dynamic pressure.
        Low-q flight retains nearly full available rudder; high-q flight reduces
        pedal sensitivity to avoid an unrealistic full-tail-load command. -->
   <scheduled_gain name="fcs/fa-pedal-rudder">
    <input>fcs/rudder-cmd-norm</input>
    <table>
     <independentVar>aero/qbar-psf</independentVar>
     <tableData>
         0.0   1.00
        50.0   0.95
       100.0   0.80
       200.0   0.55
       350.0   0.38
       600.0   0.24
      1000.0   0.16
     </tableData>
    </table>
   </scheduled_gain>

   <switch name="fcs/yaw-scheduler">
    <default value="fcs/fa-yaw-sas"/>
    <test logic="OR" value="fcs/fa-pedal-rudder">
     fcs/rudder-cmd-norm gt 0.035
     fcs/rudder-cmd-norm lt -0.035
    </test>
    <clipto>
     <min>-1</min>
     <max>1</max>
    </clipto>
   </switch>

'''
text = text[:start] + new_scheduler_region + text[end:]
path.write_text(text, encoding="utf-8")
PY

grep -q '150.0    125.0' "$RESOURCE_ROOT/aircraft/f16/f16.xml"
grep -q 'Full Authority Stage 021: PID output remains fcs/yaw-load-pid' "$RESOURCE_ROOT/aircraft/f16/f16.xml"
grep -q 'Full Authority Stage 021: centered-pedal SAS branch' "$RESOURCE_ROOT/aircraft/f16/f16.xml"
grep -q '<scheduled_gain name="fcs/fa-pedal-rudder">' "$RESOURCE_ROOT/aircraft/f16/f16.xml"
grep -q '<independentVar>aero/qbar-psf</independentVar>' "$RESOURCE_ROOT/aircraft/f16/f16.xml"
grep -q 'fcs/rudder-cmd-norm gt 0.035' "$RESOURCE_ROOT/aircraft/f16/f16.xml"
grep -q '<pid name="fcs/yaw-load-pid">' "$RESOURCE_ROOT/aircraft/f16/f16.xml"
# The actuator kinematic must be the only component explicitly writing physical
# normalized rudder position. This guards against the one-frame ceiling regressing.
test "$(grep -c '<output>fcs/rudder-pos-norm</output>' "$RESOURCE_ROOT/aircraft/f16/f16.xml")" -eq 1

# Render art is bundled from the authored, MIT-licensed vazgriz/FlightSim_F16
# import under JSBSim/visuals/f16. Do not download or stage the retired R4 OBJ here.

# Generate a deterministic terrain albedo directly into the app bundle. It is
# intentionally low-frequency and earthy: RealityKit supplies lighting while
# the material's very high roughness prevents plastic/shiny terrain.
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

echo "Staged JSBSim F-16 calibration data, Stage 021 persistent-state rudder actuator, air-data-scheduled pedal authority and terrain texture"
