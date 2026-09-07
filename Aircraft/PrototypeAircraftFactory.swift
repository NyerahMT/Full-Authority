import Foundation
import RealityKit
import UIKit
import simd

@MainActor
enum PrototypeAircraftFactory {
    static let aircraftName = "FA.aircraft"
    static let visualRootName = "FA.aircraft.visual-root"
    static let meshName = "FA.aircraft.f16.mesh"
    static let afterburnerName = "FA.aircraft.afterburner"
    static let nozzleName = "FA.aircraft.nozzle"
    static let speedbrakeName = "FA.aircraft.speedbrake"
    static let leftAileronName = "FA.aircraft.aileron.left"
    static let rightAileronName = "FA.aircraft.aileron.right"
    static let leftElevatorName = "FA.aircraft.elevator.left"
    static let rightElevatorName = "FA.aircraft.elevator.right"
    static let rudderName = "FA.aircraft.rudder"
    static let noseGearName = "FA.aircraft.gear.nose"
    static let leftGearName = "FA.aircraft.gear.left"
    static let rightGearName = "FA.aircraft.gear.right"
    static let vaporLeftName = "FA.aircraft.vapor.left"
    static let vaporRightName = "FA.aircraft.vapor.right"
    static let contrailLeftName = "FA.aircraft.contrail.left"
    static let contrailRightName = "FA.aircraft.contrail.right"

    /// The source OBJ is centered around its visual bounding box, not the F-16
    /// CG used by JSBSim. JSBSim places the radome only ~0.09 m below the CG,
    /// while the source mesh placed it ~1.02 m below the root. This offset aligns
    /// the visual airframe with the FDM structural/reference coordinates.
    static let visualVerticalOffset: Float = 0.93

    private struct OBJVertexKey: Hashable {
        let position: Int
        let normal: Int
    }

    private enum OBJError: Error {
        case missingAsset
        case invalidGeometry
    }

    static func make() -> Entity {
        let root = Entity()
        root.name = aircraftName

        do {
            let visualRoot = Entity()
            visualRoot.name = visualRootName
            visualRoot.position = [0, visualVerticalOffset, 0]
            root.addChild(visualRoot)

            let geometry = try loadF16MeshSet()
            let airframeMaterial = SimpleMaterial(
                color: UIColor(red: 0.43, green: 0.45, blue: 0.46, alpha: 1),
                isMetallic: false
            )

            let model = ModelEntity(mesh: geometry.airframe, materials: [airframeMaterial])
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

            addAnimatedSurfaces(
                to: visualRoot,
                geometry: geometry,
                airframeMaterial: airframeMaterial
            )

            addLandingGear(to: root)
        } catch {
            let fallback = ModelEntity(
                mesh: .generateBox(size: [4, 1, 10], cornerRadius: 0.2),
                materials: [SimpleMaterial(color: .red, isMetallic: false)]
            )
            fallback.name = "FA.aircraft.missing-mesh"
            root.addChild(fallback)
        }

        return root
    }

    private static func addAnimatedSurfaces(
        to root: Entity,
        geometry: F16MeshSet,
        airframeMaterial: SimpleMaterial
    ) {
        // The R4 OBJ is welded and has no named flight-control groups. Classify
        // and remove its existing source triangles from the static shell, then
        // hinge those exact triangles as children. These are not overlay panels.
        addSourceMeshSurface(to: root, name: leftAileronName, movingMesh: geometry.leftAileron, material: airframeMaterial)
        addSourceMeshSurface(to: root, name: rightAileronName, movingMesh: geometry.rightAileron, material: airframeMaterial)
        addSourceMeshSurface(to: root, name: leftElevatorName, movingMesh: geometry.leftStabilator, material: airframeMaterial)
        addSourceMeshSurface(to: root, name: rightElevatorName, movingMesh: geometry.rightStabilator, material: airframeMaterial)
        addSourceMeshSurface(to: root, name: rudderName, movingMesh: geometry.rudder, material: airframeMaterial)

        // No procedural speedbrake geometry: keep the stock mesh silhouette clean.
    }

    private static func addSourceMeshSurface(
        to root: Entity,
        name: String,
        movingMesh: F16MovingMesh?,
        material: SimpleMaterial
    ) {
        guard let movingMesh else { return }
        let hinge = Entity()
        hinge.name = name
        hinge.position = movingMesh.pivot
        hinge.addChild(ModelEntity(mesh: movingMesh.mesh, materials: [material]))
        root.addChild(hinge)
    }

    private static func addLandingGear(to root: Entity) {
        let strutColor = UIColor(red: 0.72, green: 0.73, blue: 0.71, alpha: 1)
        let tireColor = UIColor(red: 0.025, green: 0.025, blue: 0.026, alpha: 1)

        // JSBSim F-16 contact geometry, converted from structural inches to
        // visual meters relative to CG. +Z in Full Authority is nose-forward.
        root.addChild(gearAssembly(
            name: noseGearName,
            rootPosition: [0, -0.33, 2.71],
            strutHeight: 1.12,
            wheelRadius: 0.25,
            wheelWidth: 0.20,
            strutColor: strutColor,
            tireColor: tireColor
        ))
        root.addChild(gearAssembly(
            name: leftGearName,
            rootPosition: [-1.22, -0.38, -0.87],
            strutHeight: 1.00,
            wheelRadius: 0.31,
            wheelWidth: 0.24,
            strutColor: strutColor,
            tireColor: tireColor
        ))
        root.addChild(gearAssembly(
            name: rightGearName,
            rootPosition: [1.22, -0.38, -0.87],
            strutHeight: 1.00,
            wheelRadius: 0.31,
            wheelWidth: 0.24,
            strutColor: strutColor,
            tireColor: tireColor
        ))
    }

    private static func gearAssembly(
        name: String,
        rootPosition: SIMD3<Float>,
        strutHeight: Float,
        wheelRadius: Float,
        wheelWidth: Float,
        strutColor: UIColor,
        tireColor: UIColor
    ) -> Entity {
        let assembly = Entity()
        assembly.name = name
        assembly.position = rootPosition

        let upperStrut = ModelEntity(
            mesh: .generateCylinder(height: strutHeight, radius: 0.068),
            materials: [SimpleMaterial(color: strutColor, isMetallic: true)]
        )
        upperStrut.position = [0, -strutHeight * 0.5, 0]
        assembly.addChild(upperStrut)

        let fork = ModelEntity(
            mesh: .generateBox(size: [wheelWidth + 0.10, 0.10, 0.10], cornerRadius: 0.03),
            materials: [SimpleMaterial(color: strutColor, isMetallic: true)]
        )
        fork.position = [0, -strutHeight + 0.03, 0]
        assembly.addChild(fork)

        let wheel = ModelEntity(
            mesh: .generateCylinder(height: wheelWidth, radius: wheelRadius),
            materials: [SimpleMaterial(color: tireColor, isMetallic: false)]
        )
        wheel.position = [0, -strutHeight, 0]
        wheel.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        assembly.addChild(wheel)

        return assembly
    }

    // FlightGear's mature F-16 model is used only as hinge-direction
    // engineering reference. Convert its model axes (+X forward, +Y right,
    // +Z up) into the R4 / Full Authority mesh axes (+Z forward, +X right,
    // +Y up). Left/right vectors are exact mirrors by construction.
    static let leftAileronVisualAxis = simd_normalize(SIMD3<Float>(2.5165, 0.096955, -0.39329))
    static let rightAileronVisualAxis = simd_normalize(SIMD3<Float>(-2.5165, 0.096955, -0.39329))
    static let leftStabilatorVisualAxis = simd_normalize(SIMD3<Float>(-0.981645, -0.190720, 0))
    static let rightStabilatorVisualAxis = simd_normalize(SIMD3<Float>(0.981645, -0.190720, 0))
    static let rudderVisualAxis = simd_normalize(SIMD3<Float>(0, 0.836890, 0.547371))

    private enum F16MeshPart: Hashable {
        case airframe
        case canopy
        case radome
        case exhaust
        case leftAileron
        case rightAileron
        case leftStabilator
        case rightStabilator
        case rudder
    }

    private struct ParsedOBJVertex {
        let position: SIMD3<Float>
        let normal: SIMD3<Float>
    }

    private struct RawMeshBuilder {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        mutating func appendTriangle(_ a: ParsedOBJVertex, _ b: ParsedOBJVertex, _ c: ParsedOBJVertex) {
            let base = UInt32(positions.count)
            positions.append(contentsOf: [a.position, b.position, c.position])
            normals.append(contentsOf: [a.normal, b.normal, c.normal])
            indices.append(contentsOf: [base, base + 1, base + 2])
        }
    }

    private struct F16MovingMesh {
        let mesh: MeshResource
        let pivot: SIMD3<Float>
    }

    private struct F16MeshSet {
        let airframe: MeshResource
        let canopy: MeshResource?
        let radome: MeshResource?
        let exhaust: MeshResource?
        let leftAileron: F16MovingMesh?
        let rightAileron: F16MovingMesh?
        let leftStabilator: F16MovingMesh?
        let rightStabilator: F16MovingMesh?
        let rudder: F16MovingMesh?
    }

    /// Split existing OBJ triangles into a static shell plus real moving faces.
    private static func loadF16MeshSet() throws -> F16MeshSet {
        guard let url = Bundle.main.url(forResource: "f16", withExtension: "obj", subdirectory: "Models") else {
            throw OBJError.missingAsset
        }

        let source = try String(contentsOf: url, encoding: .utf8)
        let lines = source.split(whereSeparator: \.isNewline)
        var sourcePositions: [SIMD3<Float>] = []
        var sourceNormals: [SIMD3<Float>] = []
        sourcePositions.reserveCapacity(2_500)
        sourceNormals.reserveCapacity(4_000)

        for line in lines {
            if line.hasPrefix("v ") {
                let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard fields.count >= 4,
                      let x = Float(fields[1]), let y = Float(fields[2]), let z = Float(fields[3]) else { continue }
                sourcePositions.append([x, y, z])
            } else if line.hasPrefix("vn ") {
                let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard fields.count >= 4,
                      let x = Float(fields[1]), let y = Float(fields[2]), let z = Float(fields[3]) else { continue }
                let value = SIMD3<Float>(x, y, z)
                sourceNormals.append(simd_length_squared(value) > 0 ? simd_normalize(value) : SIMD3<Float>(0, 1, 0))
            }
        }

        guard !sourcePositions.isEmpty else { throw OBJError.invalidGeometry }
        var minZ = Float.greatestFiniteMagnitude
        var maxZ = -Float.greatestFiniteMagnitude
        for p in sourcePositions { minZ = min(minZ, p.z); maxZ = max(maxZ, p.z) }
        let sourceLength = maxZ - minZ
        guard sourceLength > 0.001 else { throw OBJError.invalidGeometry }
        let scale: Float = 15.03 / sourceLength

        func resolvedIndex(_ raw: Int, count: Int) -> Int? {
            if raw > 0 { let v = raw - 1; return v < count ? v : nil }
            if raw < 0 { let v = count + raw; return v >= 0 && v < count ? v : nil }
            return nil
        }

        func parsedVertex(_ token: Substring) -> ParsedOBJVertex? {
            let components = token.split(separator: "/", omittingEmptySubsequences: false)
            guard !components.isEmpty,
                  let rawPosition = Int(components[0]),
                  let positionIndex = resolvedIndex(rawPosition, count: sourcePositions.count) else { return nil }
            var normal = SIMD3<Float>(0, 1, 0)
            if components.count >= 3,
               let rawNormal = Int(components[2]),
               let normalIndex = resolvedIndex(rawNormal, count: sourceNormals.count) {
                normal = sourceNormals[normalIndex]
            }
            return ParsedOBJVertex(position: sourcePositions[positionIndex] * scale, normal: normal)
        }

        var builders: [F16MeshPart: RawMeshBuilder] = [.airframe: RawMeshBuilder()]
        for line in lines where line.hasPrefix("f ") {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 4 else { continue }
            var face: [ParsedOBJVertex] = []
            for token in fields.dropFirst() {
                guard let vertex = parsedVertex(token) else { face.removeAll(keepingCapacity: true); break }
                face.append(vertex)
            }
            guard face.count >= 3 else { continue }
            for index in 1..<(face.count - 1) {
                let a = face[0], b = face[index], c = face[index + 1]
                let part = classifyF16Triangle(a.position, b.position, c.position)
                var builder = builders[part] ?? RawMeshBuilder()
                builder.appendTriangle(a, b, c)
                builders[part] = builder
            }
        }

        guard let airframeBuilder = builders[.airframe], airframeBuilder.indices.count >= 3 else {
            throw OBJError.invalidGeometry
        }
        let airframe = try makeMeshResource(from: airframeBuilder, name: "F-16A static shell", subtracting: .zero)
        return F16MeshSet(
            airframe: airframe,
            canopy: try makeStaticMesh(builders[.canopy], name: "F-16 canopy stock faces"),
            radome: try makeStaticMesh(builders[.radome], name: "F-16 radome stock faces"),
            exhaust: try makeStaticMesh(builders[.exhaust], name: "F-16 exhaust stock faces"),
            leftAileron: try makeMovingMesh(builders[.leftAileron], part: .leftAileron),
            rightAileron: try makeMovingMesh(builders[.rightAileron], part: .rightAileron),
            leftStabilator: try makeMovingMesh(builders[.leftStabilator], part: .leftStabilator),
            rightStabilator: try makeMovingMesh(builders[.rightStabilator], part: .rightStabilator),
            rudder: try makeMovingMesh(builders[.rudder], part: .rudder)
        )
    }

    private static let rightFlaperonPlanform: [SIMD2<Float>] = [
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

    private static func pointInPolygon(_ point: SIMD2<Float>, polygon: [SIMD2<Float>]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var previous = polygon.count - 1
        for index in polygon.indices {
            let currentPoint = polygon[index], previousPoint = polygon[previous]
            if (currentPoint.y > point.y) != (previousPoint.y > point.y) {
                let denominator = previousPoint.y - currentPoint.y
                if abs(denominator) > 0.000001 {
                    let crossingX = (previousPoint.x - currentPoint.x) * (point.y - currentPoint.y) / denominator + currentPoint.x
                    if point.x < crossingX { inside.toggle() }
                }
            }
            previous = index
        }
        return inside
    }

    private static func makeStaticMesh(_ builder: RawMeshBuilder?, name: String) throws -> MeshResource? {
        guard let builder, builder.indices.count >= 3 else { return nil }
        return try makeMeshResource(from: builder, name: name, subtracting: .zero)
    }

    private static func makeMovingMesh(_ builder: RawMeshBuilder?, part: F16MeshPart) throws -> F16MovingMesh? {
        guard let builder, builder.indices.count >= 3 else { return nil }
        let pivot = movingSurfacePivot(part: part, positions: builder.positions)
        return F16MovingMesh(mesh: try makeMeshResource(from: builder, name: "F-16 source control surface", subtracting: pivot), pivot: pivot)
    }

    private static func movingSurfacePivot(part: F16MeshPart, positions: [SIMD3<Float>]) -> SIMD3<Float> {
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

    private static func makeMeshResource(from builder: RawMeshBuilder, name: String, subtracting pivot: SIMD3<Float>) throws -> MeshResource {
        guard builder.positions.count >= 3, builder.indices.count >= 3 else { throw OBJError.invalidGeometry }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(builder.positions.map { $0 - pivot })
        descriptor.normals = MeshBuffers.Normals(builder.normals)
        descriptor.primitives = .triangles(builder.indices)
        return try MeshResource.generate(from: [descriptor])
    }
}
