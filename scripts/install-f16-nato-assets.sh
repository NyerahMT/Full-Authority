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

python3 - "$DEST" "$ROOT/App/PrototypeSceneView.swift" "$ROOT/Aircraft/PrototypeAircraftFactory.swift" <<'PY'
import hashlib
import json
import math
import pathlib
import struct
import sys

root = pathlib.Path(sys.argv[1])
scene_path = pathlib.Path(sys.argv[2])
aircraft_path = pathlib.Path(sys.argv[3])

# Validate the untouched runtime assets first.
for path in root.glob('*.famesh'):
    data = path.read_bytes()
    if len(data) < 12 or data[:4] != b'FAM2':
        raise SystemExit(f"{path.name}: invalid FAM2 header")
    vertices, indices = struct.unpack_from('<II', data, 4)
    expected = 12 + vertices * (3 + 3 + 3 + 2) * 4 + indices * 4
    if indices % 3 or len(data) != expected:
        raise SystemExit(f"{path.name}: invalid FAM2 payload")

# Smooth only duplicated-position body normals. Geometry, UVs and topology stay
# byte-identical to the known-good runtime archive.
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
            clusters.append({'members': [vertex_index], 'sum': [normal[0], normal[1], normal[2]]})

    for cluster in clusters:
        if len(cluster['members']) < 2:
            continue
        normal = unit(cluster['sum'])
        for vertex_index in cluster['members']:
            smoothed[vertex_index] = normal
            changed += 1

for index, normal in enumerate(smoothed):
    struct.pack_into('<fff', data, normals_offset + index * 12, *normal)
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
    struct.pack_into('<fff', data, tangents_offset + index * 12, tx / length, ty / length, tz / length)

if bytes(data[positions_offset:normals_offset]) != original_positions:
    raise SystemExit('F-16 smoothing unexpectedly changed vertex positions')
if bytes(data[indices_offset:]) != original_indices:
    raise SystemExit('F-16 smoothing unexpectedly changed triangle indices')
body.write_bytes(data)

manifest_path = root / 'manifest.json'
manifest = json.loads(manifest_path.read_text())
manifest['meshes']['body']['sha256'] = hashlib.sha256(data).hexdigest()
manifest['runtimePostprocess'] = {
    'smoothBodyNormals': True,
    'creaseAngleDegrees': 38.0,
    'positionsAndIndicesPreserved': True,
}
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')

# Lower the actual RealityKit cockpit eyepoint.
scene = scene_path.read_text()
scene = scene.replace('localCameraOffset = [0, 1.08, 3.05]', 'localCameraOffset = [0, 0.88, 3.05]')
scene = scene.replace('localLookPoint = [0, 1.08, 90]', 'localLookPoint = [0, 0.88, 90]')
if 'localCameraOffset = [0, 0.88, 3.05]' not in scene:
    raise SystemExit('Could not apply stage026 cockpit camera height patch')

# Replace the old opaque cone/cylinder exhaust animation with a restrained
# translucent plume. There are deliberately no capped cylinders, so the camera
# can never see the orange "washer" shock cells from the previous version.
update_start = scene.index('    @MainActor\n    private func updateAfterburner')
update_end = scene.index('    @MainActor\n    private func updateGear', update_start)
new_update = r'''    @MainActor
    private func updateAfterburner(_ aircraft: Entity, state: AircraftState) {
        let n2 = clamp((state.engineN2Percent - 96.0) / 4.0, 0, 1)
        let fuel = clamp((state.engineFuelFlowPoundsPerSecond - 0.30) / 1.30, 0, 1)
        let intensity = state.afterburnerActive ? clamp(0.48 + 0.40 * n2 + 0.12 * fuel, 0, 1) : 0
        let time = Float(simulation.simulationTime)

        let pressureExpansion = clamp(sqrtf(2_116.22 / max(state.ambientPressurePSF, 450)), 0.92, 1.45)
        let speedCompression = clamp(1.0 - 0.055 * state.mach, 0.89, 1.0)
        let plumeVisible = intensity > 0.01

        if let plume = aircraft.findEntity(named: PrototypeAircraftFactory.afterburnerName) {
            plume.isEnabled = plumeVisible
        }

        if plumeVisible {
            let fast = sin(time * 51.0)
            let mid = sin(time * 21.0 + 1.1)
            let turbulence = 1.0 + 0.010 * fast + 0.008 * mid
            let width = (0.92 + 0.08 * intensity) * turbulence
            let length = (0.90 + 0.38 * intensity) * pressureExpansion * speedCompression

            func shape(_ name: String, radius: Float, meters: Float, opacity: Float) {
                guard let entity = aircraft.findEntity(named: name) else { return }
                entity.scale = [radius * width, meters * length, radius * width]
                entity.components.set(OpacityComponent(opacity: opacity))
            }

            // Blue-violet low-opacity sheath, pale inner plume, hot compact core.
            // No solid orange geometry and no cross-sectional shock discs.
            shape(PrototypeAircraftFactory.afterburnerHaloName, radius: 0.43, meters: 2.85, opacity: 0.44)
            shape(PrototypeAircraftFactory.afterburnerOuterName, radius: 0.31, meters: 2.45, opacity: 0.62)
            shape(PrototypeAircraftFactory.afterburnerInnerName, radius: 0.20, meters: 1.90, opacity: 0.78)
            shape(PrototypeAircraftFactory.afterburnerCoreName, radius: 0.095, meters: 1.28, opacity: 0.94)
        }

        if let glow = aircraft.findEntity(named: PrototypeAircraftFactory.nozzleGlowName) {
            let dryHeat = clamp((state.engineN2Percent - 80) / 20, 0, 1)
            let hot = max(dryHeat * 0.22, intensity)
            glow.isEnabled = hot > 0.03
            if glow.isEnabled {
                let flicker = 1.0 + 0.010 * sin(time * 57.0)
                glow.scale = [0.36 + 0.04 * hot, 0.10 * flicker, 0.36 + 0.04 * hot]
                glow.components.set(OpacityComponent(opacity: 0.35 + 0.45 * hot))
            }
        }
    }

'''
scene = scene[:update_start] + new_update + scene[update_end:]
scene_path.write_text(scene)

# Replace the actual Stage 026 procedural exhaust constructor. The new geometry
# uses open frusta only: no end caps, no cylinders, and therefore no visible
# orange discs from side/rear views.
aircraft = aircraft_path.read_text()
constructor_start = aircraft.index('    private static func addAfterburner(to root: Entity)')
constructor_end = aircraft.index('    // MARK: - Functional landing gear', constructor_start)
new_constructor = r'''    private static func addAfterburner(to root: Entity) {
        let plume = Entity()
        plume.name = afterburnerName
        plume.position = [0, 0, -7.20]
        plume.isEnabled = false

        let aft = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))

        func openFrustum(endRadius: Float, segments: Int = 28) -> MeshResource {
            let count = max(12, segments)
            var positions: [SIMD3<Float>] = []
            var indices: [UInt32] = []
            positions.reserveCapacity(count * 2)
            indices.reserveCapacity(count * 6)

            for i in 0..<count {
                let angle = Float(i) / Float(count) * 2 * Float.pi
                let x = cos(angle)
                let z = sin(angle)
                positions.append([x, 0, z])
                positions.append([x * endRadius, 1, z * endRadius])
            }

            for i in 0..<count {
                let next = (i + 1) % count
                let a = UInt32(i * 2)
                let b = UInt32(next * 2)
                let c = UInt32(i * 2 + 1)
                let d = UInt32(next * 2 + 1)
                indices.append(contentsOf: [a, b, d, a, d, c])
            }

            var descriptor = MeshDescriptor(name: "Full Authority open exhaust frustum")
            descriptor.positions = MeshBuffers.Positions(positions)
            descriptor.primitives = .triangles(indices)
            descriptor.materials = .allFaces(0)
            return try! MeshResource.generate(from: [descriptor])
        }

        func exhaustMaterial(
            _ color: UIColor,
            opacity: Float
        ) -> UnlitMaterial {
            var material = UnlitMaterial(color: color, applyPostProcessToneMap: true)
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
            material.faceCulling = .none
            material.readsDepth = true
            material.writesDepth = false
            return material
        }

        func shell(
            name: String,
            endRadius: Float,
            color: UIColor,
            opacity: Float
        ) -> ModelEntity {
            let entity = ModelEntity(
                mesh: openFrustum(endRadius: endRadius),
                materials: [exhaustMaterial(color, opacity: opacity)]
            )
            entity.name = name
            entity.orientation = aft
            entity.components.set(OpacityComponent(opacity: 1.0))
            return entity
        }

        plume.addChild(shell(
            name: afterburnerHaloName,
            endRadius: 0.34,
            color: UIColor(red: 0.22, green: 0.42, blue: 1.00, alpha: 1),
            opacity: 0.08
        ))
        plume.addChild(shell(
            name: afterburnerOuterName,
            endRadius: 0.22,
            color: UIColor(red: 0.46, green: 0.68, blue: 1.00, alpha: 1),
            opacity: 0.11
        ))
        plume.addChild(shell(
            name: afterburnerInnerName,
            endRadius: 0.12,
            color: UIColor(red: 1.00, green: 0.79, blue: 0.48, alpha: 1),
            opacity: 0.17
        ))
        plume.addChild(shell(
            name: afterburnerCoreName,
            endRadius: 0.045,
            color: UIColor(red: 1.00, green: 0.96, blue: 0.84, alpha: 1),
            opacity: 0.26
        ))
        root.addChild(plume)

        let glow = shell(
            name: nozzleGlowName,
            endRadius: 0.74,
            color: UIColor(red: 1.00, green: 0.58, blue: 0.22, alpha: 1),
            opacity: 0.18
        )
        glow.position = [0, 0, -7.18]
        glow.scale = [0.36, 0.10, 0.36]
        glow.isEnabled = false
        root.addChild(glow)
    }

'''
aircraft = aircraft[:constructor_start] + new_constructor + aircraft[constructor_end:]
aircraft_path.write_text(aircraft)

print(f'NATO F-16 runtime assets installed and validated; smoothed {changed} body normal entries.')
print('Stage026 cockpit camera lowered from 1.08 m to 0.88 m.')
print('Stage026 exhaust rebuilt with translucent open-frustum shells; old shock-disc geometry removed.')
PY
