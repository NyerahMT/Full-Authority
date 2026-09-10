import Foundation
import RealityKit
import UIKit
import simd

// MARK: - Stage 021 real-world Malta layer

/// A mobile-first real-world scenery layer baked from OpenStreetMap and Terrarium.
///
/// The 3 MB runtime payload preserves Malta's real road/building layout while the
/// generated DEM is compiled into the JSBSim bridge. Stage2TerrainProfile calls that
/// same bridge function, so the rendered terrain and aircraft contact surface remain
/// one mathematical surface instead of drifting apart.
@MainActor
enum Stage021MaltaWorld {
    private static let rootName = "FA.world.stage021.malta"
    private static let payloadName = "stage021_malta_world"
    private static let payloadSubdirectory = "JSBSim/visuals/world"
    private static let chunkMeters: Float = 4_000

    private struct BuildingRecord {
        let center: SIMD2<Float>
        let width: Float
        let depth: Float
        let yaw: Float
        let height: Float
        let style: Int
    }

    private struct Dataset {
        let data: Data
        let buildings: [BuildingRecord]
        let roadOffset: Int
        let roadCount: Int
        let seaLevel: Float
        let worldHalf: Float
    }

    private struct ChunkKey: Hashable {
        let x: Int
        let z: Int
    }

    private final class GeometryPart {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        func addQuad(
            _ a: SIMD3<Float>,
            _ b: SIMD3<Float>,
            _ c: SIMD3<Float>,
            _ d: SIMD3<Float>,
            normal: SIMD3<Float>
        ) {
            let base = UInt32(positions.count)
            positions.append(contentsOf: [a, b, c, d])
            normals.append(contentsOf: Array(repeating: normal, count: 4))
            indices.append(contentsOf: [base, base + 2, base + 1, base + 1, base + 2, base + 3])
        }

        var isEmpty: Bool { positions.isEmpty }
    }

    private final class ChunkGeometry {
        // Five wall families + one common roof family.
        let parts = (0..<6).map { _ in GeometryPart() }
    }

    private struct BinaryCursor {
        let data: Data
        var offset: Int

        init(data: Data, offset: Int = 0) {
            self.data = data
            self.offset = offset
        }

        mutating func readUInt8() -> UInt8? {
            guard offset + 1 <= data.count else { return nil }
            let value = data[offset]
            offset += 1
            return value
        }

        mutating func readUInt16() -> UInt16? {
            guard offset + 2 <= data.count else { return nil }
            let value: UInt16 = data.withUnsafeBytes { raw in
                raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
            }
            offset += 2
            return UInt16(littleEndian: value)
        }

        mutating func readUInt32() -> UInt32? {
            guard offset + 4 <= data.count else { return nil }
            let value: UInt32 = data.withUnsafeBytes { raw in
                raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            }
            offset += 4
            return UInt32(littleEndian: value)
        }

        mutating func readFloat() -> Float? {
            guard let bits = readUInt32() else { return nil }
            return Float(bitPattern: bits)
        }

        mutating func skip(_ count: Int) -> Bool {
            guard count >= 0, offset + count <= data.count else { return false }
            offset += count
            return true
        }

        mutating func readMagic() -> [UInt8]? {
            guard offset + 4 <= data.count else { return nil }
            let bytes = Array(data[offset..<(offset + 4)])
            offset += 4
            return bytes
        }
    }

    static func make(base: Entity) -> Entity {
        guard base.findEntity(named: rootName) == nil else { return base }

        // Stage 019's curated fake settlement was useful while the world was fictional,
        // but mixing it into a geographically real Malta layer immediately destroys scale.
        base.findEntity(named: "FA.world.stage019.professional-environment")?.isEnabled = false
        base.findEntity(named: "FA.world.stage020.procedural-region")?.isEnabled = false

        guard let dataset = loadDataset() else { return base }

        let root = Entity()
        root.name = rootName

        addMediterranean(to: root, seaLevel: dataset.seaLevel, halfExtent: dataset.worldHalf)
        addRoadNetwork(to: root, dataset: dataset)
        addBuildings(to: root, dataset: dataset)

        base.addChild(root)
        return base
    }

    // MARK: - Dataset

    private static func loadDataset() -> Dataset? {
        guard let url = Bundle.main.url(
            forResource: payloadName,
            withExtension: "bin",
            subdirectory: payloadSubdirectory
        ), let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return nil
        }

        var cursor = BinaryCursor(data: data)
        guard cursor.readMagic() == [70, 65, 50, 49], // "FA21"
              let version = cursor.readUInt16(), version == 1,
              cursor.readUInt16() != nil,
              let buildingCountRaw = cursor.readUInt32(),
              let roadCountRaw = cursor.readUInt32(),
              let seaLevel = cursor.readFloat(),
              let worldHalf = cursor.readFloat() else {
            return nil
        }

        let buildingCount = Int(buildingCountRaw)
        let roadCount = Int(roadCountRaw)
        guard buildingCount >= 0, buildingCount <= 100_000,
              roadCount >= 0, roadCount <= 250_000,
              worldHalf > 1_000, worldHalf < 100_000 else {
            return nil
        }

        var buildings: [BuildingRecord] = []
        buildings.reserveCapacity(buildingCount)

        for _ in 0..<buildingCount {
            guard let x = cursor.readFloat(),
                  let z = cursor.readFloat(),
                  let width = cursor.readFloat(),
                  let depth = cursor.readFloat(),
                  let yaw = cursor.readFloat(),
                  let height = cursor.readFloat(),
                  let style = cursor.readUInt8(),
                  cursor.skip(3) else {
                return nil
            }

            guard x.isFinite, z.isFinite, width.isFinite, depth.isFinite,
                  yaw.isFinite, height.isFinite,
                  width > 1, depth > 1, height > 1 else { continue }

            buildings.append(BuildingRecord(
                center: [x, z],
                width: width,
                depth: depth,
                yaw: yaw,
                height: min(height, 300),
                style: min(Int(style), 4)
            ))
        }

        return Dataset(
            data: data,
            buildings: buildings,
            roadOffset: cursor.offset,
            roadCount: roadCount,
            seaLevel: seaLevel,
            worldHalf: worldHalf
        )
    }

    // MARK: - Water

    private static func addMediterranean(to root: Entity, seaLevel: Float, halfExtent: Float) {
        var water = PhysicallyBasedMaterial()
        water.baseColor = .init(tint: UIColor(red: 0.035, green: 0.185, blue: 0.245, alpha: 1))
        water.roughness = .init(floatLiteral: 0.23)
        water.metallic = .init(floatLiteral: 0.0)
        water.specular = .init(floatLiteral: 0.72)

        let sea = ModelEntity(
            mesh: .generatePlane(width: halfExtent * 2.12, depth: halfExtent * 2.12),
            materials: [water]
        )
        sea.name = "FA.world.stage021.mediterranean"
        sea.position = [0, seaLevel + 0.035, 0]
        root.addChild(sea)
    }

    // MARK: - Roads

    private static func addRoadNetwork(to root: Entity, dataset: Dataset) {
        let roadParts = (0..<6).map { _ in GeometryPart() }
        let markingPart = GeometryPart()
        var cursor = BinaryCursor(data: dataset.data, offset: dataset.roadOffset)

        for _ in 0..<dataset.roadCount {
            guard let roadClassByte = cursor.readUInt8(),
                  cursor.readUInt8() != nil,
                  let pointCountRaw = cursor.readUInt16(),
                  let width = cursor.readFloat() else { break }

            let roadClass = min(Int(roadClassByte), 5)
            let pointCount = Int(pointCountRaw)
            guard pointCount >= 2, pointCount <= 65_535 else { break }

            var points: [SIMD2<Float>] = []
            points.reserveCapacity(pointCount)
            var malformed = false
            for _ in 0..<pointCount {
                guard let x = cursor.readFloat(), let z = cursor.readFloat() else {
                    malformed = true
                    break
                }
                points.append([x, z])
            }
            if malformed { break }

            // Service roads are extremely numerous in OSM. Keep them where a low pass
            // can actually resolve them, while the complete higher-order network remains.
            if roadClass == 5 {
                let nearest = points.reduce(Float.greatestFiniteMagnitude) { partial, point in
                    min(partial, simd_length(point))
                }
                if nearest > 8_500 { continue }
            }

            for index in 0..<(points.count - 1) {
                addRoadSegment(
                    from: points[index],
                    to: points[index + 1],
                    width: width,
                    verticalOffset: roadVerticalOffset(for: roadClass),
                    into: roadParts[roadClass]
                )

                if roadClass <= 1 {
                    addRoadSegment(
                        from: points[index],
                        to: points[index + 1],
                        width: 0.30,
                        verticalOffset: roadVerticalOffset(for: roadClass) + 0.022,
                        into: markingPart
                    )
                }
            }
        }

        let materials = roadMaterials()
        for index in 0..<roadParts.count where !roadParts[index].isEmpty {
            guard let mesh = meshResource(part: roadParts[index], name: "Malta roads \(index)") else { continue }
            let entity = ModelEntity(mesh: mesh, materials: [materials[index]])
            entity.name = "FA.world.stage021.roads.\(index)"
            root.addChild(entity)
        }

        if !markingPart.isEmpty,
           let mesh = meshResource(part: markingPart, name: "Malta arterial markings") {
            var marking = PhysicallyBasedMaterial()
            marking.baseColor = .init(tint: UIColor(red: 0.87, green: 0.78, blue: 0.53, alpha: 1))
            marking.roughness = .init(floatLiteral: 0.90)
            marking.metallic = .init(floatLiteral: 0)
            marking.specular = .init(floatLiteral: 0.10)
            let entity = ModelEntity(mesh: mesh, materials: [marking])
            entity.name = "FA.world.stage021.arterial-markings"
            root.addChild(entity)
        }
    }

    private static func addRoadSegment(
        from start: SIMD2<Float>,
        to end: SIMD2<Float>,
        width: Float,
        verticalOffset: Float,
        into part: GeometryPart
    ) {
        let delta = end - start
        let length = simd_length(delta)
        guard length > 0.65 else { return }

        let forward = delta / length
        let side = SIMD2<Float>(forward.y, -forward.x) * max(width, 0.18) * 0.5
        let left0 = start + side
        let right0 = start - side
        let left1 = end + side
        let right1 = end - side

        let p0 = terrainPoint(left0, offset: verticalOffset)
        let p1 = terrainPoint(right0, offset: verticalOffset)
        let p2 = terrainPoint(left1, offset: verticalOffset)
        let p3 = terrainPoint(right1, offset: verticalOffset)
        let normal = simd_normalize(
            Stage2TerrainProfile.normal(east: start.x, north: start.y) +
            Stage2TerrainProfile.normal(east: end.x, north: end.y)
        )

        part.addQuad(p0, p1, p2, p3, normal: normal)
    }

    private static func terrainPoint(_ point: SIMD2<Float>, offset: Float) -> SIMD3<Float> {
        [
            point.x,
            Stage2TerrainProfile.heightMeters(east: point.x, north: point.y) + offset,
            point.y
        ]
    }

    private static func roadVerticalOffset(for roadClass: Int) -> Float {
        0.13 + Float(max(0, 4 - roadClass)) * 0.007
    }

    private static func roadMaterials() -> [PhysicallyBasedMaterial] {
        let tints: [UIColor] = [
            UIColor(red: 0.155, green: 0.158, blue: 0.160, alpha: 1),
            UIColor(red: 0.175, green: 0.177, blue: 0.178, alpha: 1),
            UIColor(red: 0.195, green: 0.196, blue: 0.194, alpha: 1),
            UIColor(red: 0.215, green: 0.214, blue: 0.207, alpha: 1),
            UIColor(red: 0.235, green: 0.231, blue: 0.220, alpha: 1),
            UIColor(red: 0.255, green: 0.247, blue: 0.230, alpha: 1)
        ]

        return tints.enumerated().map { index, tint in
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: tint)
            material.roughness = .init(floatLiteral: index <= 2 ? 0.93 : 0.97)
            material.metallic = .init(floatLiteral: 0)
            material.specular = .init(floatLiteral: 0.17)
            return material
        }
    }

    // MARK: - Buildings

    private static func addBuildings(to root: Entity, dataset: Dataset) {
        var chunks: [ChunkKey: ChunkGeometry] = [:]

        for building in dataset.buildings {
            let key = ChunkKey(
                x: Int(floor(building.center.x / chunkMeters)),
                z: Int(floor(building.center.y / chunkMeters))
            )
            let chunk = chunks[key] ?? ChunkGeometry()
            chunks[key] = chunk
            appendBuilding(building, to: chunk)
        }

        let materials = buildingMaterials()
        let buildingRoot = Entity()
        buildingRoot.name = "FA.world.stage021.buildings"

        for (key, chunk) in chunks {
            var descriptors: [MeshDescriptor] = []
            var entityMaterials: [PhysicallyBasedMaterial] = []

            for partIndex in 0..<chunk.parts.count {
                let part = chunk.parts[partIndex]
                guard !part.isEmpty else { continue }
                var descriptor = MeshDescriptor(name: "Malta buildings \(key.x),\(key.z) part \(partIndex)")
                descriptor.positions = MeshBuffers.Positions(part.positions)
                descriptor.normals = MeshBuffers.Normals(part.normals)
                descriptor.primitives = .triangles(part.indices)
                descriptors.append(descriptor)
                entityMaterials.append(materials[partIndex])
            }

            guard !descriptors.isEmpty,
                  let mesh = try? MeshResource.generate(from: descriptors) else { continue }

            let entity = ModelEntity(mesh: mesh, materials: entityMaterials)
            entity.name = "FA.world.stage021.building-chunk.\(key.x).\(key.z)"
            buildingRoot.addChild(entity)
        }

        root.addChild(buildingRoot)
    }

    private static func appendBuilding(_ building: BuildingRecord, to chunk: ChunkGeometry) {
        let halfW = building.width * 0.5
        let halfD = building.depth * 0.5
        let c = cos(building.yaw)
        let s = sin(building.yaw)

        func rotated(_ x: Float, _ z: Float) -> SIMD2<Float> {
            [
                building.center.x + x * c - z * s,
                building.center.y + x * s + z * c
            ]
        }

        let footprint = [
            rotated(-halfW, -halfD),
            rotated( halfW, -halfD),
            rotated( halfW,  halfD),
            rotated(-halfW,  halfD)
        ]

        let groundSamples = footprint.map {
            Stage2TerrainProfile.heightMeters(east: $0.x, north: $0.y)
        }
        let ground = (groundSamples.reduce(0, +) / 4.0) - 0.45
        let top = ground + building.height
        let wallPart = chunk.parts[min(max(building.style, 0), 4)]
        let roofPart = chunk.parts[5]

        for index in 0..<4 {
            let next = (index + 1) % 4
            let a2 = footprint[index]
            let b2 = footprint[next]
            let edge = b2 - a2
            guard simd_length_squared(edge) > 0.01 else { continue }

            var outward = simd_normalize(SIMD3<Float>(edge.y, 0, -edge.x))
            let midpoint = (a2 + b2) * 0.5
            let fromCenter = SIMD3<Float>(midpoint.x - building.center.x, 0, midpoint.y - building.center.y)
            if simd_dot(outward, fromCenter) < 0 { outward = -outward }

            wallPart.addQuad(
                [a2.x, ground, a2.y],
                [b2.x, ground, b2.y],
                [a2.x, top, a2.y],
                [b2.x, top, b2.y],
                normal: outward
            )
        }

        // Flat roofs are characteristic of much of Malta and read extremely well from
        // aviation altitudes. A separate slightly darker stone material breaks up massing.
        roofPart.addQuad(
            [footprint[0].x, top, footprint[0].y],
            [footprint[1].x, top, footprint[1].y],
            [footprint[3].x, top, footprint[3].y],
            [footprint[2].x, top, footprint[2].y],
            normal: [0, 1, 0]
        )
    }

    private static func buildingMaterials() -> [PhysicallyBasedMaterial] {
        let wallTints: [UIColor] = [
            UIColor(red: 0.72, green: 0.66, blue: 0.52, alpha: 1),
            UIColor(red: 0.80, green: 0.75, blue: 0.63, alpha: 1),
            UIColor(red: 0.66, green: 0.63, blue: 0.57, alpha: 1),
            UIColor(red: 0.57, green: 0.55, blue: 0.49, alpha: 1),
            UIColor(red: 0.83, green: 0.78, blue: 0.64, alpha: 1)
        ]

        var result = wallTints.map { tint -> PhysicallyBasedMaterial in
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: tint)
            material.roughness = .init(floatLiteral: 0.88)
            material.metallic = .init(floatLiteral: 0)
            material.specular = .init(floatLiteral: 0.18)
            material.faceCulling = .none
            return material
        }

        var roof = PhysicallyBasedMaterial()
        roof.baseColor = .init(tint: UIColor(red: 0.60, green: 0.56, blue: 0.47, alpha: 1))
        roof.roughness = .init(floatLiteral: 0.94)
        roof.metallic = .init(floatLiteral: 0)
        roof.specular = .init(floatLiteral: 0.12)
        roof.faceCulling = .none
        result.append(roof)
        return result
    }

    // MARK: - Mesh helpers

    private static func meshResource(part: GeometryPart, name: String) -> MeshResource? {
        guard !part.isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(part.positions)
        descriptor.normals = MeshBuffers.Normals(part.normals)
        descriptor.primitives = .triangles(part.indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}
