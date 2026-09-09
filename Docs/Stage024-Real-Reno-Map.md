# Stage 024 — Real Reno Map

Stage 024 replaces Full Authority's procedural test world with a 48 km × 48 km real-world region centered on the south threshold of KRNO runway 35L.

## Sources

- USGS 3DEP 1 arc-second DEM — public domain / no use restrictions.
- USGS The National Map `USGSImageryOnly` orthoimagery service — primarily USDA NAIP in CONUS.
- OpenStreetMap vectors via Geofabrik Nevada free extract — ODbL 1.0; attribution required.
- FAA AIP KRNO runway threshold coordinates, lengths/elevations.

## Runtime architecture

- `reno_dem.bin` is the sole terrain elevation database. Swift terrain rendering and the Objective-C++ JSBSim ground callback independently load the same file and use the same triangle interpolation.
- `reno_imagery.jpg` is a single macro orthoimage for high-altitude coherence. It is intentionally not used as close-range geometry.
- `reno_world.json` contains simplified real OSM building layout, road network and runway metadata. Buildings are batched into meshes by 4 km cells rather than instantiated as tens of thousands of RealityKit entities.
- Old Stage 019/020/023 procedural towns, parcels and scenery are bypassed whenever the Stage 024 package is present.

See `Assets/JSBSim/visuals/world/reno/ATTRIBUTION.txt` for redistribution/licensing details.
