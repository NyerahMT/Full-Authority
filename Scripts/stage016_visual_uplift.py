from __future__ import annotations

import json
import pathlib
import re
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
WORLD = ROOT / "App" / "Stage2WorldFactory.swift"
AIRCRAFT = ROOT / "Aircraft" / "PrototypeAircraftFactory.swift"
SCENE = ROOT / "App" / "PrototypeSceneView.swift"
CONTENT = ROOT / "App" / "ContentView.swift"
ASSET_DIR = ROOT / "Assets" / "JSBSim" / "visuals" / "world"
DOCS = ROOT / "Docs" / "VisualSources.md"
USER_AGENT = "FullAuthorityAssetImporter/1.0 (github.com/NyerahMT/Full-Authority)"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"Could not find patch anchor: {label}")
    return text.replace(old, new, 1)


def fetch_json(url: str):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as response:
        return json.load(response)


def walk_urls(node, path=()):
    if isinstance(node, dict):
        if isinstance(node.get("url"), str):
            yield path, node["url"], int(node.get("size") or 0)
        for key, value in node.items():
            yield from walk_urls(value, path + (str(key),))
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from walk_urls(value, path + (str(index),))


def choose_map(files, token: str) -> str:
    candidates = []
    for path, url, size in walk_urls(files):
        lower_url = url.lower()
        joined = "/".join(path).lower()
        basename = lower_url.rsplit("/", 1)[-1]
        if not lower_url.endswith(".jpg"):
            continue
        if token not in lower_url and token not in joined:
            continue

        score = 0
        if "/1k/" in lower_url or "_1k." in lower_url or "1k" in joined:
            score += 100
        if f"_{token}_" in basename:
            score += 60
        if token in basename:
            score += 30
        if token == "rough" and "rough_ao" in basename:
            score -= 80
        if token == "diff" and any(x in basename for x in ("nor", "rough", "ao", "disp", "mask")):
            score -= 100
        score -= size / 50_000_000.0
        candidates.append((score, url))

    if not candidates:
        raise SystemExit(f"No 1K-ish JPG map containing '{token}' found in Poly Haven response")
    candidates.sort(reverse=True)
    return candidates[0][1]


def download(url: str, destination: pathlib.Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=120) as response:
        data = response.read()
    if len(data) < 1024:
        raise SystemExit(f"Downloaded asset is suspiciously small: {url} ({len(data)} bytes)")
    destination.write_bytes(data)
    print(f"Downloaded {destination.relative_to(ROOT)} ({len(data) / 1024:.1f} KiB)")


def import_poly_haven_assets() -> dict[str, dict[str, str]]:
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    assets = {
        "runway_asphalt": "asphalt_02",
        "terrain_grass": "leafy_grass",
        "apron_concrete": "concrete_floor_01",
    }
    provenance: dict[str, dict[str, str]] = {}

    for local_name, slug in assets.items():
        files = fetch_json(f"https://api.polyhaven.com/files/{slug}")
        diff = choose_map(files, "diff")
        rough = choose_map(files, "rough")
        download(diff, ASSET_DIR / f"{local_name}_diff.jpg")
        download(rough, ASSET_DIR / f"{local_name}_rough.jpg")
        provenance[local_name] = {
            "slug": slug,
            "page": f"https://polyhaven.com/a/{slug}",
            "diff": diff,
            "rough": rough,
        }

    return provenance


def patch_world() -> None:
    text = WORLD.read_text()
    if "Stage 016 sourced PBR surface pass" in text:
        return

    text = replace_once(
        text,
        "import RealityKit\nimport UIKit\nimport simd\n",
        "import Metal\nimport RealityKit\nimport UIKit\nimport simd\n",
        "Stage2WorldFactory imports",
    )

    text = replace_once(
        text,
        """    private struct TerrainMeshes {\n        let ground: MeshResource\n        let rock: MeshResource?\n    }\n""",
        """    private struct TerrainMeshes {\n        let ground: MeshResource\n        let rock: MeshResource?\n    }\n\n    // Stage 016 sourced PBR surface pass. These maps are CC0 Poly Haven\n    // assets imported at build time; the game never depends on a live API.\n    private struct WorldTextureSet {\n        let baseColor: TextureResource?\n        let roughness: TextureResource?\n    }\n""",
        "world texture struct",
    )

    text = replace_once(
        text,
        """        let tileSize: Float = 6_000\n        let resolution = 81\n        let texture = try? TextureResource.load(named: \"terrain_albedo\")\n""",
        """        let tileSize: Float = 6_000\n        let resolution = 81\n        let terrainTextures = worldTextureSet(named: \"terrain_grass\")\n""",
        "terrain texture load",
    )

    text = replace_once(
        text,
        "materials: [terrainMaterial(texture: texture, selector: selector)]",
        "materials: [terrainMaterial(textures: terrainTextures, selector: selector)]",
        "terrain material call",
    )

    text = replace_once(
        text,
        """                var u = Float(xIndex) / Float(resolution - 1)\n                var v = Float(zIndex) / Float(resolution - 1)\n                if mirrorU { u = 1 - u }\n                if mirrorV { v = 1 - v }\n                texcoords.append([u, v])\n""",
        """                // World-space UVs keep ground detail at a readable physical scale\n                // instead of stretching one texture across a 6 km tile. 24 m is\n                // deliberately stylized: visible from low altitude without noisy moire.\n                let textureScaleMeters: Float = 24\n                var u = globalX / textureScaleMeters\n                var v = globalZ / textureScaleMeters\n                if mirrorU { u = -u }\n                if mirrorV { v = -v }\n                texcoords.append([u, v])\n""",
        "terrain world UVs",
    )

    start = text.index("    private static func terrainMaterial(")
    end = text.index("    private static func rockMaterial", start)
    new_material_section = r'''    private static func worldTextureSet(named stem: String) -> WorldTextureSet {
        WorldTextureSet(
            baseColor: loadWorldTexture("\(stem)_diff"),
            roughness: loadWorldTexture("\(stem)_rough")
        )
    }

    private static func loadWorldTexture(_ name: String) -> TextureResource? {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "jpg",
            subdirectory: "JSBSim/visuals/world"
        ) else { return nil }
        return try? TextureResource.load(contentsOf: url, withName: name)
    }

    private static func repeatedTexture(
        _ resource: TextureResource,
        anisotropy: Int = 8
    ) -> MaterialParameters.Texture {
        var texture = MaterialParameters.Texture(resource)
        texture.sampler.modify { descriptor in
            descriptor.sAddressMode = .repeat
            descriptor.tAddressMode = .repeat
            descriptor.mipFilter = .linear
            descriptor.minFilter = .linear
            descriptor.magFilter = .linear
            descriptor.maxAnisotropy = anisotropy
        }
        return texture
    }

    private static func terrainMaterial(
        textures: WorldTextureSet,
        selector: Int
    ) -> PhysicallyBasedMaterial {
        let tints: [UIColor] = [
            UIColor(red: 0.72, green: 0.78, blue: 0.58, alpha: 1),
            UIColor(red: 0.82, green: 0.78, blue: 0.54, alpha: 1),
            UIColor(red: 0.64, green: 0.73, blue: 0.51, alpha: 1),
            UIColor(red: 0.82, green: 0.69, blue: 0.47, alpha: 1),
            UIColor(red: 0.68, green: 0.68, blue: 0.47, alpha: 1),
            UIColor(red: 0.76, green: 0.79, blue: 0.57, alpha: 1)
        ]

        var material = PhysicallyBasedMaterial()
        if let base = textures.baseColor {
            material.baseColor = PhysicallyBasedMaterial.BaseColor(
                tint: tints[selector % tints.count],
                texture: repeatedTexture(base)
            )
        } else {
            material.baseColor = PhysicallyBasedMaterial.BaseColor(
                tint: UIColor(red: 0.30, green: 0.38, blue: 0.19, alpha: 1)
            )
        }
        if let rough = textures.roughness {
            material.roughness = PhysicallyBasedMaterial.Roughness(
                scale: 0.94,
                texture: repeatedTexture(rough)
            )
        } else {
            material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.90)
        }
        material.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: 0.0)
        material.specular = PhysicallyBasedMaterial.Specular(floatLiteral: 0.32)
        return material
    }

    private static func pbrSurfaceMaterial(
        textures: WorldTextureSet,
        tint: UIColor,
        roughnessScale: Float
    ) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        if let base = textures.baseColor {
            material.baseColor = .init(tint: tint, texture: repeatedTexture(base))
        } else {
            material.baseColor = .init(tint: tint)
        }
        if let rough = textures.roughness {
            material.roughness = .init(scale: roughnessScale, texture: repeatedTexture(rough))
        } else {
            material.roughness = .init(floatLiteral: roughnessScale)
        }
        material.metallic = .init(floatLiteral: 0.0)
        material.specular = .init(floatLiteral: 0.38)
        return material
    }

'''
    text = text[:start] + new_material_section + text[end:]

    airbase_anchor = """        towerCab.position = [715, 52, 900]\n        root.addChild(towerCab)\n    }\n\n    private static func addRunwayLight"""
    airbase_replacement = r'''        towerCab.position = [715, 52, 900]
        root.addChild(towerCab)

        addAirbaseMaterialOverlays(to: root)
    }

    /// Thin PBR overlays preserve the existing runway geometry/markings while
    /// replacing the giant flat-color surfaces with real, tiled material detail.
    private static func addAirbaseMaterialOverlays(to root: Entity) {
        let asphalt = worldTextureSet(named: "runway_asphalt")
        let concrete = worldTextureSet(named: "apron_concrete")

        if let runway = makeTexturedSurface(
            size: [64, 4_800],
            center: [0, 0.108, 2_000],
            tileMeters: 7.5,
            material: pbrSurfaceMaterial(
                textures: asphalt,
                tint: UIColor(red: 0.54, green: 0.55, blue: 0.55, alpha: 1),
                roughnessScale: 0.96
            )
        ) {
            root.addChild(runway)
        }

        if let taxiway = makeTexturedSurface(
            size: [30, 3_050],
            center: [320, 0.082, 1_650],
            tileMeters: 7.0,
            material: pbrSurfaceMaterial(
                textures: asphalt,
                tint: UIColor(red: 0.50, green: 0.51, blue: 0.51, alpha: 1),
                roughnessScale: 0.97
            )
        ) {
            root.addChild(taxiway)
        }

        for connectorZ: Float in [250, 1_100, 2_100, 3_050] {
            if let connector = makeTexturedSurface(
                size: [320, 24],
                center: [160, 0.082, connectorZ],
                tileMeters: 7.0,
                material: pbrSurfaceMaterial(
                    textures: asphalt,
                    tint: UIColor(red: 0.50, green: 0.51, blue: 0.51, alpha: 1),
                    roughnessScale: 0.97
                )
            ) {
                root.addChild(connector)
            }
        }

        if let apron = makeTexturedSurface(
            size: [430, 360],
            center: [520, 0.084, 720],
            tileMeters: 6.5,
            material: pbrSurfaceMaterial(
                textures: concrete,
                tint: UIColor(red: 0.68, green: 0.68, blue: 0.65, alpha: 1),
                roughnessScale: 0.94
            )
        ) {
            root.addChild(apron)
        }
    }

    private static func makeTexturedSurface(
        size: SIMD2<Float>,
        center: SIMD3<Float>,
        tileMeters: Float,
        material: PhysicallyBasedMaterial
    ) -> ModelEntity? {
        let halfX = size.x * 0.5
        let halfZ = size.y * 0.5
        let positions: [SIMD3<Float>] = [
            [-halfX, 0, -halfZ], [halfX, 0, -halfZ],
            [-halfX, 0, halfZ], [halfX, 0, halfZ]
        ]
        let normals = Array(repeating: SIMD3<Float>(0, 1, 0), count: 4)
        let u = size.x / max(tileMeters, 0.5)
        let v = size.y / max(tileMeters, 0.5)
        let texcoords: [SIMD2<Float>] = [[0, 0], [u, 0], [0, v], [u, v]]
        let indices: [UInt32] = [0, 2, 1, 1, 2, 3]

        var descriptor = MeshDescriptor(name: "Stage 016 PBR surface")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(texcoords)
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = center
        return entity
    }

    private static func addRunwayLight'''
    text = replace_once(text, airbase_anchor, airbase_replacement, "airbase PBR overlays")

    WORLD.write_text(text)


def patch_aircraft() -> None:
    text = AIRCRAFT.read_text()
    if "Stage 016 material hierarchy" in text:
        return

    start = text.index("    private static func makeF16Materials() throws -> [PhysicallyBasedMaterial] {")
    end = text.index("    private static func addMovingPart", start)
    replacement = r'''    private static func makeF16Materials() throws -> [PhysicallyBasedMaterial] {
        // Stage 016 material hierarchy: keep the permissively licensed FlightSim_F16
        // geometry, but let PBR response carry much more of the visual quality.
        // This follows the standard metallic/roughness workflow rather than adding
        // expensive geometry simply to create highlights.
        func material(
            _ tint: UIColor,
            roughness: Float,
            metallic: Float,
            specular: Float,
            clearcoat: Float,
            clearcoatRoughness: Float
        ) -> PhysicallyBasedMaterial {
            var result = PhysicallyBasedMaterial()
            result.baseColor = .init(tint: tint)
            result.roughness = .init(floatLiteral: roughness)
            result.metallic = .init(floatLiteral: metallic)
            result.specular = .init(floatLiteral: specular)
            result.clearcoat = .init(floatLiteral: clearcoat)
            result.clearcoatRoughness = .init(floatLiteral: clearcoatRoughness)
            return result
        }

        // Hill Gray stays recognizable, but surfaces now separate by gloss as well
        // as color. The canopy is deliberately jewel-like so the jet remains the
        // hero object in chase view; the exhaust is hot, dark metallic rather than gray.
        return [
            material(UIColor(red: 0.300, green: 0.325, blue: 0.340, alpha: 1), roughness: 0.43, metallic: 0.035, specular: 0.55, clearcoat: 0.14, clearcoatRoughness: 0.30),
            material(UIColor(red: 0.470, green: 0.490, blue: 0.500, alpha: 1), roughness: 0.50, metallic: 0.020, specular: 0.48, clearcoat: 0.10, clearcoatRoughness: 0.36),
            material(UIColor(red: 0.145, green: 0.153, blue: 0.158, alpha: 1), roughness: 0.72, metallic: 0.000, specular: 0.30, clearcoat: 0.02, clearcoatRoughness: 0.70),
            material(UIColor(red: 0.020, green: 0.050, blue: 0.072, alpha: 1), roughness: 0.045, metallic: 0.16, specular: 1.00, clearcoat: 1.00, clearcoatRoughness: 0.018),
            material(UIColor(red: 0.105, green: 0.095, blue: 0.082, alpha: 1), roughness: 0.18, metallic: 0.98, specular: 0.78, clearcoat: 0.05, clearcoatRoughness: 0.22),
            material(UIColor(red: 0.315, green: 0.340, blue: 0.355, alpha: 1), roughness: 0.48, metallic: 0.025, specular: 0.50, clearcoat: 0.10, clearcoatRoughness: 0.34),
            material(UIColor(red: 0.245, green: 0.270, blue: 0.285, alpha: 1), roughness: 0.46, metallic: 0.030, specular: 0.54, clearcoat: 0.12, clearcoatRoughness: 0.32),
            material(UIColor(red: 0.270, green: 0.295, blue: 0.310, alpha: 1), roughness: 0.44, metallic: 0.030, specular: 0.55, clearcoat: 0.13, clearcoatRoughness: 0.30)
        ]
    }

'''
    text = text[:start] + replacement + text[end:]
    AIRCRAFT.write_text(text)


def patch_scene() -> None:
    text = SCENE.read_text()
    if "Stage 016 cinematic lighting" in text:
        return

    text = replace_once(
        text,
        """                    let world = Stage2WorldFactory.make()\n                    content.add(world)\n""",
        """                    let world = Stage2WorldFactory.make()\n                    // Stage 016 cinematic lighting: reduce the flat default IBL so\n                    // directional sunlight and material roughness can actually shape terrain.\n                    world.components.set(EnvironmentLightingConfigurationComponent(\n                        environmentLightingWeight: 0.48\n                    ))\n                    content.add(world)\n""",
        "world environment lighting",
    )

    text = replace_once(
        text,
        """                    let aircraft = PrototypeAircraftFactory.make()\n                    aircraft.position = simulation.state.positionMeters\n                    aircraft.orientation = simulation.state.orientation\n""",
        """                    let aircraft = PrototypeAircraftFactory.make()\n                    aircraft.components.set(EnvironmentLightingConfigurationComponent(\n                        environmentLightingWeight: 0.70\n                    ))\n                    aircraft.position = simulation.state.positionMeters\n                    aircraft.orientation = simulation.state.orientation\n""",
        "aircraft environment lighting",
    )

    text = replace_once(
        text,
        """                        DirectionalLightComponent(\n                            color: UIColor(red: 1.0, green: 0.95, blue: 0.87, alpha: 1),\n                            intensity: 7_800\n                        ),\n""",
        """                        DirectionalLightComponent(\n                            color: UIColor(red: 1.0, green: 0.88, blue: 0.72, alpha: 1),\n                            intensity: 10_400\n                        ),\n""",
        "warm key light",
    )
    text = replace_once(
        text,
        "sun.look(at: .zero, from: [-8_800, 9_600, -2_300], relativeTo: nil)",
        "sun.look(at: .zero, from: [-9_600, 5_600, -3_200], relativeTo: nil)",
        "lower sun angle",
    )
    text = replace_once(
        text,
        """                    fill.components.set(DirectionalLightComponent(\n                        color: UIColor(red: 0.50, green: 0.66, blue: 0.90, alpha: 1),\n                        intensity: 340\n                    ))\n                    fill.look(at: .zero, from: [6_500, 5_200, 6_200], relativeTo: nil)\n""",
        """                    fill.components.set(DirectionalLightComponent(\n                        color: UIColor(red: 0.42, green: 0.58, blue: 0.86, alpha: 1),\n                        intensity: 210\n                    ))\n                    fill.look(at: .zero, from: [6_800, 6_200, 7_600], relativeTo: nil)\n""",
        "cool fill light",
    )

    start = text.index("    private var stage2Sky: some View {")
    end = text.index("    private var cameraSelector: some View {", start)
    sky = r'''    private var stage2Sky: some View {
        // Stage 016 cinematic sky. The zenith-to-horizon progression follows the
        // aerial-perspective structure described by Bruneton & Neyret, while the
        // warmer low horizon is intentionally pushed for a readable game palette.
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.008, green: 0.070, blue: 0.205), location: 0.00),
                .init(color: Color(red: 0.025, green: 0.205, blue: 0.455), location: 0.38),
                .init(color: Color(red: 0.225, green: 0.455, blue: 0.655), location: 0.68),
                .init(color: Color(red: 0.565, green: 0.625, blue: 0.640), location: 0.86),
                .init(color: Color(red: 0.760, green: 0.665, blue: 0.535), location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

'''
    text = text[:start] + sky + text[end:]
    SCENE.write_text(text)


def patch_content() -> None:
    text = CONTENT.read_text()
    if "cameraMode == .cockpit ? 1.0 : 0.78" in text:
        return
    text = replace_once(
        text,
        """                F16HUD(state: simulation.state, controls: simulation.controls)\n                    .allowsHitTesting(false)\n""",
        """                F16HUD(state: simulation.state, controls: simulation.controls)\n                    // Keep full symbology in the cockpit; in chase view the jet\n                    // becomes the hero instead of fighting a neon-green overlay.\n                    .opacity(cameraMode == .cockpit ? 1.0 : 0.78)\n                    .allowsHitTesting(false)\n""",
        "chase HMD hierarchy",
    )
    CONTENT.write_text(text)


def write_docs(provenance: dict[str, dict[str, str]]) -> None:
    DOCS.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Full Authority Visual Sources",
        "",
        "Full Authority uses a source-first visual pipeline: permissively licensed assets and published rendering references are preferred over rebuilding solved art/graphics problems from scratch.",
        "",
        "## Stage 016 imported assets",
        "",
        "The following textures are imported from **Poly Haven** through its public API at development/build time. Poly Haven assets are **CC0**. The app does not contact Poly Haven at runtime.",
        "",
    ]
    for local_name, item in provenance.items():
        lines += [
            f"- `{local_name}`: {item['page']}",
            f"  - diffuse source: {item['diff']}",
            f"  - roughness source: {item['rough']}",
        ]
    lines += [
        "",
        "Poly Haven license: https://polyhaven.com/license",
        "Poly Haven API: https://api.polyhaven.com/",
        "",
        "## Aircraft source",
        "",
        "The current external F-16 geometry is derived from Ryan Vazquez's `FlightSim_F16`, which is MIT-licensed. Its license is already bundled at `Assets/JSBSim/visuals/f16/LICENSE-FlightSim_F16.txt`.",
        "",
        "Source: https://github.com/vazgriz/FlightSim_F16",
        "",
        "## Rendering references",
        "",
        "- Eric Bruneton & Fabrice Neyret, *Precomputed Atmospheric Scattering* (2008): https://inria.hal.science/inria-00288758/document",
        "- Eric Bruneton's BSD reference implementation: https://github.com/ebruneton/precomputed_atmospheric_scattering",
        "- Khronos glTF 2.0 metallic/roughness PBR material model: https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html",
        "- Apple RealityKit PBR and environment-lighting documentation: https://developer.apple.com/documentation/realitykit/physicallybasedmaterial",
        "",
        "Stage 016 uses these references for material hierarchy, sky palette/aerial-perspective cues, and lighting structure. It does not vendor Bruneton's renderer; a Metal atmosphere implementation can be evaluated later if the stylized pass needs true distance-dependent scattering.",
        "",
    ]
    DOCS.write_text("\n".join(lines))


def main() -> None:
    provenance = import_poly_haven_assets()
    patch_world()
    patch_aircraft()
    patch_scene()
    patch_content()
    write_docs(provenance)
    print("Stage 016 sourced visual uplift applied.")


if __name__ == "__main__":
    main()
