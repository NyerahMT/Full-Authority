#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import math
import os
import re
import struct
import sys
import zipfile
from pathlib import Path

import geopandas as gpd
import numpy as np
import requests
import rasterio
from PIL import Image
from pyproj import Transformer
from rasterio.transform import from_origin
from rasterio.warp import Resampling, reproject
from shapely.geometry import LineString, MultiLineString, MultiPolygon, Polygon, box

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Assets/JSBSim/visuals/world/reno"
CACHE = ROOT / ".stage024-cache"
OUT.mkdir(parents=True, exist_ok=True)
CACHE.mkdir(parents=True, exist_ok=True)

# Reno/Tahoe International RWY 35L threshold. FAA AIP coordinates/elevation.
ORIGIN_LAT = 39.48364825
ORIGIN_LON = -119.76929861111111
REFERENCE_ELEVATION_M = 4414.5 * 0.3048
CRS_UTM = "EPSG:32611"
CELL = 40.0
MIN_X, MAX_X = -24_000.0, 24_000.0
MIN_Z, MAX_Z = -16_000.0, 32_000.0
MAX_BUILDINGS = 35_000
IMAGERY_SIZE = 4096

WGS_TO_UTM = Transformer.from_crs("EPSG:4326", CRS_UTM, always_xy=True)
UTM_TO_WGS = Transformer.from_crs(CRS_UTM, "EPSG:4326", always_xy=True)
ORIGIN_E, ORIGIN_N = WGS_TO_UTM.transform(ORIGIN_LON, ORIGIN_LAT)

# FAA AIP runway threshold coordinates/elevations. Coordinates are true-world
# geometry; the local Full Authority map keeps east = +X and north = +Z.
RUNWAYS = [
    {
        "name": "35L-17R",
        "start": (39.48364825, -119.76929861111111, 4414.5),
        "end": (39.51384391666667, -119.76922047222222, 4414.8),
        "width": 150 * 0.3048,
    },
    {
        "name": "35R-17L",
        "start": (39.48913747222222, -119.76680475, 4408.3),
        "end": (39.5138405, -119.76674055555556, 4414.8),
        "width": 150 * 0.3048,
    },
    {
        "name": "08-26",
        "start": (39.49628608333333, -119.77883944444445, 4409.2),
        "end": (39.49621497222222, -119.7572216111111, 4399.6),
        "width": 150 * 0.3048,
    },
]


def log(message: str) -> None:
    print(f"[stage024] {message}", flush=True)


def download(url: str, destination: Path, params=None, timeout=240) -> Path:
    if destination.exists() and destination.stat().st_size > 1024:
        return destination
    log(f"download {url}")
    with requests.get(url, params=params, stream=True, timeout=timeout) as response:
        response.raise_for_status()
        content_type = response.headers.get("content-type", "")
        if "json" in content_type and destination.suffix.lower() in {".jpg", ".tif", ".zip"}:
            raise RuntimeError(f"unexpected JSON response for {url}: {response.text[:500]}")
        with destination.open("wb") as handle:
            for chunk in response.iter_content(chunk_size=1024 * 1024):
                if chunk:
                    handle.write(chunk)
    return destination


def local_to_lonlat(x: float, z: float):
    return UTM_TO_WGS.transform(ORIGIN_E + x, ORIGIN_N + z)


def lonlat_bbox():
    corners = [
        local_to_lonlat(MIN_X, MIN_Z),
        local_to_lonlat(MIN_X, MAX_Z),
        local_to_lonlat(MAX_X, MIN_Z),
        local_to_lonlat(MAX_X, MAX_Z),
    ]
    lons = [p[0] for p in corners]
    lats = [p[1] for p in corners]
    return min(lons), min(lats), max(lons), max(lats)


def local_xy_from_lonlat(lon: float, lat: float):
    e, n = WGS_TO_UTM.transform(lon, lat)
    return float(e - ORIGIN_E), float(n - ORIGIN_N)


def runway_records():
    output = []
    for runway in RUNWAYS:
        slat, slon, selev_ft = runway["start"]
        elat, elon, eelev_ft = runway["end"]
        sx, sz = local_xy_from_lonlat(slon, slat)
        ex, ez = local_xy_from_lonlat(elon, elat)
        output.append(
            {
                "name": runway["name"],
                "startX": round(sx, 3),
                "startZ": round(sz, 3),
                "endX": round(ex, 3),
                "endZ": round(ez, 3),
                "width": round(runway["width"], 3),
                "startElevM": selev_ft * 0.3048,
                "endElevM": eelev_ft * 0.3048,
            }
        )
    return output


def get_usgs_dem() -> Path:
    # Our 48 km KRNO box sits inside the n40w120 1-degree tile. Try the current
    # staged 3DEP path first; fall back to TNMAccess so the pipeline survives a
    # future storage layout change.
    current = "https://prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/1/TIFF/current/n40w120/USGS_1_n40w120.tif"
    target = CACHE / "USGS_1_n40w120.tif"
    try:
        return download(current, target)
    except Exception as exc:
        log(f"direct 3DEP path failed ({exc}); querying TNMAccess")

    minlon, minlat, maxlon, maxlat = lonlat_bbox()
    params = {
        "bbox": f"{minlon},{minlat},{maxlon},{maxlat}",
        "datasets": "National Elevation Dataset (NED) 1 arc-second",
        "prodFormats": "GeoTIFF",
        "max": 50,
    }
    response = requests.get("https://tnmaccess.nationalmap.gov/api/v1/products", params=params, timeout=120)
    response.raise_for_status()
    items = response.json().get("items", [])
    candidates = []
    for item in items:
        title = item.get("title", "")
        urls = []
        direct = item.get("downloadURL")
        if isinstance(direct, str):
            urls.append(direct)
        for f in item.get("files", []) or []:
            if isinstance(f, dict) and isinstance(f.get("url"), str):
                urls.append(f["url"])
        for url in urls:
            if url.lower().endswith((".tif", ".tiff")) and "n40w120" in (title + " " + url).lower():
                candidates.append((title, url))
    if not candidates:
        raise RuntimeError("TNMAccess returned no n40w120 1 arc-second GeoTIFF")
    # The API generally returns newest first. Prefer URLs that explicitly say current.
    candidates.sort(key=lambda pair: ("/current/" not in pair[1], pair[0]))
    return download(candidates[0][1], target)


def build_dem() -> np.ndarray:
    source_path = get_usgs_dem()
    width = int(round((MAX_X - MIN_X) / CELL)) + 1
    height = int(round((MAX_Z - MIN_Z) / CELL)) + 1
    destination = np.full((height, width), np.nan, dtype=np.float32)
    # Shift the raster transform half a cell so pixel centers equal the exact mesh vertices.
    target_transform = from_origin(
        ORIGIN_E + MIN_X - CELL * 0.5,
        ORIGIN_N + MAX_Z + CELL * 0.5,
        CELL,
        CELL,
    )

    with rasterio.open(source_path) as src:
        reproject(
            source=rasterio.band(src, 1),
            destination=destination,
            src_transform=src.transform,
            src_crs=src.crs,
            src_nodata=src.nodata,
            dst_transform=target_transform,
            dst_crs=CRS_UTM,
            dst_nodata=np.nan,
            resampling=Resampling.bilinear,
        )

    destination = np.flipud(destination)  # row zero = MIN_Z for game interpolation
    if np.isnan(destination).any():
        median = float(np.nanmedian(destination))
        destination = np.nan_to_num(destination, nan=median)

    xs = MIN_X + np.arange(width, dtype=np.float32) * CELL
    zs = MIN_Z + np.arange(height, dtype=np.float32) * CELL
    xx, zz = np.meshgrid(xs, zs)

    # Flatten the three real KRNO runway corridors to FAA threshold elevations,
    # with a soft shoulder blend. Visual mesh and JSBSim both use this baked grid.
    for runway in runway_records():
        ax, az = runway["startX"], runway["startZ"]
        bx, bz = runway["endX"], runway["endZ"]
        dx, dz = bx - ax, bz - az
        length2 = dx * dx + dz * dz
        t = np.clip(((xx - ax) * dx + (zz - az) * dz) / max(length2, 1.0), 0.0, 1.0)
        px = ax + t * dx
        pz = az + t * dz
        distance = np.sqrt((xx - px) ** 2 + (zz - pz) ** 2)
        half_width = runway["width"] * 0.5
        blend_radius = half_width + 55.0
        weight = np.clip((blend_radius - distance) / max(blend_radius - half_width, 1.0), 0.0, 1.0)
        target = runway["startElevM"] + t * (runway["endElevM"] - runway["startElevM"])
        destination = destination * (1 - weight) + target * weight

    header = struct.pack(
        "<4sIIIffff",
        b"FAM2",
        1,
        width,
        height,
        CELL,
        MIN_X,
        MIN_Z,
        REFERENCE_ELEVATION_M,
    )
    with (OUT / "reno_dem.bin").open("wb") as handle:
        handle.write(header)
        handle.write(destination.astype("<f4", copy=False).tobytes(order="C"))

    log(f"DEM {width}x{height}, {destination.min():.1f}..{destination.max():.1f} m")
    return destination


def export_usgs_imagery() -> None:
    path = OUT / "reno_imagery.jpg"
    if path.exists() and path.stat().st_size > 100_000:
        return
    bbox = f"{ORIGIN_E + MIN_X},{ORIGIN_N + MIN_Z},{ORIGIN_E + MAX_X},{ORIGIN_N + MAX_Z}"
    params = {
        "bbox": bbox,
        "bboxSR": "32611",
        "imageSR": "32611",
        "size": f"{IMAGERY_SIZE},{IMAGERY_SIZE}",
        "format": "jpg",
        "transparent": "false",
        "dpi": "96",
        "f": "image",
    }
    temp = CACHE / "reno_usgs_export.jpg"
    download(
        "https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/MapServer/export",
        temp,
        params=params,
    )
    with Image.open(temp) as image:
        image = image.convert("RGB")
        if image.size != (IMAGERY_SIZE, IMAGERY_SIZE):
            image = image.resize((IMAGERY_SIZE, IMAGERY_SIZE), Image.Resampling.LANCZOS)
        image.save(path, "JPEG", quality=88, optimize=True, progressive=True)
    log(f"USGS orthoimagery {path.stat().st_size / 1024 / 1024:.1f} MiB")


def extract_geofabrik() -> Path:
    archive = CACHE / "nevada-latest-free.shp.zip"
    download("https://download.geofabrik.de/north-america/us/nevada-latest-free.shp.zip", archive, timeout=600)
    folder = CACHE / "nevada-shp"
    marker = folder / ".done"
    if not marker.exists():
        folder.mkdir(exist_ok=True)
        log("extract Geofabrik Nevada shapefiles")
        with zipfile.ZipFile(archive) as zf:
            zf.extractall(folder)
        marker.touch()
    return folder


def find_shapefile(folder: Path, name: str) -> Path:
    matches = list(folder.rglob(name))
    if not matches:
        raise FileNotFoundError(name)
    return matches[0]


def read_layer(path: Path, bbox_wgs84):
    try:
        gdf = gpd.read_file(path, bbox=bbox_wgs84, engine="pyogrio")
    except Exception:
        gdf = gpd.read_file(path, bbox=bbox_wgs84)
    if gdf.empty:
        return gdf
    return gdf.to_crs(CRS_UTM)


def deterministic_unit(value) -> float:
    digest = hashlib.blake2b(str(value).encode("utf-8"), digest_size=8).digest()
    return int.from_bytes(digest, "little") / float(2**64 - 1)


def rectangle_from_polygon(poly: Polygon):
    if poly.is_empty or poly.area < 25:
        return None
    rect = poly.minimum_rotated_rectangle
    coords = list(rect.exterior.coords)[:4]
    if len(coords) != 4:
        return None
    e0 = np.array(coords[1]) - np.array(coords[0])
    e1 = np.array(coords[2]) - np.array(coords[1])
    l0 = float(np.linalg.norm(e0))
    l1 = float(np.linalg.norm(e1))
    if l0 < 1 or l1 < 1:
        return None
    if l0 >= l1:
        width, depth = l0, l1
        vector = e0
    else:
        width, depth = l1, l0
        vector = e1
    yaw = math.atan2(float(vector[1]), float(vector[0]))
    center = rect.centroid
    return center.x - ORIGIN_E, center.y - ORIGIN_N, width, depth, yaw


def infer_building_height(name: str, area: float, x: float, z: float, seed) -> tuple[float, int]:
    r = deterministic_unit(seed)
    lowered = (name or "").lower()
    landmarks = {
        "silver legacy": 125.0,
        "grand sierra": 115.0,
        "peppermill": 75.0,
        "atlantis": 65.0,
        "circus circus": 70.0,
        "eldorado": 90.0,
    }
    for key, height in landmarks.items():
        if key in lowered:
            return height, 2

    # Reno downtown lies roughly four km north-west of the runway threshold.
    downtown_lon, downtown_lat = -119.8138, 39.5296
    dx, dz = local_xy_from_lonlat(downtown_lon, downtown_lat)
    downtown_distance = math.hypot(x - dx, z - dz)

    if downtown_distance < 1_900:
        height = 11 + r * 28 + min(math.sqrt(max(area, 1)) * 0.22, 28)
        return min(height, 72), 2
    if area > 2_800:
        return 8 + r * 11, 1
    if area > 900:
        return 7 + r * 9, 3
    return 4.0 + r * 5.5, 0


def build_osm_vectors():
    folder = extract_geofabrik()
    minlon, minlat, maxlon, maxlat = lonlat_bbox()
    bbox_wgs = (minlon, minlat, maxlon, maxlat)
    clip_box = box(ORIGIN_E + MIN_X, ORIGIN_N + MIN_Z, ORIGIN_E + MAX_X, ORIGIN_N + MAX_Z)

    buildings_path = find_shapefile(folder, "gis_osm_buildings_a_free_1.shp")
    roads_path = find_shapefile(folder, "gis_osm_roads_free_1.shp")

    buildings_gdf = read_layer(buildings_path, bbox_wgs)
    if not buildings_gdf.empty:
        buildings_gdf = buildings_gdf.explode(index_parts=False, ignore_index=True)

    building_records = []
    for idx, row in buildings_gdf.iterrows():
        geom = row.geometry
        if not isinstance(geom, Polygon) or geom.is_empty:
            continue
        if not geom.intersects(clip_box):
            continue
        geom = geom.intersection(clip_box)
        if not isinstance(geom, Polygon) or geom.area < 30:
            continue
        rect = rectangle_from_polygon(geom)
        if rect is None:
            continue
        x, z, width, depth, yaw = rect
        if not (MIN_X <= x <= MAX_X and MIN_Z <= z <= MAX_Z):
            continue
        area = float(geom.area)
        name = str(row.get("name") or "")
        osm_id = row.get("osm_id", idx)
        height, material = infer_building_height(name, area, x, z, osm_id)
        building_records.append(
            {
                "x": round(float(x), 1),
                "z": round(float(z), 1),
                "width": round(float(min(width, 320)), 1),
                "depth": round(float(min(depth, 320)), 1),
                "yaw": round(float(yaw), 4),
                "height": round(float(height), 1),
                "material": int(material),
                "_area": area,
            }
        )

    # If the full metro extract is larger than our mobile budget, preserve the
    # central city first, then larger outer structures. This retains a real city
    # silhouette rather than random uniform sampling.
    if len(building_records) > MAX_BUILDINGS:
        downtown_x, downtown_z = local_xy_from_lonlat(-119.8138, 39.5296)
        building_records.sort(
            key=lambda b: (
                math.hypot(b["x"] - downtown_x, b["z"] - downtown_z) > 10_000,
                math.hypot(b["x"] - downtown_x, b["z"] - downtown_z) - min(b["_area"], 5_000) * 0.15,
            )
        )
        building_records = building_records[:MAX_BUILDINGS]
    for b in building_records:
        b.pop("_area", None)

    roads_gdf = read_layer(roads_path, bbox_wgs)
    road_records = []
    class_map = {
        "motorway": (3, 20.0, 3.0),
        "motorway_link": (3, 12.0, 3.0),
        "trunk": (0, 15.0, 4.0),
        "trunk_link": (0, 10.0, 4.0),
        "primary": (0, 13.0, 5.0),
        "primary_link": (0, 9.0, 5.0),
        "secondary": (1, 10.0, 6.0),
        "tertiary": (1, 8.0, 7.0),
        "residential": (2, 6.0, 9.0),
        "living_street": (2, 5.0, 10.0),
        "service": (2, 5.0, 10.0),
        "unclassified": (2, 5.0, 10.0),
    }

    def append_line(line: LineString, kind: int, width: float, tolerance: float):
        line = line.intersection(clip_box)
        if line.is_empty:
            return
        parts = list(line.geoms) if isinstance(line, MultiLineString) else [line]
        for part in parts:
            if not isinstance(part, LineString) or part.length < 12:
                continue
            part = part.simplify(tolerance, preserve_topology=False)
            coords = list(part.coords)
            if len(coords) < 2:
                continue
            points = []
            for e, n in coords:
                points.extend([round(float(e - ORIGIN_E), 1), round(float(n - ORIGIN_N), 1)])
            road_records.append({"width": width, "kind": kind, "points": points})

    for _, row in roads_gdf.iterrows():
        fclass = str(row.get("fclass") or row.get("type") or "").lower()
        if fclass not in class_map:
            continue
        kind, width, tolerance = class_map[fclass]
        geom = row.geometry
        if isinstance(geom, LineString):
            append_line(geom, kind, width, tolerance)
        elif isinstance(geom, MultiLineString):
            for line in geom.geoms:
                append_line(line, kind, width, tolerance)

    # Airport-specific OSM taxiways are small enough for Overpass and materially
    # improve the airport read versus inventing taxiway geometry.
    try:
        query = """[out:json][timeout:90];(way[\"aeroway\"=\"taxiway\"](39.47,-119.79,39.52,-119.74););out tags geom;"""
        response = requests.post("https://overpass-api.de/api/interpreter", data={"data": query}, timeout=120)
        response.raise_for_status()
        for element in response.json().get("elements", []):
            geometry = element.get("geometry") or []
            if len(geometry) < 2:
                continue
            points = []
            for p in geometry:
                x, z = local_xy_from_lonlat(float(p["lon"]), float(p["lat"]))
                points.extend([round(x, 1), round(z, 1)])
            road_records.append({"width": 15.0, "kind": 4, "points": points})
    except Exception as exc:
        log(f"Overpass taxiways unavailable, continuing with Geofabrik roads: {exc}")

    log(f"OSM vectors: {len(building_records)} buildings, {len(road_records)} road/taxiway ways")
    return building_records, road_records


def write_world_json(buildings, roads):
    document = {
        "name": "Reno / Tahoe International and Reno-Sparks",
        "minX": MIN_X,
        "minZ": MIN_Z,
        "maxX": MAX_X,
        "maxZ": MAX_Z,
        "referenceElevationMeters": REFERENCE_ELEVATION_M,
        "buildings": buildings,
        "roads": roads,
        "runways": [
            {k: v for k, v in r.items() if k not in {"startElevM", "endElevM"}}
            for r in runway_records()
        ],
    }
    (OUT / "reno_world.json").write_text(json.dumps(document, separators=(",", ":")), encoding="utf-8")

    attribution = """FULL AUTHORITY — STAGE 024 REAL-WORLD MAP DATA\n\nMap/vector data: © OpenStreetMap contributors, Open Database License (ODbL) 1.0.\nExtract source: Geofabrik Nevada free extract.\nhttps://www.openstreetmap.org/copyright\nhttps://download.geofabrik.de/north-america/us/nevada.html\n\nElevation: U.S. Geological Survey 3D Elevation Program (3DEP) 1 arc-second DEM. Public domain / no use restrictions.\nhttps://www.usgs.gov/3d-elevation-program\n\nOrthoimagery: USGS The National Map USGSImageryOnly service, primarily USDA NAIP for CONUS. Public-domain imagery sources as described by the service.\nhttps://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/MapServer\n\nAirport geometry/reference: Federal Aviation Administration AIP, Reno/Tahoe International (KRNO).\n\nThe generated reno_world.json is derived from OpenStreetMap data and is distributed under ODbL 1.0.\n"""
    (OUT / "ATTRIBUTION.txt").write_text(attribution, encoding="utf-8")


def patch_sources():
    # World factory: when the real package exists, do not instantiate any of the
    # old procedural terrain, random towns, roads, fields or props.
    world = ROOT / "App/Stage2WorldFactory.swift"
    text = world.read_text(encoding="utf-8")
    old = '''        addTerrain(to: root)\n        addCloudscape(to: root)\n        addAirbase(to: root)\n        addRoads(to: root)\n        addStage019Environment(to: root)\n        root.addChild(Stage020WorldUpgrade.make())\n        root.addChild(Stage023TerrainSystem.make())\n\n        return root\n'''
    new = '''        if Stage024RealMapData.shared.isLoaded {\n            root.addChild(Stage024RealMapWorld.make())\n            addCloudscape(to: root)\n            return root\n        }\n\n        // Development fallback only. Shipping Stage 024 builds include the Reno\n        // package and never instantiate these older procedural scenery layers.\n        addTerrain(to: root)\n        addCloudscape(to: root)\n        addAirbase(to: root)\n        addRoads(to: root)\n        addStage019Environment(to: root)\n        root.addChild(Stage020WorldUpgrade.make())\n        root.addChild(Stage023TerrainSystem.make())\n        return root\n'''
    if old not in text:
        raise RuntimeError("Stage2WorldFactory make anchor not found")
    world.write_text(text.replace(old, new, 1), encoding="utf-8")

    sim = ROOT / "Simulation/FlightSimulation.swift"
    text = sim.read_text(encoding="utf-8")
    profile_pattern = re.compile(r'enum Stage2TerrainProfile \{.*?\n\}\n\n@MainActor\nfinal class FlightSimulation', re.S)
    replacement = '''enum Stage2TerrainProfile {\n    static func heightMeters(east: Float, north: Float) -> Float {\n        let map = Stage024RealMapData.shared\n        return map.isLoaded ? map.relativeHeight(east: east, north: north) : 0\n    }\n\n    static func normal(east: Float, north: Float) -> SIMD3<Float> {\n        let map = Stage024RealMapData.shared\n        return map.isLoaded ? map.normal(east: east, north: north) : SIMD3<Float>(0, 1, 0)\n    }\n}\n\n@MainActor\nfinal class FlightSimulation'''
    text, count = profile_pattern.subn(replacement, text, count=1)
    if count != 1:
        raise RuntimeError("Stage2TerrainProfile replacement failed")
    old_y = '        state.positionMeters.y = state.altitudeFeetMSL * feetToMeters\n'
    new_y = '''        // JSBSim keeps real Reno MSL altitude while RealityKit renders around\n        // a local airport-height origin to preserve floating-point precision.\n        state.positionMeters.y = state.altitudeFeetMSL * feetToMeters\n            - Stage024RealMapData.shared.referenceElevationMeters\n'''
    if old_y not in text:
        raise RuntimeError("FlightSimulation altitude anchor not found")
    sim.write_text(text.replace(old_y, new_y, 1), encoding="utf-8")

    bridge = ROOT / "Simulation/Bridge/FAJSBSimBridge.mm"
    text = bridge.read_text(encoding="utf-8")
    text = text.replace('#include <exception>\n', '#include <exception>\n#include <cstdint>\n#include <fstream>\n#include <vector>\n')
    pattern = re.compile(r'double FATerrainAnalyticHeightMeters\(double eastMeters, double northMeters\) \{.*?\n\}\n\nextern "C" double FATerrainHeightMeters\(double eastMeters, double northMeters\) \{.*?\n\}\n\n@interface FAJSBSimBridge', re.S)
    replacement = r'''struct FATerrainGrid {
    bool loaded = false;
    uint32_t width = 0;
    uint32_t height = 0;
    float cell = 40.0f;
    float minX = 0.0f;
    float minZ = 0.0f;
    float referenceElevation = 0.0f;
    std::vector<float> samples;

    bool Load(const std::string& path) {
        std::ifstream stream(path, std::ios::binary);
        if (!stream) return false;
        char magic[4] = {};
        uint32_t version = 0;
        stream.read(magic, 4);
        stream.read(reinterpret_cast<char*>(&version), sizeof(version));
        stream.read(reinterpret_cast<char*>(&width), sizeof(width));
        stream.read(reinterpret_cast<char*>(&height), sizeof(height));
        stream.read(reinterpret_cast<char*>(&cell), sizeof(cell));
        stream.read(reinterpret_cast<char*>(&minX), sizeof(minX));
        stream.read(reinterpret_cast<char*>(&minZ), sizeof(minZ));
        stream.read(reinterpret_cast<char*>(&referenceElevation), sizeof(referenceElevation));
        if (!stream || std::string(magic, 4) != "FAM2" || version != 1 || width < 2 || height < 2 || cell <= 0.0f) {
            loaded = false;
            return false;
        }
        samples.resize(static_cast<size_t>(width) * static_cast<size_t>(height));
        stream.read(reinterpret_cast<char*>(samples.data()), static_cast<std::streamsize>(samples.size() * sizeof(float)));
        loaded = static_cast<bool>(stream);
        return loaded;
    }

    double Height(double eastMeters, double northMeters) const {
        if (!loaded || samples.empty()) return 0.0;
        const double gx = (eastMeters - minX) / cell;
        const double gz = (northMeters - minZ) / cell;
        const int ix = std::clamp(static_cast<int>(std::floor(gx)), 0, static_cast<int>(width) - 2);
        const int iz = std::clamp(static_cast<int>(std::floor(gz)), 0, static_cast<int>(height) - 2);
        const double tx = std::clamp(gx - ix, 0.0, 1.0);
        const double tz = std::clamp(gz - iz, 0.0, 1.0);
        const size_t i00 = static_cast<size_t>(iz) * width + static_cast<size_t>(ix);
        const size_t i10 = i00 + 1;
        const size_t i01 = static_cast<size_t>(iz + 1) * width + static_cast<size_t>(ix);
        const size_t i11 = i01 + 1;
        const double h00 = samples[i00];
        const double h10 = samples[i10];
        const double h01 = samples[i01];
        const double h11 = samples[i11];
        if (tx + tz <= 1.0) {
            return h00 + tx * (h10 - h00) + tz * (h01 - h00);
        }
        return h11 + (1.0 - tz) * (h10 - h11) + (1.0 - tx) * (h01 - h11);
    }
};

FATerrainGrid gTerrainGrid;

extern "C" double FATerrainHeightMeters(double eastMeters, double northMeters) {
    return gTerrainGrid.Height(eastMeters, northMeters);
}

@interface FAJSBSimBridge'''
    text, count = pattern.subn(replacement, text, count=1)
    if count != 1:
        raise RuntimeError("FAJSBSimBridge terrain replacement failed")

    init_anchor = '''        _rootPath = [rootPath copy];\n        _deltaTime = 1.0 / 120.0;\n        [self rebuildExecutive];\n'''
    init_replacement = '''        _rootPath = [rootPath copy];\n        _deltaTime = 1.0 / 120.0;\n        const std::string terrainPath = std::string(_rootPath.UTF8String ?: "") + "/visuals/world/reno/reno_dem.bin";\n        gTerrainGrid.Load(terrainPath);\n        [self rebuildExecutive];\n'''
    if init_anchor not in text:
        raise RuntimeError("bridge init anchor not found")
    bridge.write_text(text.replace(init_anchor, init_replacement, 1), encoding="utf-8")

    # Add Stage024 Swift source to Xcode.
    project = ROOT / "FullAuthority.xcodeproj/project.pbxproj"
    text = project.read_text(encoding="utf-8")
    if "Stage024RealMap.swift in Sources" not in text:
        build_anchor = '\t\tFA0230000000000000000001 /* Stage023TerrainSystem.swift in Sources */ = {isa = PBXBuildFile; fileRef = FA0230000000000000000011 /* Stage023TerrainSystem.swift */; };\n'
        file_anchor = '\t\tFA0230000000000000000011 /* Stage023TerrainSystem.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Stage023TerrainSystem.swift; sourceTree = "<group>"; };\n'
        group_anchor = '\t\t\t\tFA0230000000000000000011 /* Stage023TerrainSystem.swift */,\n'
        phase_anchor = '\t\t\t\tFA0230000000000000000001 /* Stage023TerrainSystem.swift in Sources */,\n'
        for anchor, replacement_text in [
            (build_anchor, build_anchor + '\t\tFA0240000000000000000001 /* Stage024RealMap.swift in Sources */ = {isa = PBXBuildFile; fileRef = FA0240000000000000000011 /* Stage024RealMap.swift */; };\n'),
            (file_anchor, file_anchor + '\t\tFA0240000000000000000011 /* Stage024RealMap.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Stage024RealMap.swift; sourceTree = "<group>"; };\n'),
            (group_anchor, group_anchor + '\t\t\t\tFA0240000000000000000011 /* Stage024RealMap.swift */,\n'),
            (phase_anchor, phase_anchor + '\t\t\t\tFA0240000000000000000001 /* Stage024RealMap.swift in Sources */,\n'),
        ]:
            if anchor not in text:
                raise RuntimeError(f"project anchor missing: {anchor.strip()}")
            text = text.replace(anchor, replacement_text, 1)
        project.write_text(text, encoding="utf-8")

    # Required OSM attribution in the in-app credits.
    menu = ROOT / "App/Stage022MainMenu.swift"
    text = menu.read_text(encoding="utf-8")
    old = 'Text("Flight dynamics: JSBSim. Aircraft geometry and world assets retain their in-repository source/license notices. Stage 022 menu scene reuses the same game renderer rather than a prerecorded background.")'
    new = 'Text("Flight dynamics: JSBSim. Reno map/vector data © OpenStreetMap contributors (ODbL). Elevation and orthoimagery: USGS The National Map / 3DEP public-domain sources. Aircraft and other assets retain their in-repository notices.")'
    if old in text:
        text = text.replace(old, new, 1)
    menu.write_text(text, encoding="utf-8")


def write_docs():
    doc = ROOT / "Docs/Stage024-Real-Reno-Map.md"
    doc.write_text(
        """# Stage 024 — Real Reno Map\n\nStage 024 replaces Full Authority's procedural test world with a 48 km × 48 km real-world region centered on the south threshold of KRNO runway 35L.\n\n## Sources\n\n- USGS 3DEP 1 arc-second DEM — public domain / no use restrictions.\n- USGS The National Map `USGSImageryOnly` orthoimagery service — primarily USDA NAIP in CONUS.\n- OpenStreetMap vectors via Geofabrik Nevada free extract — ODbL 1.0; attribution required.\n- FAA AIP KRNO runway threshold coordinates, lengths/elevations.\n\n## Runtime architecture\n\n- `reno_dem.bin` is the sole terrain elevation database. Swift terrain rendering and the Objective-C++ JSBSim ground callback independently load the same file and use the same triangle interpolation.\n- `reno_imagery.jpg` is a single macro orthoimage for high-altitude coherence. It is intentionally not used as close-range geometry.\n- `reno_world.json` contains simplified real OSM building layout, road network and runway metadata. Buildings are batched into meshes by 4 km cells rather than instantiated as tens of thousands of RealityKit entities.\n- Old Stage 019/020/023 procedural towns, parcels and scenery are bypassed whenever the Stage 024 package is present.\n\nSee `Assets/JSBSim/visuals/world/reno/ATTRIBUTION.txt` for redistribution/licensing details.\n""",
        encoding="utf-8",
    )


def main():
    export_usgs_imagery()
    build_dem()
    buildings, roads = build_osm_vectors()
    write_world_json(buildings, roads)
    patch_sources()
    write_docs()
    log("Stage 024 real map package complete")


if __name__ == "__main__":
    main()
