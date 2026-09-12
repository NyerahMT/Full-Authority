#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE="$ROOT/Assets/F16NATO/f16_nato_runtime_assets.zip"
DEST="$ROOT/Assets/JSBSim/visuals/f16_nato"
EXPECTED_SHA256="7d6a5af9854f39dceb1b3c041e60eeb48da4920b0f2ad96dabbf0aed097e843d"

if [[ ! -f "$ARCHIVE" ]]; then
  echo "Missing NATO F-16 runtime archive: $ARCHIVE" >&2
  echo "Upload the optimized runtime ZIP to Assets/F16NATO/f16_nato_runtime_assets.zip" >&2
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

python3 - "$DEST" "$ROOT/App/PrototypeSceneView.swift" <<'PY'
import hashlib
import json
import math
import pathlib
import struct
import sys

root = pathlib.Path(sys.argv[1])
scene_path = pathlib.Path(sys.argv[2])

# Validate the untouched runtime assets first.
for path in root.glob('*.famesh'):
    data = path.read_bytes()
    if len(data) < 12 or data[:4] != b'FAM2':
        raise SystemExit(f"{path.name}: invalid FAM2 header")
    vertices, indices = struct.unpack_from('<II', data, 4)
    expected = 12 + vertices * (3 + 3 + 3 + 2) * 4 + indices * 4
    if indices % 3 or len(data) != expected:
        raise SystemExit(f"{path.name}: invalid FAM2 payload")

# The source FBX carries effectively per-face normals across many duplicated
# vertices, which makes the 100k-triangle model read like a low-poly mesh in
# RealityKit. Smooth only vertices that occupy the exact same position and whose
# original normals are already within a conservative 38 degree crease angle.
# Positions, UVs, topology and triangle indices are never modified.
body = root / 'f16_nato_body.famesh'
data = bytearray(body.read_bytes())
vertex_count, index_count = struct.unpack_from('<II', data, 4)
positions_offset = 12
positions_bytes = vertex_count * 3 * 4
normals_offset = positions_offset + positions_bytes
normals_bytes = vertex_count * 3 * 4
tangents_offset = normals_offset + normals_bytes
tangents_bytes = vertex_count * 3 * 4
uv_offset = tangents_offset + tangents_bytes
uv_bytes = vertex_count * 2 * 4
indices_offset = uv_offset + uv_bytes

original_positions = bytes(data[positions_offset:normals_offset])
original_indices = bytes(data[indices_offset:])
positions = list(struct.iter_unpack('<fff', data[positions_offset:normals_offset]))
normals = [list(v) for v in struct.iter_unpack('<fff', data[normals_offset:tangents_offset])]
tangents = [list(v) for v in struct.iter_unpack('<fff', data[tangents_offset:uv_offset])]

def unit(v):
    length = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    if length < 1.0e-12:
        return (0.0, 1.0, 0.0)
    return (v[0] / length, v[1] / length, v[2] / length)

groups = {}
for index, position in enumerate(positions):
    groups.setdefault(position, []).append(index)

crease_cos = math.cos(math.radians(38.0))
smoothed = [unit(value) for value in normals]
changed = 0

for vertex_indices in groups.values():
    if len(vertex_indices) < 2:
        continue

    clusters = []
    for vertex_index in vertex_indices:
        normal = unit(normals[vertex_index])
        best_cluster = None
        best_dot = -2.0

        for cluster_index, cluster in enumerate(clusters):
            mean = unit(cluster['sum'])
            dot = normal[0] * mean[0] + normal[1] * mean[1] + normal[2] * mean[2]
            if dot > best_dot:
                best_dot = dot
                best_cluster = cluster_index

        if best_cluster is not None and best_dot >= crease_cos:
            cluster = clusters[best_cluster]
            cluster['members'].append(vertex_index)
            cluster['sum'][0] += normal[0]
            cluster['sum'][1] += normal[1]
            cluster['sum'][2] += normal[2]
        else:
            clusters.append({
                'members': [vertex_index],
                'sum': [normal[0], normal[1], normal[2]],
            })

    for cluster in clusters:
        if len(cluster['members']) < 2:
            continue
        normal = unit(cluster['sum'])
        for vertex_index in cluster['members']:
            smoothed[vertex_index] = normal
            changed += 1

for index, normal in enumerate(smoothed):
    struct.pack_into('<fff', data, normals_offset + index * 12, *normal)

    # Keep the authored tangent direction/UV seam behavior, but orthogonalize it
    # against the new normal so the existing normal map remains well behaved.
    tangent = tangents[index]
    dot = tangent[0] * normal[0] + tangent[1] * normal[1] + tangent[2] * normal[2]
    tx = tangent[0] - normal[0] * dot
    ty = tangent[1] - normal[1] * dot
    tz = tangent[2] - normal[2] * dot
    length = math.sqrt(tx * tx + ty * ty + tz * tz)

    if length < 1.0e-12:
        axis = (1.0, 0.0, 0.0) if abs(normal[0]) < 0.9 else (0.0, 1.0, 0.0)
        tx = axis[1] * normal[2] - axis[2] * normal[1]
        ty = axis[2] * normal[0] - axis[0] * normal[2]
        tz = axis[0] * normal[1] - axis[1] * normal[0]
        length = math.sqrt(tx * tx + ty * ty + tz * tz)

    struct.pack_into(
        '<fff',
        data,
        tangents_offset + index * 12,
        tx / length,
        ty / length,
        tz / length,
    )

# Safety assertions: smoothing is allowed to touch only normals and tangents.
if bytes(data[positions_offset:normals_offset]) != original_positions:
    raise SystemExit('F-16 smoothing unexpectedly changed vertex positions')
if bytes(data[indices_offset:]) != original_indices:
    raise SystemExit('F-16 smoothing unexpectedly changed triangle indices')

body.write_bytes(data)

# Keep the packaged manifest truthful after deterministic post-processing.
manifest_path = root / 'manifest.json'
manifest = json.loads(manifest_path.read_text())
manifest['meshes']['body']['sha256'] = hashlib.sha256(data).hexdigest()
manifest['runtimePostprocess'] = {
    'smoothBodyNormals': True,
    'creaseAngleDegrees': 38.0,
    'positionsAndIndicesPreserved': True,
}
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')

# Stage 026 still keeps the camera values in PrototypeSceneView. Apply the actual
# cockpit eyepoint change during asset preparation so this test build lowers the
# pilot view without touching JSBSim's unrelated EYEPOINT metric.
scene = scene_path.read_text()
scene = scene.replace(
    'localCameraOffset = [0, 1.08, 3.05]',
    'localCameraOffset = [0, 0.88, 3.05]',
)
scene = scene.replace(
    'localLookPoint = [0, 1.08, 90]',
    'localLookPoint = [0, 0.88, 90]',
)
if 'localCameraOffset = [0, 0.88, 3.05]' not in scene:
    raise SystemExit('Could not apply stage026 cockpit camera height patch')
scene_path.write_text(scene)

print(f'NATO F-16 runtime assets installed and validated; smoothed {changed} body normal entries.')
print('Stage026 cockpit camera lowered from 1.08 m to 0.88 m.')
PY
