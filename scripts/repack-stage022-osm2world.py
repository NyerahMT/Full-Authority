#!/usr/bin/env python3
"""
Repack OSM2World zoom-15 GLB tiles into Full Authority Stage 022 chunks.

OSM2World remains the authoritative geometry generator. This script:
- reads available LOD2 / LOD4 GLB tiles;
- converts each tile from its glTF scene origin into Full Authority's runway-aligned
  local coordinates;
- drapes generated geometry over the exact Stage 022 Malta DEM/contact surface;
- collapses material textures to stable averaged PBR colors for a small first import;
- merges tiles into 4 km superchunks;
- quantizes positions/normals and writes compact RealityKit-friendly binary chunks.

The source GLBs are build intermediates and are not shipped in the app.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import struct
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable
from urllib.parse import unquote, urlparse

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
TERRAIN_INC = ROOT / "Simulation/Bridge/Stage022MaltaTerrain.inc"
OUT_ROOT = ROOT / "Assets/JSBSim/visuals/world/stage022"
OUT_MANIFEST = ROOT / "Docs/Stage022MaltaFullWorld.json"

ANCHOR_LAT = 35.8351666667
ANCHOR_LON = 14.5051666667
ANCHOR_HEADING_DEG = 312.0
MIN_X_M = -32_000.0
MAX_X_M = 32_000.0
MIN_Z_M = -16_000.0
MAX_Z_M = 48_000.0
SUPERCHUNK_M = 4_000.0

POS_SCALE_XZ = 0.25
POS_SCALE_Y = 0.10
MAX_PART_VERTICES = 60_000

COMPONENT_FORMATS = {
    5120: ("b", 1),
    5121: ("B", 1),
    5122: ("h", 2),
    5123: ("H", 2),
    5125: ("I", 4),
    5126: ("f", 4),
}
TYPE_COMPONENTS = {
    "SCALAR": 1,
    "VEC2": 2,
    "VEC3": 3,
    "VEC4": 4,
    "MAT2": 4,
    "MAT3": 9,
    "MAT4": 16,
}


@dataclass(frozen=True)
class MaterialKey:
    rgba: tuple[int, int, int, int]
    roughness: int
    metallic: int
    double_sided: bool


@dataclass
class Material:
    name: str
    rgba: tuple[float, float, float, float]
    roughness: float
    metallic: float
    double_sided: bool


@dataclass
class MeshAccum:
    material: Material
    positions: list[tuple[float, float, float]] = field(default_factory=list)
    normals: list[tuple[float, float, float]] = field(default_factory=list)
    indices: list[int] = field(default_factory=list)


@dataclass
class TerrainGrid:
    resolution_x: int
    resolution_z: int
    min_x: float
    max_x: float
    min_z: float
    max_z: float
    spacing: float
    sea_level: float
    values_dm: list[int]

    @classmethod
    def load(cls, path: Path) -> "TerrainGrid":
        text = path.read_text()

        def number(pattern: str) -> float:
            match = re.search(pattern, text)
            if not match:
                raise RuntimeError(f"Could not parse terrain constant: {pattern}")
            return float(match.group(1))

        resolution_x = int(number(r"kFAStage022TerrainResolutionX\s*=\s*(\d+)"))
        resolution_z = int(number(r"kFAStage022TerrainResolutionZ\s*=\s*(\d+)"))
        min_x = number(r"kFAStage022TerrainMinXMeters\s*=\s*([-+0-9.eE]+)")
        max_x = number(r"kFAStage022TerrainMaxXMeters\s*=\s*([-+0-9.eE]+)")
        min_z = number(r"kFAStage022TerrainMinZMeters\s*=\s*([-+0-9.eE]+)")
        max_z = number(r"kFAStage022TerrainMaxZMeters\s*=\s*([-+0-9.eE]+)")
        spacing = number(r"kFAStage022TerrainSpacingMeters\s*=\s*([-+0-9.eE]+)")
        sea_level = number(r"kFAStage022SeaLevelMeters\s*=\s*([-+0-9.eE]+)")
        array_match = re.search(
            r"kFAStage022TerrainDecimeters\[\]\s*=\s*\{(.*?)\};",
            text,
            re.S,
        )
        if not array_match:
            raise RuntimeError("Could not parse Stage 022 terrain array.")
        values = [int(v) for v in re.findall(r"-?\d+", array_match.group(1))]
        expected = resolution_x * resolution_z
        if len(values) != expected:
            raise RuntimeError(f"Terrain sample count {len(values)} != {expected}")
        return cls(
            resolution_x, resolution_z, min_x, max_x, min_z, max_z,
            spacing, sea_level, values
        )

    def raw_height(self, east: float, north: float) -> float:
        gx = (east - self.min_x) / self.spacing
        gz = (north - self.min_z) / self.spacing
        if gx < 0 or gz < 0 or gx > self.resolution_x - 1 or gz > self.resolution_z - 1:
            return self.sea_level - 24.0
        x0 = max(0, min(self.resolution_x - 1, int(math.floor(gx))))
        z0 = max(0, min(self.resolution_z - 1, int(math.floor(gz))))
        x1 = min(x0 + 1, self.resolution_x - 1)
        z1 = min(z0 + 1, self.resolution_z - 1)
        tx, tz = gx - x0, gz - z0, gz - z0

        def sample(x: int, z: int) -> float:
            return self.values_dm[z * self.resolution_x + x] * 0.1

        h00, h10 = sample(x0, z0), sample(x1, z0)
        h01, h11 = sample(x0, z1), sample(x1, z1)
        h0 = h00 + (h10 - h00) * tx
        h1 = h01 + (h11 - h01) * tx
        return h0 + (h1 - h0) * tz

    @staticmethod
    def smoothstep(value: float) -> float:
        t = max(0.0, min(1.0, value))
        return t * t * (3.0 - 2.0 * t)

    def contact_height(self, east: float, north: float) -> float:
        raw = self.raw_height(east, north)
        dx = max(abs(east) - 900.0, 0.0)
        dz = max(abs(north - 1800.0) - 2500.0, 0.0)
        distance = math.hypot(dx, dz)
        return raw * self.smoothstep(distance / 650.0)


def local_xy(lon: float, lat: float) -> tuple[float, float]:
    east = (lon - ANCHOR_LON) * 111_320.0 * math.cos(math.radians(ANCHOR_LAT))
    north = (lat - ANCHOR_LAT) * 110_540.0
    h = math.radians(ANCHOR_HEADING_DEG)
    x = east * math.cos(h) - north * math.sin(h)
    z = east * math.sin(h) + north * math.cos(h)
    return x, z


def read_glb(path: Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    if len(data) < 20:
        raise RuntimeError(f"{path} is too short to be GLB")
    magic, version, total = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2 or total > len(data):
        raise RuntimeError(f"{path} is not glTF 2.0 binary")
    offset = 12
    doc = None
    binary = b""
    while offset + 8 <= total:
        length, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        payload = data[offset:offset + length]
        offset += length
        if chunk_type == 0x4E4F534A:
            doc = json.loads(payload.decode("utf-8").rstrip(" \t\r\n\0"))
        elif chunk_type == 0x004E4942:
            binary = payload
    if doc is None:
        raise RuntimeError(f"{path} has no JSON GLB chunk")
    return doc, binary


def component_normalize(value: float, component_type: int) -> float:
    if component_type == 5120:
        return max(float(value) / 127.0, -1.0)
    if component_type == 5121:
        return float(value) / 255.0
    if component_type == 5122:
        return max(float(value) / 32767.0, -1.0)
    if component_type == 5123:
        return float(value) / 65535.0
    if component_type == 5125:
        return float(value) / 4294967295.0
    return float(value)


def read_accessor(doc: dict, binary: bytes, accessor_index: int) -> list[tuple | int | float]:
    accessor = doc["accessors"][accessor_index]
    component_type = accessor["componentType"]
    fmt_char, component_bytes = COMPONENT_FORMATS[component_type]
    count = int(accessor["count"])
    component_count = TYPE_COMPONENTS[accessor["type"]]
    view = doc["bufferViews"][accessor["bufferView"]]
    view_offset = int(view.get("byteOffset", 0))
    accessor_offset = int(accessor.get("byteOffset", 0))
    stride = int(view.get("byteStride", component_bytes * component_count))
    start = view_offset + accessor_offset
    normalized = bool(accessor.get("normalized", False))
    fmt = "<" + fmt_char * component_count
    values = []
    for i in range(count):
        raw = struct.unpack_from(fmt, binary, start + i * stride)
        if normalized:
            raw = tuple(component_normalize(v, component_type) for v in raw)
        values.append(raw[0] if component_count == 1 else tuple(float(v) for v in raw))
    return values


def decode_data_uri(uri: str) -> bytes | None:
    if not uri.startswith("data:") or ";base64," not in uri:
        return None
    import base64
    return base64.b64decode(uri.split(";base64,", 1)[1])


def resolve_image_bytes(doc: dict, binary: bytes, image_index: int, glb_path: Path) -> bytes | None:
    image = doc["images"][image_index]
    if "bufferView" in image:
        view = doc["bufferViews"][image["bufferView"]]
        start = int(view.get("byteOffset", 0))
        return binary[start:start + int(view["byteLength"])]
    uri = image.get("uri")
    if not uri:
        return None
    data = decode_data_uri(uri)
    if data is not None:
        return data
    parsed = urlparse(uri)
    if parsed.scheme == "file":
        candidate = Path(unquote(parsed.path))
    else:
        candidate = Path(unquote(uri))
        if not candidate.is_absolute():
            candidate = glb_path.parent / candidate
    try:
        return candidate.read_bytes()
    except OSError:
        return None


_IMAGE_AVG_CACHE: dict[bytes, tuple[float, float, float, float]] = {}


def average_image_rgba(data: bytes) -> tuple[float, float, float, float] | None:
    import hashlib
    key = hashlib.sha1(data).digest()
    if key in _IMAGE_AVG_CACHE:
        return _IMAGE_AVG_CACHE[key]
    try:
        from io import BytesIO
        image = Image.open(BytesIO(data)).convert("RGBA")
        image.thumbnail((64, 64))
        pixels = list(image.getdata())
        if not pixels:
            return None
        alpha_sum = sum(p[3] for p in pixels)
        if alpha_sum <= 0:
            return None
        r = sum(p[0] * p[3] for p in pixels) / alpha_sum / 255.0
        g = sum(p[1] * p[3] for p in pixels) / alpha_sum / 255.0
        b = sum(p[2] * p[3] for p in pixels) / alpha_sum / 255.0
        a = sum(p[3] for p in pixels) / len(pixels) / 255.0
        result = (r, g, b, a)
        _IMAGE_AVG_CACHE[key] = result
        return result
    except Exception:
        return None


def material_for(doc: dict, binary: bytes, index: int | None, glb_path: Path) -> Material:
    if index is None or index >= len(doc.get("materials", [])):
        return Material("default", (0.58, 0.57, 0.54, 1.0), 0.95, 0.0, False)

    src = doc["materials"][index]
    name = str(src.get("name") or f"material-{index}")
    pbr = src.get("pbrMetallicRoughness", {})
    factor = list(pbr.get("baseColorFactor", [1.0, 1.0, 1.0, 1.0]))
    roughness = float(pbr.get("roughnessFactor", 1.0))
    metallic = float(pbr.get("metallicFactor", 0.0))
    texture_info = pbr.get("baseColorTexture")
    if texture_info:
        try:
            texture = doc["textures"][texture_info["index"]]
            image_bytes = resolve_image_bytes(doc, binary, texture["source"], glb_path)
            if image_bytes:
                avg = average_image_rgba(image_bytes)
                if avg:
                    factor = [
                        factor[0] * avg[0], factor[1] * avg[1], factor[2] * avg[2],
                        factor[3] * max(avg[3], 0.35),
                    ]
        except Exception:
            pass

    lname = name.lower()
    if max(factor[:3]) > 0.96 and min(factor[:3]) > 0.92:
        if "water" in lname:
            factor[:3] = [0.05, 0.24, 0.31]
        elif any(k in lname for k in ("grass", "forest", "tree", "hedge")):
            factor[:3] = [0.22, 0.34, 0.15]
        elif any(k in lname for k in ("road", "asphalt", "runway", "taxiway")):
            factor[:3] = [0.20, 0.20, 0.19]
        elif any(k in lname for k in ("roof", "tile")):
            factor[:3] = [0.47, 0.40, 0.31]
        elif any(k in lname for k in ("wall", "building", "concrete", "stone")):
            factor[:3] = [0.62, 0.58, 0.49]
        elif any(k in lname for k in ("rail", "metal", "power")):
            factor[:3] = [0.32, 0.33, 0.33]
    if "glass" in lname:
        roughness = min(roughness, 0.18)
    if "water" in lname:
        roughness = min(roughness, 0.14)

    return Material(
        name=name,
        rgba=tuple(max(0.0, min(1.0, float(v))) for v in factor[:4]),
        roughness=max(0.0, min(1.0, roughness)),
        metallic=max(0.0, min(1.0, metallic)),
        double_sided=bool(src.get("doubleSided", False)),
    )


def material_key(material: Material) -> MaterialKey:
    return MaterialKey(
        rgba=tuple(int(round(c * 255)) for c in material.rgba),
        roughness=int(round(material.roughness * 255)),
        metallic=int(round(material.metallic * 255)),
        double_sided=material.double_sided,
    )


def unit(v: tuple[float, float, float]) -> tuple[float, float, float]:
    length = math.sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2])
    if length <= 1e-9:
        return (0.0, 1.0, 0.0)
    return (v[0]/length, v[1]/length, v[2]/length)


def convert_normal(n: tuple[float, float, float]) -> tuple[float, float, float]:
    east = n[0]
    north = -n[2]
    h = math.radians(ANCHOR_HEADING_DEG)
    x = east * math.cos(h) - north * math.sin(h)
    z = east * math.sin(h) + north * math.cos(h)
    return unit((x, n[1], z))


def scene_origin(doc: dict) -> tuple[float, float]:
    scene_index = int(doc.get("scene", 0))
    scene = doc["scenes"][scene_index]
    origin = scene.get("extras", {}).get("origin")
    if not origin:
        root_index = scene.get("nodes", [0])[0]
        origin = doc["nodes"][root_index].get("extras", {}).get("origin")
    if not origin:
        raise RuntimeError("OSM2World GLB has no scene origin metadata")
    return float(origin["lon"]), float(origin["lat"])


def world_from_gltf(
    p: tuple[float, float, float],
    origin_world: tuple[float, float],
    terrain: TerrainGrid,
) -> tuple[float, float, float]:
    local_east = p[0]
    local_north = -p[2]
    h = math.radians(ANCHOR_HEADING_DEG)
    dx = local_east * math.cos(h) - local_north * math.sin(h)
    dz = local_east * math.sin(h) + local_north * math.cos(h)
    x = origin_world[0] + dx
    z = origin_world[1] + dz
    y = terrain.contact_height(x, z) + p[1]
    return x, y, z


def iter_mesh_instances(doc: dict) -> Iterable[tuple[int, tuple[float,float,float], tuple[float,float,float]]]:
    scene_index = int(doc.get("scene", 0))
    roots = doc["scenes"][scene_index].get("nodes", [])
    nodes = doc.get("nodes", [])

    def walk(node_index: int, parent_t, parent_s):
        node = nodes[node_index]
        t = tuple(float(v) for v in node.get("translation", [0,0,0]))
        s = tuple(float(v) for v in node.get("scale", [1,1,1]))
        if "rotation" in node or "matrix" in node:
            raise RuntimeError("Unexpected OSM2World node rotation/matrix")
        world_t = tuple(parent_t[i] + t[i] * parent_s[i] for i in range(3))
        world_s = tuple(parent_s[i] * s[i] for i in range(3))
        if "mesh" in node:
            yield int(node["mesh"]), world_t, world_s
        for child in node.get("children", []):
            yield from walk(int(child), world_t, world_s)

    for root in roots:
        yield from walk(int(root), (0.0,0.0,0.0), (1.0,1.0,1.0))


def append_glb(
    path: Path,
    lod: int,
    terrain: TerrainGrid,
    chunks: dict[tuple[int,int,int], dict[MaterialKey, MeshAccum]],
    stats: dict,
) -> None:
    doc, binary = read_glb(path)
    lon, lat = scene_origin(doc)
    origin_world = local_xy(lon, lat)
    materials_cache: dict[int | None, Material] = {}
    meshes = doc.get("meshes", [])

    for mesh_index, node_t, node_s in iter_mesh_instances(doc):
        mesh = meshes[mesh_index]
        for primitive in mesh.get("primitives", []):
            attrs = primitive.get("attributes", {})
            if "POSITION" not in attrs or primitive.get("mode", 4) != 4:
                continue
            raw_pos = read_accessor(doc, binary, attrs["POSITION"])
            raw_norm = read_accessor(doc, binary, attrs["NORMAL"]) if "NORMAL" in attrs else None
            indices = (
                [int(v) for v in read_accessor(doc, binary, primitive["indices"])]
                if "indices" in primitive else list(range(len(raw_pos)))
            )
            if len(indices) < 3:
                continue

            mat_index = primitive.get("material")
            if mat_index not in materials_cache:
                materials_cache[mat_index] = material_for(doc, binary, mat_index, path)
            material = materials_cache[mat_index]
            key = material_key(material)

            transformed = []
            for vertex in raw_pos:
                gp = (
                    vertex[0] * node_s[0] + node_t[0],
                    vertex[1] * node_s[1] + node_t[1],
                    vertex[2] * node_s[2] + node_t[2],
                )
                transformed.append(world_from_gltf(gp, origin_world, terrain))

            min_x = min(vertex[0] for vertex in transformed)
            max_x = max(vertex[0] for vertex in transformed)
            min_z = min(vertex[2] for vertex in transformed)
            max_z = max(vertex[2] for vertex in transformed)
            if max_x < MIN_X_M or min_x > MAX_X_M or max_z < MIN_Z_M or min_z > MAX_Z_M:
                continue

            cx = sum(vertex[0] for vertex in transformed) / len(transformed)
            cz = sum(vertex[2] for vertex in transformed) / len(transformed)
            chunk_x = math.floor(cx / SUPERCHUNK_M)
            chunk_z = math.floor(cz / SUPERCHUNK_M)
            chunk_key = (lod, chunk_x, chunk_z)
            by_material = chunks.setdefault(chunk_key, {})
            accum = by_material.get(key)
            if accum is None:
                accum = MeshAccum(material=material)
                by_material[key] = accum

            base = len(accum.positions)
            accum.positions.extend(transformed)
            if raw_norm:
                accum.normals.extend(convert_normal(tuple(normal)) for normal in raw_norm)
            else:
                accum.normals.extend([(0.0,1.0,0.0)] * len(transformed))
            accum.indices.extend(base + i for i in indices)
            stats["source_primitives"] += 1
            stats["source_vertices"] += len(transformed)
            stats["source_triangles"] += len(indices) // 3


def split_mesh(accum: MeshAccum) -> list[MeshAccum]:
    if len(accum.positions) <= MAX_PART_VERTICES:
        return [accum]
    result: list[MeshAccum] = []
    current = MeshAccum(material=accum.material)
    remap: dict[int, int] = {}

    def flush():
        nonlocal current, remap
        if current.indices:
            result.append(current)
        current = MeshAccum(material=accum.material)
        remap = {}

    for tri_start in range(0, len(accum.indices), 3):
        tri = accum.indices[tri_start:tri_start+3]
        if len(tri) < 3:
            break
        needed = sum(1 for old in tri if old not in remap)
        if current.indices and len(current.positions) + needed > MAX_PART_VERTICES:
            flush()
        for old in tri:
            if old not in remap:
                remap[old] = len(current.positions)
                current.positions.append(accum.positions[old])
                current.normals.append(accum.normals[old])
            current.indices.append(remap[old])
    flush()
    return result


def qpos(value: float, center: float, scale: float) -> int:
    q = int(round((value - center) / scale))
    return max(-32767, min(32767, q))


def qnormal(value: float) -> int:
    return max(-127, min(127, int(round(value * 127.0))))


def write_chunk(
    path: Path,
    lod: int,
    chunk_x: int,
    chunk_z: int,
    by_material: dict[MaterialKey, MeshAccum],
) -> dict:
    center_x = (chunk_x + 0.5) * SUPERCHUNK_M
    center_z = (chunk_z + 0.5) * SUPERCHUNK_M
    split_parts: list[MeshAccum] = []
    for accum in by_material.values():
        split_parts.extend(split_mesh(accum))

    materials: list[Material] = []
    mat_index: dict[MaterialKey, int] = {}
    for part in split_parts:
        key = material_key(part.material)
        if key not in mat_index:
            mat_index[key] = len(materials)
            materials.append(part.material)

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as handle:
        handle.write(b"F22C")
        handle.write(struct.pack("<HBBffHH", 1, lod, 0, center_x, center_z, len(materials), len(split_parts)))
        for material in materials:
            flags = 1 if material.double_sided else 0
            handle.write(struct.pack(
                "<8B",
                *(int(round(c * 255)) for c in material.rgba),
                int(round(material.roughness * 255)),
                int(round(material.metallic * 255)),
                flags,
                0,
            ))

        vertex_total = 0
        triangle_total = 0
        for part in split_parts:
            mi = mat_index[material_key(part.material)]
            vertex_count = len(part.positions)
            index_count = len(part.indices)
            if vertex_count > 65535:
                raise RuntimeError("split_mesh failed to keep UInt16 indices")
            handle.write(struct.pack("<HHII", mi, 0, vertex_count, index_count))
            for vertex, normal in zip(part.positions, part.normals):
                handle.write(struct.pack(
                    "<hhhbbb",
                    qpos(vertex[0], center_x, POS_SCALE_XZ),
                    qpos(vertex[1], 0.0, POS_SCALE_Y),
                    qpos(vertex[2], center_z, POS_SCALE_XZ),
                    qnormal(normal[0]), qnormal(normal[1]), qnormal(normal[2]),
                ))
            handle.write(struct.pack("<" + "H" * index_count, *part.indices))
            vertex_total += vertex_count
            triangle_total += index_count // 3

    return {
        "lod": lod,
        "x": chunk_x,
        "z": chunk_z,
        "center": [center_x, center_z],
        "file": str(path.relative_to(ROOT / "Assets/JSBSim/visuals/world")).replace(os.sep, "/"),
        "bytes": path.stat().st_size,
        "vertices": vertex_total,
        "triangles": triangle_total,
        "materials": len(materials),
        "meshParts": len(split_parts),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tiles", required=True, type=Path, help="OSM2World tileset base directory")
    args = parser.parse_args()

    terrain = TerrainGrid.load(TERRAIN_INC)
    chunks: dict[tuple[int,int,int], dict[MaterialKey, MeshAccum]] = {}
    stats = {
        "source_glb_files": 0,
        "source_primitives": 0,
        "source_vertices": 0,
        "source_triangles": 0,
    }

    glbs = []
    lods = []
    for lod in (2, 4):
        lod_glbs = sorted((args.tiles / f"lod{lod}").rglob("*.glb"))
        if lod_glbs:
            lods.append(lod)
            glbs.extend((lod, path) for path in lod_glbs)
    if not glbs:
        raise RuntimeError(f"No OSM2World GLBs found under {args.tiles}")

    for index, (lod, path) in enumerate(glbs, 1):
        print(f"[{index}/{len(glbs)}] repack {path}")
        append_glb(path, lod, terrain, chunks, stats)
        stats["source_glb_files"] += 1

    if OUT_ROOT.exists():
        import shutil
        shutil.rmtree(OUT_ROOT)
    OUT_ROOT.mkdir(parents=True, exist_ok=True)

    manifest_chunks = []
    for (lod, cx, cz), by_material in sorted(chunks.items()):
        out = OUT_ROOT / f"lod{lod}" / f"chunk_{cx}_{cz}.bin"
        manifest_chunks.append(write_chunk(out, lod, cx, cz, by_material))

    total_bytes = sum(chunk["bytes"] for chunk in manifest_chunks)
    manifest = {
        "stage": 22,
        "region": "Maltese archipelago",
        "generator": {
            "name": "OSM2World",
            "commit": "8ec26a9ea426444a4f7882cf0cfcab432c876ae5",
            "styleCommit": "81ade9bf9793181774891548ac29448f366efd3c",
        },
        "anchor": {
            "latitude": ANCHOR_LAT,
            "longitude": ANCHOR_LON,
            "headingDegrees": ANCHOR_HEADING_DEG,
        },
        "boundsMeters": {"minX": MIN_X_M, "maxX": MAX_X_M, "minZ": MIN_Z_M, "maxZ": MAX_Z_M},
        "superchunkMeters": SUPERCHUNK_M,
        "positionScaleXZ": POS_SCALE_XZ,
        "positionScaleY": POS_SCALE_Y,
        "terrainSource": "Stage022MaltaTerrain.inc / shared JSBSim contact surface",
        "lods": lods,
        "chunks": manifest_chunks,
        "stats": {
            **stats,
            "chunkCount": len(manifest_chunks),
            "packedBytes": total_bytes,
            "packedMiB": round(total_bytes / (1024 * 1024), 2),
            "packedVertices": sum(chunk["vertices"] for chunk in manifest_chunks),
            "packedTriangles": sum(chunk["triangles"] for chunk in manifest_chunks),
        },
        "licenses": {
            "OSM2World": "MIT",
            "OSM2WorldDefaultStyle": "CC0",
            "OpenStreetMap": "ODbL 1.0",
        },
    }
    OUT_MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    OUT_MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest["stats"], indent=2))


if __name__ == "__main__":
    main()
