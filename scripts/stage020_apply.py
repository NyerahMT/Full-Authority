from pathlib import Path


def load(path: str) -> str:
    return Path(path).read_text()


def save(path: str, text: str) -> None:
    Path(path).write_text(text)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 anchor, found {count}")
    return text.replace(old, new, 1)


# Xcode project ---------------------------------------------------------------
project_path = "FullAuthority.xcodeproj/project.pbxproj"
p = load(project_path)
build_lines = """\t\tFA0200000000000000000001 /* Stage020WorldUpgrade.swift in Sources */ = {isa = PBXBuildFile; fileRef = FA0200000000000000000011 /* Stage020WorldUpgrade.swift */; };\n\t\tFA0200000000000000000002 /* Stage020SkyEnvironment.swift in Sources */ = {isa = PBXBuildFile; fileRef = FA0200000000000000000012 /* Stage020SkyEnvironment.swift */; };\n\t\tFA0200000000000000000003 /* Stage020AircraftDetails.swift in Sources */ = {isa = PBXBuildFile; fileRef = FA0200000000000000000013 /* Stage020AircraftDetails.swift */; };\n\t\tFA0200000000000000000004 /* Stage020CockpitDetails.swift in Sources */ = {isa = PBXBuildFile; fileRef = FA0200000000000000000014 /* Stage020CockpitDetails.swift */; };\n"""
if "FA0200000000000000000001" not in p:
    p = replace_once(p, "/* End PBXBuildFile section */", build_lines + "/* End PBXBuildFile section */", "PBXBuildFile")

ref_lines = """\t\tFA0200000000000000000011 /* Stage020WorldUpgrade.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Stage020WorldUpgrade.swift; sourceTree = \"<group>\"; };\n\t\tFA0200000000000000000012 /* Stage020SkyEnvironment.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Stage020SkyEnvironment.swift; sourceTree = \"<group>\"; };\n\t\tFA0200000000000000000013 /* Stage020AircraftDetails.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Stage020AircraftDetails.swift; sourceTree = \"<group>\"; };\n\t\tFA0200000000000000000014 /* Stage020CockpitDetails.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Stage020CockpitDetails.swift; sourceTree = \"<group>\"; };\n"""
if "FA0200000000000000000011 /* Stage020WorldUpgrade.swift */ = {isa = PBXFileReference" not in p:
    p = replace_once(p, "/* End PBXFileReference section */", ref_lines + "/* End PBXFileReference section */", "PBXFileReference")

app_anchor = "\t\t\t\tFA000000000000000000001D /* Stage2FlightEffects.swift */,\n"
if "FA0200000000000000000011 /* Stage020WorldUpgrade.swift */," not in p:
    p = replace_once(
        p, app_anchor,
        app_anchor + "\t\t\t\tFA0200000000000000000011 /* Stage020WorldUpgrade.swift */,\n\t\t\t\tFA0200000000000000000012 /* Stage020SkyEnvironment.swift */,\n",
        "App group"
    )

aircraft_anchor = "\t\t\t\tFA000000000000000000001E /* PrototypeCockpitFactory.swift */,\n"
if "FA0200000000000000000013 /* Stage020AircraftDetails.swift */," not in p:
    p = replace_once(
        p, aircraft_anchor,
        aircraft_anchor + "\t\t\t\tFA0200000000000000000013 /* Stage020AircraftDetails.swift */,\n\t\t\t\tFA0200000000000000000014 /* Stage020CockpitDetails.swift */,\n",
        "Aircraft group"
    )

sources_anchor = "\t\t\t\tFA000000000000000000000B /* Stage2FlightEffects.swift in Sources */,\n"
if "FA0200000000000000000001 /* Stage020WorldUpgrade.swift in Sources */," not in p:
    p = replace_once(
        p, sources_anchor,
        sources_anchor + "\t\t\t\tFA0200000000000000000001 /* Stage020WorldUpgrade.swift in Sources */,\n\t\t\t\tFA0200000000000000000002 /* Stage020SkyEnvironment.swift in Sources */,\n\t\t\t\tFA0200000000000000000003 /* Stage020AircraftDetails.swift in Sources */,\n\t\t\t\tFA0200000000000000000004 /* Stage020CockpitDetails.swift in Sources */,\n",
        "Sources phase"
    )
save(project_path, p)


# Base world ------------------------------------------------------------------
world_path = "App/Stage2WorldFactory.swift"
w = load(world_path)
w = replace_once(
    w,
    "        addStage019Environment(to: root)\n\n        return root",
    "        addStage019Environment(to: root)\n        root.addChild(Stage020WorldUpgrade.make())\n\n        return root",
    "Stage020 world hookup"
)
w = w.replace("for index in 0..<14 {", "for index in 0..<7 {", 1)
w = w.replace("for index in 0..<10 {", "for index in 0..<3 {", 1)
w = w.replace("let angle = Float(index) / 10 * 2 * Float.pi + 0.21", "let angle = Float(index) / 3 * 2 * Float.pi + 0.21", 1)

terrain_start = w.index("    private static func terrainMaterial(")
terrain_end = w.index("    private static func pbrSurfaceMaterial(", terrain_start)
terrain = w[terrain_start:terrain_end]
old_tints = """        let tints: [UIColor] = [
            UIColor(red: 0.72, green: 0.78, blue: 0.58, alpha: 1),
            UIColor(red: 0.82, green: 0.78, blue: 0.54, alpha: 1),
            UIColor(red: 0.64, green: 0.73, blue: 0.51, alpha: 1),
            UIColor(red: 0.82, green: 0.69, blue: 0.47, alpha: 1),
            UIColor(red: 0.68, green: 0.68, blue: 0.47, alpha: 1),
            UIColor(red: 0.76, green: 0.79, blue: 0.57, alpha: 1)
        ]"""
new_tints = """        let tints: [UIColor] = [
            UIColor(red: 0.68, green: 0.74, blue: 0.62, alpha: 1),
            UIColor(red: 0.73, green: 0.76, blue: 0.65, alpha: 1),
            UIColor(red: 0.62, green: 0.70, blue: 0.58, alpha: 1),
            UIColor(red: 0.70, green: 0.72, blue: 0.61, alpha: 1),
            UIColor(red: 0.64, green: 0.69, blue: 0.57, alpha: 1),
            UIColor(red: 0.71, green: 0.75, blue: 0.63, alpha: 1)
        ]"""
terrain = replace_once(terrain, old_tints, new_tints, "terrain palette")
terrain = replace_once(
    terrain,
    """        } else {
            material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.90)
        }
        material.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: 0.0)""",
    """        } else {
            material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.90)
        }
        if let normal = textures.normal {
            material.normal = PhysicallyBasedMaterial.Normal(texture: repeatedTexture(normal))
        }
        material.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: 0.0)""",
    "terrain normal material"
)
w = w[:terrain_start] + terrain + w[terrain_end:]

mesh_start = w.index("    private static func makeTerrainTile(")
mesh_end = w.index("    // MARK: -", mesh_start)
mesh = w[mesh_start:mesh_end]
mesh = replace_once(mesh, "        var normals: [SIMD3<Float>] = []\n        var texcoords:", "        var normals: [SIMD3<Float>] = []\n        var tangents: [SIMD3<Float>] = []\n        var texcoords:", "terrain tangent array")
mesh = replace_once(mesh, "        normals.reserveCapacity(vertexCount)\n        texcoords.reserveCapacity(vertexCount)", "        normals.reserveCapacity(vertexCount)\n        tangents.reserveCapacity(vertexCount)\n        texcoords.reserveCapacity(vertexCount)", "terrain tangent reserve")
mesh = replace_once(
    mesh,
    "                positions.append([localX, height, localZ])\n                normals.append(Stage2TerrainProfile.normal(east: globalX, north: globalZ))",
    """                positions.append([localX, height, localZ])
                let surfaceNormal = Stage2TerrainProfile.normal(east: globalX, north: globalZ)
                normals.append(surfaceNormal)
                let xAxis = SIMD3<Float>(1, 0, 0)
                let projected = xAxis - surfaceNormal * simd_dot(xAxis, surfaceNormal)
                tangents.append(simd_length_squared(projected) > 0.000001 ? simd_normalize(projected) : SIMD3<Float>(0, 0, 1))""",
    "terrain tangent generation"
)
mesh = replace_once(mesh, "        descriptor.normals = MeshBuffers.Normals(normals)\n        descriptor.textureCoordinates", "        descriptor.normals = MeshBuffers.Normals(normals)\n        descriptor.tangents = MeshBuffers.Tangents(tangents)\n        descriptor.textureCoordinates", "terrain descriptor tangents")
w = w[:mesh_start] + mesh + w[mesh_end:]
save(world_path, w)


# Scene / sky / lighting -------------------------------------------------------
scene_path = "App/PrototypeSceneView.swift"
s = load(scene_path)
s = replace_once(
    s,
    "                    content.environment = .default\n\n                    let world = Stage2WorldFactory.make()",
    """                    content.environment = .default
                    if let environment = await Stage020SkyEnvironment.load() {
                        content.environment = .skybox(environment)
                    }

                    let world = Stage2WorldFactory.make()""",
    "HDR sky hookup"
)
s = s.replace("environmentLightingWeight: 0.48", "environmentLightingWeight: 0.70", 1)
s = s.replace("environmentLightingWeight: 0.56", "environmentLightingWeight: 0.66", 1)
s = replace_once(s, "color: UIColor(red: 1.0, green: 0.88, blue: 0.72, alpha: 1),\n                            intensity: 10_400", "color: UIColor(red: 1.0, green: 0.965, blue: 0.90, alpha: 1),\n                            intensity: 7_800", "sun daylight")
s = replace_once(s, "color: UIColor(red: 0.42, green: 0.58, blue: 0.86, alpha: 1),\n                        intensity: 210", "color: UIColor(red: 0.58, green: 0.66, blue: 0.76, alpha: 1),\n                        intensity: 70", "fill daylight")
s = replace_once(
    s,
    """                .init(color: Color(red: 0.008, green: 0.070, blue: 0.205), location: 0.00),
                .init(color: Color(red: 0.025, green: 0.205, blue: 0.455), location: 0.38),
                .init(color: Color(red: 0.225, green: 0.455, blue: 0.655), location: 0.68),
                .init(color: Color(red: 0.565, green: 0.625, blue: 0.640), location: 0.86),
                .init(color: Color(red: 0.760, green: 0.665, blue: 0.535), location: 1.00)""",
    """                .init(color: Color(red: 0.018, green: 0.105, blue: 0.260), location: 0.00),
                .init(color: Color(red: 0.060, green: 0.245, blue: 0.470), location: 0.42),
                .init(color: Color(red: 0.285, green: 0.505, blue: 0.665), location: 0.72),
                .init(color: Color(red: 0.640, green: 0.705, blue: 0.730), location: 0.90),
                .init(color: Color(red: 0.750, green: 0.775, blue: 0.770), location: 1.00)""",
    "fallback sky palette"
)
rudder_anchor = """        if let rudder = aircraft.findEntity(named: PrototypeAircraftFactory.rudderName) {
            rudder.orientation = simd_quatf(
                angle: -state.rudderRadians,
                axis: PrototypeAircraftFactory.rudderVisualAxis
            )
        }
"""
rudder_new = rudder_anchor + """        let pedalCommand = clamp(simulation.controls.rudder, -1, 1)
        aircraft.findEntity(named: Stage020CockpitDetails.leftPedalName)?.orientation = simd_quatf(
            angle: pedalCommand * 0.16, axis: [1, 0, 0]
        )
        aircraft.findEntity(named: Stage020CockpitDetails.rightPedalName)?.orientation = simd_quatf(
            angle: -pedalCommand * 0.16, axis: [1, 0, 0]
        )
        if let beacon = aircraft.findEntity(named: Stage020AircraftDetails.antiCollisionName) {
            beacon.isEnabled = simulation.simulationTime.truncatingRemainder(dividingBy: 1.20) < 0.11
        }
"""
s = replace_once(s, rudder_anchor, rudder_new, "pedal presentation")
save(scene_path, s)


# Aircraft / cockpit -----------------------------------------------------------
aircraft_path = "Aircraft/PrototypeAircraftFactory.swift"
a = load(aircraft_path)
a = replace_once(a, "            try addAfterburner(to: visualRoot)\n            addLandingGear(to: aircraft)", "            try addAfterburner(to: visualRoot)\n            visualRoot.addChild(Stage020AircraftDetails.make())\n            addLandingGear(to: aircraft)", "aircraft details hookup")
save(aircraft_path, a)

cockpit_path = "Aircraft/PrototypeCockpitFactory.swift"
c = load(cockpit_path)
c = replace_once(c, "        return root\n    }\n\n    private static func addMFD(", "        root.addChild(Stage020CockpitDetails.make())\n        return root\n    }\n\n    private static func addMFD(", "cockpit details hookup")
save(cockpit_path, c)

detail_path = "Aircraft/Stage020CockpitDetails.swift"
d = load(detail_path)
d = d.replace(".generatePlane(width: 0.68, height: 1.25)", ".generatePlane(width: 0.68, depth: 1.25)")
d = d.replace("pane.orientation = simd_quatf(angle: side * 0.23, axis: [0, 1, 0])\n                * simd_quatf(angle: -0.08, axis: [1, 0, 0])", "pane.orientation = simd_quatf(angle: side * 0.23, axis: [0, 1, 0])\n                * simd_quatf(angle: .pi / 2 - 0.08, axis: [1, 0, 0])")
save(detail_path, d)


# UI / touch controls ----------------------------------------------------------
ui_path = "App/ContentView.swift"
u = load(ui_path)
u = u.replace(".opacity(cameraMode == .cockpit ? 1.0 : 0.78)", ".opacity(cameraMode == .cockpit ? 1.0 : 0.66)", 1)
u = replace_once(u, "                .safeAreaPadding(.horizontal, 26)\n                .padding(.bottom, 10)", "                .safeAreaPadding(.horizontal, 26)\n                .safeAreaPadding(.bottom, 12)\n                .padding(.bottom, 2)", "bottom safe area")
u = u.replace('Text("RUDDER / NWS")', 'Text("RUDDER  /  NWS")', 1)
u = u.replace(".frame(width: 26, height: 26)", ".frame(width: 34, height: 34)", 1)
u = u.replace("onChange(abs(clamped) < 0.04 ? 0 : clamped)", "onChange(abs(clamped) < 0.025 ? 0 : clamped)", 1)
u = u.replace(".frame(width: 180, height: 29)", ".frame(width: 224, height: 52)", 1)
u = u.replace('Text("STAGE 2")', 'Text("F-16A BLOCK 32")', 1)
u = u.replace('Text("F-16A / RUNWAY SORTIE")', 'Text("DAY VFR / TRAINING RANGE")', 1)
u = u.replace('Text("Runway start, direct JSBSim F-16 dynamics, native terrain contact and aircraft-relative cameras.")', 'Text("Cold start is skipped. You have the airplane, a live range, direct JSBSim dynamics, and enough world to actually fly it.")', 1)
u = u.replace('Text("F-16A · JSBSim direct FDM · STAGE 2")', 'Text("F-16A BLOCK 32 · JSBSim direct FDM")', 1)
save(ui_path, u)


# Simulation comment -----------------------------------------------------------
sim_path = "Simulation/FlightSimulation.swift"
f = load(sim_path)
f = replace_once(
    f,
    """        // Full Authority's touch control is screen-centric: dragging right means
        // right pedal / nose-right. The current F-16 resource patch converts this
        // sign again at the model boundary; NWS uses this sign directly.
        let pilotYawCommand = -Double(controls.rudder)""",
    """        // Full Authority's touch control is screen-centric: dragging right means
        // right pedal / nose-right. Stage 020 feeds this pilot command into the
        // F-16 scheduler once; stability feedback remains a separate SAS signal.
        let pilotYawCommand = -Double(controls.rudder)""",
    "yaw input comment"
)
save(sim_path, f)


# JSBSim staging / yaw law -----------------------------------------------------
stage_path = "scripts/stage-f16-calibration.sh"
sh = load(stage_path)
start = sh.index("# Keep the upstream yaw controller intact")
end = sh.index("# Render art is now bundled", start)
replacement = r"""# Stage 020 yaw-control correction.
#
# The upstream XML feeds rudder-cmd-norm into the yaw feedback error and then
# adds the same pilot command again in yaw-scheduler. Our older patch compounded
# that with another 28% feed-forward. Stage 020 removes that extra feed-forward
# and separates the pilot pedal from SAS feedback. Yaw-rate/lateral-acceleration
# feedback damps the aircraft; the pilot command enters the scheduler once.
python3 - "$RESOURCE_ROOT/aircraft/f16/f16.xml" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old_error = '''   <!--
     - Calculate the difference between the current yaw-rate
     - and the one requiested for.
     -->
   <summer name="fcs/yaw-trim-error">
    <input>fcs/rudder-cmd-norm</input>
    <input>fcs/yaw-rate-norm</input>
    <input>fcs/yaw-load-norm</input>
   </summer>'''
new_error = '''   <!-- Full Authority Stage 020: SAS feedback only. Pilot pedal
     command is summed once in yaw-scheduler below. -->
   <summer name="fcs/yaw-trim-error">
    <input>fcs/yaw-rate-norm</input>
    <input>fcs/yaw-load-norm</input>
   </summer>'''
if text.count(old_error) != 1:
    raise SystemExit(f"expected one upstream yaw feedback block, found {text.count(old_error)}")
text = text.replace(old_error, new_error, 1)
old_rate = '''      80.0  0.0
      100.0    15.0
      150.0    100.0'''
new_rate = '''      80.0  0.0
      100.0    15.0
      150.0    112.0'''
if text.count(old_rate) != 1:
    raise SystemExit(f"expected one yaw-rate schedule, found {text.count(old_rate)}")
text = text.replace(old_rate, new_rate, 1)
scheduler = '''   <summer name="fcs/yaw-scheduler">
     <input>fcs/rudder-cmd-norm</input>
     <input>fcs/yaw-trim-cmd-norm</input>
     <input>fcs/yaw-load-pid</input>'''
if text.count(scheduler) != 1:
    raise SystemExit(f"expected one direct pilot yaw scheduler, found {text.count(scheduler)}")
path.write_text(text, encoding="utf-8")
PY

grep -q 'Full Authority Stage 020: SAS feedback only' "$RESOURCE_ROOT/aircraft/f16/f16.xml"
grep -q '150.0    112.0' "$RESOURCE_ROOT/aircraft/f16/f16.xml"
test "$(grep -c '<input>fcs/rudder-cmd-norm</input>' "$RESOURCE_ROOT/aircraft/f16/f16.xml")" -eq 1
grep -q '<pid name="fcs/yaw-load-pid">' "$RESOURCE_ROOT/aircraft/f16/f16.xml"

"""
sh = sh[:start] + replacement + sh[end:]
sh = sh.replace("Staged JSBSim F-16 calibration data, yaw damping, pedal feed-forward and terrain texture", "Staged JSBSim F-16 calibration data, Stage 020 yaw SAS correction and terrain texture")
save(stage_path, sh)

Path("Assets/JSBSim/visuals/world/SOURCE-stage020-sky.txt").write_text(
    "Farm Field (Pure Sky) by Poly Haven contributors.\n"
    "Source: https://polyhaven.com/a/farm_field_puresky\n"
    "License: CC0 1.0.\n"
    "Imported at 1K EXR for RealityKit skybox/default environment lighting.\n"
)
