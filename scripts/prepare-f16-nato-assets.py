#!/usr/bin/env python3
import base64
import gzip
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

if len(sys.argv) != 3:
    raise SystemExit("usage: prepare-f16-nato-assets.py <repo-root> <asset-dest>")

repo = Path(sys.argv[1])
root = Path(sys.argv[2])
scene_path = repo / "App/PrototypeSceneView.swift"
aircraft_path = repo / "Aircraft/PrototypeAircraftFactory.swift"
payload_root = repo / "Assets/F16NATO"

IMPORTED_MESH_SHA256 = "d48e810b5c0d81f0f1c61ab8c86951b7f04d227e944953a61003ed30a94ebe41"
IMPORTED_TEXTURE_SHA256 = "7ad561e948d9143bffd7e9153b2965b30975eb471b2b7c6a8710bc18c85b715a"
IMPORTED_MESH_GZIP_SHA256 = "0ddf4315fd473b8d23821aa1dc9d66b45ad82bca8c4f79a65888ee5b3dadaaff"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def decode_imported_afterburner() -> None:
    encoded_mesh = (payload_root / "imported_afterburner.famesh.gz.b64").read_text().strip()
    compressed_mesh = base64.b64decode(encoded_mesh, validate=True)
    if sha256(compressed_mesh) != IMPORTED_MESH_GZIP_SHA256:
        raise SystemExit("Imported afterburner compressed mesh hash mismatch")
    mesh = gzip.decompress(compressed_mesh)
    if sha256(mesh) != IMPORTED_MESH_SHA256:
        raise SystemExit("Imported afterburner mesh hash mismatch")

    encoded_texture = (payload_root / "imported_afterburner.png.b64").read_text().strip()
    texture = base64.b64decode(encoded_texture, validate=True)
    if sha256(texture) != IMPORTED_TEXTURE_SHA256:
        raise SystemExit("Imported afterburner texture hash mismatch")

    (root / "f16_afterburner_imported.famesh").write_bytes(mesh)
    (root / "f16_afterburner_imported.png").write_bytes(texture)
    (root / "AFTERBURNER-LICENSE.txt").write_text(
        (payload_root / "AFTERBURNER-LICENSE.txt").read_text()
    )


def validate_fam2(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if len(data) < 12 or data[:4] != b"FAM2":
        raise SystemExit(f"{path.name}: invalid FAM2 header")
    vertices, indices = struct.unpack_from("<II", data, 4)
    expected = 12 + vertices * (3 + 3 + 3 + 2) * 4 + indices * 4
    if vertices <= 0 or indices < 3 or indices % 3 or len(data) != expected:
        raise SystemExit(f"{path.name}: invalid FAM2 payload")
    return vertices, indices


def smooth_body_normals() -> int:
    body = root / "f16_nato_body.famesh"
    data = bytearray(body.read_bytes())
    vertex_count, _ = validate_fam2(body)

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
    positions = list(struct.iter_unpack("<fff", data[positions_offset:normals_offset]))
    normals = [list(v) for v in struct.iter_unpack("<fff", data[normals_offset:tangents_offset])]
    tangents = [list(v) for v in struct.iter_unpack("<fff", data[tangents_offset:uv_offset])]

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
                mean = unit(cluster["sum"])
                dot = sum(normal[i] * mean[i] for i in range(3))
                if dot > best_dot:
                    best_dot = dot
                    best_cluster = cluster_index
            if best_cluster is not None and best_dot >= crease_cos:
                cluster = clusters[best_cluster]
                cluster["members"].append(vertex_index)
                for i in range(3):
                    cluster["sum"][i] += normal[i]
            else:
                clusters.append({"members": [vertex_index], "sum": list(normal)})

        for cluster in clusters:
            if len(cluster["members"]) < 2:
                continue
            normal = unit(cluster["sum"])
            for vertex_index in cluster["members"]:
                smoothed[vertex_index] = normal
                changed += 1

    for index, normal in enumerate(smoothed):
        struct.pack_into("<fff", data, normals_offset + index * 12, *normal)
        tangent = tangents[index]
        dot = sum(tangent[i] * normal[i] for i in range(3))
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
            "<fff",
            data,
            tangents_offset + index * 12,
            tx / length,
            ty / length,
            tz / length,
        )

    if bytes(data[positions_offset:normals_offset]) != original_positions:
        raise SystemExit("F-16 smoothing unexpectedly changed vertex positions")
    if bytes(data[indices_offset:]) != original_indices:
        raise SystemExit("F-16 smoothing unexpectedly changed triangle indices")

    body.write_bytes(data)
    manifest_path = root / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    manifest["meshes"]["body"]["sha256"] = sha256(data)
    manifest["runtimePostprocess"] = {
        "smoothBodyNormals": True,
        "creaseAngleDegrees": 38.0,
        "positionsAndIndicesPreserved": True,
        "importedAfterburner": {
            "source": "vazgriz/FlightSim_F16",
            "sourceCommit": "df9a4162f0afbdae92bf386ed9503737e0edbecd",
            "runtimeMeshSha256": IMPORTED_MESH_SHA256,
            "textureSha256": IMPORTED_TEXTURE_SHA256,
            "license": "MIT",
        },
    }
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    return changed


def patch_cockpit_camera() -> None:
    scene = scene_path.read_text()
    scene = scene.replace(
        "localCameraOffset = [0, 1.08, 3.05]",
        "localCameraOffset = [0, 0.88, 3.05]",
    )
    scene = scene.replace(
        "localLookPoint = [0, 1.08, 90]",
        "localLookPoint = [0, 0.88, 90]",
    )
    if "localCameraOffset = [0, 0.88, 3.05]" not in scene:
        raise SystemExit("Could not apply Stage 026 cockpit camera height")
    scene_path.write_text(scene)


def patch_imported_afterburner() -> None:
    aircraft = aircraft_path.read_text()

    load_anchor = '            let rightTailMesh = try loadFAMesh("f16_nato_stabilator_right")\n'
    load_replacement = load_anchor + (
        '            let afterburnerMesh = try loadFAMesh("f16_afterburner_imported")\n'
        '            let afterburnerTexture = try texture("f16_afterburner_imported")\n'
    )
    if 'let afterburnerMesh = try loadFAMesh("f16_afterburner_imported")' not in aircraft:
        if load_anchor not in aircraft:
            raise SystemExit("Could not find F-16 mesh-loading anchor")
        aircraft = aircraft.replace(load_anchor, load_replacement, 1)

    old_call = "            addAfterburner(to: visualRoot)"
    new_call = "            addAfterburner(to: visualRoot, mesh: afterburnerMesh, texture: afterburnerTexture)"
    if new_call not in aircraft:
        if old_call not in aircraft:
            raise SystemExit("Could not find Stage 026 afterburner call")
        aircraft = aircraft.replace(old_call, new_call, 1)

    constructor_start = aircraft.index("    private static func addAfterburner(to root: Entity)")
    constructor_end = aircraft.index("    // MARK: - Functional landing gear", constructor_start)
    new_constructor = r'''    private static func addAfterburner(
        to root: Entity,
        mesh: MeshResource,
        texture: TextureResource
    ) {
        // Authored afterburner imported from vazgriz/FlightSim_F16 (MIT),
        // rather than generated from primitive cones/cylinders. The converted
        // FAM2 preserves the upstream mesh's UV layout and its authored texture.
        let plume = Entity()
        plume.name = afterburnerName
        plume.position = [0, 0, -7.20]
        plume.isEnabled = false

        var material = UnlitMaterial(texture: texture)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.88))
        material.faceCulling = .none
        material.readsDepth = true
        material.writesDepth = false

        let flame = ModelEntity(mesh: mesh, materials: [material])
        flame.name = afterburnerCoreName
        plume.addChild(flame)
        root.addChild(plume)
    }

'''
    aircraft = aircraft[:constructor_start] + new_constructor + aircraft[constructor_end:]
    aircraft_path.write_text(aircraft)

    scene = scene_path.read_text()
    update_start = scene.index("    @MainActor\n    private func updateAfterburner")
    update_end = scene.index("    @MainActor\n    private func updateGear", update_start)
    new_update = r'''    @MainActor
    private func updateAfterburner(_ aircraft: Entity, state: AircraftState) {
        let n2 = clamp((state.engineN2Percent - 96.0) / 4.0, 0, 1)
        let fuel = clamp((state.engineFuelFlowPoundsPerSecond - 0.30) / 1.30, 0, 1)
        let intensity = state.afterburnerActive ? clamp(0.48 + 0.40 * n2 + 0.12 * fuel, 0, 1) : 0
        let time = Float(simulation.simulationTime)

        let pressureExpansion = clamp(sqrtf(2_116.22 / max(state.ambientPressurePSF, 450)), 0.92, 1.42)
        let speedCompression = clamp(1.0 - 0.045 * state.mach, 0.90, 1.0)
        let visible = intensity > 0.01

        guard let plume = aircraft.findEntity(named: PrototypeAircraftFactory.afterburnerName) else {
            return
        }
        plume.isEnabled = visible
        guard visible else { return }

        // The imported mesh is authored at roughly 1 m diameter x 4 m long and
        // already points aft in Full Authority coordinates. Scale the real asset
        // instead of constructing synthetic flame layers.
        let flutter = 1.0
            + 0.010 * sin(time * 47.0)
            + 0.006 * sin(time * 19.0 + 1.4)
        let width = (0.82 + 0.12 * intensity) * flutter
        let length = (0.56 + 0.34 * intensity) * pressureExpansion * speedCompression
        plume.scale = [width, width, length]
    }

'''
    scene = scene[:update_start] + new_update + scene[update_end:]
    scene_path.write_text(scene)


decode_imported_afterburner()
for fam2 in root.glob("*.famesh"):
    validate_fam2(fam2)
changed = smooth_body_normals()
patch_cockpit_camera()
patch_imported_afterburner()

print(f"NATO F-16 assets validated; smoothed {changed} body normal entries.")
print("Installed imported MIT authored afterburner mesh + texture.")
print("Stage 026 cockpit camera: 0.88 m eyepoint height.")
