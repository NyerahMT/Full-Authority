#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE="$ROOT/Assets/F16NATO/f16_nato_runtime_assets.zip"
DEST="$ROOT/Assets/JSBSim/visuals/f16_nato"
# Temporary compile-validation fixture on stage026. Replace with the real runtime
# archive hash before merging this branch.
EXPECTED_SHA256="ac46045b227c40d4062469bb10085f583f0d00a97ed8bb54f27203cd3375500a"

if [[ ! -f "$ARCHIVE" ]]; then
  echo "Missing NATO F-16 runtime archive: $ARCHIVE" >&2
  exit 1
fi

ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  echo "NATO F-16 archive hash mismatch." >&2
  echo "expected: $EXPECTED_SHA256" >&2
  echo "actual:   $ACTUAL_SHA256" >&2
  exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST"
unzip -q "$ARCHIVE" -d "$DEST"

required=(
  f16_nato_body.famesh
  f16_nato_canopy.famesh
  f16_nato_cockpit.famesh
  f16_nato_stabilator_left.famesh
  f16_nato_stabilator_right.famesh
  f16_nato_body_basecolor.png
  f16_nato_body_roughness.png
  f16_nato_body_metallic.png
  f16_nato_body_normal.png
  f16_nato_body_alpha.png
  f16_nato_cockpit_basecolor.png
  f16_nato_cockpit_roughness.png
  f16_nato_cockpit_metallic.png
  f16_nato_cockpit_normal.png
  f16_nato_cockpit_emission.png
  f16_nato_cockpit_alpha.png
  manifest.json
  ATTRIBUTION.md
)

for file in "${required[@]}"; do
  test -s "$DEST/$file" || {
    echo "NATO F-16 runtime archive is missing $file" >&2
    exit 1
  }
done

python3 - "$DEST" <<'PY'
import pathlib, struct, sys
root = pathlib.Path(sys.argv[1])
for path in root.glob('*.famesh'):
    data = path.read_bytes()
    if len(data) < 12 or data[:4] != b'FAM2':
        raise SystemExit(f"{path.name}: invalid FAM2 header")
    vertices, indices = struct.unpack_from('<II', data, 4)
    expected = 12 + vertices * (3 + 3 + 3 + 2) * 4 + indices * 4
    if indices % 3 or len(data) != expected:
        raise SystemExit(f"{path.name}: invalid FAM2 payload")
print('NATO F-16 runtime assets installed and validated.')
PY
