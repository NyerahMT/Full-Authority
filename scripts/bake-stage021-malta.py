#!/usr/bin/env python3
"""Bake a compact, offline Malta world layer for Full Authority Stage 021.

Data sources:
- OpenStreetMap Malta extract from Geofabrik (ODbL 1.0)
- Mapzen/AWS Terrarium elevation tiles (CC0 elevation dataset service)

The output is deliberately engine-friendly rather than a verbatim GIS dump:
- a fixed-grid DEM compiled into the JSBSim bridge so flight contact and rendering
  share one terrain function;
- OSM building footprints reduced to oriented boxes with OSM heights/levels when
  available, preserving real position/orientation/density at mobile-friendly cost;
- real drivable OSM road polylines with class-derived widths;
- a metadata JSON for provenance and bake statistics.
"""

from __future__ import annotations

import io
import json
import math
import os
import re
import struct
from pathlib import Path
from typing import Iterable

import numpy as np
import requests
from PIL import Image
from pyrosm import OSM
from shapely.geometry import LineString, MultiLineString, Polygon, MultiPolygon

ROOT = Path(__file__).resolve().parents[1]
OUT_BIN = ROOT / "Assets/JSBSim/visuals/world/stage021_malta_world.bin"
OUT_INC = ROOT / "Simulation/Bridge/Stage021MaltaTerrain.inc"
OUT_META = ROOT / "Docs/Stage021MaltaWorld.json"

PBF_URL = "https://download.geofabrik.de/europe/malta-latest.osm.pbf"
PBF_PATH = ROOT / "Build/stage021/malta-latest.osm.pbf"

# Runway 31 threshold at Malta/Luqa. Heading 312 points northwest along RWY 31,
# putting the denser Valletta side of the island in front of the initial takeoff.
ANCHOR_LAT = 35.8351666667
ANCHOR_LON = 14.5051666667
ANCHOR_HEADING_DEG = 312.0
ANCHOR_ELEVATION_M = 231.0 * 0.3048

WORLD_HALF_M = 24_000.0
TERRAIN_RESOLUTION = 385
TERRARIUM_ZOOM = 10
SEA_LEVEL_LOCAL_M = -ANCHOR_ELEVATION_M
SEA_FLOOR_LOCAL_M = SEA_LEVEL_LOCAL_M - 24.0

MAGIC = b"FA21"
VERSION = 1

ROAD_WIDTHS = {
    "motorway": 13.0,
    "motorway_link": 9.5,
    "trunk": 11.0,
    "trunk_link": 8.5,
    "primary": 9.5,
    "primary_link": 7.5,
    "secondary": 8.0,
    "secondary_link": 6.8,
    "tertiary": 7.0,
    "tertiary_link": 6.2,
    "residential": 5.8,
    "living_street": 5.2,
    "unclassified": 5.4,
    "service": 4.6,
}

ROAD_CLASS = {
    "motorway": 0, "motorway_link": 0,
    "trunk": 0, "trunk_link": 0,
    "primary": 1, "primary_link": 1,
    "secondary": 2, "secondary_link": 2,
    "tertiary": 3, "tertiary_link": 3,
    "residential": 4, "living_street": 4, "unclassified": 4,
    "service": 5,
}


def download(url: str, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.stat().st_size > 1000:
        return
    print(f"Downloading {url}")
    with requests.get(url, stream=True, timeout=90) as response:
        response.raise_for_status()
        with path.open("wb") as handle:
            for chunk in response.iter_content(1024 * 1024):
                if chunk:
                    handle.write(chunk)


def local_xy(lon: float, lat: float) -> tuple[float, float]:
    # Local tangent-plane approximation is comfortably accurate over a 48 km scene.
    east = (lon - ANCHOR_LON) * 111_320.0 * math.cos(math.radians(ANCHOR_LAT))
    north = (lat - ANCHOR_LAT) * 110_540.0
    h = math.radians(ANCHOR_HEADING_DEG)
    # +Z follows runway heading; +X is aircraft-right/east-ish.
    x = east * math.cos(h) - north * math.sin(h)
    z = east * math.sin(h) + north * math.cos(h)
    return x, z


def in_world(x: float, z: float, margin: float = 0.0) -> bool:
    return abs(x) <= WORLD_HALF_M + margin and abs(z) <= WORLD_HALF_M + margin


def parse_number(value) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float, np.number)):
        number = float(value)
        return number if math.isfinite(number) else None
    match = re.search(r"[-+]?\d+(?:\.\d+)?", str(value))
    if not match:
        return None
    try:
        return float(match.group(0))
    except ValueError:
        return None


def stable_hash(value: int) -> float:
    x = math.sin(value * 12.9898 + 78.233) * 43758.5453
    return x - math.floor(x)


def iter_polygons(geometry) -> Iterable[Polygon]:
    if isinstance(geometry, Polygon):
        yield geometry
    elif isinstance(geometry, MultiPolygon):
        yield from geometry.geoms


def iter_lines(geometry) -> Iterable[LineString]:
    if isinstance(geometry, LineString):
        yield geometry
    elif isinstance(geometry, MultiLineString):
        yield from geometry.geoms


def polygon_to_local(poly: Polygon) -> Polygon | None:
    points = [local_xy(lon, lat) for lon, lat, *_ in poly.exterior.coords]
    if len(points) < 4:
        return None
    result = Polygon(points)
    if not result.is_valid:
        result = result.buffer(0)
    return result if not result.is_empty else None


def infer_building_height(row, area_m2: float, seed: int) -> float:
    direct = parse_number(row.get("height"))
    if direct is not None and 2.0 <= direct <= 300.0:
        return float(direct)

    levels = parse_number(row.get("building:levels"))
    if levels is not None and 1 <= levels <= 80:
        return min(260.0, 1.2 + levels * 3.15)

    kind = str(row.get("building") or "").lower()
    jitter = stable_hash(seed) * 1.8
    if kind in {"church", "cathedral", "chapel", "mosque"}:
        return 18.0 + min(22.0, math.sqrt(max(area_m2, 1.0)) * 0.15) + jitter * 3
    if kind in {"industrial", "warehouse", "hangar"}:
        return 7.5 + min(11.0, math.sqrt(max(area_m2, 1.0)) * 0.07) + jitter
    if kind in {"commercial", "retail", "office", "hotel"}:
        return 10.0 + min(20.0, math.sqrt(max(area_m2, 1.0)) * 0.10) + jitter * 2

    # Malta is predominantly low/mid-rise. Larger footprints nudge upward without
    # turning every dense block into a fake skyscraper forest.
    return 6.8 + min(12.0, math.sqrt(max(area_m2, 1.0)) * 0.055) + jitter * 1.6


def building_style(row, seed: int) -> int:
    kind = str(row.get("building") or "").lower()
    if kind in {"industrial", "warehouse", "hangar"}:
        return 3
    if kind in {"commercial", "retail", "office", "hotel"}:
        return 2
    if kind in {"church", "cathedral", "chapel", "mosque"}:
        return 4
    return int(stable_hash(seed * 17 + 5) * 3) % 3


def bake_buildings(osm: OSM):
    print("Reading OSM buildings")
    buildings = osm.get_buildings(extra_attributes=["height"], tags_to_keep=["building", "building:levels", "name"])
    records = []
    for index, row in buildings.iterrows():
        geometry = row.geometry
        if geometry is None or geometry.is_empty:
            continue
        seed = int(row.get("id") or index or 0)
        for poly in iter_polygons(geometry):
            local = polygon_to_local(poly)
            if local is None or local.is_empty:
                continue
            centroid = local.centroid
            cx, cz = float(centroid.x), float(centroid.y)
            if not in_world(cx, cz, margin=300.0):
                continue
            area = float(local.area)
            if area < 10.0 or area > 180_000.0:
                continue

            rect = local.minimum_rotated_rectangle
            corners = list(rect.exterior.coords)[:4]
            if len(corners) != 4:
                continue
            e1 = (corners[1][0] - corners[0][0], corners[1][1] - corners[0][1])
            e2 = (corners[2][0] - corners[1][0], corners[2][1] - corners[1][1])
            l1 = math.hypot(*e1)
            l2 = math.hypot(*e2)
            if l1 < 1.5 or l2 < 1.5:
                continue

            # Store local box X direction as yaw in the X/Z plane.
            width, depth = l1, l2
            yaw = math.atan2(e1[1], e1[0])
            if width > 220 or depth > 220:
                # Split-mega-footprints are uncommon and tend to be mapping artifacts;
                # preserving their center/area but clamping prevents absurd slabs.
                width = min(width, 220.0)
                depth = min(depth, 220.0)

            height = infer_building_height(row, area, seed)
            style = building_style(row, seed)
            records.append((cx, cz, width, depth, yaw, height, style))

    # Tallest/most important geometry survives first if a future mobile cap is needed.
    records.sort(key=lambda r: (r[5] * r[2] * r[3]), reverse=True)
    print(f"Buildings: {len(records):,}")
    return records


def road_width(highway, lanes) -> float | None:
    if isinstance(highway, (list, tuple, np.ndarray)):
        highway = highway[0] if len(highway) else None
    key = str(highway or "")
    base = ROAD_WIDTHS.get(key)
    if base is None:
        return None
    lane_count = parse_number(lanes)
    if lane_count is not None and lane_count >= 3:
        base = max(base, min(18.0, lane_count * 3.15))
    return base


def bake_roads(osm: OSM):
    print("Reading OSM roads")
    roads = osm.get_network(
        network_type="driving+service",
        extra_attributes=["tunnel"],
        tags_to_keep=["highway", "lanes", "bridge", "surface", "name"],
    )
    records = []
    for _, row in roads.iterrows():
        highway = row.get("highway")
        width = road_width(highway, row.get("lanes"))
        if width is None:
            continue
        if str(row.get("tunnel") or "").lower() in {"yes", "true", "1"}:
            continue
        key = str(highway[0] if isinstance(highway, (list, tuple, np.ndarray)) and len(highway) else highway or "")
        road_class = ROAD_CLASS.get(key, 5)

        for line in iter_lines(row.geometry):
            coords = [local_xy(lon, lat) for lon, lat, *_ in line.coords]
            coords = [(x, z) for x, z in coords if in_world(x, z, margin=500.0)]
            if len(coords) < 2:
                continue
            local_line = LineString(coords).simplify(2.2, preserve_topology=False)
            points = list(local_line.coords)
            if len(points) < 2:
                continue
            # Binary format uses UInt16 point counts. Real road ways are nowhere close,
            # but split defensively so corrupt data can never overflow the record.
            for start in range(0, len(points) - 1, 65_000):
                part = points[start : min(start + 65_001, len(points))]
                if len(part) >= 2:
                    records.append((road_class, float(width), [(float(x), float(z)) for x, z in part]))

    print(f"Road polylines: {len(records):,}")
    return records


def lonlat_to_tile(lon: float, lat: float, zoom: int) -> tuple[float, float]:
    n = 2.0 ** zoom
    x = (lon + 180.0) / 360.0 * n
    lat_rad = math.radians(max(min(lat, 85.05112878), -85.05112878))
    y = (1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n
    return x, y


def local_to_lonlat(x: float, z: float) -> tuple[float, float]:
    h = math.radians(ANCHOR_HEADING_DEG)
    east = x * math.cos(h) + z * math.sin(h)
    north = -x * math.sin(h) + z * math.cos(h)
    lat = ANCHOR_LAT + north / 110_540.0
    lon = ANCHOR_LON + east / (111_320.0 * math.cos(math.radians(ANCHOR_LAT)))
    return lon, lat


def fetch_terrarium_tile(tx: int, ty: int, cache: dict[tuple[int, int], np.ndarray]) -> np.ndarray:
    key = (tx, ty)
    if key in cache:
        return cache[key]
    url = f"https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{TERRARIUM_ZOOM}/{tx}/{ty}.png"
    response = requests.get(url, timeout=60)
    response.raise_for_status()
    image = np.asarray(Image.open(io.BytesIO(response.content)).convert("RGB"), dtype=np.float32)
    elevation = image[:, :, 0] * 256.0 + image[:, :, 1] + image[:, :, 2] / 256.0 - 32768.0
    cache[key] = elevation
    print(f"Terrain tile {tx}/{ty}")
    return elevation


def sample_elevation(lon: float, lat: float, cache: dict[tuple[int, int], np.ndarray]) -> float:
    x, y = lonlat_to_tile(lon, lat, TERRARIUM_ZOOM)
    tx, ty = int(math.floor(x)), int(math.floor(y))
    fx, fy = (x - tx) * 256.0, (y - ty) * 256.0
    tile = fetch_terrarium_tile(tx, ty, cache)
    x0, y0 = int(min(max(math.floor(fx), 0), 255)), int(min(max(math.floor(fy), 0), 255))
    x1, y1 = min(x0 + 1, 255), min(y0 + 1, 255)
    ax, ay = fx - x0, fy - y0
    v0 = tile[y0, x0] * (1 - ax) + tile[y0, x1] * ax
    v1 = tile[y1, x0] * (1 - ax) + tile[y1, x1] * ax
    return float(v0 * (1 - ay) + v1 * ay)


def bake_terrain() -> np.ndarray:
    print("Baking Terrarium DEM")
    cache: dict[tuple[int, int], np.ndarray] = {}
    axis = np.linspace(-WORLD_HALF_M, WORLD_HALF_M, TERRAIN_RESOLUTION, dtype=np.float64)
    dem = np.empty((TERRAIN_RESOLUTION, TERRAIN_RESOLUTION), dtype=np.float32)
    for iz, z in enumerate(axis):
        for ix, x in enumerate(axis):
            lon, lat = local_to_lonlat(float(x), float(z))
            msl = sample_elevation(lon, lat, cache)
            # Terrarium ocean is effectively zero. Sink it below the rendered water plane
            # so the same heightfield can represent both land and open sea cleanly.
            local_height = SEA_FLOOR_LOCAL_M if msl <= 0.75 else msl - ANCHOR_ELEVATION_M
            dem[iz, ix] = local_height
        if iz % 32 == 0:
            print(f"Terrain row {iz + 1}/{TERRAIN_RESOLUTION}")
    return dem


def write_terrain_include(dem: np.ndarray) -> None:
    OUT_INC.parent.mkdir(parents=True, exist_ok=True)
    spacing = (WORLD_HALF_M * 2.0) / (TERRAIN_RESOLUTION - 1)
    decimeters = np.clip(np.rint(dem * 10.0), -32768, 32767).astype(np.int16).ravel()
    with OUT_INC.open("w", encoding="utf-8") as handle:
        handle.write("// Generated by scripts/bake-stage021-malta.py. Do not hand-edit.\n")
        handle.write(f"static constexpr int kFAStage021TerrainResolution = {TERRAIN_RESOLUTION};\n")
        handle.write(f"static constexpr double kFAStage021TerrainHalfMeters = {WORLD_HALF_M:.6f};\n")
        handle.write(f"static constexpr double kFAStage021TerrainSpacingMeters = {spacing:.9f};\n")
        handle.write(f"static constexpr double kFAStage021SeaLevelMeters = {SEA_LEVEL_LOCAL_M:.9f};\n")
        handle.write("static const int16_t kFAStage021TerrainDecimeters[] = {\n")
        for start in range(0, len(decimeters), 24):
            chunk = decimeters[start : start + 24]
            handle.write("    " + ", ".join(str(int(v)) for v in chunk) + ",\n")
        handle.write("};\n")


def write_world_binary(buildings, roads) -> None:
    OUT_BIN.parent.mkdir(parents=True, exist_ok=True)
    with OUT_BIN.open("wb") as handle:
        handle.write(struct.pack("<4sHHIIf", MAGIC, VERSION, 0, len(buildings), len(roads), float(SEA_LEVEL_LOCAL_M)))
        handle.write(struct.pack("<f", float(WORLD_HALF_M)))
        for x, z, width, depth, yaw, height, style in buildings:
            handle.write(struct.pack("<6fB3x", x, z, width, depth, yaw, height, int(style)))
        for road_class, width, points in roads:
            handle.write(struct.pack("<BBHf", int(road_class), 0, len(points), float(width)))
            for x, z in points:
                handle.write(struct.pack("<2f", x, z))


def main() -> None:
    download(PBF_URL, PBF_PATH)
    osm = OSM(str(PBF_PATH), keep_node_info=False)
    buildings = bake_buildings(osm)
    roads = bake_roads(osm)
    dem = bake_terrain()
    write_terrain_include(dem)
    write_world_binary(buildings, roads)

    OUT_META.parent.mkdir(parents=True, exist_ok=True)
    metadata = {
        "stage": 21,
        "region": "Malta",
        "anchor": {
            "name": "Malta International Airport runway 31 threshold",
            "latitude": ANCHOR_LAT,
            "longitude": ANCHOR_LON,
            "headingDegrees": ANCHOR_HEADING_DEG,
            "elevationMetersMSL": ANCHOR_ELEVATION_M,
        },
        "worldHalfExtentMeters": WORLD_HALF_M,
        "terrainResolution": TERRAIN_RESOLUTION,
        "terrainSpacingMeters": (WORLD_HALF_M * 2.0) / (TERRAIN_RESOLUTION - 1),
        "seaLevelLocalMeters": SEA_LEVEL_LOCAL_M,
        "buildingCount": len(buildings),
        "roadPolylineCount": len(roads),
        "sources": {
            "openStreetMap": PBF_URL,
            "osmLicense": "ODbL 1.0",
            "elevation": f"Mapzen/AWS Terrarium zoom {TERRARIUM_ZOOM}",
        },
        "binaryBytes": OUT_BIN.stat().st_size,
    }
    OUT_META.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    main()
