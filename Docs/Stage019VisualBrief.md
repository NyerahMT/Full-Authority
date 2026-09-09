# Stage 019 — Professional Visual Pass

Stage 019 is a deliberate correction after the rejected Stage 018 visual-generation pass. The goal is not to give Full Authority a new look. The goal is to make the existing Stage 017 look feel authored, coherent, and expensive enough that the prototype stops advertising its procedural shortcuts.

## North star

**Cold military hardware in a believable, readable world.**

The aircraft remains the visual hero. The world supplies scale and context. Visual quality should come from geometry, material response, placement, lighting, and atmospheric depth rather than camera tricks or screen-space filters.

## Hard constraints

The following Stage 017 systems are treated as control samples and are not to be replaced during the first Stage 019 implementation pass:

- Chase / close / cockpit camera framing and attitude behavior.
- Stage 017 cloud cards and cloud placement strategy.
- Stage 017 contrail, maneuver-vapor, transonic-vapor, and afterburner behavior.
- JSBSim flight dynamics and `Stage2TerrainProfile` contact topology.
- No vignette, fake sun blob, chromatic aberration, speed lines, aggressive FOV pumping, detached horizon camera, or global cinematic color filter.

Any later modification to one of these systems must solve a documented visual problem and be independently reviewable.

## Problems observed in Stage 017

### 1. Terrain surface is physically flat-looking

The CC0 Poly Haven diffuse/roughness maps are good source material, but Stage 017 discards their normal maps. Terrain, runway, and apron therefore lose useful micro-surface response under directional light.

**Action:** add tangent-space GL normal-map support for the existing Poly Haven materials. Keep the current terrain mesh/FDM alignment.

### 2. Terrain palette and land use repeat procedurally

Ground scale cues use repeated rectangular color patches. At fighter altitude they read as generated tiles rather than fields, forest margins, and disturbed ground.

**Action:** reduce checkerboard regularity; group fields into larger agricultural parcels with varied orientation, spacing, and neutral natural colors. Add a second CC0 ground material for woodland/rough ground rather than manufacturing variation through yellow tinting.

### 3. Town reads as a debug grid

The current 8×10 box-building array has obvious repetition and no relationship to roads or land use.

**Action:** replace the uniform grid with a smaller, road-oriented settlement and an airbase-adjacent industrial cluster. Use a restrained subset of coherent CC0 building silhouettes or authored procedural families. Shared meshes/materials are mandatory.

### 4. Vegetation reads as repeated spikes

A single generated conifer mesh repeated in sinusoidal belts makes the placement algorithm visible.

**Action:** introduce 3–5 silhouette families, then place them in deterministic irregular clusters following terrain/land-use masks. Reuse mesh resources; no per-tree unique mesh creation.

### 5. F-16 surface is too uniform

The MIT FlightSim_F16 geometry is useful, but the upstream texture source contains no hidden high-detail livery. The current eight constant paint materials make the aircraft clean but visually sparse.

**Action:** preserve the matte PBR hierarchy and add only reference-supported large-scale surface cues: radome boundary, canopy-frame separation, major access-panel/seam breakup, subtle upper/lower tone variation, and restrained nozzle heat/weathering cues. Avoid random panel noise and invented pseudo-detail.

## Selected sources

### Existing CC0 Poly Haven materials

- Leafy Grass — https://polyhaven.com/a/leafy_grass
- Asphalt 02 — https://polyhaven.com/a/asphalt_02
- Concrete Floor 01 — https://polyhaven.com/a/concrete_floor_01

All provide GL normal maps in addition to diffuse and roughness maps.

### Additional CC0 ground reference/material

- Forest Ground 01 — https://polyhaven.com/a/forrest_ground_01
  - dry grass, leaf litter, twigs, mossy soil
  - diffuse, roughness and GL normal maps available

### CC0 environment asset candidates

- Kenney Nature Kit — https://kenney.nl/assets/nature-kit
  - CC0
  - 330+ optimized low-poly environment objects
  - candidate use is limited to silhouette variety for trees/bushes/rocks; materials will be brought into Full Authority's restrained palette rather than used as a bright low-poly art style.
- Kenney City Kit (Industrial) — https://kenney.nl/assets/city-kit-industrial
  - CC0
  - optimized factory/warehouse/building silhouettes
  - candidate use is limited to airbase-adjacent support/industrial massing.

### F-16 visual reference

- FlightSim_F16 — https://github.com/vazgriz/FlightSim_F16 (MIT), existing geometry source.
- DVIDS / USAF public-domain F-16 maintenance and flight-line imagery, including:
  - F-16 maintenance / walkaround footage: https://www.dvidshub.net/video/360254/177th-fighter-wing-f-16-maintenance
  - flight-line reference: https://www.dvidshub.net/video/587058/f-16-flight-line
  - canopy/radome/panel maintenance imagery: https://www.dvidshub.net/image/9076945/integrity-and-precision-non-destructive-inspection-technicians-ensure-aircraft-safety
  - hangar/flight-line context: https://www.dvidshub.net/image/3078632/flightline

DVIDS imagery is used as visual reference, not automatically copied into the shipped game.

## Mobile rendering budget

Target device is iPhone 15 Pro Max, with iOS 18 as the current deployment floor.

- Prefer shared `MeshResource` and material instances.
- Keep environment textures at 1K unless a visible failure justifies more.
- Avoid runtime network access.
- Avoid full-screen beta post effects for this stage.
- Avoid volumetric raymarching until the authored world itself looks correct.
- Reduce obvious repetition before increasing entity count.
- Any new asset family must justify its memory/render cost in the normal chase camera.

## Acceptance criteria

Stage 019 is not complete merely because it builds.

A successful branch should satisfy all of the following:

1. Stage 017 camera behavior is unchanged.
2. Stage 017 cloud/effect behavior is unchanged.
3. No yellow/orange global terrain cast is introduced.
4. Runway/apron/ground react to light with visibly richer micro-surface detail without looking wet or glossy.
5. Agricultural land no longer exposes a regular checkerboard generator from normal chase altitude.
6. Town/airbase structures read as placed environments rather than repeated boxes.
7. Vegetation distribution no longer reveals a repeated belt pattern.
8. F-16 remains matte and military; added detail is subtle enough to disappear naturally at distance rather than shimmer.
9. Simulator and iPhone device CI both succeed.
10. The branch remains unmerged until an on-device recording demonstrates a clear improvement over Stage 017.
