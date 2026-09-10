#!/usr/bin/env python3
from __future__ import annotations

import json
import math
import shutil
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import build_stage024_helsinki_mesh as base

CACHE = base.ROOT / ".cache" / "stage024-helsinki-v1"
RETRY_DELAYS = (2, 5, 12, 25, 45)


def cache_paths(code: str) -> tuple[Path, Path, Path]:
    tile_dir = CACHE / code
    return (
        tile_dir / f"helsinki_{code}.fhm",
        tile_dir / f"helsinki_{code}.jpg",
        tile_dir / "metadata.json",
    )


def load_cached(code: str, expected_lod: int):
    mesh_cache, atlas_cache, meta_cache = cache_paths(code)
    if not (mesh_cache.is_file() and atlas_cache.is_file() and meta_cache.is_file()):
        return None
    if mesh_cache.stat().st_size < 1024 or atlas_cache.stat().st_size < 1024:
        return None
    try:
        metadata = json.loads(meta_cache.read_text(encoding="utf-8"))
        if metadata.get("code") != code or int(metadata.get("lod", -1)) != expected_lod:
            return None
        minima = {
            (int(item[0]), int(item[1])): float(item[2])
            for item in metadata.get("minima", [])
        }
        if not minima:
            return None
    except Exception:
        return None

    base.OUT.mkdir(parents=True, exist_ok=True)
    shutil.copy2(mesh_cache, base.OUT / mesh_cache.name)
    shutil.copy2(atlas_cache, base.OUT / atlas_cache.name)
    base.log(f"{code}: cache hit, skipping source archive")
    return {
        "code": code,
        "lod": expected_lod,
        "mesh": mesh_cache.name,
        "texture": atlas_cache.name,
        "vertices": int(metadata["vertices"]),
        "triangles": int(metadata["triangles"]),
        "minima": minima,
    }


def save_cached(result) -> None:
    code = result["code"]
    mesh_cache, atlas_cache, meta_cache = cache_paths(code)
    mesh_cache.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(base.OUT / result["mesh"], mesh_cache)
    shutil.copy2(base.OUT / result["texture"], atlas_cache)
    payload = {
        "code": code,
        "lod": result["lod"],
        "vertices": result["vertices"],
        "triangles": result["triangles"],
        "minima": [[iz, ix, value] for (iz, ix), value in result["minima"].items()],
    }
    temp = meta_cache.with_suffix(".tmp")
    temp.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
    temp.replace(meta_cache)


def process_with_retry(easting: int, northing: int):
    code = base.source_code(easting, northing)
    lod = 16 if code in base.HIGH_DETAIL_CODES else 15
    cached = load_cached(code, lod)
    if cached is not None:
        return cached

    attempts = len(RETRY_DELAYS) + 1
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            # A failed range request can leave a partial output file. Never let a
            # retry mistake that partial file for a completed city block.
            for suffix in (".fhm", ".jpg"):
                (base.OUT / f"helsinki_{code}{suffix}").unlink(missing_ok=True)
            result = base.process_source_tile(easting, northing)
            save_cached(result)
            base.log(f"{code}: checkpoint saved")
            return result
        except Exception as exc:
            last_error = exc
            if attempt >= attempts:
                break
            delay = RETRY_DELAYS[attempt - 1]
            base.log(f"{code}: attempt {attempt}/{attempts} failed: {type(exc).__name__}: {exc}; retrying in {delay}s")
            time.sleep(delay)

    raise RuntimeError(f"{code}: exhausted {attempts} attempts: {last_error}") from last_error


def write_outputs(results) -> None:
    merged_minima: dict[tuple[int, int], float] = {}
    clean_results = []
    for result in results:
        minima = result["minima"]
        for key, value in minima.items():
            previous = merged_minima.get(key)
            if previous is None or value < previous:
                merged_minima[key] = value
        clean_results.append({k: v for k, v in result.items() if k != "minima"})

    grid, reference = base.fill_ground_grid(merged_minima)
    base.write_ground(grid, reference)
    clean_results.sort(key=lambda item: item["code"])

    manifest = {
        "name": "Helsinki 3D reality mesh benchmark",
        "source": "City of Helsinki Helsinki 3D reality mesh (2017)",
        "license": "CC BY 4.0",
        "sourceURL": "https://3d.hel.ninja/mesh/",
        "coordinateSystem": "EPSG:3879 source; recentered/rotated to EFHF RWY 36",
        "minX": base.MIN_X,
        "minZ": base.MIN_Z,
        "maxX": base.MAX_X,
        "maxZ": base.MAX_Z,
        "referenceElevationMeters": reference,
        "runwayLengthMeters": math.hypot(base.RUNWAY18_E - base.RUNWAY36_E, base.RUNWAY18_N - base.RUNWAY36_N),
        "runwayHeadingTrueDegrees": math.degrees(base.RUNWAY_HEADING),
        "tiles": clean_results,
    }
    (base.OUT / "helsinki_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    (base.OUT / "ATTRIBUTION.txt").write_text(
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

    total_mesh = sum((base.OUT / r["mesh"]).stat().st_size for r in clean_results)
    total_tex = sum((base.OUT / r["texture"]).stat().st_size for r in clean_results)
    total = sum(p.stat().st_size for p in base.OUT.iterdir() if p.is_file())
    base.log(
        f"complete: {len(clean_results)} blocks, ref {reference:.2f} m, "
        f"mesh {total_mesh/1048576:.1f} MiB, textures {total_tex/1048576:.1f} MiB, "
        f"package {total/1048576:.1f} MiB"
    )


def main() -> None:
    # Final output is reproducible from checkpoints; clear it without touching CACHE.
    if base.OUT.exists():
        shutil.rmtree(base.OUT)
    base.OUT.mkdir(parents=True, exist_ok=True)
    CACHE.mkdir(parents=True, exist_ok=True)

    jobs = [
        (easting, northing)
        for northing in range(base.SOURCE_MIN_N, base.SOURCE_MAX_N, base.SOURCE_STEP)
        for easting in range(base.SOURCE_MIN_E, base.SOURCE_MAX_E, base.SOURCE_STEP)
    ]
    base.log(f"resumable build: {len(jobs)} official 2 km blocks")

    results = []
    failures = []
    with ThreadPoolExecutor(max_workers=4) as pool:
        future_map = {pool.submit(process_with_retry, e, n): (e, n) for e, n in jobs}
        for future in as_completed(future_map):
            try:
                results.append(future.result())
            except Exception as exc:
                failures.append(str(exc))
                base.log(f"FAILED BLOCK: {exc}")

    if failures:
        # Waited for every worker above on purpose: maximize completed checkpoints
        # before failing the workflow and saving the Actions cache.
        raise RuntimeError(f"{len(failures)} Helsinki block(s) failed after retries: " + " | ".join(failures))

    if len(results) != len(jobs):
        raise RuntimeError(f"expected {len(jobs)} completed blocks, got {len(results)}")
    write_outputs(results)


if __name__ == "__main__":
    main()
