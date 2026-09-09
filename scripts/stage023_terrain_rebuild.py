from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 anchor, found {count}")
    return text.replace(old, new, 1)


# 1) Export one authoritative terrain-height function through the bridge.
h = Path('Simulation/Bridge/FAJSBSimBridge.h')
text = h.read_text(encoding='utf-8')
anchor = 'NS_ASSUME_NONNULL_BEGIN\n\n'
export = '''NS_ASSUME_NONNULL_BEGIN\n\n#ifdef __cplusplus\nextern "C" {\n#endif\nFOUNDATION_EXPORT double FATerrainHeightMeters(double eastMeters, double northMeters);\n#ifdef __cplusplus\n}\n#endif\n\n'''
text = replace_once(text, anchor, export, 'bridge header export')
h.write_text(text, encoding='utf-8')

mm = Path('Simulation/Bridge/FAJSBSimBridge.mm')
text = mm.read_text(encoding='utf-8')
old_fn_pattern = re.compile(r'double TerrainHeightMeters\(double eastMeters, double northMeters\) \{.*?\n\}\n\nclass FATerrainGroundCallback', re.S)
match = old_fn_pattern.search(text)
if not match:
    raise SystemExit('old TerrainHeightMeters block not found')
text = text[:match.start()] + 'class FATerrainGroundCallback' + text[match.end():]
text = text.replace('TerrainHeightMeters(', 'FATerrainHeightMeters(')
insert_anchor = '''};\n}\n\n@interface FAJSBSimBridge ()\n'''
canonical_fn = '''};\n}\n\nextern "C" double FATerrainHeightMeters(double eastMeters, double northMeters) {\n    // Stage 023 single source of truth. RealityKit calls this exact function\n    // through the Swift bridging header, and JSBSim's ground callback calls it\n    // directly. There is no second approximated terrain formula anymore.\n    double base =\n        78.0 * std::sin(northMeters / 2750.0) * std::cos(eastMeters / 3500.0) +\n        52.0 * std::sin((eastMeters + northMeters) / 1820.0) +\n        36.0 * std::cos((eastMeters - 0.45 * northMeters) / 2250.0) +\n        19.0 * std::sin((1.25 * eastMeters + 0.72 * northMeters) / 820.0) +\n        12.0 * std::cos((0.65 * eastMeters - 1.10 * northMeters) / 510.0) +\n        6.5 * std::sin((1.80 * eastMeters + 1.35 * northMeters) / 285.0);\n\n    const double ridge1East = (eastMeters + 6500.0) / 2350.0;\n    const double ridge1North = (northMeters - 9000.0) / 3300.0;\n    base += 245.0 * std::exp(-0.5 * (ridge1East * ridge1East + ridge1North * ridge1North));\n\n    const double ridge2East = (eastMeters - 7200.0) / 2500.0;\n    const double ridge2North = (northMeters - 6500.0) / 2750.0;\n    base += 185.0 * std::exp(-0.5 * (ridge2East * ridge2East + ridge2North * ridge2North));\n\n    const double ridge3East = (eastMeters + 10500.0) / 3200.0;\n    const double ridge3North = (northMeters + 2500.0) / 2600.0;\n    base += 210.0 * std::exp(-0.5 * (ridge3East * ridge3East + ridge3North * ridge3North));\n\n    const double valleyEast = (eastMeters - 4200.0) / 2300.0;\n    const double valleyNorth = (northMeters - 9800.0) / 5000.0;\n    base -= 92.0 * std::exp(-0.5 * (valleyEast * valleyEast + valleyNorth * valleyNorth));\n\n    const double dx = std::max(std::abs(eastMeters) - 1000.0, 0.0);\n    const double dz = std::max(std::abs(northMeters - 2000.0) - 3600.0, 0.0);\n    const double distanceOutsideAirfield = std::hypot(dx, dz);\n    const double terrainBlend = SmoothStep(distanceOutsideAirfield / 1250.0);\n    return base * terrainBlend;\n}\n\n@interface FAJSBSimBridge ()\n'''
text = replace_once(text, insert_anchor, canonical_fn, 'canonical terrain insert')
mm.write_text(text, encoding='utf-8')

# 2) Swift terrain profile now samples the C++ authoritative surface.
sim = Path('Simulation/FlightSimulation.swift')
text = sim.read_text(encoding='utf-8')
pattern = re.compile(r'enum Stage2TerrainProfile \{.*?\n\}\n\n@MainActor\nfinal class FlightSimulation', re.S)
match = pattern.search(text)
if not match:
    raise SystemExit('Stage2TerrainProfile block not found')
profile = '''enum Stage2TerrainProfile {\n    static func heightMeters(east: Float, north: Float) -> Float {\n        Float(FATerrainHeightMeters(Double(east), Double(north)))\n    }\n\n    static func normal(east: Float, north: Float) -> SIMD3<Float> {\n        let sample: Float = 8\n        let dhde = (\n            heightMeters(east: east + sample, north: north) -\n            heightMeters(east: east - sample, north: north)\n        ) / (2 * sample)\n        let dhdn = (\n            heightMeters(east: east, north: north + sample) -\n            heightMeters(east: east, north: north - sample)\n        ) / (2 * sample)\n        return simd_normalize(SIMD3<Float>(-dhde, 1, -dhdn))\n    }\n}\n\n@MainActor\nfinal class FlightSimulation'''
text = text[:match.start()] + profile + text[match.end():]
sim.write_text(text, encoding='utf-8')

# 3) Terrain renderer: kill the high-altitude shimmer/rock triangles, preserve a matte base,
# and attach the Stage 023 landclass/life layer.
world = Path('App/Stage2WorldFactory.swift')
text = world.read_text(encoding='utf-8')
text = replace_once(
    text,
    '        root.addChild(Stage020WorldUpgrade.make())\n',
    '        root.addChild(Stage020WorldUpgrade.make())\n        root.addChild(Stage023TerrainSystem.make())\n',
    'attach Stage023 world'
)
text = text.replace('                    mirrorU: tileX.isMultiple(of: 2),\n                    mirrorV: tileZ.isMultiple(of: 2)',
                    '                    mirrorU: false,\n                    mirrorV: false')
rock_block = re.compile(r'''\n\s*if let rockMesh = meshes\.rock \{\n\s*let rock = ModelEntity\(\n\s*mesh: rockMesh,\n\s*materials: \[rockMaterial\(selector: selector\)\]\n\s*\)\n\s*rock\.position = \[centerX, 0\.045, centerZ\]\n\s*root\.addChild\(rock\)\n\s*\}\n''')
text, n = rock_block.subn('\n', text, count=1)
if n != 1:
    raise SystemExit(f'rock render block: expected 1, found {n}')
text = replace_once(
    text,
    '''        let tints: [UIColor] = [\n            UIColor(red: 0.68, green: 0.74, blue: 0.62, alpha: 1),\n            UIColor(red: 0.73, green: 0.76, blue: 0.65, alpha: 1),\n            UIColor(red: 0.62, green: 0.70, blue: 0.58, alpha: 1),\n            UIColor(red: 0.70, green: 0.72, blue: 0.61, alpha: 1),\n            UIColor(red: 0.64, green: 0.69, blue: 0.57, alpha: 1),\n            UIColor(red: 0.71, green: 0.75, blue: 0.63, alpha: 1)\n        ]''',
    '''        let tints: [UIColor] = [\n            UIColor(red: 0.46, green: 0.54, blue: 0.34, alpha: 1),\n            UIColor(red: 0.50, green: 0.56, blue: 0.37, alpha: 1),\n            UIColor(red: 0.42, green: 0.50, blue: 0.31, alpha: 1),\n            UIColor(red: 0.48, green: 0.52, blue: 0.34, alpha: 1),\n            UIColor(red: 0.43, green: 0.49, blue: 0.30, alpha: 1),\n            UIColor(red: 0.49, green: 0.55, blue: 0.35, alpha: 1)\n        ]''',
    'terrain tint palette'
)
text = text.replace('scale: 0.94,\n                texture: repeatedTexture(rough)', 'scale: 1.0,\n                texture: repeatedTexture(rough)', 1)
text = text.replace('material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.90)',
                    'material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 1.0)', 1)
normal_block = '''        if let normal = textures.normal {\n            material.normal = PhysicallyBasedMaterial.Normal(texture: repeatedTexture(normal))\n        }\n'''
text = replace_once(text, normal_block, '''        // Fine normal detail belongs close to the eye. On the 48 km base mesh it\n        // aliases into the glossy/shimmering look seen from altitude, so Stage 023\n        // leaves the far terrain on geometric normals and lets landclass provide\n        // macro variation.\n''', 'remove far terrain normal')
text = text.replace('material.specular = PhysicallyBasedMaterial.Specular(floatLiteral: 0.32)',
                    'material.specular = PhysicallyBasedMaterial.Specular(floatLiteral: 0.08)', 1)
text = replace_once(
    text,
    '''                // World-space UVs keep ground detail at a readable physical scale\n                // instead of stretching one texture across a 6 km tile. 24 m is\n                // deliberately stylized: visible from low altitude without noisy moire.\n                let textureScaleMeters: Float = 24''',
    '''                // A calmer base frequency survives mip filtering from altitude.\n                // Macro landclass variation now carries the large-scale read; this\n                // texture only provides medium-scale surface identity.\n                let textureScaleMeters: Float = 42''',
    'terrain UV scale'
)
rock_mesh_block = re.compile(r'''\n\s*var rockMesh: MeshResource\?\n\s*if !rockIndices\.isEmpty \{.*?\n\s*\}\n\n\s*return TerrainMeshes\(ground: groundMesh, rock: rockMesh\)''', re.S)
text, n = rock_mesh_block.subn('\n\n        return TerrainMeshes(ground: groundMesh, rock: nil)', text, count=1)
if n != 1:
    raise SystemExit(f'rock mesh generation: expected 1, found {n}')
world.write_text(text, encoding='utf-8')

# 4) Animate the tiny civil-traffic layer in gameplay and menu.
scene = Path('App/PrototypeSceneView.swift')
text = scene.read_text(encoding='utf-8')
anchor = '''                    if let atmosphere = content.entities.first(where: { $0.name == Stage021Atmosphere.rootName }) {\n                        Stage021Atmosphere.update(atmosphere, aircraftPosition: simulation.state.positionMeters)\n                    }\n'''
addition = anchor + '''\n                    if let world = content.entities.first(where: { $0.name == "FA.world.stage2" }) {\n                        Stage023TerrainSystem.update(worldRoot: world, elapsed: simulation.simulationTime)\n                    }\n'''
text = replace_once(text, anchor, addition, 'gameplay traffic update')
scene.write_text(text, encoding='utf-8')

menu = Path('App/Stage022MainMenu.swift')
text = menu.read_text(encoding='utf-8')
anchor = '''                    Stage022MenuScene.update(\n                        content: content,\n                        elapsed: elapsed,\n                        takeoffStart: runtime.latestTakeoffStart,\n                        cameraLookYaw: lookYawRadians,\n                        cameraLookPitch: lookPitchRadians\n                    )\n'''
addition = anchor + '''\n                    if let world = content.entities.first(where: { $0.name == "FA.world.stage2" }) {\n                        Stage023TerrainSystem.update(worldRoot: world, elapsed: elapsed)\n                    }\n'''
text = replace_once(text, anchor, addition, 'menu traffic update')
menu.write_text(text, encoding='utf-8')

# 5) Wire Stage023TerrainSystem.swift into Xcode.
proj = Path('FullAuthority.xcodeproj/project.pbxproj')
text = proj.read_text(encoding='utf-8')
text = replace_once(
    text,
    '\t\tFA0220000000000000000002 /* Stage022MainMenu.swift in Sources */ = {isa = PBXBuildFile; fileRef = FA0220000000000000000012 /* Stage022MainMenu.swift */; };\n',
    '\t\tFA0220000000000000000002 /* Stage022MainMenu.swift in Sources */ = {isa = PBXBuildFile; fileRef = FA0220000000000000000012 /* Stage022MainMenu.swift */; };\n\t\tFA0230000000000000000001 /* Stage023TerrainSystem.swift in Sources */ = {isa = PBXBuildFile; fileRef = FA0230000000000000000011 /* Stage023TerrainSystem.swift */; };\n',
    'project build file'
)
text = replace_once(
    text,
    '\t\tFA0220000000000000000012 /* Stage022MainMenu.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Stage022MainMenu.swift; sourceTree = "<group>"; };\n',
    '\t\tFA0220000000000000000012 /* Stage022MainMenu.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Stage022MainMenu.swift; sourceTree = "<group>"; };\n\t\tFA0230000000000000000011 /* Stage023TerrainSystem.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Stage023TerrainSystem.swift; sourceTree = "<group>"; };\n',
    'project file ref'
)
text = replace_once(
    text,
    '\t\t\t\tFA0220000000000000000012 /* Stage022MainMenu.swift */,\n',
    '\t\t\t\tFA0220000000000000000012 /* Stage022MainMenu.swift */,\n\t\t\t\tFA0230000000000000000011 /* Stage023TerrainSystem.swift */,\n',
    'project app group'
)
text = replace_once(
    text,
    '\t\t\t\tFA0220000000000000000002 /* Stage022MainMenu.swift in Sources */,\n',
    '\t\t\t\tFA0220000000000000000002 /* Stage022MainMenu.swift in Sources */,\n\t\t\t\tFA0230000000000000000001 /* Stage023TerrainSystem.swift in Sources */,\n',
    'project sources phase'
)
proj.write_text(text, encoding='utf-8')

print('Stage 023 terrain rebuild applied')
