import RealityKit
import UIKit
import simd

/// Stage 023 gives the world readable land use at altitude without turning the
/// scenery into a random prop dump. Elevation still comes exclusively from
/// Stage2TerrainProfile; everything in this file is visual dressing on that
/// authoritative surface.
@MainActor
enum Stage023TerrainSystem {
    static let rootName = "FA.world.stage023"

    private static let vehiclePrefix = "FA.world.stage023.vehicle."

    private struct Parcel {
        let center: SIMD2<Float>
        let size: SIMD2<Float>
        let rotation: Float
        let shear: SIMD2<Float>
        let color: UIColor
    }

    private struct TrafficRoute {
        let points: [SIMD2<Float>]
        let speedMetersPerSecond: Float
        let phaseSeconds: Float
        let truck: Bool
    }

    static func make() -> Entity {
        let root = Entity()
        root.name = rootName

        addAgriculturalLandclass(to: root)
        addHamlets(to: root)
        addHedgerows(to: root)
        addTraffic(to: root)

        return root
    }

    /// Lightweight movement only. Terrain and static scenery remain immutable.
    static func update(worldRoot: Entity, elapsed: TimeInterval) {
        guard let root = worldRoot.findEntity(named: rootName) else { return }

        let routes = trafficRoutes
        for index in routes.indices {
            guard let vehicle = root.findEntity(named: vehiclePrefix + String(index)) else { continue }
            let route = routes[index]
            let sample = sample(route: route, elapsed: Float(elapsed))
            let terrain = Stage2TerrainProfile.heightMeters(east: sample.position.x, north: sample.position.y)
            vehicle.position = [sample.position.x, terrain + (route.truck ? 1.0 : 0.72), sample.position.y]
            vehicle.orientation = simd_quatf(angle: sample.yaw, axis: [0, 1, 0])
        }
    }

    // MARK: - Landclass-scale agricultural breakup

    private static func addAgriculturalLandclass(to root: Entity) {
        let group = Entity()
        group.name = "FA.world.stage023.agriculture"

        let greenA = UIColor(red: 0.245, green: 0.315, blue: 0.145, alpha: 1)
        let greenB = UIColor(red: 0.285, green: 0.345, blue: 0.165, alpha: 1)
        let greenC = UIColor(red: 0.205, green: 0.285, blue: 0.125, alpha: 1)
        let hayA = UIColor(red: 0.405, green: 0.385, blue: 0.205, alpha: 1)
        let hayB = UIColor(red: 0.345, green: 0.335, blue: 0.185, alpha: 1)
        let fallow = UIColor(red: 0.315, green: 0.275, blue: 0.175, alpha: 1)

        let parcels: [Parcel] = [
            .init(center: [-10_200, -7_400], size: [1_360, 760], rotation: 0.14, shear: [0.10, -0.04], color: greenA),
            .init(center: [-8_500, -6_900], size: [1_100, 640], rotation: -0.09, shear: [-0.05, 0.08], color: hayA),
            .init(center: [-6_850, -7_450], size: [1_260, 720], rotation: 0.07, shear: [0.08, 0.05], color: greenC),
            .init(center: [-4_900, -7_750], size: [1_020, 590], rotation: -0.18, shear: [0.05, -0.07], color: fallow),
            .init(center: [-2_900, -7_100], size: [1_230, 700], rotation: 0.12, shear: [-0.08, 0.04], color: greenB),
            .init(center: [2_750, -7_750], size: [1_240, 720], rotation: -0.13, shear: [0.06, 0.08], color: hayB),
            .init(center: [4_650, -7_000], size: [1_180, 660], rotation: 0.18, shear: [-0.06, 0.04], color: greenA),
            .init(center: [6_650, -7_650], size: [1_320, 760], rotation: -0.05, shear: [0.08, -0.05], color: greenC),
            .init(center: [8_700, -6_750], size: [1_050, 620], rotation: 0.11, shear: [-0.07, 0.05], color: hayA),

            .init(center: [-10_300, -3_850], size: [1_220, 730], rotation: -0.15, shear: [0.07, 0.05], color: hayB),
            .init(center: [-8_450, -3_400], size: [1_060, 650], rotation: 0.10, shear: [-0.08, -0.03], color: greenB),
            .init(center: [-6_500, -4_150], size: [1_260, 700], rotation: -0.06, shear: [0.05, 0.08], color: greenA),
            .init(center: [-4_500, -3_650], size: [1_100, 620], rotation: 0.16, shear: [-0.05, 0.05], color: fallow),
            .init(center: [4_500, -4_000], size: [1_150, 690], rotation: -0.11, shear: [0.09, 0.04], color: greenC),
            .init(center: [6_450, -3_300], size: [1_000, 610], rotation: 0.07, shear: [-0.04, 0.07], color: hayA),
            .init(center: [8_550, -3_850], size: [1_280, 750], rotation: 0.15, shear: [0.06, -0.05], color: greenB),

            .init(center: [-10_000, 900], size: [1_340, 780], rotation: 0.08, shear: [-0.05, 0.07], color: greenA),
            .init(center: [-8_100, 1_500], size: [1_080, 650], rotation: -0.13, shear: [0.06, 0.04], color: hayB),
            .init(center: [-5_850, 700], size: [1_240, 720], rotation: 0.17, shear: [-0.08, 0.03], color: greenC),
            .init(center: [-4_000, 1_600], size: [1_000, 620], rotation: -0.05, shear: [0.05, -0.07], color: fallow),
            .init(center: [5_300, 250], size: [1_150, 700], rotation: 0.12, shear: [0.07, 0.04], color: greenB),
            .init(center: [7_350, 650], size: [1_260, 740], rotation: -0.10, shear: [-0.05, 0.08], color: hayA),
            .init(center: [9_300, 1_350], size: [1_100, 660], rotation: 0.06, shear: [0.08, -0.04], color: greenA),

            .init(center: [-9_750, 5_300], size: [1_250, 720], rotation: -0.09, shear: [0.05, 0.06], color: hayA),
            .init(center: [-7_650, 5_900], size: [1_120, 660], rotation: 0.14, shear: [-0.07, 0.05], color: greenB),
            .init(center: [-5_500, 5_150], size: [1_320, 760], rotation: -0.04, shear: [0.08, -0.05], color: greenC),
            .init(center: [-3_300, 6_100], size: [1_080, 630], rotation: 0.11, shear: [-0.04, 0.07], color: fallow),
            .init(center: [4_200, 5_650], size: [1_160, 690], rotation: -0.16, shear: [0.07, 0.03], color: greenA),
            .init(center: [6_100, 5_100], size: [1_000, 600], rotation: 0.09, shear: [-0.06, 0.08], color: hayB),
            .init(center: [8_150, 5_850], size: [1_260, 730], rotation: -0.07, shear: [0.05, -0.05], color: greenB),

            .init(center: [-9_200, 9_000], size: [1_280, 740], rotation: 0.13, shear: [-0.06, 0.05], color: greenC),
            .init(center: [-6_950, 9_250], size: [1_120, 660], rotation: -0.08, shear: [0.08, 0.04], color: hayA),
            .init(center: [-4_600, 8_650], size: [1_250, 720], rotation: 0.05, shear: [-0.05, 0.07], color: greenA),
            .init(center: [3_700, 9_050], size: [1_180, 690], rotation: -0.12, shear: [0.07, -0.04], color: fallow),
            .init(center: [5_950, 8_750], size: [1_080, 620], rotation: 0.10, shear: [-0.04, 0.08], color: greenB),
            .init(center: [8_300, 9_250], size: [1_300, 760], rotation: -0.05, shear: [0.06, 0.04], color: hayB)
        ]

        for (index, parcel) in parcels.enumerated() {
            if abs(parcel.center.x) < 1_700 && parcel.center.y > -2_700 && parcel.center.y < 6_100 {
                continue
            }
            if Stage2TerrainProfile.normal(east: parcel.center.x, north: parcel.center.y).y < 0.93 {
                continue
            }
            if let entity = makeParcel(parcel) {
                entity.name = "FA.world.stage023.parcel.\(index)"
                group.addChild(entity)
            }
        }

        root.addChild(group)
    }

    private static func makeParcel(_ parcel: Parcel) -> ModelEntity? {
        let subdivisions = 6
        let pointsPerSide = subdivisions + 1
        let c = cos(parcel.rotation)
        let s = sin(parcel.rotation)

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(pointsPerSide * pointsPerSide)
        normals.reserveCapacity(pointsPerSide * pointsPerSide)
        indices.reserveCapacity(subdivisions * subdivisions * 6)

        for zIndex in 0...subdivisions {
            let v = Float(zIndex) / Float(subdivisions)
            for xIndex in 0...subdivisions {
                let u = Float(xIndex) / Float(subdivisions)
                let baseX = (u - 0.5) * parcel.size.x
                let baseZ = (v - 0.5) * parcel.size.y
                let localX = baseX + (v - 0.5) * parcel.size.x * parcel.shear.x
                let localZ = baseZ + (u - 0.5) * parcel.size.y * parcel.shear.y
                let worldX = parcel.center.x + localX * c - localZ * s
                let worldZ = parcel.center.y + localX * s + localZ * c
                let height = Stage2TerrainProfile.heightMeters(east: worldX, north: worldZ)
                positions.append([worldX, height + 0.018, worldZ])
                normals.append(Stage2TerrainProfile.normal(east: worldX, north: worldZ))
            }
        }

        for zIndex in 0..<subdivisions {
            for xIndex in 0..<subdivisions {
                let i0 = UInt32(zIndex * pointsPerSide + xIndex)
                let i1 = i0 + 1
                let i2 = UInt32((zIndex + 1) * pointsPerSide + xIndex)
                let i3 = i2 + 1
                indices.append(contentsOf: [i0, i2, i1, i1, i2, i3])
            }
        }

        var descriptor = MeshDescriptor(name: "Stage 023 landclass parcel")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }

        return ModelEntity(mesh: mesh, materials: [matte(parcel.color, roughness: 1.0, specular: 0.05)])
    }

    // MARK: - Hamlets / farms

    private static func addHamlets(to root: Entity) {
        let group = Entity()
        group.name = "FA.world.stage023.hamlets"

        let centers: [(SIMD2<Float>, Float, Int)] = [
            ([-6_200, 2_300], 0.18, 14),
            ([7_000, -4_900], -0.12, 16),
            ([-7_900, -5_400], 0.06, 12),
            ([7_900, 7_300], -0.20, 15),
            ([-4_200, 8_300], 0.12, 11)
        ]

        for (villageIndex, entry) in centers.enumerated() {
            let (center, heading, count) = entry
            for houseIndex in 0..<count {
                let row = houseIndex / 6
                let column = houseIndex % 6
                let seed = villageIndex * 97 + houseIndex * 17
                let along = (Float(column) - 2.5) * 86 + (hash(seed + 1) - 0.5) * 26
                let across = (Float(row) - 0.8) * 112 + (hash(seed + 2) - 0.5) * 34
                let c = cos(heading)
                let s = sin(heading)
                let x = center.x + along * c - across * s
                let z = center.y + along * s + across * c
                if Stage2TerrainProfile.normal(east: x, north: z).y < 0.94 { continue }

                let width = 18 + hash(seed + 3) * 12
                let depth = 14 + hash(seed + 4) * 10
                let height = 6.5 + hash(seed + 5) * 4.0
                let yaw = heading + (hash(seed + 6) - 0.5) * 0.16
                let house = makeHouse(width: width, depth: depth, height: height, selector: seed)
                let terrain = Stage2TerrainProfile.heightMeters(east: x, north: z)
                house.position = [x, terrain, z]
                house.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
                group.addChild(house)
            }

            addFarmSiloCluster(to: group, center: center + SIMD2<Float>(210, -170), selector: villageIndex)
        }

        root.addChild(group)
    }

    private static func makeHouse(width: Float, depth: Float, height: Float, selector: Int) -> Entity {
        let root = Entity()

        let walls: [UIColor] = [
            UIColor(red: 0.48, green: 0.45, blue: 0.39, alpha: 1),
            UIColor(red: 0.39, green: 0.41, blue: 0.39, alpha: 1),
            UIColor(red: 0.52, green: 0.49, blue: 0.42, alpha: 1),
            UIColor(red: 0.34, green: 0.37, blue: 0.37, alpha: 1)
        ]
        let roofs: [UIColor] = [
            UIColor(red: 0.18, green: 0.15, blue: 0.13, alpha: 1),
            UIColor(red: 0.16, green: 0.17, blue: 0.16, alpha: 1),
            UIColor(red: 0.24, green: 0.18, blue: 0.14, alpha: 1)
        ]

        let body = ModelEntity(
            mesh: .generateBox(size: [width, height, depth], cornerRadius: 0.35),
            materials: [matte(walls[abs(selector) % walls.count], roughness: 0.94, specular: 0.10)]
        )
        body.position = [0, height * 0.5, 0]
        root.addChild(body)

        let roofColor = roofs[abs(selector / 3) % roofs.count]
        let roofThickness: Float = 0.55
        for side: Float in [-1, 1] {
            let roof = ModelEntity(
                mesh: .generateBox(size: [width + 1.8, roofThickness, depth * 0.62], cornerRadius: 0.12),
                materials: [matte(roofColor, roughness: 0.91, specular: 0.11)]
            )
            roof.position = [0, height + 1.55, side * depth * 0.20]
            roof.orientation = simd_quatf(angle: side * 0.42, axis: [1, 0, 0])
            root.addChild(roof)
        }

        return root
    }

    private static func addFarmSiloCluster(to root: Entity, center: SIMD2<Float>, selector: Int) {
        for index in 0..<2 {
            let x = center.x + Float(index) * 18
            let z = center.y + Float(index % 2) * 12
            let terrain = Stage2TerrainProfile.heightMeters(east: x, north: z)
            let height: Float = 14 + Float((selector + index) % 4) * 2
            let silo = ModelEntity(
                mesh: .generateCylinder(height: height, radius: 5.2),
                materials: [matte(
                    UIColor(red: 0.44, green: 0.45, blue: 0.42, alpha: 1),
                    roughness: 0.84,
                    specular: 0.14
                )]
            )
            silo.position = [x, terrain + height * 0.5, z]
            root.addChild(silo)
        }
    }

    // MARK: - Hedgerows / field boundaries

    private static func addHedgerows(to root: Entity) {
        let group = Entity()
        group.name = "FA.world.stage023.hedgerows"

        let rows: [(SIMD2<Float>, SIMD2<Float>)] = [
            ([-10_900, -5_900], [-6_000, -6_150]),
            ([-8_800, -2_600], [-4_300, -2_900]),
            ([-10_200, 3_300], [-5_600, 3_600]),
            ([-8_800, 7_350], [-3_500, 7_500]),
            ([2_300, -6_250], [8_700, -6_050]),
            ([4_000, -2_250], [9_500, -1_850]),
            ([4_700, 3_600], [9_000, 3_850]),
            ([3_700, 7_650], [8_900, 7_900])
        ]

        for (rowIndex, row) in rows.enumerated() {
            let delta = row.1 - row.0
            let length = simd_length(delta)
            let count = max(4, Int(length / 170))
            for index in 0...count {
                let t = Float(index) / Float(count)
                var p = simd_mix(row.0, row.1, SIMD2<Float>(repeating: t))
                p.x += sin(Float(index * 17 + rowIndex * 11)) * 15
                p.y += cos(Float(index * 13 + rowIndex * 7)) * 12
                if Stage2TerrainProfile.normal(east: p.x, north: p.y).y < 0.90 { continue }
                let tree = makeHedgeTree(selector: rowIndex * 31 + index)
                tree.position = [p.x, Stage2TerrainProfile.heightMeters(east: p.x, north: p.y), p.y]
                group.addChild(tree)
            }
        }

        root.addChild(group)
    }

    private static func makeHedgeTree(selector: Int) -> Entity {
        let root = Entity()
        let height: Float = 8 + hash(selector + 4) * 7

        let trunk = ModelEntity(
            mesh: .generateCylinder(height: height * 0.34, radius: 0.32),
            materials: [matte(
                UIColor(red: 0.15, green: 0.105, blue: 0.065, alpha: 1),
                roughness: 1.0,
                specular: 0.04
            )]
        )
        trunk.position = [0, height * 0.17, 0]
        root.addChild(trunk)

        let foliageColors: [UIColor] = [
            UIColor(red: 0.075, green: 0.165, blue: 0.065, alpha: 1),
            UIColor(red: 0.095, green: 0.185, blue: 0.075, alpha: 1),
            UIColor(red: 0.065, green: 0.145, blue: 0.060, alpha: 1)
        ]
        let crown = ModelEntity(
            mesh: .generateSphere(radius: height * 0.25),
            materials: [matte(foliageColors[abs(selector) % foliageColors.count], roughness: 1.0, specular: 0.04)]
        )
        crown.position = [0, height * 0.65, 0]
        crown.scale = [1.05, 1.25, 0.95]
        root.addChild(crown)
        return root
    }

    // MARK: - Civil traffic

    private static var trafficRoutes: [TrafficRoute] {
        [
            .init(points: [[-5_500, -1_200], [-2_500, -400], [1_300, -650], [5_500, 500], [8_500, 2_400]], speedMetersPerSecond: 20, phaseSeconds: 2, truck: false),
            .init(points: [[-8_000, 6_000], [-5_800, 4_900], [-4_200, 2_300], [-2_900, 300]], speedMetersPerSecond: 17, phaseSeconds: 19, truck: true),
            .init(points: [[4_600, -3_800], [3_200, -1_800], [2_100, 400], [1_900, 2_600]], speedMetersPerSecond: 18, phaseSeconds: 34, truck: false),
            .init(points: [[-7_200, 8_200], [-4_500, 7_500], [-1_800, 7_900], [1_200, 7_200]], speedMetersPerSecond: 21, phaseSeconds: 48, truck: false),
            .init(points: [[6_500, 6_400], [5_400, 5_000], [4_900, 3_600], [5_800, 2_500]], speedMetersPerSecond: 16, phaseSeconds: 11, truck: true),
            .init(points: [[1_800, 4_200], [3_000, 2_800], [4_500, 1_900], [7_000, 1_500]], speedMetersPerSecond: 19, phaseSeconds: 27, truck: false)
        ]
    }

    private static func addTraffic(to root: Entity) {
        let colors: [UIColor] = [
            UIColor(red: 0.18, green: 0.20, blue: 0.21, alpha: 1),
            UIColor(red: 0.42, green: 0.42, blue: 0.39, alpha: 1),
            UIColor(red: 0.24, green: 0.29, blue: 0.32, alpha: 1),
            UIColor(red: 0.32, green: 0.22, blue: 0.18, alpha: 1)
        ]

        for (index, route) in trafficRoutes.enumerated() {
            let vehicle = Entity()
            vehicle.name = vehiclePrefix + String(index)

            let bodySize: SIMD3<Float> = route.truck ? [2.4, 2.2, 6.8] : [1.9, 1.35, 4.4]
            let body = ModelEntity(
                mesh: .generateBox(size: bodySize, cornerRadius: 0.3),
                materials: [matte(colors[index % colors.count], roughness: 0.86, specular: 0.16)]
            )
            body.position = [0, route.truck ? 0.8 : 0.45, 0]
            vehicle.addChild(body)

            let glass = ModelEntity(
                mesh: .generateBox(size: route.truck ? [2.0, 0.75, 1.9] : [1.65, 0.58, 1.7], cornerRadius: 0.25),
                materials: [matte(
                    UIColor(red: 0.08, green: 0.105, blue: 0.12, alpha: 1),
                    roughness: 0.48,
                    specular: 0.25
                )]
            )
            glass.position = [0, route.truck ? 1.65 : 1.05, route.truck ? -1.8 : -0.25]
            vehicle.addChild(glass)
            root.addChild(vehicle)
        }
    }

    private static func sample(route: TrafficRoute, elapsed: Float) -> (position: SIMD2<Float>, yaw: Float) {
        guard route.points.count >= 2 else { return (route.points.first ?? .zero, 0) }

        var segmentLengths: [Float] = []
        var total: Float = 0
        for index in 0..<(route.points.count - 1) {
            let length = simd_length(route.points[index + 1] - route.points[index])
            segmentLengths.append(length)
            total += length
        }
        guard total > 1 else { return (route.points[0], 0) }

        var distance = fmod(max(0, elapsed + route.phaseSeconds) * route.speedMetersPerSecond, total * 2)
        let reversing = distance > total
        if reversing { distance = total * 2 - distance }

        var remaining = distance
        for index in segmentLengths.indices {
            let length = segmentLengths[index]
            if remaining <= length {
                let t = remaining / max(length, 0.001)
                let a = reversing ? route.points[index + 1] : route.points[index]
                let b = reversing ? route.points[index] : route.points[index + 1]
                let position = simd_mix(a, b, SIMD2<Float>(repeating: reversing ? 1 - t : t))
                let d = b - a
                let yaw = atan2(d.x, d.y)
                return (position, yaw)
            }
            remaining -= length
        }

        return (route.points.last ?? .zero, 0)
    }

    private static func matte(_ color: UIColor, roughness: Float, specular: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: 0.0)
        material.specular = .init(floatLiteral: specular)
        return material
    }

    private static func hash(_ seed: Int) -> Float {
        var value = UInt64(bitPattern: Int64(seed &* 1_103_515_245 &+ 12_345))
        value ^= value >> 17
        value &*= 0xed5ad4bb
        value ^= value >> 11
        return Float(value & 0x00FF_FFFF) / Float(0x0100_0000)
    }
}
