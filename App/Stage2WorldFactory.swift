import Foundation
import RealityKit
import UIKit
import simd

/// Base scene content that is independent of a specific theater. Terrain,
/// airfields, roads and settlements now belong to the active theater renderer.
@MainActor
enum Stage2WorldFactory {
    static func make(includeLegacyRegionalRoads: Bool = true) -> Entity {
        let root = Entity()
        root.name = "FA.world.stage2"
        addCloudscape(to: root)
        return root
    }

    // MARK: - Atmosphere / cloudscape

    /// Mobile-friendly layered cloud cards retained from the proven Stage 017
    /// presentation. They are theater-independent and remain cheap at jet speed.
    private static func addCloudscape(to root: Entity) {
        let names = ["cloud_alpha_03", "cloud_alpha_05", "cloud_alpha_08"]
        let textures = names.compactMap(loadCloudTexture)
        guard !textures.isEmpty else { return }

        let cloudRoot = Entity()
        cloudRoot.name = "FA.world.cloudscape"

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
}

// MARK: - Coherent theater features

/// Runtime presentation for geography authored by `bake-worldsmith-theater.mjs`.
/// Terrain remains the exact Stage022 / JSBSim heightfield; this layer only
/// renders features whose topology was derived from that same surface at build time.
@MainActor
enum Stage023TheaterFeatures {
    static let rootName = "FA.world.coherent-features"

    private struct FeatureFile: Decodable {
        let version: Int
        let theaterMeters: Float
        let cellMeters: Float
        let rivers: [River]
        let roads: [Road]
        let lakes: [Lake]
        let settlements: [Settlement]
    }

    private struct River: Decodable {
        let maxAccumulation: Int
        let points: [[Float]]
    }

    private struct Road: Decodable {
        let roadClass: String
        let widthMeters: Float
        let shoulderMeters: Float
        let from: String
        let to: String
        let points: [[Float]]

        private enum CodingKeys: String, CodingKey {
            case roadClass = "class"
            case widthMeters, shoulderMeters, from, to, points
        }
    }

    private struct Lake: Decodable {
        let surfaceMeters: Float
        let maxDepthMeters: Float
        let patches: [[Float]]
    }

    private struct Settlement: Decodable {
        let name: String
        let kind: String
        let east: Float
        let north: Float
        let radiusMeters: Float
        let seed: Int
        let score: Float
        let headingRadians: Float
    }

    private struct LCG {
        var state: UInt64

        mutating func unit() -> Float {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float((state >> 40) & 0xFF_FFFF) / Float(0xFF_FFFF)
        }
    }

    static func attach(to world: Entity) {
        guard world.findEntity(named: rootName) == nil,
              let theaterRoot = world.findEntity(named: Stage022MaltaWorld.rootName),
              let features = loadFeatures() else { return }

        let root = Entity()
        root.name = rootName

        let water = makeWaterMaterial()
        for (index, lake) in features.lakes.enumerated() {
            if let entity = makeLake(lake, cellMeters: features.cellMeters, material: water) {
                entity.name = "FA.world.lake.\(index)"
                root.addChild(entity)
            }
        }
        for (index, river) in features.rivers.enumerated() {
            if let entity = makeRiver(river, material: water) {
                entity.name = "FA.world.river.\(index)"
                root.addChild(entity)
            }
        }

        let primaryRoad = roadMaterial(
            color: UIColor(red: 0.075, green: 0.080, blue: 0.080, alpha: 1),
            roughness: 0.91
        )
        let secondaryRoad = roadMaterial(
            color: UIColor(red: 0.105, green: 0.103, blue: 0.095, alpha: 1),
            roughness: 0.94
        )
        let shoulder = roadMaterial(
            color: UIColor(red: 0.28, green: 0.25, blue: 0.20, alpha: 1),
            roughness: 0.98
        )

        for (index, road) in features.roads.enumerated() {
            if let shoulderEntity = makeDrapedRoadRibbon(
                points: road.points,
                width: road.widthMeters + road.shoulderMeters * 2,
                verticalOffset: 0.11,
                material: shoulder
            ) {
                shoulderEntity.name = "FA.world.road.shoulder.\(index)"
                root.addChild(shoulderEntity)
            }
            if let roadEntity = makeDrapedRoadRibbon(
                points: road.points,
                width: road.widthMeters,
                verticalOffset: 0.18,
                material: road.roadClass == "primary" ? primaryRoad : secondaryRoad
            ) {
                roadEntity.name = "FA.world.road.\(index)"
                root.addChild(roadEntity)
            }
        }

        for settlement in features.settlements {
            root.addChild(makeSettlement(settlement))
        }

        theaterRoot.addChild(root)
    }

    private static func loadFeatures() -> FeatureFile? {
        guard let url = Bundle.main.url(
            forResource: "worldsmith_1337_features",
            withExtension: "json",
            subdirectory: "JSBSim/visuals/world"
        ), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FeatureFile.self, from: data)
    }

    private static func makeWaterMaterial() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(
            tint: UIColor(red: 0.018, green: 0.095, blue: 0.135, alpha: 1)
        )
        material.roughness = .init(floatLiteral: 0.12)
        material.metallic = .init(floatLiteral: 0.0)
        material.specular = .init(floatLiteral: 0.90)
        material.clearcoat = .init(floatLiteral: 0.62)
        material.clearcoatRoughness = .init(floatLiteral: 0.08)
        material.faceCulling = .none

        if let url = Bundle.main.url(
            forResource: "worldsmith_water_normal_256",
            withExtension: "png",
            subdirectory: "JSBSim/visuals/world"
        ), let resource = try? TextureResource.load(
            contentsOf: url,
            withName: "Full Authority inland water normal"
        ) {
            var texture = MaterialParameters.Texture(resource)
            texture.sampler.modify { sampler in
                sampler.sAddressMode = .repeat
                sampler.tAddressMode = .repeat
                sampler.mipFilter = .linear
                sampler.minFilter = .linear
                sampler.magFilter = .linear
                sampler.maxAnisotropy = 8
            }
            material.normal = PhysicallyBasedMaterial.Normal(texture: texture)
            material.textureCoordinateTransform = .init(
                offset: .zero,
                scale: SIMD2<Float>(repeating: 44),
                rotation: 0.17
            )
        }
        return material
    }

    private static func roadMaterial(color: UIColor, roughness: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: 0)
        material.specular = .init(floatLiteral: 0.10)
        material.faceCulling = .none
        return material
    }

    private static func makeDrapedRoadRibbon(
        points: [[Float]],
        width: Float,
        verticalOffset: Float,
        material: PhysicallyBasedMaterial
    ) -> ModelEntity? {
        guard points.count >= 2 else { return nil }
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var texcoords: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(points.count * 2)
        normals.reserveCapacity(points.count * 2)
        texcoords.reserveCapacity(points.count * 2)
        indices.reserveCapacity((points.count - 1) * 6)

        var distance: Float = 0
        var previousCenter: SIMD2<Float>?
        for index in points.indices {
            guard points[index].count >= 2 else { return nil }
            let center = SIMD2<Float>(points[index][0], points[index][1])
            if let previousCenter { distance += simd_distance(center, previousCenter) }
            previousCenter = center

            let p0 = SIMD2<Float>(points[max(0, index - 1)][0], points[max(0, index - 1)][1])
            let p1 = SIMD2<Float>(points[min(points.count - 1, index + 1)][0], points[min(points.count - 1, index + 1)][1])
            var tangent = p1 - p0
            if simd_length_squared(tangent) < 0.0001 { tangent = SIMD2<Float>(0, 1) }
            tangent = simd_normalize(tangent)
            let lateral = SIMD2<Float>(tangent.y, -tangent.x) * (width * 0.5)
            let left = center + lateral
            let right = center - lateral

            let leftY = Stage2TerrainProfile.heightMeters(east: left.x, north: left.y) + verticalOffset
            let rightY = Stage2TerrainProfile.heightMeters(east: right.x, north: right.y) + verticalOffset
            positions.append([left.x, leftY, left.y])
            positions.append([right.x, rightY, right.y])
            normals.append(Stage2TerrainProfile.normal(east: left.x, north: left.y))
            normals.append(Stage2TerrainProfile.normal(east: right.x, north: right.y))
            texcoords.append([0, distance / 90])
            texcoords.append([1, distance / 90])
        }

        for index in 0..<(points.count - 1) {
            let i0 = UInt32(index * 2)
            let i1 = i0 + 1
            let i2 = i0 + 2
            let i3 = i0 + 3
            indices.append(contentsOf: [i0, i2, i1, i1, i2, i3])
        }

        var descriptor = MeshDescriptor(name: "Terrain-draped road")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(texcoords)
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }
        return ModelEntity(mesh: mesh, materials: [material])
    }

    private static func makeRiver(
        _ river: River,
        material: PhysicallyBasedMaterial
    ) -> ModelEntity? {
        let points = river.points
        guard points.count >= 2 else { return nil }
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var texcoords: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(points.count * 2)
        normals.reserveCapacity(points.count * 2)
        texcoords.reserveCapacity(points.count * 2)

        var distance: Float = 0
        var previousCenter: SIMD2<Float>?
        for index in points.indices {
            guard points[index].count >= 4 else { return nil }
            let center = SIMD2<Float>(points[index][0], points[index][1])
            if let previousCenter { distance += simd_distance(center, previousCenter) }
            previousCenter = center

            let p0 = SIMD2<Float>(points[max(0, index - 1)][0], points[max(0, index - 1)][1])
            let p1 = SIMD2<Float>(points[min(points.count - 1, index + 1)][0], points[min(points.count - 1, index + 1)][1])
            var tangent = p1 - p0
            if simd_length_squared(tangent) < 0.0001 { tangent = SIMD2<Float>(0, 1) }
            tangent = simd_normalize(tangent)
            let halfWidth = max(3.0, points[index][3] * 0.5)
            let lateral = SIMD2<Float>(tangent.y, -tangent.x) * halfWidth
            let left = center + lateral
            let right = center - lateral
            let terrainY = Stage2TerrainProfile.heightMeters(east: center.x, north: center.y)
            let waterY = max(points[index][2], terrainY) + 0.16

            positions.append([left.x, waterY, left.y])
            positions.append([right.x, waterY, right.y])
            normals.append([0, 1, 0])
            normals.append([0, 1, 0])
            texcoords.append([0, distance / 120])
            texcoords.append([1, distance / 120])
        }
        for index in 0..<(points.count - 1) {
            let i0 = UInt32(index * 2), i1 = i0 + 1, i2 = i0 + 2, i3 = i0 + 3
            indices.append(contentsOf: [i0, i2, i1, i1, i2, i3])
        }
        var descriptor = MeshDescriptor(name: "Hydrologic river")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(texcoords)
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }
        return ModelEntity(mesh: mesh, materials: [material])
    }

    private static func makeLake(
        _ lake: Lake,
        cellMeters: Float,
        material: PhysicallyBasedMaterial
    ) -> ModelEntity? {
        guard !lake.patches.isEmpty else { return nil }
        let heading: Float = 1.0384709
        let c = cos(heading), s = sin(heading)
        let uBasis = SIMD2<Float>(c, s)
        let vBasis = SIMD2<Float>(s, -c)
        let half = cellMeters * 0.515
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var texcoords: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(lake.patches.count * 4)
        normals.reserveCapacity(lake.patches.count * 4)
        texcoords.reserveCapacity(lake.patches.count * 4)
        indices.reserveCapacity(lake.patches.count * 6)
        let y = lake.surfaceMeters + 0.18

        for patch in lake.patches where patch.count >= 2 {
            let center = SIMD2<Float>(patch[0], patch[1])
            let corners = [
                center - uBasis * half - vBasis * half,
                center + uBasis * half - vBasis * half,
                center - uBasis * half + vBasis * half,
                center + uBasis * half + vBasis * half,
            ]
            let base = UInt32(positions.count)
            for (index, corner) in corners.enumerated() {
                positions.append([corner.x, y, corner.y])
                normals.append([0, 1, 0])
                texcoords.append(index == 0 ? [0,0] : index == 1 ? [1,0] : index == 2 ? [0,1] : [1,1])
            }
            indices.append(contentsOf: [base, base + 2, base + 1, base + 1, base + 2, base + 3])
        }
        var descriptor = MeshDescriptor(name: "Priority-Flood lake")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(texcoords)
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }
        return ModelEntity(mesh: mesh, materials: [material])
    }

    private static func makeSettlement(_ settlement: Settlement) -> Entity {
        let root = Entity()
        root.name = "FA.world.settlement.\(settlement.name)"

        let road = roadMaterial(
            color: UIColor(red: 0.105, green: 0.100, blue: 0.090, alpha: 1),
            roughness: 0.95
        )
        let heading = settlement.headingRadians
        let forward = SIMD2<Float>(sin(heading), cos(heading))
        let right = SIMD2<Float>(cos(heading), -sin(heading))
        let center = SIMD2<Float>(settlement.east, settlement.north)
        let streetLength = settlement.radiusMeters * 1.55
        let localStreetWidth: Float = settlement.kind == "town" ? 8.0 : 6.5

        let longitudinal = [center - forward * streetLength, center + forward * streetLength]
        let cross = [center - right * streetLength * 0.82, center + right * streetLength * 0.82]
        for (index, line) in [longitudinal, cross].enumerated() {
            let points = line.map { [$0.x, $0.y] }
            if let street = makeDrapedRoadRibbon(
                points: points,
                width: localStreetWidth,
                verticalOffset: 0.19,
                material: road
            ) {
                street.name = "FA.world.settlement.\(settlement.name).street.\(index)"
                root.addChild(street)
            }
        }

        if let buildings = makeSettlementBuildings(settlement, forward: forward, right: right) {
            buildings.name = "FA.world.settlement.\(settlement.name).buildings"
            root.addChild(buildings)
        }
        return root
    }

    private static func makeSettlementBuildings(
        _ settlement: Settlement,
        forward: SIMD2<Float>,
        right: SIMD2<Float>
    ) -> ModelEntity? {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var faceMaterials: [UInt32] = []
        var random = LCG(state: UInt64(bitPattern: Int64(settlement.seed)))
        let isTown = settlement.kind == "town"
        let spacing: Float = isTown ? 92 : 105
        let maxBuildings = isTown ? 62 : 28
        let gridRadius = isTown ? 5 : 3
        var count = 0

        func appendFace(_ corners: [SIMD3<Float>], normal: SIMD3<Float>, material: UInt32) {
            let base = UInt32(positions.count)
            positions.append(contentsOf: corners)
            normals.append(contentsOf: Array(repeating: normal, count: 4))
            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
            faceMaterials.append(material)
            faceMaterials.append(material)
        }

        func appendBox(center: SIMD3<Float>, width: Float, depth: Float, height: Float, angle: Float, material: UInt32) {
            let c = cos(angle), s = sin(angle)
            let rx = SIMD2<Float>(c, -s)
            let rz = SIMD2<Float>(s, c)
            let hx = width * 0.5, hz = depth * 0.5
            func point(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> {
                let p = SIMD2<Float>(center.x, center.z) + rx * x + rz * z
                return [p.x, center.y + y, p.y]
            }
            let y0: Float = 0, y1 = height
            let p000 = point(-hx,y0,-hz), p100 = point(hx,y0,-hz)
            let p110 = point(hx,y1,-hz), p010 = point(-hx,y1,-hz)
            let p001 = point(-hx,y0,hz), p101 = point(hx,y0,hz)
            let p111 = point(hx,y1,hz), p011 = point(-hx,y1,hz)
            let nX = SIMD3<Float>(rx.x, 0, rx.y)
            let nZ = SIMD3<Float>(rz.x, 0, rz.y)
            appendFace([p100,p101,p111,p110], normal: nX, material: material)
            appendFace([p001,p000,p010,p011], normal: -nX, material: material)
            appendFace([p101,p001,p011,p111], normal: nZ, material: material)
            appendFace([p000,p100,p110,p010], normal: -nZ, material: material)
            appendFace([p010,p110,p111,p011], normal: [0,1,0], material: material)
            appendFace([p001,p101,p100,p000], normal: [0,-1,0], material: material)
        }

        for gz in -gridRadius...gridRadius {
            for gx in -gridRadius...gridRadius {
                if count >= maxBuildings { break }
                if gx == 0 || gz == 0 { continue }
                if random.unit() < (isTown ? 0.12 : 0.30) { continue }

                let localRight = Float(gx) * spacing + (random.unit() - 0.5) * 24
                let localForward = Float(gz) * spacing + (random.unit() - 0.5) * 24
                if hypot(localRight, localForward) > settlement.radiusMeters * 0.93 { continue }
                let p = SIMD2<Float>(settlement.east, settlement.north)
                    + right * localRight + forward * localForward
                let normal = Stage2TerrainProfile.normal(east: p.x, north: p.y)
                if normal.y < 0.93 { continue }
                let ground = Stage2TerrainProfile.heightMeters(east: p.x, north: p.y)
                let width: Float = (isTown ? 24 : 20) + random.unit() * (isTown ? 28 : 19)
                let depth: Float = (isTown ? 22 : 19) + random.unit() * (isTown ? 30 : 18)
                let height: Float = (isTown ? 7 : 5.5) + random.unit() * (isTown ? 20 : 8.5)
                let angle = settlement.headingRadians + (random.unit() - 0.5) * 0.16
                let material = UInt32(min(2, Int(random.unit() * 3)))
                appendBox(center: [p.x, ground + 0.08, p.y], width: width, depth: depth, height: height, angle: angle, material: material)
                count += 1
            }
        }

        guard !positions.isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: "Terrain-sited settlement")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        descriptor.materials = .perFace(faceMaterials)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }

        let materials = [
            SimpleMaterial(color: UIColor(red: 0.50, green: 0.46, blue: 0.39, alpha: 1), roughness: 0.95, isMetallic: false),
            SimpleMaterial(color: UIColor(red: 0.40, green: 0.40, blue: 0.37, alpha: 1), roughness: 0.96, isMetallic: false),
            SimpleMaterial(color: UIColor(red: 0.58, green: 0.54, blue: 0.46, alpha: 1), roughness: 0.94, isMetallic: false),
        ]
        return ModelEntity(mesh: mesh, materials: materials)
    }
}
