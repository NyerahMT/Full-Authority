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
                color: UIColor(red: 0.39, green: 0.41, blue: 0.42, alpha: 1),
                isMetallic: false
            )

            let model = ModelEntity(mesh: geometry.airframe, materials: [airframeMaterial])
            model.name = meshName
            visualRoot.addChild(model)

            addVisualDetail(to: visualRoot)
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

    private static func addVisualDetail(to root: Entity) {
        let canopy = ellipsoid(
            radii: [0.62, 0.38, 1.50],
            color: UIColor(red: 0.045, green: 0.105, blue: 0.135, alpha: 0.94),
            metallic: true
        )
        canopy.name = "FA.aircraft.canopy"
        canopy.position = [0, -0.18, 2.78]
        root.addChild(canopy)

        let radome = ellipsoid(
            radii: [0.34, 0.28, 0.88],
            color: UIColor(red: 0.16, green: 0.18, blue: 0.18, alpha: 1),
            metallic: false
        )
        radome.name = "FA.aircraft.radome"
        radome.position = [0, -1.02, 6.82]
        root.addChild(radome)

        let nozzle = cylinder(
            length: 0.70,
            radius: 0.66,
            color: UIColor(red: 0.16, green: 0.15, blue: 0.14, alpha: 1),
            metallic: true,
            axisAlongZ: true
        )
        nozzle.name = nozzleName
        nozzle.position = [0, -1.14, -7.13]
        root.addChild(nozzle)

        let nozzleCore = cylinder(
            length: 0.80,
            radius: 0.42,
            color: UIColor(red: 0.022, green: 0.022, blue: 0.025, alpha: 1),
            metallic: false,
            axisAlongZ: true
        )
        nozzleCore.position = [0, -1.14, -7.31]
        root.addChild(nozzleCore)

        let afterburner = ellipsoid(
            radii: [0.40, 0.40, 1.65],
            color: UIColor(red: 1.0, green: 0.38, blue: 0.055, alpha: 0.72),
            metallic: false
        )
        afterburner.name = afterburnerName
        afterburner.position = [0, -1.14, -8.45]
        afterburner.isEnabled = false
        root.addChild(afterburner)

        addNavigationLight(
            to: root,
            name: "FA.aircraft.nav.left",
            position: [-5.03, -1.34, -2.35],
            color: UIColor(red: 0.98, green: 0.08, blue: 0.08, alpha: 1)
        )
        addNavigationLight(
            to: root,
            name: "FA.aircraft.nav.right",
            position: [5.03, -1.34, -2.35],
            color: UIColor(red: 0.08, green: 0.96, blue: 0.24, alpha: 1)
        )
        addNavigationLight(
            to: root,
            name: "FA.aircraft.nav.tail",
            position: [0, -0.40, -7.25],
            color: UIColor(white: 0.98, alpha: 1)
        )
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

        // The source mesh does not contain clean separable four-petal speedbrakes,
        // so retain only this small procedural system panel for now.
        let panelColor = UIColor(red: 0.335, green: 0.35, blue: 0.36, alpha: 1)
        let speedbrake = Entity()
        speedbrake.name = speedbrakeName
        speedbrake.position = [0, -0.28, -4.00]
        if let leftMesh = makeHorizontalSurfaceMesh(
            outline: [[-1.10, 0.00], [-0.18, 0.00], [-0.22, -0.78], [-0.98, -0.62]],
            thickness: 0.026
        ) {
            speedbrake.addChild(ModelEntity(mesh: leftMesh, materials: [SimpleMaterial(color: panelColor, isMetallic: false)]))
        }
        if let rightMesh = makeHorizontalSurfaceMesh(
            outline: [[0.18, 0.00], [1.10, 0.00], [0.98, -0.62], [0.22, -0.78]],
            thickness: 0.026
        ) {
            speedbrake.addChild(ModelEntity(mesh: rightMesh, materials: [SimpleMaterial(color: panelColor, isMetallic: false)]))
        }
        root.addChild(speedbrake)
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

    private static func horizontalHingedSurface(
        name: String,
        hingePosition: SIMD3<Float>,
        outline: [SIMD2<Float>],
        color: UIColor
    ) -> Entity {
        let hinge = Entity()
        hinge.name = name
        hinge.position = hingePosition
        if let mesh = makeHorizontalSurfaceMesh(outline: outline, thickness: 0.034) {
            let panel = ModelEntity(
                mesh: mesh,
                materials: [SimpleMaterial(color: color, isMetallic: false)]
            )
            hinge.addChild(panel)
        }
        return hinge
    }

    private static func verticalHingedSurface(
        name: String,
        hingePosition: SIMD3<Float>,
        outline: [SIMD2<Float>],
        color: UIColor
    ) -> Entity {
        let hinge = Entity()
        hinge.name = name
        hinge.position = hingePosition
        if let mesh = makeVerticalSurfaceMesh(outline: outline, thickness: 0.034) {
            let panel = ModelEntity(
                mesh: mesh,
                materials: [SimpleMaterial(color: color, isMetallic: false)]
            )
            hinge.addChild(panel)
        }
        return hinge
    }

    /// Outline coordinates are (spanwise X, chordwise Z), with Z=0 on the hinge
    /// and negative Z extending aft. Two faces give the panel visible thickness
    /// without relying on RealityKit primitive boxes.
    private static func makeHorizontalSurfaceMesh(
        outline: [SIMD2<Float>],
        thickness: Float
    ) -> MeshResource? {
        guard outline.count >= 3 else { return nil }
        let half = thickness * 0.5
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for point in outline {
            positions.append([point.x, half, point.y])
            normals.append([0, 1, 0])
        }
        for point in outline {
            positions.append([point.x, -half, point.y])
            normals.append([0, -1, 0])
        }

        let count = UInt32(outline.count)
        for index in 1..<(outline.count - 1) {
            indices.append(contentsOf: [0, UInt32(index), UInt32(index + 1)])
            indices.append(contentsOf: [count, count + UInt32(index + 1), count + UInt32(index)])
        }

        var descriptor = MeshDescriptor(name: "F-16 horizontal control surface")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    /// Outline coordinates are (vertical Y, chordwise Z), with Z=0 on the
    /// vertical hinge. Faces are duplicated on either side of the fin plane.
    private static func makeVerticalSurfaceMesh(
        outline: [SIMD2<Float>],
        thickness: Float
    ) -> MeshResource? {
        guard outline.count >= 3 else { return nil }
        let half = thickness * 0.5
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for point in outline {
            positions.append([half, point.x, point.y])
            normals.append([1, 0, 0])
        }
        for point in outline {
            positions.append([-half, point.x, point.y])
            normals.append([-1, 0, 0])
        }

        let count = UInt32(outline.count)
        for index in 1..<(outline.count - 1) {
            indices.append(contentsOf: [0, UInt32(index), UInt32(index + 1)])
            indices.append(contentsOf: [count, count + UInt32(index + 1), count + UInt32(index)])
        }

        var descriptor = MeshDescriptor(name: "F-16 vertical control surface")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
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

    private static func addNavigationLight(
        to root: Entity,
        name: String,
        position: SIMD3<Float>,
        color: UIColor
    ) {
        let light = ModelEntity(
            mesh: .generateSphere(radius: 0.085),
            materials: [SimpleMaterial(color: color, isMetallic: false)]
        )
        light.name = name
        light.position = position
        root.addChild(light)
    }

    private static func ellipsoid(
        radii: SIMD3<Float>,
        color: UIColor,
        metallic: Bool
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateSphere(radius: 1),
            materials: [SimpleMaterial(color: color, isMetallic: metallic)]
        )
        entity.scale = radii
        return entity
    }

    private static func cylinder(
        length: Float,
        radius: Float,
        color: UIColor,
        metallic: Bool,
        axisAlongZ: Bool
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateCylinder(height: length, radius: radius),
            materials: [SimpleMaterial(color: color, isMetallic: metallic)]
        )
        if axisAlongZ {
            entity.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        }
        return entity
    }

    // FlightGear's mature F-16 model exposes these hinge-axis directions.
    // Use the geometry as engineering reference only; no GPL mesh/code is copied.
    // Moving triangles remain from Full Authority's MIT-licensed R4 OBJ.
    static let leftAileronVisualAxis = simd_normalize(SIMD3<Float>(2.5165, 0.096955, 0.39329))
    static let rightAileronVisualAxis = simd_normalize(SIMD3<Float>(2.5165, 0.096955, -0.39329))
    static let leftStabilatorVisualAxis = simd_normalize(SIMD3<Float>(0.981645, 0.190720, 0))
    static let rightStabilatorVisualAxis = simd_normalize(SIMD3<Float>(0.981645, -0.190720, 0))
    static let rudderVisualAxis = simd_normalize(SIMD3<Float>(0, 0.836890, -0.547371))

    private enum F16MeshPart: Hashable {
        case airframe
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
                let centroid = (a.position + b.position + c.position) / 3
                let part = classifyF16Triangle(centroid)
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
            leftAileron: try makeMovingMesh(builders[.leftAileron], part: .leftAileron),
            rightAileron: try makeMovingMesh(builders[.rightAileron], part: .rightAileron),
            leftStabilator: try makeMovingMesh(builders[.leftStabilator], part: .leftStabilator),
            rightStabilator: try makeMovingMesh(builders[.rightStabilator], part: .rightStabilator),
            rudder: try makeMovingMesh(builders[.rudder], part: .rudder)
        )
    }

    private static func classifyF16Triangle(_ point: SIMD3<Float>) -> F16MeshPart {
        let x = point.x, y = point.y, z = point.z
        if y > -1.60, y < -0.90 {
            let right: [SIMD2<Float>] = [[1.05,-2.48],[3.60,-2.88],[3.62,-3.58],[1.35,-3.58]]
            let left: [SIMD2<Float>] = [[-1.05,-2.48],[-3.60,-2.88],[-3.62,-3.58],[-1.35,-3.58]]
            if pointInPolygon(SIMD2<Float>(x,z), polygon: left) { return .leftAileron }
            if pointInPolygon(SIMD2<Float>(x,z), polygon: right) { return .rightAileron }
        }
        if y < -0.35, z < -4.0, z > -7.12 {
            if x < -0.65, x > -3.35 { return .leftStabilator }
            if x > 0.65, x < 3.35 { return .rightStabilator }
        }
        if abs(x) < 0.50, y > 0, y < 2.40, z > -7.45 {
            let hingeZ = -5.50 - 0.654 * y
            if z < hingeZ { return .rudder }
        }
        return .airframe
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

    private static func makeMovingMesh(_ builder: RawMeshBuilder?, part: F16MeshPart) throws -> F16MovingMesh? {
        guard let builder, builder.indices.count >= 3 else { return nil }
        let pivot = movingSurfacePivot(part: part, positions: builder.positions)
        return F16MovingMesh(mesh: try makeMeshResource(from: builder, name: "F-16 source control surface", subtracting: pivot), pivot: pivot)
    }

    private static func movingSurfacePivot(part: F16MeshPart, positions: [SIMD3<Float>]) -> SIMD3<Float> {
        switch part {
        case .leftAileron: return [-2.325, meanSurfaceY(positions, nearZ: -2.68), -2.68]
        case .rightAileron: return [2.325, meanSurfaceY(positions, nearZ: -2.68), -2.68]
        case .leftStabilator: return [-1.965, meanSurfaceY(positions, nearZ: -5.30), -5.30]
        case .rightStabilator: return [1.965, meanSurfaceY(positions, nearZ: -5.30), -5.30]
        case .rudder:
            let pivotY: Float = 1.15
            return [0, pivotY, -5.50 - 0.654 * pivotY]
        case .airframe: return .zero
        }
    }

    private static func meanSurfaceY(_ positions: [SIMD3<Float>], nearZ targetZ: Float) -> Float {
        let close = positions.filter { abs($0.z - targetZ) < 0.42 }
        let sample = close.isEmpty ? positions : close
        guard !sample.isEmpty else { return -1.20 }
        return sample.reduce(Float(0)) { $0 + $1.y } / Float(sample.count)
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
