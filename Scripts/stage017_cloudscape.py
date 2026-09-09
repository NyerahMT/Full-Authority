from __future__ import annotations

import pathlib
import urllib.request
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[1]
WORLD = ROOT / "App" / "Stage2WorldFactory.swift"
AIRCRAFT = ROOT / "Aircraft" / "PrototypeAircraftFactory.swift"
SCENE = ROOT / "App" / "PrototypeSceneView.swift"
DOCS = ROOT / "Docs" / "VisualSources.md"
ASSET_DIR = ROOT / "Assets" / "JSBSim" / "visuals" / "world"

CLOUDS = {
    "cloud_alpha_03": "https://opengameart.org/sites/default/files/oga-textures/136561/fx_cloudalpha03.png",
    "cloud_alpha_05": "https://opengameart.org/sites/default/files/oga-textures/136561/fx_cloudalpha05.png",
    "cloud_alpha_08": "https://opengameart.org/sites/default/files/oga-textures/136561/fx_cloudalpha08.png",
}


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"Missing patch anchor: {label}")
    return text.replace(old, new, 1)


def download_clouds() -> None:
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    for name, url in CLOUDS.items():
        raw = ASSET_DIR / f"{name}_2k.png"
        dest = ASSET_DIR / f"{name}.png"
        req = urllib.request.Request(url, headers={"User-Agent": "FullAuthority/Stage017"})
        with urllib.request.urlopen(req, timeout=120) as response:
            raw.write_bytes(response.read())
        with Image.open(raw) as image:
            image = image.convert("RGBA")
            image.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
            image.save(dest, optimize=True)
        raw.unlink()
        if dest.stat().st_size < 50_000:
            raise SystemExit(f"Cloud asset {name} looks invalid")
        print(f"Imported {dest.relative_to(ROOT)}")


def patch_aircraft() -> None:
    text = AIRCRAFT.read_text()
    old = '''        // Hill Gray stays recognizable, but surfaces now separate by gloss as well
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
'''
    new = '''        // Stage 017: the fuselage is painted polyurethane, not bare metal. Keep the
        // canopy and nozzle glossy, but push every painted zone toward a diffuse,
        // low-specular dielectric response so sunlight reads as a soft highlight.
        return [
            material(UIColor(red: 0.300, green: 0.325, blue: 0.340, alpha: 1), roughness: 0.70, metallic: 0.000, specular: 0.20, clearcoat: 0.015, clearcoatRoughness: 0.72),
            material(UIColor(red: 0.470, green: 0.490, blue: 0.500, alpha: 1), roughness: 0.73, metallic: 0.000, specular: 0.18, clearcoat: 0.010, clearcoatRoughness: 0.76),
            material(UIColor(red: 0.145, green: 0.153, blue: 0.158, alpha: 1), roughness: 0.82, metallic: 0.000, specular: 0.14, clearcoat: 0.000, clearcoatRoughness: 0.90),
            material(UIColor(red: 0.020, green: 0.050, blue: 0.072, alpha: 1), roughness: 0.055, metallic: 0.08, specular: 1.00, clearcoat: 1.00, clearcoatRoughness: 0.020),
            material(UIColor(red: 0.105, green: 0.095, blue: 0.082, alpha: 1), roughness: 0.21, metallic: 0.98, specular: 0.78, clearcoat: 0.03, clearcoatRoughness: 0.30),
            material(UIColor(red: 0.315, green: 0.340, blue: 0.355, alpha: 1), roughness: 0.72, metallic: 0.000, specular: 0.18, clearcoat: 0.010, clearcoatRoughness: 0.76),
            material(UIColor(red: 0.245, green: 0.270, blue: 0.285, alpha: 1), roughness: 0.71, metallic: 0.000, specular: 0.19, clearcoat: 0.012, clearcoatRoughness: 0.74),
            material(UIColor(red: 0.270, green: 0.295, blue: 0.310, alpha: 1), roughness: 0.69, metallic: 0.000, specular: 0.20, clearcoat: 0.014, clearcoatRoughness: 0.72)
        ]
'''
    text = replace_once(text, old, new, "F-16 paint response")
    AIRCRAFT.write_text(text)


def patch_scene() -> None:
    text = SCENE.read_text()
    text = replace_once(
        text,
        "environmentLightingWeight: 0.70",
        "environmentLightingWeight: 0.56",
        "aircraft environment lighting",
    )
    SCENE.write_text(text)


def patch_world() -> None:
    text = WORLD.read_text()
    text = replace_once(
        text,
        '''        addTerrain(to: root)\n        addGroundScaleCues(to: root)''',
        '''        addTerrain(to: root)\n        addCloudscape(to: root)\n        addGroundScaleCues(to: root)''',
        "cloudscape call",
    )

    anchor = "    // MARK: - Terrain\n"
    cloud_code = r'''    // MARK: - Atmosphere / cloudscape

    /// Stage 017 uses CC0 cloud alpha art as a mobile-friendly first layer. The
    /// placement strategy follows the same visual goals as published volumetric
    /// cloud work (coverage, depth, scale and lighting separation) without paying
    /// the ray-marching cost before the rest of the scene warrants it.
    private static func addCloudscape(to root: Entity) {
        let names = ["cloud_alpha_03", "cloud_alpha_05", "cloud_alpha_08"]
        let textures = names.compactMap(loadCloudTexture)
        guard !textures.isEmpty else { return }

        let cloudRoot = Entity()
        cloudRoot.name = "FA.world.cloudscape"

        // Broad overhead/near-field puffs. Two offset cards per cloud give a little
        // parallax and stop the layer from reading like a single painted ceiling.
        for index in 0..<14 {
            let angle = Float(index) * 2.3999632 + 0.37
            let radius = Float(4_800 + (index * 1_917) % 10_800)
            let x = cos(angle) * radius
            let z = 2_000 + sin(angle) * radius
            let altitude = Float(2_200 + (index * 347) % 1_650)
            let width = Float(2_900 + (index * 733) % 3_700)
            let depth = Float(1_700 + (index * 419) % 2_700)
            let texture = textures[index % textures.count]

            let underside = cloudCard(
                texture: texture,
                size: [width, depth],
                tint: UIColor(red: 0.73, green: 0.76, blue: 0.79, alpha: 0.64)
            )
            underside.position = [x, altitude, z]
            underside.orientation = simd_quatf(
                angle: Float(index) * 0.71,
                axis: SIMD3<Float>(0, 1, 0)
            )
            cloudRoot.addChild(underside)

            let highlight = cloudCard(
                texture: textures[(index + 1) % textures.count],
                size: [width * 0.78, depth * 0.82],
                tint: UIColor(red: 0.94, green: 0.94, blue: 0.91, alpha: 0.34)
            )
            highlight.position = [x + 140, altitude + 135, z - 95]
            highlight.orientation = simd_quatf(
                angle: Float(index) * 0.71 + 0.42,
                axis: SIMD3<Float>(0, 1, 0)
            )
            cloudRoot.addChild(highlight)
        }

        // Distant vertical banks break up the horizon and make the atmosphere read
        // in kilometres, not as a flat blue background.
        for index in 0..<10 {
            let angle = Float(index) / 10 * 2 * Float.pi + 0.21
            let radius = Float(15_000 + (index * 1_037) % 4_800)
            let x = cos(angle) * radius
            let z = 2_000 + sin(angle) * radius
            let width = Float(5_000 + (index * 911) % 3_800)
            let height = Float(2_400 + (index * 557) % 2_100)
            let centerY = Float(2_300 + (index * 229) % 1_500)
            let texture = textures[(index + 2) % textures.count]

            let bank = cloudCard(
                texture: texture,
                size: [width, height],
                tint: UIColor(red: 0.86, green: 0.87, blue: 0.86, alpha: 0.50)
            )
            bank.position = [x, centerY, z]

            let pitch = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
            let yaw = simd_quatf(angle: -angle + .pi / 2, axis: SIMD3<Float>(0, 1, 0))
            bank.orientation = yaw * pitch
            cloudRoot.addChild(bank)
        }

        root.addChild(cloudRoot)
    }

    private static func loadCloudTexture(_ name: String) -> TextureResource? {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "JSBSim/visuals/world"
        ) else { return nil }
        return try? TextureResource.load(contentsOf: url, withName: name)
    }

    private static func cloudCard(
        texture: TextureResource,
        size: SIMD2<Float>,
        tint: UIColor
    ) -> ModelEntity {
        let map = MaterialParameters.Texture(texture)
        var material = UnlitMaterial()
        material.color = .init(tint: tint, texture: map)
        material.blending = .transparent(opacity: .init(texture: map))
        material.faceCulling = .none
        material.readsDepth = true
        material.writesDepth = false

        return ModelEntity(
            mesh: .generatePlane(width: size.x, depth: size.y),
            materials: [material]
        )
    }

'''
    if anchor not in text:
        raise SystemExit("Missing terrain anchor")
    text = text.replace(anchor, cloud_code + anchor, 1)
    WORLD.write_text(text)


def patch_docs() -> None:
    text = DOCS.read_text()
    if "## Stage 017 cloudscape" in text:
        return
    addition = '''

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
'''
    DOCS.write_text(text.rstrip() + addition + "\n")


def main() -> None:
    download_clouds()
    patch_aircraft()
    patch_scene()
    patch_world()
    patch_docs()
    print("Stage 017 cloudscape + matte aircraft pass applied")


if __name__ == "__main__":
    main()
