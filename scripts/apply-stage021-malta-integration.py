#!/usr/bin/env python3
"""Apply the Stage 021 Malta integration as exact, fail-fast source patches."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def regex_once(text: str, pattern: str, replacement: str, label: str) -> str:
    result, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one regex match, found {count}")
    return result


def patch_bridge_header() -> None:
    path = "Simulation/Bridge/FAJSBSimBridge.h"
    text = read(path)
    marker = "NS_ASSUME_NONNULL_BEGIN\n"
    addition = """NS_ASSUME_NONNULL_BEGIN\n\n/// Stage 021 terrain is owned by the Objective-C++ bridge so JSBSim contact and\n/// RealityKit rendering sample the exact same baked Malta DEM.\nFOUNDATION_EXPORT double FATerrainHeightMeters(double eastMeters, double northMeters);\nFOUNDATION_EXPORT double FATerrainSeaLevelMeters(void);\n"""
    text = replace_once(text, marker, addition, "bridge header terrain exports")
    write(path, text)


def patch_bridge_impl() -> None:
    path = "Simulation/Bridge/FAJSBSimBridge.mm"
    text = read(path)
    text = replace_once(
        text,
        "#include <cmath>\n#include <exception>",
        "#include <cmath>\n#include <cstdint>\n#include <exception>",
        "bridge cstdint include",
    )
    text = replace_once(
        text,
        "#include <string>\n\nnamespace {",
        "#include <string>\n\n#include \"Stage021MaltaTerrain.inc\"\n\nnamespace {",
        "bridge generated terrain include",
    )

    terrain_replacement = r'''// Stage 021 replaces the synthetic terrain equation with a compact, baked Malta
// heightfield. The array is generated from Terrarium elevation data at 125 m sample
// spacing. Airfield flattening is applied here, once, so both JSBSim and RealityKit
// receive the same runway/contact surface.
double SampleStage021TerrainMeters(double eastMeters, double northMeters) {
    const double gridX = (eastMeters + kFAStage021TerrainHalfMeters) /
        kFAStage021TerrainSpacingMeters;
    const double gridZ = (northMeters + kFAStage021TerrainHalfMeters) /
        kFAStage021TerrainSpacingMeters;

    if (gridX < 0.0 || gridZ < 0.0 ||
        gridX > static_cast<double>(kFAStage021TerrainResolution - 1) ||
        gridZ > static_cast<double>(kFAStage021TerrainResolution - 1)) {
        return kFAStage021SeaLevelMeters - 24.0;
    }

    const int x0 = std::clamp(
        static_cast<int>(std::floor(gridX)),
        0,
        kFAStage021TerrainResolution - 1
    );
    const int z0 = std::clamp(
        static_cast<int>(std::floor(gridZ)),
        0,
        kFAStage021TerrainResolution - 1
    );
    const int x1 = std::min(x0 + 1, kFAStage021TerrainResolution - 1);
    const int z1 = std::min(z0 + 1, kFAStage021TerrainResolution - 1);
    const double tx = gridX - static_cast<double>(x0);
    const double tz = gridZ - static_cast<double>(z0);

    const auto sample = [](int x, int z) {
        const int index = z * kFAStage021TerrainResolution + x;
        return static_cast<double>(kFAStage021TerrainDecimeters[index]) * 0.1;
    };

    const double h00 = sample(x0, z0);
    const double h10 = sample(x1, z0);
    const double h01 = sample(x0, z1);
    const double h11 = sample(x1, z1);
    const double h0 = h00 + (h10 - h00) * tx;
    const double h1 = h01 + (h11 - h01) * tx;
    return h0 + (h1 - h0) * tz;
}

double TerrainHeightMeters(double eastMeters, double northMeters) {
    const double rawHeight = SampleStage021TerrainMeters(eastMeters, northMeters);

    // Full Authority's authored airbase sits over Luqa RWY 31. Keep the runway,
    // parallel taxiway and apron genuinely flat, then blend into Malta's real relief.
    const double dx = std::max(std::abs(eastMeters) - 900.0, 0.0);
    const double dz = std::max(std::abs(northMeters - 1800.0) - 2500.0, 0.0);
    const double distanceOutsideAirfield = std::hypot(dx, dz);
    const double terrainBlend = SmoothStep(distanceOutsideAirfield / 650.0);
    return rawHeight * terrainBlend;
}

class FATerrainGroundCallback'''

    pattern = r'''// This function is intentionally mirrored in Stage2TerrainProfile on the Swift\n// side\..*?double TerrainHeightMeters\(double eastMeters, double northMeters\) \{.*?\n\}\n\nclass FATerrainGroundCallback'''
    text = regex_once(text, pattern, terrain_replacement, "bridge terrain implementation")

    text = replace_once(
        text,
        "};\n}\n\n@interface FAJSBSimBridge ()",
        """};
}

extern "C" double FATerrainHeightMeters(double eastMeters, double northMeters) {
    return TerrainHeightMeters(eastMeters, northMeters);
}

extern "C" double FATerrainSeaLevelMeters(void) {
    return kFAStage021SeaLevelMeters;
}

@interface FAJSBSimBridge ()""",
        "bridge C terrain exports",
    )
    write(path, text)


def patch_swift_terrain() -> None:
    path = "Simulation/FlightSimulation.swift"
    text = read(path)
    replacement = '''enum Stage2TerrainProfile {
    static func heightMeters(east: Float, north: Float) -> Float {
        Float(FATerrainHeightMeters(Double(east), Double(north)))
    }

    static var seaLevelMeters: Float {
        Float(FATerrainSeaLevelMeters())
    }

    static func normal(east: Float, north: Float) -> SIMD3<Float> {
        let sample: Float = 8
        let dhde = (
            heightMeters(east: east + sample, north: north) -
            heightMeters(east: east - sample, north: north)
        ) / (2 * sample)
        let dhdn = (
            heightMeters(east: east, north: north + sample) -
            heightMeters(east: east, north: north - sample)
        ) / (2 * sample)
        return simd_normalize(SIMD3<Float>(-dhde, 1, -dhdn))
    }
}

@MainActor
final class FlightSimulation'''
    text = regex_once(
        text,
        r'''enum Stage2TerrainProfile \{.*?\n\}\n\n@MainActor\nfinal class FlightSimulation''',
        replacement,
        "Swift Stage2TerrainProfile",
    )
    write(path, text)


def patch_world_factory() -> None:
    path = "App/Stage2WorldFactory.swift"
    text = read(path)
    text = replace_once(
        text,
        '''    static func make() -> Entity {
        let root = Entity()
        root.name = "FA.world.stage2"

        addTerrain(to: root)
        addCloudscape(to: root)
        addAirbase(to: root)
        addRoads(to: root)
        addStage019Environment(to: root)

        return root
    }''',
        '''    static func make(includeLegacyRegionalRoads: Bool = true) -> Entity {
        let root = Entity()
        root.name = "FA.world.stage2"

        addTerrain(to: root)
        addCloudscape(to: root)
        addAirbase(to: root)
        if includeLegacyRegionalRoads {
            addRoads(to: root)
        }
        addStage019Environment(to: root)

        return root
    }''',
        "Stage2WorldFactory legacy-road switch",
    )
    write(path, text)


def patch_scene() -> None:
    path = "App/PrototypeSceneView.swift"
    text = read(path)
    text = replace_once(
        text,
        "let world = Stage020ProceduralWorld.make(base: Stage2WorldFactory.make())",
        "let world = Stage021MaltaWorld.make(base: Stage2WorldFactory.make(includeLegacyRegionalRoads: false))",
        "PrototypeSceneView world selection",
    )
    write(path, text)


def patch_stage021_renderer() -> None:
    path = "App/Stage021MaltaWorld.swift"
    text = read(path)
    text = replace_once(
        text,
        "            material.specular = .init(floatLiteral: 0.17)\n            return material",
        "            material.specular = .init(floatLiteral: 0.17)\n            material.faceCulling = .none\n            return material",
        "Stage021 road culling",
    )
    text = replace_once(
        text,
        "            marking.specular = .init(floatLiteral: 0.10)\n            let entity",
        "            marking.specular = .init(floatLiteral: 0.10)\n            marking.faceCulling = .none\n            let entity",
        "Stage021 marking culling",
    )
    write(path, text)


def patch_xcode_project() -> None:
    path = "FullAuthority.xcodeproj/project.pbxproj"
    text = read(path)
    text = replace_once(
        text,
        "\t\tFA000000000000000000000D /* Stage020ProceduralWorld.swift in Sources */ = {isa = PBXBuildFile; fileRef = FA000000000000000000001F /* Stage020ProceduralWorld.swift */; };\n",
        "\t\tFA000000000000000000000D /* Stage020ProceduralWorld.swift in Sources */ = {isa = PBXBuildFile; fileRef = FA000000000000000000001F /* Stage020ProceduralWorld.swift */; };\n\t\tFA2100000000000000000001 /* Stage021MaltaWorld.swift in Sources */ = {isa = PBXBuildFile; fileRef = FA2100000000000000000011 /* Stage021MaltaWorld.swift */; };\n",
        "Xcode Stage021 build file",
    )
    text = replace_once(
        text,
        "\t\tFA000000000000000000001F /* Stage020ProceduralWorld.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Stage020ProceduralWorld.swift; sourceTree = \"<group>\"; };\n",
        "\t\tFA000000000000000000001F /* Stage020ProceduralWorld.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Stage020ProceduralWorld.swift; sourceTree = \"<group>\"; };\n\t\tFA2100000000000000000011 /* Stage021MaltaWorld.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Stage021MaltaWorld.swift; sourceTree = \"<group>\"; };\n",
        "Xcode Stage021 file reference",
    )
    text = replace_once(
        text,
        "\t\t\t\tFA000000000000000000001F /* Stage020ProceduralWorld.swift */,\n\t\t\t\tFA000000000000000000001D /* Stage2FlightEffects.swift */,",
        "\t\t\t\tFA000000000000000000001F /* Stage020ProceduralWorld.swift */,\n\t\t\t\tFA2100000000000000000011 /* Stage021MaltaWorld.swift */,\n\t\t\t\tFA000000000000000000001D /* Stage2FlightEffects.swift */,",
        "Xcode Stage021 App group",
    )
    text = replace_once(
        text,
        "\t\t\t\tFA000000000000000000000D /* Stage020ProceduralWorld.swift in Sources */,\n\t\t\t\tFA000000000000000000000B /* Stage2FlightEffects.swift in Sources */,",
        "\t\t\t\tFA000000000000000000000D /* Stage020ProceduralWorld.swift in Sources */,\n\t\t\t\tFA2100000000000000000001 /* Stage021MaltaWorld.swift in Sources */,\n\t\t\t\tFA000000000000000000000B /* Stage2FlightEffects.swift in Sources */,",
        "Xcode Stage021 Sources phase",
    )
    write(path, text)


def patch_ci() -> None:
    for path in [".github/workflows/ios-simulator.yml", ".github/workflows/ios-device-ipa.yml"]:
        text = read(path)
        needle = "          test -s \"$APP_PATH/JSBSim/visuals/f16/LICENSE-FlightSim_F16.txt\"\n"
        replacement = needle + "          test -s \"$APP_PATH/JSBSim/visuals/world/stage021_malta_world.bin\"\n          test -s \"$APP_PATH/JSBSim/visuals/world/LICENSE-Stage021-Malta-Data.txt\"\n"
        text = replace_once(text, needle, replacement, f"{path} Stage021 resource checks")
        write(path, text)


def main() -> None:
    patch_bridge_header()
    patch_bridge_impl()
    patch_swift_terrain()
    patch_world_factory()
    patch_scene()
    patch_stage021_renderer()
    patch_xcode_project()
    patch_ci()
    print("Stage 021 Malta integration patches applied successfully.")


if __name__ == "__main__":
    main()
