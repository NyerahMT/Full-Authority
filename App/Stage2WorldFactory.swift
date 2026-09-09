import Metal
import RealityKit
import UIKit
import simd

@MainActor
enum Stage2WorldFactory {
    private struct TerrainMeshes {
        let ground: MeshResource
        let rock: MeshResource?
    }

    // Stage 016 sourced PBR surface pass. These maps are CC0 Poly Haven
    // assets imported at build time; the game never depends on a live API.
    private struct WorldTextureSet {
        let baseColor: TextureResource?
        let roughness: TextureResource?
        let normal: TextureResource?
    }

    static func make() -> Entity {
        let root = Entity()
        root.name = "FA.world.stage2"

        addTerrain(to: root)
        addCloudscape(to: root)
        addAirbase(to: root)
        addRoads(to: root)
        addStage019Environment(to: root)

        return root
    }

    // MARK: - Atmosphere / cloudscape

    /// Stage 017 uses CC0 cloud alpha art as a mobile-friendly first layer. The
    /// placement strategy follows the same visual goals as published volumetric
    /// cloud work (coverage, depth, scale and lighting separation) without paying
    /// the ray-marching cost before the rest of the scene warrants it.
    private static func addCloudscape(to root: Entity) {
        let names = ["cloud_alpha_03", "cloud_alpha_05", "cloud_alpha_08"]
        let textures = names.compactMap(loadCloudTexture)
        guard !textures.isEmpty else { return }

        let cloudRoot = Entity()
        cloudRoot.name = "FA.world.cloudscape"

        // Broad overhead/near-field puffs. Two offset cards per cloud give a little
        // parallax and stop the layer from reading like a single painted ceiling.
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

        // Distant vertical banks break up the horizon and make the atmosphere read
        // in kilometres, not as a flat blue background.
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

    // MARK: - Terrain

    private static func addTerrain(to root: Entity) {
        // The FDM and renderer continue to share Stage2TerrainProfile. This is a
        // denser render of the exact JSBSim contact surface, not a decorative hill layer.
        let tileSize: Float = 6_000
        let resolution = 81
        let terrainTextures = worldTextureSet(named: "terrain_grass")

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
                    materials: [terrainMaterial(textures: terrainTextures, selector: selector)]
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

    private static func worldTextureSet(named stem: String) -> WorldTextureSet {
        WorldTextureSet(
            baseColor: loadWorldTexture("\(stem)_diff"),
            roughness: loadWorldTexture("\(stem)_rough"),
            normal: loadWorldTexture("\(stem)_nor")
        )
    }

    private static func loadWorldTexture(_ name: String) -> TextureResource? {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "jpg",
            subdirectory: "JSBSim/visuals/world"
        ) else { return nil }
        return try? TextureResource.load(contentsOf: url, withName: name)
    }

    private static func repeatedTexture(
        _ resource: TextureResource,
        anisotropy: Int = 8
    ) -> MaterialParameters.Texture {
        var texture = MaterialParameters.Texture(resource)
        texture.sampler.modify { descriptor in
            descriptor.sAddressMode = .repeat
            descriptor.tAddressMode = .repeat
            descriptor.mipFilter = .linear
            descriptor.minFilter = .linear
            descriptor.magFilter = .linear
            descriptor.maxAnisotropy = anisotropy
        }
        return texture
    }

    private static func terrainMaterial(
        textures: WorldTextureSet,
        selector: Int
    ) -> PhysicallyBasedMaterial {
        let tints: [UIColor] = [
            UIColor(red: 0.72, green: 0.78, blue: 0.58, alpha: 1),
            UIColor(red: 0.82, green: 0.78, blue: 0.54, alpha: 1),
            UIColor(red: 0.64, green: 0.73, blue: 0.51, alpha: 1),
            UIColor(red: 0.82, green: 0.69, blue: 0.47, alpha: 1),
            UIColor(red: 0.68, green: 0.68, blue: 0.47, alpha: 1),
            UIColor(red: 0.76, green: 0.79, blue: 0.57, alpha: 1)
        ]

        var material = PhysicallyBasedMaterial()
        if let base = textures.baseColor {
            material.baseColor = PhysicallyBasedMaterial.BaseColor(
                tint: tints[selector % tints.count],
                texture: repeatedTexture(base)
            )
        } else {
            material.baseColor = PhysicallyBasedMaterial.BaseColor(
                tint: UIColor(red: 0.30, green: 0.38, blue: 0.19, alpha: 1)
            )
        }
        if let rough = textures.roughness {
            material.roughness = PhysicallyBasedMaterial.Roughness(
                scale: 0.94,
                texture: repeatedTexture(rough)
            )
        } else {
            material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.90)
        }
        material.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: 0.0)
        material.specular = PhysicallyBasedMaterial.Specular(floatLiteral: 0.32)
        return material
    }

    private static func pbrSurfaceMaterial(
        textures: WorldTextureSet,
        tint: UIColor,
        roughnessScale: Float
    ) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        if let base = textures.baseColor {
            material.baseColor = .init(tint: tint, texture: repeatedTexture(base))
        } else {
            material.baseColor = .init(tint: tint)
        }
        if let rough = textures.roughness {
            material.roughness = .init(scale: roughnessScale, texture: repeatedTexture(rough))
        } else {
            material.roughness = .init(floatLiteral: roughnessScale)
        }
        if let normal = textures.normal {
            material.normal = PhysicallyBasedMaterial.Normal(
                texture: repeatedTexture(normal)
            )
        }
        material.metallic = .init(floatLiteral: 0.0)
        material.specular = .init(floatLiteral: 0.30)
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

                // World-space UVs keep ground detail at a readable physical scale
                // instead of stretching one texture across a 6 km tile. 24 m is
                // deliberately stylized: visible from low altitude without noisy moire.
                let textureScaleMeters: Float = 24
                var u = globalX / textureScaleMeters
                var v = globalZ / textureScaleMeters
                if mirrorU { u = -u }
                if mirrorV { v = -v }
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


    // MARK: - Ground scale cues

    /// Adds fixed-size, terrain-conforming features that give the pilot a visual
    /// ruler at low altitude. The underlying heightfield remains authoritative;
    /// these are thin surface treatments only and never change collision geometry.
    private static func addGroundScaleCues(to root: Entity) {
        let fieldColors: [UIColor] = [
            UIColor(red: 0.205, green: 0.285, blue: 0.125, alpha: 1),
            UIColor(red: 0.255, green: 0.315, blue: 0.145, alpha: 1),
            UIColor(red: 0.315, green: 0.305, blue: 0.145, alpha: 1),
            UIColor(red: 0.285, green: 0.245, blue: 0.120, alpha: 1),
            UIColor(red: 0.180, green: 0.260, blue: 0.115, alpha: 1),
            UIColor(red: 0.335, green: 0.335, blue: 0.175, alpha: 1)
        ]

        // A deterministic patchwork around the primary operating area. Individual
        // fields are hundreds of metres across: large enough to read from altitude,
        // but small enough to create obvious ground rush below ~500 ft AGL.
        for row in -5...5 {
            for column in -5...5 {
                let selector = (row + 7) * 31 + (column + 7) * 17
                if selector.isMultiple(of: 4) { continue }

                let x = Float(column) * 2_150 + sin(Float(selector) * 0.63) * 390
                let z = Float(row) * 1_850 + cos(Float(selector) * 0.41) * 340

                // Leave the runway/apron complex clean and readable.
                if abs(x) < 1_550 && z > -2_400 && z < 5_900 { continue }

                // Fields belong on readable rolling ground, not cliff faces.
                let centerNormal = Stage2TerrainProfile.normal(east: x, north: z)
                if centerNormal.y < 0.94 { continue }

                let width = Float(520 + (selector * 37) % 620)
                let depth = Float(360 + (selector * 53) % 520)
                let rotationDegrees = Float((selector * 29) % 31) - 15
                let rotation = rotationDegrees * .pi / 180

                if let patch = makeTerrainPatch(
                    center: [x, z],
                    size: [width, depth],
                    rotation: rotation,
                    color: fieldColors[selector % fieldColors.count]
                ) {
                    root.addChild(patch)
                }
            }
        }

        // Narrow farm/service tracks create a second, smaller scale reference than
        // the existing 15.5 m paved roads. They conform to the same terrain profile.
        let trackColor = UIColor(red: 0.245, green: 0.215, blue: 0.145, alpha: 1)
        let tracks: [[SIMD2<Float>]] = [
            [[-10_800, -6_900], [-8_100, -5_500], [-5_300, -5_900], [-2_700, -7_200]],
            [[-9_600, 1_600], [-6_900, 900], [-4_600, 1_500], [-2_300, 3_100]],
            [[-10_200, 7_600], [-7_300, 6_700], [-4_200, 6_900], [-1_900, 8_300]],
            [[1_800, -7_800], [3_500, -5_900], [5_900, -5_200], [8_800, -5_900]],
            [[2_000, -2_700], [4_100, -1_800], [6_300, -2_200], [9_500, -900]],
            [[6_000, 8_700], [4_500, 7_100], [3_500, 5_200], [2_700, 3_900]],
            [[-7_800, -2_200], [-6_000, -500], [-4_400, 900], [-2_800, 1_700]],
            [[8_900, 6_200], [7_400, 4_500], [6_600, 2_500], [7_100, 700]]
        ]

        for track in tracks {
            for index in 0..<(track.count - 1) {
                if let ribbon = makeConformingRibbon(
                    from: track[index],
                    to: track[index + 1],
                    width: 4.2,
                    color: trackColor
                ) {
                    root.addChild(ribbon)
                }
            }
        }
    }

    private static func makeTerrainPatch(
        center: SIMD2<Float>,
        size: SIMD2<Float>,
        rotation: Float,
        color: UIColor
    ) -> ModelEntity? {
        let subdivisions = 5
        let pointsPerSide = subdivisions + 1
        let c = cos(rotation)
        let s = sin(rotation)

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
                let localX = (u - 0.5) * size.x
                let localZ = (v - 0.5) * size.y
                let worldX = center.x + localX * c - localZ * s
                let worldZ = center.y + localX * s + localZ * c
                let height = Stage2TerrainProfile.heightMeters(east: worldX, north: worldZ) + 0.055

                positions.append([worldX, height, worldZ])
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

        var descriptor = MeshDescriptor(name: "Ground scale field")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }

        return ModelEntity(
            mesh: mesh,
            materials: [SimpleMaterial(color: color, roughness: 0.99, isMetallic: false)]
        )
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

        addAirbaseMaterialOverlays(to: root)
    }

    /// Thin PBR overlays preserve the existing runway geometry/markings while
    /// replacing the giant flat-color surfaces with real, tiled material detail.
    private static func addAirbaseMaterialOverlays(to root: Entity) {
        let asphalt = worldTextureSet(named: "runway_asphalt")
        let concrete = worldTextureSet(named: "apron_concrete")

        if let runway = makeTexturedSurface(
            size: [64, 4_800],
            center: [0, 0.108, 2_000],
            tileMeters: 7.5,
            material: pbrSurfaceMaterial(
                textures: asphalt,
                tint: UIColor(red: 0.54, green: 0.55, blue: 0.55, alpha: 1),
                roughnessScale: 0.96
            )
        ) {
            root.addChild(runway)
        }

        if let taxiway = makeTexturedSurface(
            size: [30, 3_050],
            center: [320, 0.082, 1_650],
            tileMeters: 7.0,
            material: pbrSurfaceMaterial(
                textures: asphalt,
                tint: UIColor(red: 0.50, green: 0.51, blue: 0.51, alpha: 1),
                roughnessScale: 0.97
            )
        ) {
            root.addChild(taxiway)
        }

        for connectorZ: Float in [250, 1_100, 2_100, 3_050] {
            if let connector = makeTexturedSurface(
                size: [320, 24],
                center: [160, 0.082, connectorZ],
                tileMeters: 7.0,
                material: pbrSurfaceMaterial(
                    textures: asphalt,
                    tint: UIColor(red: 0.50, green: 0.51, blue: 0.51, alpha: 1),
                    roughnessScale: 0.97
                )
            ) {
                root.addChild(connector)
            }
        }

        if let apron = makeTexturedSurface(
            size: [430, 360],
            center: [520, 0.084, 720],
            tileMeters: 6.5,
            material: pbrSurfaceMaterial(
                textures: concrete,
                tint: UIColor(red: 0.68, green: 0.68, blue: 0.65, alpha: 1),
                roughnessScale: 0.94
            )
        ) {
            root.addChild(apron)
        }
    }

    private static func makeTexturedSurface(
        size: SIMD2<Float>,
        center: SIMD3<Float>,
        tileMeters: Float,
        material: PhysicallyBasedMaterial
    ) -> ModelEntity? {
        let halfX = size.x * 0.5
        let halfZ = size.y * 0.5
        let positions: [SIMD3<Float>] = [
            [-halfX, 0, -halfZ], [halfX, 0, -halfZ],
            [-halfX, 0, halfZ], [halfX, 0, halfZ]
        ]
        let normals = Array(repeating: SIMD3<Float>(0, 1, 0), count: 4)
        let tangents = Array(repeating: SIMD3<Float>(1, 0, 0), count: 4)
        let u = size.x / max(tileMeters, 0.5)
        let v = size.y / max(tileMeters, 0.5)
        let texcoords: [SIMD2<Float>] = [[0, 0], [u, 0], [0, v], [u, v]]
        let indices: [UInt32] = [0, 2, 1, 1, 2, 3]

        var descriptor = MeshDescriptor(name: "Stage 016 PBR surface")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.tangents = MeshBuffers.Tangents(tangents)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(texcoords)
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = center
        return entity
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

    // MARK: - Stage 019 professional environment pass

    private struct CuratedWorldModel {
        let mesh: MeshResource
        let materialNames: [String]
        let minimum: SIMD3<Float>
        let maximum: SIMD3<Float>

        var size: SIMD3<Float> { maximum - minimum }
    }

    /// Stage 019 deliberately leaves the Stage 017 camera, clouds, flight effects,
    /// lighting and F-16 presentation untouched. This layer removes the strongest
    /// procedural tells in the ground scene: regular field grids, one repeated tree,
    /// and box-only settlements. Geometry comes from the audited Kenney CC0 subset;
    /// Poly Haven CC0 normals add micro-surface response to existing PBR surfaces.
    private static func addStage019Environment(to root: Entity) {
        let environment = Entity()
        environment.name = "FA.world.stage019.professional-environment"

        addStage019LandUse(to: environment)
        addStage019Vegetation(to: environment)
        addStage019Settlement(to: environment)
        addStage019AirbaseProps(to: environment)

        root.addChild(environment)
    }

    private static func stage019Hash(_ value: Int) -> Float {
        let x = sin(Float(value) * 12.9898 + 78.233) * 43_758.5453
        return x - floor(x)
    }

    private static func addStage019LandUse(to root: Entity) {
        let grass = worldTextureSet(named: "terrain_grass")
        let palette: [UIColor] = [
            UIColor(red: 0.36, green: 0.43, blue: 0.24, alpha: 1),
            UIColor(red: 0.31, green: 0.39, blue: 0.22, alpha: 1),
            UIColor(red: 0.43, green: 0.40, blue: 0.24, alpha: 1),
            UIColor(red: 0.39, green: 0.34, blue: 0.20, alpha: 1),
            UIColor(red: 0.29, green: 0.40, blue: 0.25, alpha: 1),
            UIColor(red: 0.40, green: 0.44, blue: 0.27, alpha: 1)
        ]

        // Agriculture is intentionally deterministic but no longer arranged on a
        // visible row/column lattice. Adjacent parcels still share a broadly similar
        // scale so the landscape reads as land use rather than camouflage noise.
        for index in 0..<52 {
            let x = -11_000 + stage019Hash(index * 7 + 1) * 22_000
            let z = -8_500 + stage019Hash(index * 7 + 2) * 17_000

            // Protect the runway/airbase footprint and the authored settlement.
            if abs(x) < 1_450 && z > -2_200 && z < 5_700 { continue }
            if x > 2_150 && x < 4_450 && z > 2_300 && z < 4_650 { continue }

            let normal = Stage2TerrainProfile.normal(east: x, north: z)
            if normal.y < 0.955 { continue }

            let width = 460 + stage019Hash(index * 7 + 3) * 920
            let depth = 330 + stage019Hash(index * 7 + 4) * 650
            let rotation = (stage019Hash(index * 7 + 5) - 0.5) * 0.78
            let shear = SIMD2<Float>(
                (stage019Hash(index * 7 + 6) - 0.5) * 0.22,
                (stage019Hash(index * 7 + 7) - 0.5) * 0.18
            )
            let tint = palette[index % palette.count]

            if let patch = makeStage019TerrainPatch(
                center: [x, z],
                size: [width, depth],
                rotation: rotation,
                shear: shear,
                textures: grass,
                tint: tint
            ) {
                patch.name = "FA.world.stage019.field.\(index)"
                root.addChild(patch)
            }
        }
    }

    private static func makeStage019TerrainPatch(
        center: SIMD2<Float>,
        size: SIMD2<Float>,
        rotation: Float,
        shear: SIMD2<Float>,
        textures: WorldTextureSet,
        tint: UIColor
    ) -> ModelEntity? {
        let subdivisions = 5
        let pointsPerSide = subdivisions + 1
        let c = cos(rotation)
        let s = sin(rotation)

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var tangents: [SIMD3<Float>] = []
        var texcoords: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        positions.reserveCapacity(pointsPerSide * pointsPerSide)
        normals.reserveCapacity(pointsPerSide * pointsPerSide)
        tangents.reserveCapacity(pointsPerSide * pointsPerSide)
        texcoords.reserveCapacity(pointsPerSide * pointsPerSide)

        for zIndex in 0...subdivisions {
            let v = Float(zIndex) / Float(subdivisions)
            for xIndex in 0...subdivisions {
                let u = Float(xIndex) / Float(subdivisions)
                let baseX = (u - 0.5) * size.x
                let baseZ = (v - 0.5) * size.y
                let localX = baseX + (v - 0.5) * size.x * shear.x
                let localZ = baseZ + (u - 0.5) * size.y * shear.y
                let worldX = center.x + localX * c - localZ * s
                let worldZ = center.y + localX * s + localZ * c
                let surfaceNormal = Stage2TerrainProfile.normal(east: worldX, north: worldZ)
                let height = Stage2TerrainProfile.heightMeters(east: worldX, north: worldZ) + 0.058

                let baseTangent = SIMD3<Float>(1, 0, 0)
                let projected = baseTangent - surfaceNormal * simd_dot(baseTangent, surfaceNormal)
                let tangent = simd_length_squared(projected) > 0.000001
                    ? simd_normalize(projected)
                    : SIMD3<Float>(0, 0, 1)

                positions.append([worldX, height, worldZ])
                normals.append(surfaceNormal)
                tangents.append(tangent)
                texcoords.append([worldX / 22, worldZ / 22])
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

        var descriptor = MeshDescriptor(name: "Stage 019 terrain parcel")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.tangents = MeshBuffers.Tangents(tangents)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(texcoords)
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }

        var material = PhysicallyBasedMaterial()
        if let base = textures.baseColor {
            material.baseColor = .init(tint: tint, texture: repeatedTexture(base))
        } else {
            material.baseColor = .init(tint: tint)
        }
        if let rough = textures.roughness {
            material.roughness = .init(scale: 0.97, texture: repeatedTexture(rough))
        } else {
            material.roughness = .init(floatLiteral: 0.97)
        }
        if let normal = textures.normal {
            material.normal = .init(texture: repeatedTexture(normal))
        }
        material.metallic = .init(floatLiteral: 0.0)
        material.specular = .init(floatLiteral: 0.22)

        return ModelEntity(mesh: mesh, materials: [material])
    }

    private static func addStage019Vegetation(to root: Entity) {
        let candidates = [
            loadCuratedWorldModel(folder: "kenney_nature", name: "tree_default"),
            loadCuratedWorldModel(folder: "kenney_nature", name: "tree_oak"),
            loadCuratedWorldModel(folder: "kenney_nature", name: "tree_pineDefaultA"),
            loadCuratedWorldModel(folder: "kenney_nature", name: "tree_pineTallA")
        ].compactMap { $0 }
        guard !candidates.isEmpty else { return }

        let clusterCenters: [SIMD2<Float>] = [
            [-9_300, -5_800], [-7_500, -1_900], [-8_500, 3_300], [-7_100, 7_100],
            [-4_900, -6_600], [-4_600, 5_500], [-2_300, 8_000], [2_700, -7_300],
            [5_400, -5_100], [8_300, -2_700], [8_900, 1_800], [7_600, 6_100],
            [4_300, 7_800], [1_400, 8_700], [-9_800, 6_000], [9_800, 7_700]
        ]

        let group = Entity()
        group.name = "FA.world.stage019.vegetation"

        for (clusterIndex, center) in clusterCenters.enumerated() {
            let count = 16 + clusterIndex % 9
            let radius: Float = 520 + Float((clusterIndex * 83) % 420)

            for treeIndex in 0..<count {
                let seed = clusterIndex * 101 + treeIndex * 13
                let radial = sqrt(stage019Hash(seed + 1)) * radius
                let angle = stage019Hash(seed + 2) * 2 * .pi
                let x = center.x + cos(angle) * radial
                let z = center.y + sin(angle) * radial * (0.72 + stage019Hash(seed + 3) * 0.42)

                if abs(x) < 1_100 && z > -2_000 && z < 5_600 { continue }
                let terrainNormal = Stage2TerrainProfile.normal(east: x, north: z)
                if terrainNormal.y < 0.90 { continue }

                let model = candidates[(seed + treeIndex) % candidates.count]
                let targetHeight = 11 + stage019Hash(seed + 4) * 17
                let sourceHeight = max(model.size.y, 0.05)
                let scale = targetHeight / sourceHeight
                let terrain = Stage2TerrainProfile.heightMeters(east: x, north: z)

                let tree = ModelEntity(
                    mesh: model.mesh,
                    materials: stage019NatureMaterials(for: model, selector: seed)
                )
                tree.position = [x, terrain - model.minimum.y * scale, z]
                tree.scale = [scale, scale, scale]
                tree.orientation = simd_quatf(
                    angle: stage019Hash(seed + 5) * 2 * .pi,
                    axis: [0, 1, 0]
                )
                group.addChild(tree)
            }
        }

        root.addChild(group)
    }

    private static func addStage019Settlement(to root: Entity) {
        let candidates = [
            loadCuratedWorldModel(folder: "kenney_industrial", name: "building-h"),
            loadCuratedWorldModel(folder: "kenney_industrial", name: "building-i"),
            loadCuratedWorldModel(folder: "kenney_industrial", name: "building-k"),
            loadCuratedWorldModel(folder: "kenney_industrial", name: "building-s")
        ].compactMap { $0 }
        guard !candidates.isEmpty else { return }

        let group = Entity()
        group.name = "FA.world.stage019.settlement"

        // A loose industrial/service settlement sits beside the existing road
        // network. Buildings align broadly to two street directions, but their
        // spacing and setbacks vary enough to avoid the previous debug-grid read.
        for index in 0..<32 {
            let model = candidates[index % candidates.count]
            let x = 2_380 + stage019Hash(index * 11 + 1) * 1_760
            let z = 2_560 + stage019Hash(index * 11 + 2) * 1_430
            let terrainNormal = Stage2TerrainProfile.normal(east: x, north: z)
            if terrainNormal.y < 0.94 { continue }

            let targetFootprint = 34 + stage019Hash(index * 11 + 3) * 48
            let sourceFootprint = max(max(model.size.x, model.size.z), 0.08)
            let scale = targetFootprint / sourceFootprint
            let terrain = Stage2TerrainProfile.heightMeters(east: x, north: z)
            let quarterTurn = (index % 3 == 0) ? Float.pi / 2 : 0
            let yaw = quarterTurn + (stage019Hash(index * 11 + 4) - 0.5) * 0.16

            let building = ModelEntity(
                mesh: model.mesh,
                materials: stage019IndustrialMaterials(for: model, selector: index)
            )
            building.position = [x, terrain - model.minimum.y * scale, z]
            building.scale = [scale, scale, scale]
            building.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            group.addChild(building)
        }

        root.addChild(group)
    }

    private static func addStage019AirbaseProps(to root: Entity) {
        let group = Entity()
        group.name = "FA.world.stage019.airbase-props"

        if let waterTower = loadCuratedWorldModel(folder: "kenney_industrial", name: "water-tower") {
            let targetHeight: Float = 34
            let scale = targetHeight / max(waterTower.size.y, 0.05)
            let x: Float = 1_020
            let z: Float = 1_080
            let terrain = Stage2TerrainProfile.heightMeters(east: x, north: z)
            let entity = ModelEntity(
                mesh: waterTower.mesh,
                materials: stage019IndustrialMaterials(for: waterTower, selector: 80)
            )
            entity.position = [x, terrain - waterTower.minimum.y * scale, z]
            entity.scale = [scale, scale, scale]
            group.addChild(entity)
        }

        if let tank = loadCuratedWorldModel(folder: "kenney_industrial", name: "detail-tank") {
            for index in 0..<3 {
                let targetWidth: Float = 18 + Float(index) * 2.5
                let scale = targetWidth / max(tank.size.x, 0.05)
                let x: Float = 790 + Float(index) * 31
                let z: Float = 390 + Float(index % 2) * 34
                let terrain = Stage2TerrainProfile.heightMeters(east: x, north: z)
                let entity = ModelEntity(
                    mesh: tank.mesh,
                    materials: stage019IndustrialMaterials(for: tank, selector: 90 + index)
                )
                entity.position = [x, terrain - tank.minimum.y * scale, z]
                entity.scale = [scale, scale, scale]
                entity.orientation = simd_quatf(angle: Float(index) * 0.41, axis: [0, 1, 0])
                group.addChild(entity)
            }
        }

        if let container = loadCuratedWorldModel(folder: "kenney_industrial", name: "shipping-container-a") {
            for index in 0..<8 {
                let targetLength: Float = 11.5
                let sourceLength = max(max(container.size.x, container.size.z), 0.05)
                let scale = targetLength / sourceLength
                let x: Float = 760 + Float(index % 4) * 14.0
                let z: Float = 810 + Float(index / 4) * 10.5
                let terrain = Stage2TerrainProfile.heightMeters(east: x, north: z)
                let entity = ModelEntity(
                    mesh: container.mesh,
                    materials: stage019IndustrialMaterials(for: container, selector: 110 + index)
                )
                entity.position = [x, terrain - container.minimum.y * scale, z]
                entity.scale = [scale, scale, scale]
                entity.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
                group.addChild(entity)
            }
        }

        root.addChild(group)
    }

    private static func stage019NatureMaterials(
        for model: CuratedWorldModel,
        selector: Int
    ) -> [PhysicallyBasedMaterial] {
        let foliage: [UIColor] = [
            UIColor(red: 0.075, green: 0.155, blue: 0.070, alpha: 1),
            UIColor(red: 0.095, green: 0.185, blue: 0.082, alpha: 1),
            UIColor(red: 0.060, green: 0.135, blue: 0.064, alpha: 1),
            UIColor(red: 0.110, green: 0.190, blue: 0.090, alpha: 1)
        ]
        let bark: [UIColor] = [
            UIColor(red: 0.155, green: 0.115, blue: 0.082, alpha: 1),
            UIColor(red: 0.125, green: 0.095, blue: 0.070, alpha: 1),
            UIColor(red: 0.175, green: 0.125, blue: 0.085, alpha: 1)
        ]

        return model.materialNames.enumerated().map { index, name in
            let lowered = name.lowercased()
            let isWood = lowered.contains("wood") || lowered.contains("bark")
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(
                tint: isWood
                    ? bark[(selector + index) % bark.count]
                    : foliage[(selector + index) % foliage.count]
            )
            material.roughness = .init(floatLiteral: isWood ? 0.97 : 0.94)
            material.metallic = .init(floatLiteral: 0.0)
            material.specular = .init(floatLiteral: 0.18)
            return material
        }
    }

    private static func stage019IndustrialMaterials(
        for model: CuratedWorldModel,
        selector: Int
    ) -> [PhysicallyBasedMaterial] {
        let palette: [UIColor] = [
            UIColor(red: 0.36, green: 0.37, blue: 0.35, alpha: 1),
            UIColor(red: 0.43, green: 0.42, blue: 0.37, alpha: 1),
            UIColor(red: 0.31, green: 0.33, blue: 0.33, alpha: 1),
            UIColor(red: 0.48, green: 0.46, blue: 0.40, alpha: 1),
            UIColor(red: 0.33, green: 0.35, blue: 0.31, alpha: 1)
        ]

        return model.materialNames.enumerated().map { index, name in
            let detail = name.lowercased().contains("specular")
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: palette[(selector + index) % palette.count])
            material.roughness = .init(floatLiteral: detail ? 0.77 : 0.91)
            material.metallic = .init(floatLiteral: detail ? 0.04 : 0.0)
            material.specular = .init(floatLiteral: detail ? 0.30 : 0.20)
            return material
        }
    }

    private static func loadCuratedWorldModel(
        folder: String,
        name: String
    ) -> CuratedWorldModel? {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "obj",
            subdirectory: "JSBSim/visuals/world/models/\(folder)"
        ), let source = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        let lines = source.split(whereSeparator: \.isNewline)
        var sourcePositions: [SIMD3<Float>] = []
        var sourceNormals: [SIMD3<Float>] = []

        for line in lines {
            if line.hasPrefix("v ") {
                let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if fields.count >= 4,
                   let x = Float(fields[1]),
                   let y = Float(fields[2]),
                   let z = Float(fields[3]) {
                    sourcePositions.append([x, y, z])
                }
            } else if line.hasPrefix("vn ") {
                let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if fields.count >= 4,
                   let x = Float(fields[1]),
                   let y = Float(fields[2]),
                   let z = Float(fields[3]) {
                    let normal = SIMD3<Float>(x, y, z)
                    sourceNormals.append(
                        simd_length_squared(normal) > 0.000001
                            ? simd_normalize(normal)
                            : SIMD3<Float>(0, 1, 0)
                    )
                }
            }
        }

        guard let firstPosition = sourcePositions.first else { return nil }

        func resolved(_ raw: Int, count: Int) -> Int? {
            if raw > 0 {
                let index = raw - 1
                return index < count ? index : nil
            }
            if raw < 0 {
                let index = count + raw
                return index >= 0 && index < count ? index : nil
            }
            return nil
        }

        func parsedVertex(_ token: Substring) -> (position: SIMD3<Float>, normal: SIMD3<Float>?)? {
            let components = token.split(separator: "/", omittingEmptySubsequences: false)
            guard let rawPosition = components.first.flatMap({ Int($0) }),
                  let positionIndex = resolved(rawPosition, count: sourcePositions.count) else {
                return nil
            }

            var normal: SIMD3<Float>?
            if components.count >= 3,
               !components[2].isEmpty,
               let rawNormal = Int(components[2]),
               let normalIndex = resolved(rawNormal, count: sourceNormals.count) {
                normal = sourceNormals[normalIndex]
            }
            return (sourcePositions[positionIndex], normal)
        }

        var materialOrder: [String] = []
        var currentMaterial = "default"
        var partPositions: [String: [SIMD3<Float>]] = [:]
        var partNormals: [String: [SIMD3<Float>]] = [:]
        var partIndices: [String: [UInt32]] = [:]

        for line in lines {
            if line.hasPrefix("usemtl ") {
                currentMaterial = String(line.dropFirst("usemtl ".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !materialOrder.contains(currentMaterial) {
                    materialOrder.append(currentMaterial)
                }
                continue
            }

            guard line.hasPrefix("f ") else { continue }
            if !materialOrder.contains(currentMaterial) {
                materialOrder.append(currentMaterial)
            }

            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 4 else { continue }
            let face = fields.dropFirst().compactMap(parsedVertex)
            guard face.count == fields.count - 1, face.count >= 3 else { continue }

            for i in 1..<(face.count - 1) {
                let triangle = [face[0], face[i], face[i + 1]]
                let cross = simd_cross(
                    triangle[1].position - triangle[0].position,
                    triangle[2].position - triangle[0].position
                )
                let geometricNormal = simd_length_squared(cross) > 0.000001
                    ? simd_normalize(cross)
                    : SIMD3<Float>(0, 1, 0)

                for vertex in triangle {
                    let nextIndex = UInt32(partPositions[currentMaterial, default: []].count)
                    partIndices[currentMaterial, default: []].append(nextIndex)
                    partPositions[currentMaterial, default: []].append(vertex.position)
                    partNormals[currentMaterial, default: []].append(vertex.normal ?? geometricNormal)
                }
            }
        }

        var descriptors: [MeshDescriptor] = []
        var finalMaterialNames: [String] = []
        for materialName in materialOrder {
            guard let positions = partPositions[materialName],
                  let normals = partNormals[materialName],
                  let indices = partIndices[materialName],
                  !positions.isEmpty,
                  !indices.isEmpty else { continue }

            var descriptor = MeshDescriptor(name: "Stage 019 \(name) \(materialName)")
            descriptor.positions = MeshBuffers.Positions(positions)
            descriptor.normals = MeshBuffers.Normals(normals)
            descriptor.primitives = .triangles(indices)
            descriptors.append(descriptor)
            finalMaterialNames.append(materialName)
        }

        guard !descriptors.isEmpty,
              let mesh = try? MeshResource.generate(from: descriptors) else {
            return nil
        }

        var minimum = firstPosition
        var maximum = firstPosition
        for position in sourcePositions.dropFirst() {
            minimum = SIMD3<Float>(
                Swift.min(minimum.x, position.x),
                Swift.min(minimum.y, position.y),
                Swift.min(minimum.z, position.z)
            )
            maximum = SIMD3<Float>(
                Swift.max(maximum.x, position.x),
                Swift.max(maximum.y, position.y),
                Swift.max(maximum.z, position.z)
            )
        }

        return CuratedWorldModel(
            mesh: mesh,
            materialNames: finalMaterialNames,
            minimum: minimum,
            maximum: maximum
        )
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