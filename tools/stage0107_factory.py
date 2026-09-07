from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected 1 match for {old[:100]!r}, got {count}")
    p.write_text(text.replace(old, new, 1))


def replace_between(path, start, end, new):
    p = Path(path)
    text = p.read_text()
    i = text.find(start)
    if i < 0:
        raise SystemExit(f"{path}: missing start marker {start!r}")
    j = text.find(end, i)
    if j < 0:
        raise SystemExit(f"{path}: missing end marker {end!r}")
    p.write_text(text[:i] + new.rstrip() + "\n\n" + text[j:])


def replace_tail_before_final_brace(path, start, new):
    p = Path(path)
    text = p.read_text()
    i = text.find(start)
    if i < 0:
        raise SystemExit(f"{path}: missing tail start {start!r}")
    j = text.rfind("\n}")
    if j < i:
        raise SystemExit(f"{path}: final brace not found")
    p.write_text(text[:i] + new.rstrip() + text[j:])


factory = "Aircraft/PrototypeAircraftFactory.swift"

replace_between(
    factory,
    "    static func make() -> Entity {",
    "    private static func addVisualDetail",
    r'''    static func make() -> Entity {
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
    }'''
)

replace_between(
    factory,
    "    private static func addAnimatedSurfaces(to root: Entity) {",
    "    private static func addLandingGear",
    r'''    private static func addAnimatedSurfaces(
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
    }'''
)

replace_tail_before_final_brace(
    factory,
    "    /// Loads the pinned MIT-licensed F-16 OBJ staged by CI",
    r'''    // FlightGear's mature F-16 model exposes these hinge-axis directions.
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
    }'''
)
