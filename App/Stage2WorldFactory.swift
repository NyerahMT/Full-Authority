import RealityKit
import UIKit
import simd

@MainActor
enum Stage2WorldFactory {
    private struct TerrainMeshes {
        let ground: MeshResource
        let rock: MeshResource?
    }

    static func make() -> Entity {
        let root = Entity()
        root.name = "FA.world.stage2"

        addTerrain(to: root)
        addAirbase(to: root)
        addRoads(to: root)
        addTown(to: root)
        addVegetation(to: root)

        return root
    }

    // MARK: - Terrain

    private static func addTerrain(to root: Entity) {
        // The FDM and renderer continue to share Stage2TerrainProfile. This is a
        // denser render of the exact JSBSim contact surface, not a decorative hill layer.
        let tileSize: Float = 6_000
        let resolution = 81
        let texture = try? TextureResource.load(named: "terrain_albedo")

        for tileX in -4..<4 {
            for tileZ in -4..<4 {
                let centerX = (Float(tileX) + 0.5) * tileSize
                let centerZ = (Float(tileZ) + 0.5) * tileSize
                guard let meshes = makeTerrainTile(
                    centerX: centerX,
                    centerZ: centerZ,
                    size: tileSize,
                    resolution: resolution,
                    mirrorU: tileX.isMultiple(of: 2),
                    mirrorV: tileZ.isMultiple(of: 2)
                ) else { continue }

                let selector = abs(tileX * 19 + tileZ * 11)
                let ground = ModelEntity(
                    mesh: meshes.ground,
                    materials: [terrainMaterial(texture: texture, selector: selector)]
                )
                ground.position = [centerX, 0, centerZ]
                root.addChild(ground)

                if let rockMesh = meshes.rock {
                    let rock = ModelEntity(
                        mesh: rockMesh,
                        materials: [rockMaterial(selector: selector)]
                    )
                    rock.position = [centerX, 0.045, centerZ]
                    root.addChild(rock)
                }
            }
        }
    }

    private static func terrainMaterial(texture: TextureResource?, selector: Int) -> PhysicallyBasedMaterial {
        let tints: [UIColor] = [
            UIColor(red: 0.48, green: 0.56, blue: 0.34, alpha: 1),
            UIColor(red: 0.57, green: 0.57, blue: 0.35, alpha: 1),
            UIColor(red: 0.39, green: 0.50, blue: 0.30, alpha: 1),
            UIColor(red: 0.59, green: 0.52, blue: 0.31, alpha: 1),
            UIColor(red: 0.43, green: 0.47, blue: 0.28, alpha: 1),
            UIColor(red: 0.53, green: 0.60, blue: 0.39, alpha: 1)
        ]

        var material = PhysicallyBasedMaterial()
        if let texture {
            material.baseColor = PhysicallyBasedMaterial.BaseColor(
                tint: tints[selector % tints.count],
                texture: MaterialParameters.Texture(texture)
            )
        } else {
            material.baseColor = PhysicallyBasedMaterial.BaseColor(
                tint: UIColor(red: 0.24, green: 0.32, blue: 0.16, alpha: 1)
            )
        }
        material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.90)
        material.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: 0.0)
        return material
    }

    private static func rockMaterial(selector: Int) -> PhysicallyBasedMaterial {
        let rocks: [UIColor] = [
            UIColor(red: 0.24, green: 0.235, blue: 0.21, alpha: 1),
            UIColor(red: 0.31, green: 0.285, blue: 0.235, alpha: 1),
            UIColor(red: 0.225, green: 0.25, blue: 0.225, alpha: 1),
            UIColor(red: 0.36, green: 0.325, blue: 0.255, alpha: 1)
        ]
        var material = PhysicallyBasedMaterial()
        material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: rocks[selector % rocks.count])
        material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.99)
        material.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: 0.0)
        return material
    }

    private static func makeTerrainTile(
        centerX: Float,
        centerZ: Float,
        size: Float,
        resolution: Int,
        mirrorU: Bool,
        mirrorV: Bool
    ) -> TerrainMeshes? {
        guard resolution >= 3 else { return nil }

        let vertexCount = resolution * resolution
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var texcoords: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        var rockIndices: [UInt32] = []
        positions.reserveCapacity(vertexCount)
        normals.reserveCapacity(vertexCount)
        texcoords.reserveCapacity(vertexCount)
        indices.reserveCapacity((resolution - 1) * (resolution - 1) * 6)
        rockIndices.reserveCapacity(indices.capacity / 5)

        let half = size * 0.5
        let step = size / Float(resolution - 1)

        for zIndex in 0..<resolution {
            for xIndex in 0..<resolution {
                let localX = -half + Float(xIndex) * step
                let localZ = -half + Float(zIndex) * step
                let globalX = centerX + localX
                let globalZ = centerZ + localZ
                let height = Stage2TerrainProfile.heightMeters(east: globalX, north: globalZ)
                positions.append([localX, height, localZ])
                normals.append(Stage2TerrainProfile.normal(east: globalX, north: globalZ))

                var u = Float(xIndex) / Float(resolution - 1)
                var v = Float(zIndex) / Float(resolution - 1)
                if mirrorU { u = 1 - u }
                if mirrorV { v = 1 - v }
                texcoords.append([u, v])
            }
        }

        for zIndex in 0..<(resolution - 1) {
            for xIndex in 0..<(resolution - 1) {
                let i0 = UInt32(zIndex * resolution + xIndex)
                let i1 = UInt32(zIndex * resolution + xIndex + 1)
                let i2 = UInt32((zIndex + 1) * resolution + xIndex)
                let i3 = UInt32((zIndex + 1) * resolution + xIndex + 1)
                let cell = [i0, i2, i1, i1, i2, i3]
                indices.append(contentsOf: cell)

                let centerIndex = zIndex * resolution + xIndex
                let n = normals[centerIndex]
                let h = positions[centerIndex].y
                let worldX = centerX + positions[centerIndex].x
                let worldZ = centerZ + positions[centerIndex].z
                let breakup = sin(worldX / 610.0 + worldZ / 930.0) * cos(worldZ / 470.0)
                if n.y < 0.955 || h > 115 + breakup * 32 {
                    rockIndices.append(contentsOf: cell)
                }
            }
        }

        var descriptor = MeshDescriptor(name: "Stage2 Terrain Ground")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(texcoords)
        descriptor.primitives = .triangles(indices)
        guard let groundMesh = try? MeshResource.generate(from: [descriptor]) else { return nil }

        var rockMesh: MeshResource?
        if !rockIndices.isEmpty {
            var rockPositions = positions
            for index in rockPositions.indices {
                rockPositions[index].y += 0.035
            }
            var rockDescriptor = MeshDescriptor(name: "Stage2 Terrain Rock")
            rockDescriptor.positions = MeshBuffers.Positions(rockPositions)
            rockDescriptor.normals = MeshBuffers.Normals(normals)
            rockDescriptor.primitives = .triangles(rockIndices)
            rockMesh = try? MeshResource.generate(from: [rockDescriptor])
        }

        return TerrainMeshes(ground: groundMesh, rock: rockMesh)
    }

    // MARK: - Airbase

    private static func addAirbase(to root: Entity) {
        let asphalt = UIColor(red: 0.055, green: 0.060, blue: 0.064, alpha: 1)
        let concrete = UIColor(red: 0.39, green: 0.40, blue: 0.39, alpha: 1)
        let marking = UIColor(white: 0.91, alpha: 1)
        let taxiYellow = UIColor(red: 0.88, green: 0.67, blue: 0.07, alpha: 1)

        let runway = block(size: [64, 0.10, 4_800], color: asphalt, roughness: 0.96, cornerRadius: 0.8)
        runway.position = [0, 0.055, 2_000]
        root.addChild(runway)

        for z in stride(from: -260, through: 4_260, by: 120) {
            let dash = block(size: [1.3, 0.024, 38], color: marking, roughness: 0.92, cornerRadius: 0.03)
            dash.position = [0, 0.12, Float(z)]
            root.addChild(dash)
        }
        for x: Float in [-30.5, 30.5] {
            let edge = block(size: [0.7, 0.022, 4_720], color: marking, roughness: 0.92, cornerRadius: 0.03)
            edge.position = [x, 0.12, 2_000]
            root.addChild(edge)
        }
        for endZ: Float in [-360, 4_360] {
            for stripe in -3...3 {
                let threshold = block(size: [5.0, 0.025, 28], color: marking, roughness: 0.92, cornerRadius: 0)
                threshold.position = [Float(stripe) * 7.2, 0.125, endZ]
                root.addChild(threshold)
            }
        }

        for z in stride(from: -350, through: 4_350, by: 120) {
            addRunwayLight(to: root, position: [-33.5, 0.24, Float(z)], color: .white)
            addRunwayLight(to: root, position: [33.5, 0.24, Float(z)], color: .white)
        }
        for index in 0..<8 {
            addRunwayLight(to: root, position: [0, 0.24, -450 - Float(index) * 55], color: .white)
        }

        // Subtle rubber, seams and repaired slabs keep the runway from reading
        // like one giant perfect gray rectangle at low altitude.
        let rubber = UIColor(red: 0.026, green: 0.028, blue: 0.030, alpha: 1)
        for z: Float in [-250, -120, 3_980, 4_110] {
            for x: Float in [-5.4, -2.0, 2.0, 5.4] {
                let skid = block(size: [1.4, 0.012, 84], color: rubber, roughness: 0.99, cornerRadius: 0.05)
                skid.position = [x, 0.126, z]
                root.addChild(skid)
            }
        }
        let seam = UIColor(red: 0.075, green: 0.078, blue: 0.080, alpha: 1)
        for z in stride(from: -300, through: 4_300, by: 240) {
            let joint = block(size: [62, 0.010, 0.18], color: seam, roughness: 0.99, cornerRadius: 0)
            joint.position = [0, 0.126, Float(z)]
            root.addChild(joint)
        }

        let parallelTaxiway = block(size: [30, 0.07, 3_050], color: asphalt, roughness: 0.96, cornerRadius: 1.5)
        parallelTaxiway.position = [320, 0.045, 1_650]
        root.addChild(parallelTaxiway)

        let taxiCenter = block(size: [0.45, 0.025, 3_000], color: taxiYellow, roughness: 0.94, cornerRadius: 0.03)
        taxiCenter.position = [320, 0.10, 1_650]
        root.addChild(taxiCenter)

        for connectorZ: Float in [250, 1_100, 2_100, 3_050] {
            let connector = block(size: [320, 0.07, 24], color: asphalt, roughness: 0.96, cornerRadius: 1.5)
            connector.position = [160, 0.045, connectorZ]
            root.addChild(connector)
        }

        let apron = block(size: [430, 0.075, 360], color: concrete, roughness: 0.96, cornerRadius: 2)
        apron.position = [520, 0.045, 720]
        root.addChild(apron)

        for row in 0..<2 {
            for column in 0..<4 {
                addHangar(to: root, position: [390 + Float(column) * 94, 0, 610 + Float(row) * 135])
            }
        }

        let towerShaft = block(
            size: [18, 48, 18],
            color: UIColor(red: 0.44, green: 0.45, blue: 0.43, alpha: 1),
            roughness: 0.88,
            cornerRadius: 0.8
        )
        towerShaft.position = [715, 24, 900]
        root.addChild(towerShaft)

        let towerCab = block(
            size: [31, 10, 31],
            color: UIColor(red: 0.055, green: 0.105, blue: 0.13, alpha: 1),
            roughness: 0.35,
            cornerRadius: 1.5
        )
        towerCab.position = [715, 52, 900]
        root.addChild(towerCab)
    }

    private static func addRunwayLight(to root: Entity, position: SIMD3<Float>, color: UIColor) {
        let light = ModelEntity(
            mesh: .generateSphere(radius: 0.11),
            materials: [SimpleMaterial(color: color.withAlphaComponent(0.9), roughness: 0.35, isMetallic: false)]
        )
        light.position = position
        root.addChild(light)
    }

    private static func addHangar(to root: Entity, position: SIMD3<Float>) {
        let body = block(
            size: [70, 18, 55],
            color: UIColor(red: 0.31, green: 0.32, blue: 0.31, alpha: 1),
            roughness: 0.86,
            cornerRadius: 1.4
        )
        body.position = [position.x, 9, position.z]
        root.addChild(body)

        let door = block(
            size: [50, 12, 0.8],
            color: UIColor(red: 0.10, green: 0.11, blue: 0.11, alpha: 1),
            roughness: 0.68,
            cornerRadius: 0.3
        )
        door.position = [position.x, 6.1, position.z - 27.7]
        root.addChild(door)
    }

    // MARK: - Surface details

    private static func addRoads(to root: Entity) {
        let roadColor = UIColor(red: 0.105, green: 0.108, blue: 0.105, alpha: 1)
        let roads: [[SIMD2<Float>]] = [
            [[-5_500, -1_200], [-2_500, -400], [1_300, -650], [5_500, 500], [8_500, 2_400]],
            [[-3_500, 5_500], [-1_400, 3_800], [-900, 1_200], [-1_100, -2_500]],
            [[1_800, 4_200], [3_000, 2_800], [4_500, 1_900], [7_000, 1_500]],
            [[2_100, 7_000], [2_400, 4_800], [3_500, 3_000], [5_800, 2_500]],
            [[-8_000, 6_000], [-5_800, 4_900], [-4_200, 2_300], [-2_900, 300]],
            [[-7_200, 8_200], [-4_500, 7_500], [-1_800, 7_900], [1_200, 7_200]],
            [[4_600, -3_800], [3_200, -1_800], [2_100, 400], [1_900, 2_600]],
            [[6_500, 6_400], [5_400, 5_000], [4_900, 3_600], [5_800, 2_500]]
        ]

        for road in roads {
            for index in 0..<(road.count - 1) {
                if let ribbon = makeConformingRibbon(from: road[index], to: road[index + 1], width: 15.5, color: roadColor) {
                    root.addChild(ribbon)
                }
            }
        }
    }

    private static func makeConformingRibbon(
        from start: SIMD2<Float>,
        to end: SIMD2<Float>,
        width: Float,
        color: UIColor
    ) -> ModelEntity? {
        let delta = end - start
        let length = simd_length(delta)
        guard length > 1 else { return nil }

        let forward = delta / length
        let side = SIMD2<Float>(forward.y, -forward.x)
        let segments = max(3, Int(ceil(length / 180)))
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity((segments + 1) * 2)
        normals.reserveCapacity((segments + 1) * 2)

        for index in 0...segments {
            let t = Float(index) / Float(segments)
            let center = simd_mix(start, end, SIMD2<Float>(repeating: t))
            let left = center + side * (width * 0.5)
            let right = center - side * (width * 0.5)
            let leftHeight = Stage2TerrainProfile.heightMeters(east: left.x, north: left.y) + 0.10
            let rightHeight = Stage2TerrainProfile.heightMeters(east: right.x, north: right.y) + 0.10
            positions.append([left.x, leftHeight, left.y])
            positions.append([right.x, rightHeight, right.y])
            normals.append(Stage2TerrainProfile.normal(east: left.x, north: left.y))
            normals.append(Stage2TerrainProfile.normal(east: right.x, north: right.y))
        }

        for index in 0..<segments {
            let i0 = UInt32(index * 2)
            let i1 = i0 + 1
            let i2 = i0 + 2
            let i3 = i0 + 3
            indices.append(contentsOf: [i0, i2, i1, i1, i2, i3])
        }

        var descriptor = MeshDescriptor(name: "Conforming road")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }
        return ModelEntity(
            mesh: mesh,
            materials: [SimpleMaterial(color: color, roughness: 0.98, isMetallic: false)]
        )
    }

    private static func addTown(to root: Entity) {
        let wallColors: [UIColor] = [
            UIColor(red: 0.42, green: 0.40, blue: 0.35, alpha: 1),
            UIColor(red: 0.32, green: 0.34, blue: 0.35, alpha: 1),
            UIColor(red: 0.47, green: 0.44, blue: 0.38, alpha: 1),
            UIColor(red: 0.37, green: 0.36, blue: 0.33, alpha: 1)
        ]

        for row in 0..<8 {
            for column in 0..<10 {
                let selector = row * 10 + column
                let height = Float(16 + (selector * 13) % 52)
                let width = Float(32 + (selector * 7) % 30)
                let depth = Float(30 + (selector * 11) % 28)
                let x = 2_650 + Float(column) * 108
                let z = 2_900 + Float(row) * 112
                let terrain = Stage2TerrainProfile.heightMeters(east: x, north: z)

                let building = block(
                    size: [width, height, depth],
                    color: wallColors[selector % wallColors.count],
                    roughness: 0.88,
                    cornerRadius: 0.7
                )
                building.position = [x, terrain + height * 0.5, z]
                root.addChild(building)

                let roof = block(
                    size: [width + 2, 1.0, depth + 2],
                    color: UIColor(red: 0.13, green: 0.14, blue: 0.14, alpha: 1),
                    roughness: 0.80,
                    cornerRadius: 0.2
                )
                roof.position = [x, terrain + height + 0.5, z]
                root.addChild(roof)
            }
        }
    }

    // MARK: - Vegetation

    private static func addVegetation(to root: Entity) {
        guard let coniferMesh = makeConiferMesh() else { return }
        let trunk = SimpleMaterial(
            color: UIColor(red: 0.15, green: 0.09, blue: 0.045, alpha: 1),
            roughness: 0.98,
            isMetallic: false
        )
        let foliageColors: [UIColor] = [
            UIColor(red: 0.045, green: 0.145, blue: 0.040, alpha: 1),
            UIColor(red: 0.070, green: 0.185, blue: 0.050, alpha: 1),
            UIColor(red: 0.090, green: 0.205, blue: 0.055, alpha: 1)
        ]

        for belt in 0..<28 {
            let baseX = Float(-9_200 + belt * 690)
            let baseZ = Float(-1_600 + (belt % 7) * 1_280)
            for treeIndex in 0..<16 {
                let x = baseX + Float(treeIndex) * 64 + sin(Float(belt + treeIndex) * 1.91) * 42
                let z = baseZ + sin(Float(treeIndex) * 0.82 + Float(belt)) * 230
                let terrain = Stage2TerrainProfile.heightMeters(east: x, north: z)
                let height = Float(11 + ((belt * 17 + treeIndex * 7) % 15))
                let foliage = SimpleMaterial(
                    color: foliageColors[(belt + treeIndex) % foliageColors.count],
                    roughness: 0.98,
                    isMetallic: false
                )
                let tree = ModelEntity(mesh: coniferMesh, materials: [trunk, foliage])
                tree.position = [x, terrain, z]
                tree.scale = [height * 0.38, height, height * 0.38]
                tree.orientation = simd_quatf(
                    angle: Float((belt * 37 + treeIndex * 19) % 360) * .pi / 180,
                    axis: [0, 1, 0]
                )
                root.addChild(tree)
            }
        }
    }

    private static func makeConiferMesh() -> MeshResource? {
        var trunkPositions: [SIMD3<Float>] = []
        var trunkNormals: [SIMD3<Float>] = []
        var trunkIndices: [UInt32] = []
        let sides = 7
        let trunkRadius: Float = 0.085
        let trunkTop: Float = 0.36

        for i in 0..<sides {
            let angle = Float(i) / Float(sides) * 2 * .pi
            let x = cos(angle) * trunkRadius
            let z = sin(angle) * trunkRadius
            let normal = simd_normalize(SIMD3<Float>(x, 0, z))
            trunkPositions.append([x, 0, z])
            trunkPositions.append([x, trunkTop, z])
            trunkNormals.append(normal)
            trunkNormals.append(normal)
        }
        for i in 0..<sides {
            let next = (i + 1) % sides
            let b0 = UInt32(i * 2)
            let t0 = b0 + 1
            let b1 = UInt32(next * 2)
            let t1 = b1 + 1
            trunkIndices.append(contentsOf: [b0, t0, b1, b1, t0, t1])
        }

        var foliagePositions: [SIMD3<Float>] = []
        var foliageNormals: [SIMD3<Float>] = []
        var foliageIndices: [UInt32] = []
        let tiers: [(baseY: Float, topY: Float, radius: Float)] = [
            (0.20, 0.63, 0.49),
            (0.43, 0.82, 0.39),
            (0.64, 1.00, 0.28)
        ]
        let canopySides = 10

        for tier in tiers {
            let baseIndex = UInt32(foliagePositions.count)
            for i in 0..<canopySides {
                let angle = Float(i) / Float(canopySides) * 2 * .pi
                let radial = SIMD3<Float>(cos(angle), 0.34, sin(angle))
                foliagePositions.append([cos(angle) * tier.radius, tier.baseY, sin(angle) * tier.radius])
                foliageNormals.append(simd_normalize(radial))
            }
            let apex = UInt32(foliagePositions.count)
            foliagePositions.append([0, tier.topY, 0])
            foliageNormals.append([0, 1, 0])
            for i in 0..<canopySides {
                let next = (i + 1) % canopySides
                foliageIndices.append(contentsOf: [baseIndex + UInt32(i), apex, baseIndex + UInt32(next)])
            }
        }

        var trunkDescriptor = MeshDescriptor(name: "Conifer trunk")
        trunkDescriptor.positions = MeshBuffers.Positions(trunkPositions)
        trunkDescriptor.normals = MeshBuffers.Normals(trunkNormals)
        trunkDescriptor.primitives = .triangles(trunkIndices)

        var foliageDescriptor = MeshDescriptor(name: "Conifer foliage")
        foliageDescriptor.positions = MeshBuffers.Positions(foliagePositions)
        foliageDescriptor.normals = MeshBuffers.Normals(foliageNormals)
        foliageDescriptor.primitives = .triangles(foliageIndices)

        return try? MeshResource.generate(from: [trunkDescriptor, foliageDescriptor])
    }

    // MARK: - Helpers

    private static func block(
        size: SIMD3<Float>,
        color: UIColor,
        roughness: Float,
        cornerRadius: Float
    ) -> ModelEntity {
        ModelEntity(
            mesh: .generateBox(size: size, cornerRadius: cornerRadius),
            materials: [SimpleMaterial(color: color, roughness: MaterialScalarParameter.float(roughness), isMetallic: false)]
        )
    }
}