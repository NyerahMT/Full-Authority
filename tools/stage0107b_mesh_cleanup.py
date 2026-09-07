from pathlib import Path
import re

factory = Path("Aircraft/PrototypeAircraftFactory.swift")
text = factory.read_text()

def replace_once(old, new, label):
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, got {count}")
    text = text.replace(old, new, 1)

replace_once("            addVisualDetail(to: visualRoot)\n", "", "remove addVisualDetail call")

replace_once(
'''            let airframeMaterial = SimpleMaterial(
                color: UIColor(red: 0.39, green: 0.41, blue: 0.42, alpha: 1),
                isMetallic: false
            )''',
'''            let airframeMaterial = SimpleMaterial(
                color: UIColor(red: 0.43, green: 0.45, blue: 0.46, alpha: 1),
                isMetallic: false
            )''',
"airframe material"
)

needle = '''            let model = ModelEntity(mesh: geometry.airframe, materials: [airframeMaterial])
            model.name = meshName
            visualRoot.addChild(model)

'''
insert = '''            let model = ModelEntity(mesh: geometry.airframe, materials: [airframeMaterial])
            model.name = meshName
            visualRoot.addChild(model)

            if let canopyMesh = geometry.canopy {
                let canopyMaterial = SimpleMaterial(
                    color: UIColor(red: 0.055, green: 0.085, blue: 0.10, alpha: 1),
                    isMetallic: true
                )
                let canopy = ModelEntity(mesh: canopyMesh, materials: [canopyMaterial])
                canopy.name = "FA.aircraft.canopy.stock"
                visualRoot.addChild(canopy)
            }

            if let radomeMesh = geometry.radome {
                let radomeMaterial = SimpleMaterial(
                    color: UIColor(red: 0.20, green: 0.21, blue: 0.21, alpha: 1),
                    isMetallic: false
                )
                let radome = ModelEntity(mesh: radomeMesh, materials: [radomeMaterial])
                radome.name = "FA.aircraft.radome.stock"
                visualRoot.addChild(radome)
            }

            if let exhaustMesh = geometry.exhaust {
                let exhaustMaterial = SimpleMaterial(
                    color: UIColor(red: 0.15, green: 0.15, blue: 0.145, alpha: 1),
                    isMetallic: true
                )
                let exhaust = ModelEntity(mesh: exhaustMesh, materials: [exhaustMaterial])
                exhaust.name = "FA.aircraft.exhaust.stock"
                visualRoot.addChild(exhaust)
            }

'''
replace_once(needle, insert, "stock material parts insertion")

pattern = re.compile(
    r'\n    private static func addVisualDetail\(to root: Entity\) \{.*?\n    \}\n\n    private static func addAnimatedSurfaces',
    re.S,
)
text, n = pattern.subn('\n    private static func addAnimatedSurfaces', text, count=1)
if n != 1:
    raise SystemExit(f"remove addVisualDetail function: expected 1 match, got {n}")

pattern = re.compile(
    r'\n        // The source mesh does not contain clean separable four-petal speedbrakes,.*?\n        root\.addChild\(speedbrake\)\n',
    re.S,
)
text, n = pattern.subn(
    '\n        // No procedural speedbrake geometry: keep the stock mesh silhouette clean.\n',
    text,
    count=1,
)
if n != 1:
    raise SystemExit(f"remove procedural speedbrake: expected 1 match, got {n}")

axis_pattern = re.compile(
    r'    // FlightGear\'s mature F-16 model exposes these hinge-axis directions\..*?'
    r'    static let rudderVisualAxis = simd_normalize\(SIMD3<Float>\([^\n]+\)\)\n',
    re.S,
)
axis_repl = '''    // FlightGear's mature F-16 model is used only as hinge-direction
    // engineering reference. Convert its model axes (+X forward, +Y right,
    // +Z up) into the R4 / Full Authority mesh axes (+Z forward, +X right,
    // +Y up). Left/right vectors are exact mirrors by construction.
    static let leftAileronVisualAxis = simd_normalize(SIMD3<Float>(2.5165, 0.096955, -0.39329))
    static let rightAileronVisualAxis = simd_normalize(SIMD3<Float>(-2.5165, 0.096955, -0.39329))
    static let leftStabilatorVisualAxis = simd_normalize(SIMD3<Float>(-0.981645, -0.190720, 0))
    static let rightStabilatorVisualAxis = simd_normalize(SIMD3<Float>(0.981645, -0.190720, 0))
    static let rudderVisualAxis = simd_normalize(SIMD3<Float>(0, 0.836890, 0.547371))
'''
text, n = axis_pattern.subn(axis_repl, text, count=1)
if n != 1:
    raise SystemExit(f"axis block: expected 1 match, got {n}")

replace_once(
'''    private enum F16MeshPart: Hashable {
        case airframe
        case leftAileron''',
'''    private enum F16MeshPart: Hashable {
        case airframe
        case canopy
        case radome
        case exhaust
        case leftAileron''',
"mesh part enum"
)

replace_once(
'''    private struct F16MeshSet {
        let airframe: MeshResource
        let leftAileron: F16MovingMesh?''',
'''    private struct F16MeshSet {
        let airframe: MeshResource
        let canopy: MeshResource?
        let radome: MeshResource?
        let exhaust: MeshResource?
        let leftAileron: F16MovingMesh?''',
"mesh set fields"
)

replace_once(
'''                let a = face[0], b = face[index], c = face[index + 1]
                let centroid = (a.position + b.position + c.position) / 3
                let part = classifyF16Triangle(centroid)''',
'''                let a = face[0], b = face[index], c = face[index + 1]
                let part = classifyF16Triangle(a.position, b.position, c.position)''',
"triangle classification call"
)

replace_once(
'''        return F16MeshSet(
            airframe: airframe,
            leftAileron: try makeMovingMesh(builders[.leftAileron], part: .leftAileron),''',
'''        return F16MeshSet(
            airframe: airframe,
            canopy: try makeStaticMesh(builders[.canopy], name: "F-16 canopy stock faces"),
            radome: try makeStaticMesh(builders[.radome], name: "F-16 radome stock faces"),
            exhaust: try makeStaticMesh(builders[.exhaust], name: "F-16 exhaust stock faces"),
            leftAileron: try makeMovingMesh(builders[.leftAileron], part: .leftAileron),''',
"mesh set return"
)

class_pattern = re.compile(
    r'    private static func classifyF16Triangle\(_ point: SIMD3<Float>\) -> F16MeshPart \{.*?\n    \}\n\n    private static func pointInPolygon',
    re.S,
)
class_repl = r'''    private static let rightFlaperonPlanform: [SIMD2<Float>] = [
        [1.05, -2.48],
        [3.60, -2.88],
        [3.62, -3.58],
        [1.35, -3.58]
    ]

    private static let rightStabilatorPlanform: [SIMD2<Float>] = [
        [0.92, -4.52],
        [1.48, -4.50],
        [3.06, -6.02],
        [3.06, -6.92],
        [0.92, -6.86]
    ]

    private static func classifyF16Triangle(
        _ a: SIMD3<Float>,
        _ b: SIMD3<Float>,
        _ c: SIMD3<Float>
    ) -> F16MeshPart {
        let vertices = [a, b, c]
        let centroid = (a + b + c) / 3

        if let side = mirroredSurfaceSide(
            vertices,
            yRange: -1.42 ... -0.82,
            canonicalRightPlanform: rightFlaperonPlanform
        ) {
            return side < 0 ? .leftAileron : .rightAileron
        }

        if let side = mirroredSurfaceSide(
            vertices,
            yRange: -1.32 ... -0.55,
            canonicalRightPlanform: rightStabilatorPlanform
        ) {
            return side < 0 ? .leftStabilator : .rightStabilator
        }

        let rudderTriangle = vertices.allSatisfy { vertex in
            guard abs(vertex.x) < 0.34,
                  vertex.y > 0.18,
                  vertex.y < 2.38,
                  vertex.z > -7.35 else {
                return false
            }
            let hingeZ = -5.50 - 0.654 * vertex.y
            return vertex.z < hingeZ - 0.015
        }
        if rudderTriangle {
            return .rudder
        }

        if centroid.z > 2.18,
           centroid.z < 4.55,
           centroid.y > -0.52,
           abs(centroid.x) < 0.95 {
            return .canopy
        }

        if centroid.z > 6.05 {
            return .radome
        }

        if centroid.z < -6.45,
           abs(centroid.x) < 0.95,
           centroid.y < -0.55 {
            return .exhaust
        }

        return .airframe
    }

    private static func mirroredSurfaceSide(
        _ vertices: [SIMD3<Float>],
        yRange: ClosedRange<Float>,
        canonicalRightPlanform: [SIMD2<Float>]
    ) -> Float? {
        guard vertices.count == 3 else { return nil }
        let centroidX = vertices.reduce(Float(0)) { $0 + $1.x } / Float(vertices.count)
        let side: Float = centroidX < 0 ? -1 : 1

        guard vertices.allSatisfy({
            ($0.x * side) > 0.72 &&
            yRange.contains($0.y) &&
            pointInPolygon(SIMD2<Float>(abs($0.x), $0.z), polygon: canonicalRightPlanform)
        }) else {
            return nil
        }
        return side
    }

    private static func pointInPolygon'''
text, n = class_pattern.subn(class_repl, text, count=1)
if n != 1:
    raise SystemExit(f"classifier block: expected 1 match, got {n}")

needle = '''    private static func makeMovingMesh(_ builder: RawMeshBuilder?, part: F16MeshPart) throws -> F16MovingMesh? {
'''
insert = '''    private static func makeStaticMesh(_ builder: RawMeshBuilder?, name: String) throws -> MeshResource? {
        guard let builder, builder.indices.count >= 3 else { return nil }
        return try makeMeshResource(from: builder, name: name, subtracting: .zero)
    }

    private static func makeMovingMesh(_ builder: RawMeshBuilder?, part: F16MeshPart) throws -> F16MovingMesh? {
'''
replace_once(needle, insert, "static mesh helper")

pivot_pattern = re.compile(
    r'    private static func movingSurfacePivot\(part: F16MeshPart, positions: \[SIMD3<Float>\]\) -> SIMD3<Float> \{.*?\n    \}\n',
    re.S,
)
pivot_repl = '''    private static func movingSurfacePivot(part: F16MeshPart, positions: [SIMD3<Float>]) -> SIMD3<Float> {
        _ = positions
        switch part {
        case .leftAileron: return [-2.325, -1.12, -2.68]
        case .rightAileron: return [2.325, -1.12, -2.68]
        case .leftStabilator: return [-1.965, -0.94, -5.30]
        case .rightStabilator: return [1.965, -0.94, -5.30]
        case .rudder:
            let pivotY: Float = 1.15
            return [0, pivotY, -5.50 - 0.654 * pivotY]
        case .airframe, .canopy, .radome, .exhaust:
            return .zero
        }
    }
'''
text, n = pivot_pattern.subn(pivot_repl, text, count=1)
if n != 1:
    raise SystemExit(f"pivot block: expected 1 match, got {n}")

factory.write_text(text)

scene = Path("App/PrototypeSceneView.swift")
s = scene.read_text()
old = '''        if let left = aircraft.findEntity(named: PrototypeAircraftFactory.leftElevatorName) {
            // JSBSim's differential-tail left/right outputs use mirrored local
            // surface conventions. Our two visual hinges share +X, so the left
            // tail must invert its angle to represent the same physical motion.
            left.orientation = simd_quatf(angle: -state.leftStabilatorRadians, axis: PrototypeAircraftFactory.leftStabilatorVisualAxis)
        }'''
new = '''        if let left = aircraft.findEntity(named: PrototypeAircraftFactory.leftElevatorName) {
            // JSBSim's dht-left/dht-right outputs already carry mirrored local
            // signs. With mirror-correct hinge axes, use those angles verbatim.
            left.orientation = simd_quatf(angle: state.leftStabilatorRadians, axis: PrototypeAircraftFactory.leftStabilatorVisualAxis)
        }'''
if s.count(old) != 1:
    raise SystemExit("scene left stabilator block mismatch")
s = s.replace(old, new, 1)

old = '''        if let rudder = aircraft.findEntity(named: PrototypeAircraftFactory.rudderName) {
            rudder.orientation = simd_quatf(angle: -state.rudderRadians, axis: PrototypeAircraftFactory.rudderVisualAxis)
        }'''
new = '''        if let rudder = aircraft.findEntity(named: PrototypeAircraftFactory.rudderName) {
            rudder.orientation = simd_quatf(angle: state.rudderRadians, axis: PrototypeAircraftFactory.rudderVisualAxis)
        }'''
if s.count(old) != 1:
    raise SystemExit("scene rudder block mismatch")
s = s.replace(old, new, 1)
scene.write_text(s)
