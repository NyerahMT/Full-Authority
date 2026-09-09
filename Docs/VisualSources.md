# Full Authority Visual Sources

Full Authority uses a source-first visual pipeline: permissively licensed assets and published rendering references are preferred over rebuilding solved art/graphics problems from scratch.

## Stage 016 imported assets

The following textures are imported from **Poly Haven** through its public API at development/build time. Poly Haven assets are **CC0**. The app does not contact Poly Haven at runtime.

- `runway_asphalt`: https://polyhaven.com/a/asphalt_02
  - diffuse source: https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/asphalt_02/asphalt_02_diff_1k.jpg
  - roughness source: https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/asphalt_02/asphalt_02_rough_1k.jpg
- `terrain_grass`: https://polyhaven.com/a/leafy_grass
  - diffuse source: https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/leafy_grass/leafy_grass_diff_1k.jpg
  - roughness source: https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/leafy_grass/leafy_grass_rough_1k.jpg
- `apron_concrete`: https://polyhaven.com/a/concrete_floor_01
  - diffuse source: https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/concrete_floor_01/concrete_floor_01_diff_1k.jpg
  - roughness source: https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/concrete_floor_01/concrete_floor_01_rough_1k.jpg

Poly Haven license: https://polyhaven.com/license
Poly Haven API: https://api.polyhaven.com/

## Aircraft source

The current external F-16 geometry is derived from Ryan Vazquez's `FlightSim_F16`, which is MIT-licensed. Its license is already bundled at `Assets/JSBSim/visuals/f16/LICENSE-FlightSim_F16.txt`.

Source: https://github.com/vazgriz/FlightSim_F16

## Rendering references

- Eric Bruneton & Fabrice Neyret, *Precomputed Atmospheric Scattering* (2008): https://inria.hal.science/inria-00288758/document
- Eric Bruneton's BSD reference implementation: https://github.com/ebruneton/precomputed_atmospheric_scattering
- Khronos glTF 2.0 metallic/roughness PBR material model: https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html
- Apple RealityKit PBR and environment-lighting documentation: https://developer.apple.com/documentation/realitykit/physicallybasedmaterial

Stage 016 uses these references for material hierarchy, sky palette/aerial-perspective cues, and lighting structure. It does not vendor Bruneton's renderer; a Metal atmosphere implementation can be evaluated later if the stylized pass needs true distance-dependent scattering.

## Stage 017 cloudscape

Cloud sprites are from WickedInsignia's **Clouds with Transparency** pack on OpenGameArt, released under **CC0**. The 2048px source PNGs are downsampled to 1024px for the mobile build.

- https://opengameart.org/content/clouds-with-transparency-fxcloudalpha03png
- https://opengameart.org/content/clouds-with-transparency-fxcloudalpha05png
- https://opengameart.org/content/clouds-with-transparency-fxcloudalpha08png

Cloud rendering references used for the scene strategy:

- Dihara Wijetunga, `volumetric-clouds` (MIT), ray-marched volumetric cloud sample: https://github.com/diharaw/volumetric-clouds
- `lightest/clouds` (MIT), WebGL2 sky/cloud implementation referencing Hillaire, Schneider, Bouthors and Bauer: https://github.com/lightest/clouds
- Apple RealityKit material transparency documentation: https://developer.apple.com/documentation/realitykit/physicallybasedmaterial/blending-swift.property

The Stage 017 renderer intentionally uses layered alpha cards rather than a full volume ray marcher. This keeps the mobile GPU cost low while establishing believable cloud scale and depth; the open volumetric implementations remain the reference for a later high-quality weather renderer.

## Stage 017 aircraft paint response

The exterior remains based on the MIT-licensed FlightSim_F16 geometry. Painted body zones are treated as non-metallic polyurethane coating with higher roughness and much lower clearcoat/specular response; canopy and exhaust materials remain intentionally glossy/metallic. The general coating family is consistent with MIL-PRF-85285, the U.S. military performance specification for polyurethane aircraft/support-equipment coatings.

Reference: https://quicksearch.dla.mil/qsDocDetails.aspx?ident_number=95909

