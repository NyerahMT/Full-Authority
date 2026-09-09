import Foundation
import RealityKit
import UIKit
import simd

// Stage 024 deliberately stops synthesizing a world. The terrain, roads and
// building placement come from an offline real-world Reno data package generated
// from USGS elevation/orthoimagery and OpenStreetMap vectors. Rendering uses the
// same sampled height grid that the JSBSim ground callback loads from disk.
final class Stage024RealMapData {
    static let shared = Stage024RealMapData()

    struct Building: Decodable {
        let x: Float
        let z: Float
        let width: Float
        let depth: Float
        let yaw: Float
        let height: Float
        let material: Int
    }

    struct Road: Decodable {
        let width: Float
        let kind: Int
        let points: [Float]
    }

    struct Runway: Decodable {
        let name: String
        let startX: Float
        let startZ: Float
        let endX: Float
        let endZ: Float
        let width: Float
    }

    struct MapDocument: Decodable {
        let name: String
        let minX: Float
        let minZ: Float
        let maxX: Float
        let maxZ: Float
        let referenceElevationMeters: Float
        let buildings: [Building]
        let roads: [Road]
        let runways: [Runway]
    }

    private(set) var map: MapDocument?
    private(set) var gridWidth = 0
    private(set) var gridHeight = 0
    private(set) var cellMeters: Float = 40
    private(set) var gridMinX: Float = 0
    private(set) var gridMinZ: Float = 0
    private(set) var gridReferenceElevationMeters: Float = 0
    private var heights: [Float] = []

    var isLoaded: Bool {
        map != nil && gridWidth > 1 && gridHeight > 1 && heights.count == gridWidth * gridHeight
    }

    var referenceElevationMeters: Float {
        map?.referenceElevationMeters ?? gridReferenceElevationMeters
    }

    private init() {
        load()
    }

    private func load() {
        guard let worldURL = Bundle.main.url(
            forResource: "reno_world",
            withExtension: "json",
            subdirectory: "JSBSim/visuals/world/reno"
        ), let terrainURL = Bundle.main.url(
            forResource: "reno_dem",
            withExtension: "bin",
            subdirectory: "JSBSim/visuals/world/reno"
        ) else {
            return
        }

        if let json = try? Data(contentsOf: worldURL) {
            map = try? JSONDecoder().decode(MapDocument.self, from: json)
        }
        guard let binary = try? Data(contentsOf: terrainURL), binary.count >= 32 else { return }

        func uint32(_ offset: Int) -> UInt32 {
            guard offset + 4 <= binary.count else { return 0 }
            let b0 = UInt32(binary[offset])
            let b1 = UInt32(binary[offset + 1]) << 8
            let b2 = UInt32(binary[offset + 2]) << 16
            let b3 = UInt32(binary[offset + 3]) << 24
            return b0 | b1 | b2 | b3
        }
        func float32(_ offset: Int) -> Float {
            Float(bitPattern: uint32(offset))
        }

        let magic = String(data: binary.prefix(4), encoding: .ascii)
        guard magic == "FAM2", uint32(4) == 1 else { return }

        gridWidth = Int(uint32(8))
        gridHeight = Int(uint32(12))
        cellMeters = float32(16)
        gridMinX = float32(20)
        gridMinZ = float32(24)
        gridReferenceElevationMeters = float32(28)

        let count = gridWidth * gridHeight
        let payloadOffset = 32
        guard gridWidth > 1,
              gridHeight > 1,
              cellMeters > 0,
              payloadOffset + count * MemoryLayout<Float>.size <= binary.count else {
            gridWidth = 0
            gridHeight = 0
            return
        }

        heights = Array(repeating: 0, count: count)
        heights.withUnsafeMutableBytes { destination in
            binary.copyBytes(
                to: destination,
                from: payloadOffset..<(payloadOffset + count * MemoryLayout<Float>.size)
            )
        }
    }

    func absoluteHeight(east: Float, north: Float) -> Float {
        guard isLoaded else { return 0 }

        let gx = (east - gridMinX) / cellMeters
        let gz = (north - gridMinZ) / cellMeters
        let ix = min(max(Int(floor(gx)), 0), gridWidth - 2)
        let iz = min(max(Int(floor(gz)), 0), gridHeight - 2)
        let tx = min(max(gx - Float(ix), 0), 1)
        let tz = min(max(gz - Float(iz), 0), 1)

        let i00 = iz * gridWidth + ix
        let i10 = i00 + 1
        let i01 = (iz + 1) * gridWidth + ix
        let i11 = i01 + 1
        let h00 = heights[i00]
        let h10 = heights[i10]
        let h01 = heights[i01]
        let h11 = heights[i11]

        // Matches the exact diagonal used by the RealityKit terrain mesh.
        if tx + tz <= 1 {
            return h00 + tx * (h10 - h00) + tz * (h01 - h00)
        }
        return h11 + (1 - tz) * (h10 - h11) + (1 - tx) * (h01 - h11)
    }

    func relativeHeight(east: Float, north: Float) -> Float {
        absoluteHeight(east: east, north: north) - referenceElevationMeters
    }

    func normal(east: Float, north: Float) -> SIMD3<Float> {
        let sample = max(cellMeters * 0.5, 10)
        let dhdx = (
            relativeHeight(east: east + sample, north: north) -
            relativeHeight(east: east - sample, north: north)
        ) / (2 * sample)
        let dhdz = (
            relativeHeight(east: east, north: north + sample) -
            relativeHeight(east: east, north: north - sample)
        ) / (2 * sample)
        return simd_normalize(SIMD3<Float>(-dhdx, 1, -dhdz))
    }
}

@MainActor
enum Stage024RealMapWorld {
    static let rootName = "FA.world.stage024.reno"

    private struct BuildingBatchKey: Hashable {
        let x: Int
        let z: Int
        let material: Int
    }

    static func make() -> Entity {
        let root = Entity()
        root.name = rootName

        let data = Stage024RealMapData.shared
        guard data.isLoaded, let map = data.map else { return root }

        addTerrain(to: root, data: data, map: map)
        addRoads(to: root, data: data, roads: map.roads)
        addBuildings(to: root, data: data, buildings: map.buildings)
        addRunways(to: root, data: data, runways: map.runways)
        return root
    }

    private static func addTerrain(
        to root: Entity,
        data: Stage024RealMapData,
        map: Stage024RealMapData.MapDocument
    ) {
        guard let imageURL = Bundle.main.url(
            forResource: "reno_imagery",
            withExtension: "jpg",
            subdirectory: "JSBSim/visuals/world/reno"
        ), let image = try? TextureResource.load(contentsOf: imageURL, withName: "KRNO USGS orthoimagery") else {
            return
        }

        var texture = MaterialParameters.Texture(image)
        texture.sampler.modify { sampler in
            sampler.sAddressMode = .clampToEdge
            sampler.tAddressMode = .clampToEdge
            sampler.minFilter = .linear
            sampler.magFilter = .linear
            sampler.mipFilter = .linear
            sampler.maxAnisotropy = 8
        }

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .white, texture: texture)
        material.roughness = .init(floatLiteral: 1.0)
        material.metallic = .init(floatLiteral: 0.0)
        material.specular = .init(floatLiteral: 0.045)

        let tileMeters: Float = 4_000
        let cell = data.cellMeters
        let stepsPerTile = max(2, Int(round(tileMeters / cell)))
        let actualTile = Float(stepsPerTile) * cell
        let spanX = max(map.maxX - map.minX, 1)
        let spanZ = max(map.maxZ - map.minZ, 1)

        var tileZ = map.minZ
        var tileIndex = 0
        while tileZ < map.maxZ - 0.1 {
            var tileX = map.minX
            while tileX < map.maxX - 0.1 {
                let endX = min(tileX + actualTile, map.maxX)
                let endZ = min(tileZ + actualTile, map.maxZ)
                let nx = max(2, Int(round((endX - tileX) / cell)) + 1)
                let nz = max(2, Int(round((endZ - tileZ) / cell)) + 1)

                var positions: [SIMD3<Float>] = []
                var normals: [SIMD3<Float>] = []
                var texcoords: [SIMD2<Float>] = []
                var indices: [UInt32] = []
                positions.reserveCapacity(nx * nz)
                normals.reserveCapacity(nx * nz)
                texcoords.reserveCapacity(nx * nz)

                for zIndex in 0..<nz {
                    let z = min(tileZ + Float(zIndex) * cell, endZ)
                    for xIndex in 0..<nx {
                        let x = min(tileX + Float(xIndex) * cell, endX)
                        positions.append([x, data.relativeHeight(east: x, north: z), z])
                        normals.append(data.normal(east: x, north: z))
                        let u = (x - map.minX) / spanX
                        // ArcGIS image row zero is north/top; Metal texture v=0 is top.
                        let v = 1 - (z - map.minZ) / spanZ
                        texcoords.append([u, v])
                    }
                }

                for zIndex in 0..<(nz - 1) {
                    for xIndex in 0..<(nx - 1) {
                        let i0 = UInt32(zIndex * nx + xIndex)
                        let i1 = i0 + 1
                        let i2 = UInt32((zIndex + 1) * nx + xIndex)
                        let i3 = i2 + 1
                        indices.append(contentsOf: [i0, i2, i1, i1, i2, i3])
                    }
                }

                var descriptor = MeshDescriptor(name: "KRNO terrain tile \(tileIndex)")
                descriptor.positions = .init(positions)
                descriptor.normals = .init(normals)
                descriptor.textureCoordinates = .init(texcoords)
                descriptor.primitives = .triangles(indices)
                if let mesh = try? MeshResource.generate(from: [descriptor]) {
                    let entity = ModelEntity(mesh: mesh, materials: [material])
                    entity.name = "FA.stage024.terrain.\(tileIndex)"
                    root.addChild(entity)
                }

                tileIndex += 1
                tileX += actualTile
            }
            tileZ += actualTile
        }
    }

    private static func addRoads(
        to root: Entity,
        data: Stage024RealMapData,
        roads: [Stage024RealMapData.Road]
    ) {
        let materials: [PhysicallyBasedMaterial] = [
            roadMaterial(UIColor(red: 0.105, green: 0.108, blue: 0.108, alpha: 1), roughness: 0.95),
            roadMaterial(UIColor(red: 0.145, green: 0.145, blue: 0.140, alpha: 1), roughness: 0.96),
            roadMaterial(UIColor(red: 0.190, green: 0.185, blue: 0.175, alpha: 1), roughness: 0.98),
            roadMaterial(UIColor(red: 0.095, green: 0.100, blue: 0.100, alpha: 1), roughness: 0.94),
            roadMaterial(UIColor(red: 0.155, green: 0.160, blue: 0.158, alpha: 1), roughness: 0.95)
        ]

        for kind in 0..<materials.count {
            var positions: [SIMD3<Float>] = []
            var normals: [SIMD3<Float>] = []
            var indices: [UInt32] = []

            for road in roads where road.kind == kind {
                guard road.points.count >= 4 else { continue }
                let points = stride(from: 0, to: road.points.count - 1, by: 2).map {
                    SIMD2<Float>(road.points[$0], road.points[$0 + 1])
                }
                guard points.count >= 2 else { continue }

                for index in 0..<(points.count - 1) {
                    let a = points[index]
                    let b = points[index + 1]
                    let delta = b - a
                    let length = simd_length(delta)
                    guard length > 1 else { continue }
                    let direction = delta / length
                    let side = SIMD2<Float>(direction.y, -direction.x) * (road.width * 0.5)
                    let corners = [a + side, a - side, b + side, b - side]
                    let base = UInt32(positions.count)
                    for p in corners {
                        positions.append([p.x, data.relativeHeight(east: p.x, north: p.y) + 0.16, p.y])
                        normals.append(data.normal(east: p.x, north: p.y))
                    }
                    indices.append(contentsOf: [base, base + 2, base + 1, base + 1, base + 2, base + 3])
                }
            }

            guard !positions.isEmpty else { continue }
            var descriptor = MeshDescriptor(name: "KRNO road class \(kind)")
            descriptor.positions = .init(positions)
            descriptor.normals = .init(normals)
            descriptor.primitives = .triangles(indices)
            if let mesh = try? MeshResource.generate(from: [descriptor]) {
                let entity = ModelEntity(mesh: mesh, materials: [materials[kind]])
                entity.name = "FA.stage024.roads.\(kind)"
                root.addChild(entity)
            }
        }
    }

    private static func addBuildings(
        to root: Entity,
        data: Stage024RealMapData,
        buildings: [Stage024RealMapData.Building]
    ) {
        let tileSize: Float = 4_000
        var batches: [BuildingBatchKey: [Stage024RealMapData.Building]] = [:]

        for building in buildings {
            let key = BuildingBatchKey(
                x: Int(floor(building.x / tileSize)),
                z: Int(floor(building.z / tileSize)),
                material: min(max(building.material, 0), 3)
            )
            batches[key, default: []].append(building)
        }

        let materials = buildingMaterials()
        for (key, group) in batches {
            var positions: [SIMD3<Float>] = []
            var normals: [SIMD3<Float>] = []
            var indices: [UInt32] = []
            positions.reserveCapacity(group.count * 20)
            normals.reserveCapacity(group.count * 20)
            indices.reserveCapacity(group.count * 30)

            for building in group {
                appendBuilding(
                    building,
                    baseHeight: data.relativeHeight(east: building.x, north: building.z),
                    positions: &positions,
                    normals: &normals,
                    indices: &indices
                )
            }

            guard !positions.isEmpty else { continue }
            var descriptor = MeshDescriptor(name: "KRNO buildings \(key.x),\(key.z),\(key.material)")
            descriptor.positions = .init(positions)
            descriptor.normals = .init(normals)
            descriptor.primitives = .triangles(indices)
            if let mesh = try? MeshResource.generate(from: [descriptor]) {
                let entity = ModelEntity(mesh: mesh, materials: [materials[key.material]])
                entity.name = "FA.stage024.buildings.\(key.x).\(key.z).\(key.material)"
                root.addChild(entity)
            }
        }
    }

    private static func appendBuilding(
        _ building: Stage024RealMapData.Building,
        baseHeight: Float,
        positions: inout [SIMD3<Float>],
        normals: inout [SIMD3<Float>],
        indices: inout [UInt32]
    ) {
        let hx = max(building.width, 2) * 0.5
        let hz = max(building.depth, 2) * 0.5
        let h = max(building.height, 2.5)
        let c = cos(building.yaw)
        let s = sin(building.yaw)

        func world(_ local: SIMD3<Float>) -> SIMD3<Float> {
            [
                building.x + local.x * c - local.z * s,
                baseHeight + local.y,
                building.z + local.x * s + local.z * c
            ]
        }
        func rotatedNormal(_ local: SIMD3<Float>) -> SIMD3<Float> {
            simd_normalize(SIMD3<Float>(local.x * c - local.z * s, local.y, local.x * s + local.z * c))
        }
        func face(_ corners: [SIMD3<Float>], normal: SIMD3<Float>) {
            let base = UInt32(positions.count)
            positions.append(contentsOf: corners.map(world))
            normals.append(contentsOf: Array(repeating: rotatedNormal(normal), count: 4))
            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }

        face([[-hx, 0, -hz], [-hx, h, -hz], [hx, h, -hz], [hx, 0, -hz]], normal: [0, 0, -1])
        face([[hx, 0, -hz], [hx, h, -hz], [hx, h, hz], [hx, 0, hz]], normal: [1, 0, 0])
        face([[hx, 0, hz], [hx, h, hz], [-hx, h, hz], [-hx, 0, hz]], normal: [0, 0, 1])
        face([[-hx, 0, hz], [-hx, h, hz], [-hx, h, -hz], [-hx, 0, -hz]], normal: [-1, 0, 0])
        face([[-hx, h, -hz], [-hx, h, hz], [hx, h, hz], [hx, h, -hz]], normal: [0, 1, 0])
    }

    private static func addRunways(
        to root: Entity,
        data: Stage024RealMapData,
        runways: [Stage024RealMapData.Runway]
    ) {
        let asphalt = roadMaterial(UIColor(red: 0.105, green: 0.108, blue: 0.105, alpha: 1), roughness: 0.95)
        let marking = SimpleMaterial(color: UIColor(white: 0.86, alpha: 1), roughness: 0.91, isMetallic: false)

        for runway in runways {
            let start = SIMD2<Float>(runway.startX, runway.startZ)
            let end = SIMD2<Float>(runway.endX, runway.endZ)
            let delta = end - start
            let length = simd_length(delta)
            guard length > 10 else { continue }
            let direction = delta / length
            let side = SIMD2<Float>(direction.y, -direction.x) * (runway.width * 0.5)
            let corners = [start + side, start - side, end + side, end - side]
            var positions: [SIMD3<Float>] = []
            var normals: [SIMD3<Float>] = []
            for p in corners {
                positions.append([p.x, data.relativeHeight(east: p.x, north: p.y) + 0.20, p.y])
                normals.append(data.normal(east: p.x, north: p.y))
            }
            var descriptor = MeshDescriptor(name: "KRNO runway \(runway.name)")
            descriptor.positions = .init(positions)
            descriptor.normals = .init(normals)
            descriptor.primitives = .triangles([0, 2, 1, 1, 2, 3])
            if let mesh = try? MeshResource.generate(from: [descriptor]) {
                let entity = ModelEntity(mesh: mesh, materials: [asphalt])
                entity.name = "FA.stage024.runway.\(runway.name)"
                root.addChild(entity)
            }

            // Simple real-scale centerline dashes keep the runway crisp below the
            // orthoimagery's macro resolution without inventing a fake airbase.
            let dashLength: Float = 30
            let gap: Float = 30
            var distance: Float = 90
            while distance < length - 90 {
                let center = start + direction * distance
                let height = data.relativeHeight(east: center.x, north: center.y) + 0.27
                let dash = ModelEntity(
                    mesh: .generateBox(size: [1.0, 0.025, dashLength], cornerRadius: 0.03),
                    materials: [marking]
                )
                dash.position = [center.x, height, center.y]
                let yaw = atan2(direction.x, direction.y)
                dash.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
                root.addChild(dash)
                distance += dashLength + gap
            }
        }
    }

    private static func roadMaterial(_ color: UIColor, roughness: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: 0)
        material.specular = .init(floatLiteral: 0.12)
        return material
    }

    private static func buildingMaterials() -> [PhysicallyBasedMaterial] {
        let colors: [UIColor] = [
            UIColor(red: 0.48, green: 0.45, blue: 0.40, alpha: 1),
            UIColor(red: 0.38, green: 0.39, blue: 0.38, alpha: 1),
            UIColor(red: 0.52, green: 0.50, blue: 0.46, alpha: 1),
            UIColor(red: 0.34, green: 0.36, blue: 0.37, alpha: 1)
        ]
        return colors.enumerated().map { index, color in
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: color)
            material.roughness = .init(floatLiteral: index == 2 ? 0.82 : 0.91)
            material.metallic = .init(floatLiteral: 0)
            material.specular = .init(floatLiteral: index == 2 ? 0.20 : 0.13)
            return material
        }
    }
}
