#!/usr/bin/env python3
from __future__ import annotations

import io
import json
import math
import os
import shutil
import struct
import warnings
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import numpy as np
from PIL import Image
from remotezip import RemoteZip
import urllib3

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Assets/JSBSim/visuals/world/helsinki"
SOURCE_BASE = "https://3d.hel.ninja/data/mesh/Helsinki3D-MESH_2017_OBJ_2km-250m_ZIP"

# City of Helsinki reality mesh local frame (EPSG:3879 minus the documented
# Helsinki model origin 25,490,000 / 6,668,000). Full Authority recenters the
# visual world on EFHF runway 36 and rotates the real 006-ish runway to +Z.
MODEL_ORIGIN_E = 25_490_000.0
MODEL_ORIGIN_N = 6_668_000.0
RUNWAY36_E = 25_502_318.627510272
RUNWAY36_N = 6_681_948.214688566
RUNWAY18_E = 25_502_422.161423218
RUNWAY18_N = 6_682_902.119642362
RUNWAY36_LOCAL_E = RUNWAY36_E - MODEL_ORIGIN_E
RUNWAY36_LOCAL_N = RUNWAY36_N - MODEL_ORIGIN_N
RUNWAY_HEADING = math.atan2(RUNWAY18_E - RUNWAY36_E, RUNWAY18_N - RUNWAY36_N)

# 14 x 14 km benchmark region: Helsinki waterfront/downtown north to Malmi.
SOURCE_MIN_E = 25_490_000
SOURCE_MAX_E = 25_504_000
SOURCE_MIN_N = 6_670_000
SOURCE_MAX_N = 6_684_000
SOURCE_STEP = 2_000
GRID_CELL = 50.0

# Four blocks surrounding Malmi get higher geometry fidelity for runway-side
# views. The rest stays L15, which the City of Helsinki Blender loader also
# recommends as a useful large-area working level.
HIGH_DETAIL_CODES = {"680500", "680502", "682500", "682502"}

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
warnings.filterwarnings("ignore", message="Unverified HTTPS request")


def log(message: str) -> None:
    print(f"[helsinki] {message}", flush=True)


def source_code(easting: int, northing: int) -> str:
    dx = (easting - 25_490_000) // 2_000
    dy = (northing - 6_668_000) // 2_000
    return str(668_490 + dx * 2 + dy * 2_000)


def to_game(easting_local: float, northing_local: float) -> tuple[float, float]:
    dx = easting_local - RUNWAY36_LOCAL_E
    dz = northing_local - RUNWAY36_LOCAL_N
    c = math.cos(RUNWAY_HEADING)
    s = math.sin(RUNWAY_HEADING)
    # Rotation that maps the real EFHF 36 centerline to Full Authority +Z.
    return c * dx - s * dz, s * dx + c * dz


def game_bounds() -> tuple[float, float, float, float]:
    points = []
    for e in (SOURCE_MIN_E, SOURCE_MAX_E):
        for n in (SOURCE_MIN_N, SOURCE_MAX_N):
            points.append(to_game(e - MODEL_ORIGIN_E, n - MODEL_ORIGIN_N))
    xs = [p[0] for p in points]
    zs = [p[1] for p in points]
    min_x = math.floor(min(xs) / GRID_CELL) * GRID_CELL
    max_x = math.ceil(max(xs) / GRID_CELL) * GRID_CELL
    min_z = math.floor(min(zs) / GRID_CELL) * GRID_CELL
    max_z = math.ceil(max(zs) / GRID_CELL) * GRID_CELL
    return min_x, min_z, max_x, max_z


MIN_X, MIN_Z, MAX_X, MAX_Z = game_bounds()
GRID_W = int(round((MAX_X - MIN_X) / GRID_CELL)) + 1
GRID_H = int(round((MAX_Z - MIN_Z) / GRID_CELL)) + 1


def resolve_index(raw: int, count: int) -> int | None:
    if raw > 0:
        i = raw - 1
    elif raw < 0:
        i = count + raw
    else:
        return None
    return i if 0 <= i < count else None


def parse_obj(
    text: str,
    slot: int,
    grid_minima: dict[tuple[int, int], float],
) -> tuple[list[tuple[float, float, float, float, float]], list[int], list[int]]:
    src_pos: list[tuple[float, float, float]] = []
    src_uv: list[tuple[float, float]] = []
    faces: list[tuple[list[tuple[int, int | None]], bool]] = []
    untextured = False

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if line.startswith("v "):
            p = line.split()
            if len(p) >= 4:
                x, y, z = float(p[1]), float(p[2]), float(p[3])
                src_pos.append((x, y, z))
                gx, gz = to_game(x, y)
                ix = int(math.floor((gx - MIN_X) / GRID_CELL))
                iz = int(math.floor((gz - MIN_Z) / GRID_CELL))
                if 0 <= ix < GRID_W and 0 <= iz < GRID_H:
                    key = (iz, ix)
                    previous = grid_minima.get(key)
                    if previous is None or z < previous:
                        grid_minima[key] = z
        elif line.startswith("vt "):
            p = line.split()
            if len(p) >= 3:
                src_uv.append((float(p[1]), float(p[2])))
        elif line.startswith("usemtl "):
            untextured = line.lower().endswith("_untextured")
        elif line.startswith("f "):
            tokens = line.split()[1:]
            parsed: list[tuple[int, int | None]] = []
            valid = True
            for token in tokens:
                bits = token.split("/")
                try:
                    pi_raw = int(bits[0])
                except Exception:
                    valid = False
                    break
                pi = resolve_index(pi_raw, len(src_pos))
                if pi is None:
                    valid = False
                    break
                ti = None
                if len(bits) > 1 and bits[1]:
                    try:
                        ti = resolve_index(int(bits[1]), len(src_uv))
                    except Exception:
                        ti = None
                parsed.append((pi, ti))
            if valid and len(parsed) >= 3:
                faces.append((parsed, untextured))

    vertices: list[tuple[float, float, float, float, float]] = []
    indices: list[int] = []
    materials: list[int] = []
    cache: dict[tuple[int, int | None, bool], int] = {}
    col = slot % 8
    row = slot // 8

    def vertex_for(pi: int, ti: int | None, plain: bool) -> int:
        key = (pi, ti, plain)
        found = cache.get(key)
        if found is not None:
            return found
        sx, sn, elevation = src_pos[pi]
        gx, gz = to_game(sx, sn)
        if plain or ti is None:
            u = 0.5
            v = 0.5
        else:
            ou, ov = src_uv[ti]
            # OBJ V=0 is image bottom; RealityKit's texture coordinate path uses
            # V=0 at image top for raw texture resources.
            u = (col + min(max(ou, 0.001), 0.999)) / 8.0
            v = (row + min(max(1.0 - ov, 0.001), 0.999)) / 8.0
        idx = len(vertices)
        # Keep elevation absolute in the package. Runtime subtracts the derived
        # runway reference height so collision and visuals share one datum.
        vertices.append((gx, elevation, gz, u, v))
        cache[key] = idx
        return idx

    for polygon, plain in faces:
        for i in range(1, len(polygon) - 1):
            # Mapping source (X east, Y north, Z up) to RealityKit (X, Y up, Z)
            # swaps handedness. Reverse winding while fan-triangulating.
            tri = (polygon[0], polygon[i + 1], polygon[i])
            for pi, ti in tri:
                indices.append(vertex_for(pi, ti, plain))
            materials.append(1 if plain else 0)

    return vertices, indices, materials


def encode_tile(path: Path, vertices, indices, materials) -> None:
    with path.open("wb") as f:
        f.write(struct.pack("<4sIIII", b"FHM1", 1, len(vertices), len(indices), len(materials)))
        if vertices:
            f.write(np.asarray(vertices, dtype="<f4").tobytes(order="C"))
        if indices:
            f.write(np.asarray(indices, dtype="<u4").tobytes(order="C"))
        if materials:
            f.write(bytes(materials))


def process_source_tile(easting: int, northing: int):
    code = source_code(easting, northing)
    lod = 16 if code in HIGH_DETAIL_CODES else 15
    mesh_path = OUT / f"helsinki_{code}.fhm"
    atlas_path = OUT / f"helsinki_{code}.jpg"
    url = f"{SOURCE_BASE}/Helsinki3D_2017_OBJ_{code}x2.zip"
    log(f"{code}: inspect official archive, LOD{lod}")

    with RemoteZip(url, verify=False, timeout=180) as archive:
        infos = archive.infolist()
        objects = sorted(
            [i for i in infos if f"_L{lod}_" in i.filename and i.filename.lower().endswith(".obj")],
            key=lambda i: i.filename,
        )
        if not objects:
            raise RuntimeError(f"{code}: no LOD{lod} OBJ members")
        if len(objects) > 64:
            raise RuntimeError(f"{code}: expected <=64 LOD{lod} cells, got {len(objects)}")

        cell_px = 256 if lod == 16 else 128
        atlas = Image.new("RGB", (cell_px * 8, cell_px * 8), (105, 105, 105))
        all_vertices = []
        all_indices = []
        all_materials = []
        minima: dict[tuple[int, int], float] = {}

        for slot, info in enumerate(objects):
            stem = info.filename[:-4]
            image_name = stem + "_0.jpg"
            try:
                obj_bytes = archive.read(info)
                image_bytes = archive.read(image_name)
            except Exception as exc:
                raise RuntimeError(f"{code}: failed reading {info.filename}: {exc}") from exc

            image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
            if image.size != (cell_px, cell_px):
                image = image.resize((cell_px, cell_px), Image.Resampling.LANCZOS)
            atlas.paste(image, ((slot % 8) * cell_px, (slot // 8) * cell_px))

            vertices, indices, materials = parse_obj(
                obj_bytes.decode("utf-8", errors="replace"),
                slot,
                minima,
            )
            base = len(all_vertices)
            all_vertices.extend(vertices)
            all_indices.extend(base + i for i in indices)
            all_materials.extend(materials)

        if not all_vertices or not all_indices:
            raise RuntimeError(f"{code}: parsed mesh is empty")

        encode_tile(mesh_path, all_vertices, all_indices, all_materials)
        atlas.save(atlas_path, "JPEG", quality=84, optimize=True, progressive=True)
        log(
            f"{code}: LOD{lod} {len(all_vertices):,} verts / "
            f"{len(all_indices)//3:,} tris / {mesh_path.stat().st_size/1048576:.2f} MiB mesh / "
            f"{atlas_path.stat().st_size/1048576:.2f} MiB atlas"
        )
        return {
            "code": code,
            "lod": lod,
            "mesh": mesh_path.name,
            "texture": atlas_path.name,
            "vertices": len(all_vertices),
            "triangles": len(all_indices) // 3,
            "minima": minima,
        }


def fill_ground_grid(minima: dict[tuple[int, int], float]) -> np.ndarray:
    grid = np.full((GRID_H, GRID_W), np.nan, dtype=np.float32)
    for (iz, ix), value in minima.items():
        grid[iz, ix] = value

    # Photogrammetry is dense, but roofs can cover a whole 50 m cell. Fill holes
    # from neighboring low surface samples rather than treating roofs as ground.
    for _ in range(max(GRID_W, GRID_H)):
        missing = np.isnan(grid)
        if not missing.any():
            break
        padded = np.pad(grid, 1, mode="constant", constant_values=np.nan)
        neighbors = []
        for dz in range(3):
            for dx in range(3):
                if dx == 1 and dz == 1:
                    continue
                neighbors.append(padded[dz:dz + GRID_H, dx:dx + GRID_W])
        stack = np.stack(neighbors)
        with np.errstate(invalid="ignore"):
            mean = np.nanmean(stack, axis=0)
        can_fill = missing & np.isfinite(mean)
        grid[can_fill] = mean[can_fill]
        if not can_fill.any():
            break

    if np.isnan(grid).any():
        fallback = float(np.nanmedian(grid)) if np.isfinite(grid).any() else 17.0
        grid = np.nan_to_num(grid, nan=fallback)

    # Gentle 3x3 median pass removes roof spikes while preserving the actual
    # large-scale Helsinki terrain profile.
    padded = np.pad(grid, 1, mode="edge")
    windows = []
    for dz in range(3):
        for dx in range(3):
            windows.append(padded[dz:dz + GRID_H, dx:dx + GRID_W])
    median = np.median(np.stack(windows), axis=0).astype(np.float32)
    grid = grid * 0.45 + median * 0.55

    # Smooth the actual EFHF 18/36 pavement corridor while using the scanned
    # local elevation as datum. This prevents gear contact from following tiny
    # photogrammetry ripples or parked-aircraft geometry.
    ix0 = int(round((0.0 - MIN_X) / GRID_CELL))
    iz0 = int(round((0.0 - MIN_Z) / GRID_CELL))
    r = 2
    runway_ref = float(np.median(grid[max(0, iz0-r):iz0+r+1, max(0, ix0-r):ix0+r+1]))
    runway_length = math.hypot(RUNWAY18_E - RUNWAY36_E, RUNWAY18_N - RUNWAY36_N)
    for iz in range(GRID_H):
        z = MIN_Z + iz * GRID_CELL
        if z < -120 or z > runway_length + 120:
            continue
        for ix in range(GRID_W):
            x = MIN_X + ix * GRID_CELL
            lateral = abs(x)
            if lateral >= 70:
                continue
            weight = 1.0 if lateral <= 18 else max(0.0, (70 - lateral) / 52.0)
            along = min(max(z / max(runway_length, 1.0), 0.0), 1.0)
            # Keep the runway essentially level; Malmi's published field/runway
            # elevation is around 15-17 m MSL and the scan supplies the exact datum.
            target = runway_ref
            grid[iz, ix] = grid[iz, ix] * (1.0 - weight) + target * weight

    return grid, runway_ref


def write_ground(grid: np.ndarray, reference: float) -> None:
    path = OUT / "helsinki_ground.bin"
    header = struct.pack(
        "<4sIIIffff",
        b"FAM2", 1, GRID_W, GRID_H, GRID_CELL,
        float(MIN_X), float(MIN_Z), float(reference),
    )
    path.write_bytes(header + grid.astype("<f4", copy=False).tobytes(order="C"))


def main() -> None:
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True, exist_ok=True)

    jobs = []
    for northing in range(SOURCE_MIN_N, SOURCE_MAX_N, SOURCE_STEP):
        for easting in range(SOURCE_MIN_E, SOURCE_MAX_E, SOURCE_STEP):
            jobs.append((easting, northing))

    log(f"building {len(jobs)} official 2 km source blocks ({(SOURCE_MAX_E-SOURCE_MIN_E)//1000} x {(SOURCE_MAX_N-SOURCE_MIN_N)//1000} km)")
    results = []
    # Moderate concurrency keeps the City open-data host and runner memory sane.
    with ThreadPoolExecutor(max_workers=4) as pool:
        future_map = {pool.submit(process_source_tile, e, n): (e, n) for e, n in jobs}
        for future in as_completed(future_map):
            results.append(future.result())

    merged_minima: dict[tuple[int, int], float] = {}
    for result in results:
        for key, value in result.pop("minima").items():
            previous = merged_minima.get(key)
            if previous is None or value < previous:
                merged_minima[key] = value

    grid, reference = fill_ground_grid(merged_minima)
    write_ground(grid, reference)

    results.sort(key=lambda item: item["code"])
    manifest = {
        "name": "Helsinki 3D reality mesh benchmark",
        "source": "City of Helsinki Helsinki 3D reality mesh (2017)",
        "license": "CC BY 4.0",
        "sourceURL": "https://3d.hel.ninja/mesh/",
        "coordinateSystem": "EPSG:3879 source; recentered/rotated to EFHF RWY 36",
        "minX": MIN_X,
        "minZ": MIN_Z,
        "maxX": MAX_X,
        "maxZ": MAX_Z,
        "referenceElevationMeters": reference,
        "runwayLengthMeters": math.hypot(RUNWAY18_E - RUNWAY36_E, RUNWAY18_N - RUNWAY36_N),
        "runwayHeadingTrueDegrees": math.degrees(RUNWAY_HEADING),
        "tiles": results,
    }
    (OUT / "helsinki_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    (OUT / "ATTRIBUTION.txt").write_text(
        "Full Authority Stage 024 benchmark map\n\n"
        "Source: Helsinki 3D reality mesh (2017), City of Helsinki\n"
        "License: Creative Commons Attribution 4.0 International (CC BY 4.0)\n"
        "Source: https://3d.hel.ninja/mesh/\n\n"
        "The source OBJ reality mesh was recentered, rotated, merged into 2 km chunks,\n"
        "texture-atlased and selectively downsampled for mobile rendering. No generated\n"
        "buildings, roads, vegetation, vehicles, shoreline or terrain geometry replaces\n"
        "the City of Helsinki photogrammetry in the visual benchmark layer.\n",
        encoding="utf-8",
    )

    total_mesh = sum((OUT / r["mesh"]).stat().st_size for r in results)
    total_tex = sum((OUT / r["texture"]).stat().st_size for r in results)
    log(f"complete: {len(results)} blocks, ref {reference:.2f} m, mesh {total_mesh/1048576:.1f} MiB, textures {total_tex/1048576:.1f} MiB")
    log(f"bounds game X {MIN_X:.0f}..{MAX_X:.0f}, Z {MIN_Z:.0f}..{MAX_Z:.0f}")


if __name__ == "__main__":
    main()
