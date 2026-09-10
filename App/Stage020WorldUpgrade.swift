import RealityKit
import UIKit
import simd

/// Stage 020 changes the *read* of the world instead of adding another layer of
/// small props. Everything here is deterministic, terrain-conforming, and built
/// from existing CC0 surface assets plus simple shared geometry.
@MainActor
enum Stage020WorldUpgrade {
    static let rootName = "FA.world.stage020"

    private struct TextureSet {
        let baseColor: TextureResource?
        let roughness: TextureResource?
        let normal: TextureResource?
    }

    static func make() -> Entity {
        let root = Entity()
        root.name = rootName

        addWoodlandFloor(to: root)
        addRiverSystem(to: root)
        addAirbaseExpansion(to: root)
        addUtilityScaleCues(to: root)
        addRockOutcrops(to: root)

        return root
    }

    // MARK: - Woodland land cover

    private static func addWoodlandFloor(to root: Entity) {
        let textures = textureSet(named: "terrain_forest")
        let centers: [(SIMD2<Float>, SIMD2<Float>, Float)] = [
            ([-9_250, -5_750], [1_450, 920], 0.28),
            ([-7_450, -1_950], [1_180, 820], -0.18),
            ([-8_420, 3_350], [1_520, 940], 0.12),
            ([-7_050, 7_050], [1_620, 1_020], -0.31),
            ([-4_850, -6_650], [1_250, 830], 0.22),
            ([-4_550, 5_550], [1_500, 900], -0.10),
            ([-2_300, 8_000], [1_360, 850], 0.36),
            ([2_700, -7_300], [1_480, 900], -0.24),
            ([5_350, -5_050], [1_350, 840], 0.15),
            ([8_250, -2_650], [1_500, 960], -0.33),
            ([8_850, 1_850], [1_460, 880], 0.18),
            ([7_550, 6_100], [1_700, 1_050], -0.12),
            ([4_250, 7_800], [1_420, 900], 0.27),
            ([1_400, 8_700], [1_250, 800], -0.18)
        ]

        let group = Entity()
        group.name = "FA.world.stage020.woodland-floor"

        for (index, entry) in centers.enumerated() {
            let (center, size, rotation) = entry
            guard Stage2TerrainProfile.normal(east: center.x, north: center.y).y > 0.88 else { continue }

            // Two offset patches avoid the obvious giant-rectangle silhouette while
            // keeping the geometry cheap and coherent with the tree clusters.
            if let primary = terrainPatch(
                center: center,
                size: size,
                rotation: rotation,
                shear: [0.10, -0.06],
                textures: textures,
                tint: UIColor(red: 0.34, green: 0.36, blue: 0.25, alpha: 1),
                heightOffset: 0.050
            ) {
                primary.name = "FA.world.stage020.forest.primary.\(index)"
                group.addChild(primary)
            }

            let offset = SIMD2<Float>(size.x * 0.20 * cos(rotation), size.y * 0.18 * sin(rotation + 0.8))
            if let secondary = terrainPatch(
                center: center + offset,
                size: size * SIMD2<Float>(0.62, 0.68),
                rotation: rotation + 0.42,
                shear: [-0.08, 0.12],
                textures: textures,
                tint: UIColor(red: 0.29, green: 0.34, blue: 0.23, alpha: 1),
                heightOffset: 0.054
            ) {
                secondary.name = "FA.world.stage020.forest.secondary.\(index)"
                group.addChild(secondary)
            }
        }

        root.addChild(group)
    }

    // MARK: - River / valley landmark

    private static func addRiverSystem(to root: Entity) {
        let path: [SIMD2<Float>] = [
            [9_500, -9_000],
            [8_450, -7_100],
            [7_150, -5_000],
            [6_350, -2_900],
            [5_250, -950],
            [4_550, 1_250],
            [4_750, 3_300],
            [5_500, 5_300],
            [6_650, 7_100],
            [7_150, 9_300],
            [6_650, 11_400]
        ]

        let river = Entity()
        river.name = "FA.world.stage020.river"

        let bankMaterial = earthyBankMaterial()
        let waterMaterial = waterMaterial()

        for index in 0..<(path.count - 1) {
            let width = Float(105 + (index * 29) % 72)
            if let bank = terrainRibbon(
                from: path[index],
                to: path[index + 1],
                width: width + 54,
                material: bankMaterial,
                heightOffset: 0.045
            ) {
                bank.name = "FA.world.stage020.river-bank.\(index)"
                river.addChild(bank)
            }
            if let water = terrainRibbon(
                from: path[index],
                to: path[index + 1],
                width: width,
                material: waterMaterial,
                heightOffset: 0.095
            ) {
                water.name = "FA.world.stage020.river-water.\(index)"
                river.addChild(water)
            }
        }

        // Two simple crossings make the river part of the world rather than a
        // decorative stripe. Their scale is legible from a few thousand feet.
        addBridge(to: river, center: [5_080, 0, -560], yaw: -0.42, length: 172)
        addBridge(to: river, center: [5_210, 0, 4_520], yaw: 0.58, length: 188)

        root.addChild(river)
    }

    private static func addBridge(to root: Entity, center: SIMD3<Float>, yaw: Float, length: Float) {
        let terrain = Stage2TerrainProfile.heightMeters(east: center.x, north: center.z)
        let deck = ModelEntity(
            mesh: .generateBox(size: [length, 0.8, 12], cornerRadius: 0.5),
            materials: [matteMaterial(
                UIColor(red: 0.19, green: 0.20, blue: 0.19, alpha: 1),
                roughness: 0.91,
                specular: 0.18
            )]
        )
        deck.position = [center.x, terrain + 2.1, center.z]
        deck.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        root.addChild(deck)

        for side: Float in [-1, 1] {
            let rail = ModelEntity(
                mesh: .generateBox(size: [length, 1.0, 0.28], cornerRadius: 0.08),
                materials: [matteMaterial(
                    UIColor(red: 0.42, green: 0.43, blue: 0.40, alpha: 1),
                    roughness: 0.78,
                    specular: 0.24
                )]
            )
            rail.position = [center.x, terrain + 2.9, center.z + side * 5.5]
            rail.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            root.addChild(rail)
        }
    }

    // MARK: - Airbase identity

    private static func addAirbaseExpansion(to root: Entity) {
        let group = Entity()
        group.name = "FA.world.stage020.airbase"

        let shoulder = matteMaterial(
            UIColor(red: 0.16, green: 0.17, blue: 0.16, alpha: 1),
            roughness: 0.98,
            specular: 0.12
        )
        let concrete = matteMaterial(
            UIColor(red: 0.38, green: 0.39, blue: 0.37, alpha: 1),
            roughness: 0.93,
            specular: 0.22
        )
        let darkConcrete = matteMaterial(
            UIColor(red: 0.25, green: 0.26, blue: 0.25, alpha: 1),
            roughness: 0.95,
            specular: 0.18
        )

        // Runway shoulders and overruns frame the existing 64 m runway so it reads
        // as a complete airfield surface rather than a floating dark rectangle.
        for x: Float in [-38.5, 38.5] {
            let strip = block(size: [13, 0.045, 4_980], material: shoulder)
            strip.position = [x, 0.025, 2_000]
            group.addChild(strip)
        }
        for z: Float in [-515, 4_515] {
            let overrun = block(size: [90, 0.050, 220], material: darkConcrete)
            overrun.position = [0, 0.028, z]
            group.addChild(overrun)
        }

        // Maintenance / alert ramp east of the main apron.
        let maintenancePad = block(size: [540, 0.060, 420], material: concrete)
        maintenancePad.position = [1_010, 0.034, 1_260]
        group.addChild(maintenancePad)

        for index in 0..<5 {
            addHardenedShelter(
                to: group,
                position: [900 + Float(index % 3) * 145, 0, 1_140 + Float(index / 3) * 190],
                yaw: index.isMultiple(of: 2) ? 0.05 : -0.06
            )
        }

        addFuelFarm(to: group)
        addRunwayDesignation(to: group, digits: [3, 6], centerZ: -245, facingNorth: true)
        addRunwayDesignation(to: group, digits: [1, 8], centerZ: 4_245, facingNorth: false)
        addApproachLighting(to: group, southEnd: true)
        addApproachLighting(to: group, southEnd: false)
        addRadioMast(to: group, position: [1_420, 0, 720])

        root.addChild(group)
    }

    private static func addHardenedShelter(to root: Entity, position: SIMD3<Float>, yaw: Float) {
        let shell = matteMaterial(
            UIColor(red: 0.29, green: 0.31, blue: 0.29, alpha: 1),
            roughness: 0.96,
            specular: 0.17
        )
        let dark = matteMaterial(
            UIColor(red: 0.065, green: 0.070, blue: 0.068, alpha: 1),
            roughness: 0.89,
            specular: 0.18
        )

        let terrain = Stage2TerrainProfile.heightMeters(east: position.x, north: position.z)
        let shelter = Entity()
        shelter.position = [position.x, terrain, position.z]
        shelter.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])

        let body = block(size: [86, 17, 63], material: shell, cornerRadius: 3.5)
        body.position = [0, 8.5, 0]
        shelter.addChild(body)

        let opening = block(size: [58, 12, 1.1], material: dark, cornerRadius: 0.5)
        opening.position = [0, 6.0, -31.8]
        shelter.addChild(opening)

        for side: Float in [-1, 1] {
            let berm = block(size: [18, 8, 78], material: earthyBankMaterial(), cornerRadius: 2.0)
            berm.position = [side * 50, 4.0, 2]
            shelter.addChild(berm)
        }

        root.addChild(shelter)
    }

    private static func addFuelFarm(to root: Entity) {
        let tankMaterial = matteMaterial(
            UIColor(red: 0.64, green: 0.65, blue: 0.61, alpha: 1),
            roughness: 0.70,
            specular: 0.28
        )
        let dark = matteMaterial(
            UIColor(red: 0.18, green: 0.19, blue: 0.18, alpha: 1),
            roughness: 0.88,
            specular: 0.20
        )

        for index in 0..<6 {
            let x = Float(1_180 + (index % 3) * 34)
            let z = Float(1_760 + (index / 3) * 42)
            let terrain = Stage2TerrainProfile.heightMeters(east: x, north: z)
            let tank = ModelEntity(
                mesh: .generateCylinder(height: 14, radius: 10),
                materials: [tankMaterial]
            )
            tank.position = [x, terrain + 7, z]
            root.addChild(tank)
        }

        let containment = block(size: [118, 1.2, 94], material: dark)
        containment.position = [1_214, 0.65, 1_781]
        root.addChild(containment)
    }

    private static func addRunwayDesignation(
        to root: Entity,
        digits: [Int],
        centerZ: Float,
        facingNorth: Bool
    ) {
        let marking = matteMaterial(.white, roughness: 0.88, specular: 0.22)
        let digitWidth: Float = 14
        let spacing: Float = 18
        let yaw: Float = facingNorth ? 0 : .pi

        for (index, digit) in digits.enumerated() {
            let x = (Float(index) - Float(digits.count - 1) * 0.5) * spacing
            let entity = sevenSegmentDigit(digit, material: marking)
            entity.position = [x, 0.142, centerZ]
            entity.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            entity.scale = [digitWidth / 10, 1, digitWidth / 10]
            root.addChild(entity)
        }
    }

    private static func sevenSegmentDigit(_ digit: Int, material: PhysicallyBasedMaterial) -> Entity {
        let active: [Int: Set<Int>] = [
            0: [0, 1, 2, 4, 5, 6],
            1: [2, 5],
            2: [0, 2, 3, 4, 6],
            3: [0, 2, 3, 5, 6],
            4: [1, 2, 3, 5],
            5: [0, 1, 3, 5, 6],
            6: [0, 1, 3, 4, 5, 6],
            7: [0, 2, 5],
            8: [0, 1, 2, 3, 4, 5, 6],
            9: [0, 1, 2, 3, 5, 6]
        ]
        let root = Entity()
        let segments = active[digit] ?? []
        let horizontal: [(Int, SIMD3<Float>)] = [
            (0, [0, 0, -9]), (3, [0, 0, 0]), (6, [0, 0, 9])
        ]
        let vertical: [(Int, SIMD3<Float>)] = [
            (1, [-4.5, 0, -4.5]), (2, [4.5, 0, -4.5]),
            (4, [-4.5, 0, 4.5]), (5, [4.5, 0, 4.5])
        ]
        for (id, position) in horizontal where segments.contains(id) {
            let segment = block(size: [8.6, 0.022, 1.35], material: material)
            segment.position = position
            root.addChild(segment)
        }
        for (id, position) in vertical where segments.contains(id) {
            let segment = block(size: [1.35, 0.022, 8.6], material: material)
            segment.position = position
            root.addChild(segment)
        }
        return root
    }

    private static func addApproachLighting(to root: Entity, southEnd: Bool) {
        let direction: Float = southEnd ? -1 : 1
        let startZ: Float = southEnd ? -470 : 4_470
        let material = UnlitMaterial(color: UIColor(white: 0.92, alpha: 0.90))

        for row in 0..<10 {
            let z = startZ + direction * Float(row) * 46
            let width: Float = row < 4 ? 34 : 18
            for x in stride(from: -width, through: width, by: 9) {
                let light = ModelEntity(mesh: .generateSphere(radius: 0.085), materials: [material])
                light.position = [x, 0.22, z]
                root.addChild(light)
            }
        }
    }

    private static func addRadioMast(to root: Entity, position: SIMD3<Float>) {
        let terrain = Stage2TerrainProfile.heightMeters(east: position.x, north: position.z)
        let metal = matteMaterial(
            UIColor(red: 0.46, green: 0.47, blue: 0.45, alpha: 1),
            roughness: 0.58,
            specular: 0.36
        )
        let mast = Entity()
        mast.position = [position.x, terrain, position.z]
        for side: Float in [-1, 1] {
            mast.addChild(bar(from: [side * 3.2, 0, 0], to: [side * 0.9, 48, 0], radius: 0.18, material: metal))
            mast.addChild(bar(from: [0, 0, side * 3.2], to: [0, 48, side * 0.9], radius: 0.18, material: metal))
        }
        for level in stride(from: Float(8), through: Float(44), by: 8) {
            mast.addChild(bar(from: [-2.8, level, 0], to: [2.8, level, 0], radius: 0.10, material: metal))
            mast.addChild(bar(from: [0, level, -2.8], to: [0, level, 2.8], radius: 0.10, material: metal))
        }
        let beacon = ModelEntity(
            mesh: .generateSphere(radius: 0.30),
            materials: [UnlitMaterial(color: UIColor(red: 0.95, green: 0.10, blue: 0.06, alpha: 0.90))]
        )
        beacon.position = [0, 49, 0]
        mast.addChild(beacon)
        root.addChild(mast)
    }

    // MARK: - World scale cues

    private static func addUtilityScaleCues(to root: Entity) {
        let group = Entity()
        group.name = "FA.world.stage020.utilities"
        let poleMaterial = matteMaterial(
            UIColor(red: 0.19, green: 0.15, blue: 0.105, alpha: 1),
            roughness: 0.96,
            specular: 0.12
        )

        let start = SIMD2<Float>(-6_400, -4_600)
        let end = SIMD2<Float>(4_900, -1_450)
        for index in 0...18 {
            let t = Float(index) / 18
            let p = simd_mix(start, end, SIMD2<Float>(repeating: t))
            let terrain = Stage2TerrainProfile.heightMeters(east: p.x, north: p.y)
            let pole = ModelEntity(
                mesh: .generateCylinder(height: 14, radius: 0.20),
                materials: [poleMaterial]
            )
            pole.position = [p.x, terrain + 7, p.y]
            group.addChild(pole)

            let cross = block(size: [7.2, 0.22, 0.22], material: poleMaterial)
            cross.position = [p.x, terrain + 13.2, p.y]
            group.addChild(cross)
        }
        root.addChild(group)
    }

    private static func addRockOutcrops(to root: Entity) {
        let material = matteMaterial(
            UIColor(red: 0.27, green: 0.27, blue: 0.245, alpha: 1),
            roughness: 0.99,
            specular: 0.10
        )
        let points: [SIMD2<Float>] = [
            [-11_800, 9_600], [-10_900, 10_100], [-9_800, 9_800],
            [8_900, 7_700], [9_800, 8_450], [10_600, 7_950],
            [-11_200, -1_500], [-10_500, -2_100], [7_500, -6_800], [8_200, -7_200]
        ]
        for (index, point) in points.enumerated() {
            let terrain = Stage2TerrainProfile.heightMeters(east: point.x, north: point.y)
            let rock = ModelEntity(mesh: .generateSphere(radius: 1), materials: [material])
            rock.position = [point.x, terrain + 3.0, point.y]
            let sx = Float(4 + (index * 7) % 9)
            let sy = Float(2 + (index * 5) % 5)
            let sz = Float(5 + (index * 11) % 10)
            rock.scale = [sx, sy, sz]
            rock.orientation = simd_quatf(angle: Float(index) * 0.71, axis: simd_normalize(SIMD3<Float>(0.2, 1, 0.15)))
            root.addChild(rock)
        }
    }

    // MARK: - Mesh / material helpers

    private static func terrainPatch(
        center: SIMD2<Float>,
        size: SIMD2<Float>,
        rotation: Float,
        shear: SIMD2<Float>,
        textures: TextureSet,
        tint: UIColor,
        heightOffset: Float
    ) -> ModelEntity? {
        let subdivisions = 8
        let pointsPerSide = subdivisions + 1
        let c = cos(rotation)
        let s = sin(rotation)

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var tangents: [SIMD3<Float>] = []
        var texcoords: [SIMD2<Float>] = []
        var indices: [UInt32] = []

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
                let normal = Stage2TerrainProfile.normal(east: worldX, north: worldZ)
                let height = Stage2TerrainProfile.heightMeters(east: worldX, north: worldZ) + heightOffset
                positions.append([worldX, height, worldZ])
                normals.append(normal)
                tangents.append(projectedTangent(normal))
                texcoords.append([worldX / 18, worldZ / 18])
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

        var descriptor = MeshDescriptor(name: "Stage 020 terrain patch")
        descriptor.positions = .init(positions)
        descriptor.normals = .init(normals)
        descriptor.tangents = .init(tangents)
        descriptor.textureCoordinates = .init(texcoords)
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }
        return ModelEntity(mesh: mesh, materials: [surfaceMaterial(textures: textures, tint: tint)])
    }

    private static func terrainRibbon(
        from start: SIMD2<Float>,
        to end: SIMD2<Float>,
        width: Float,
        material: PhysicallyBasedMaterial,
        heightOffset: Float
    ) -> ModelEntity? {
        let delta = end - start
        let length = simd_length(delta)
        guard length > 1 else { return nil }
        let forward = delta / length
        let side = SIMD2<Float>(forward.y, -forward.x)
        let segments = max(5, Int(ceil(length / 130)))
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var tangents: [SIMD3<Float>] = []
        var texcoords: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        for index in 0...segments {
            let t = Float(index) / Float(segments)
            let center = start + delta * t
            let bend = sin(t * .pi) * width * 0.08
            let centerBent = center + side * bend
            for sign: Float in [-1, 1] {
                let point = centerBent + side * width * 0.5 * sign
                let normal = Stage2TerrainProfile.normal(east: point.x, north: point.y)
                positions.append([
                    point.x,
                    Stage2TerrainProfile.heightMeters(east: point.x, north: point.y) + heightOffset,
                    point.y
                ])
                normals.append(normal)
                tangents.append(projectedTangent(normal))
                texcoords.append([t * length / 24, sign > 0 ? 1 : 0])
            }
        }

        for index in 0..<segments {
            let i0 = UInt32(index * 2)
            let i1 = i0 + 1
            let i2 = i0 + 2
            let i3 = i0 + 3
            indices.append(contentsOf: [i0, i2, i1, i1, i2, i3])
        }

        var descriptor = MeshDescriptor(name: "Stage 020 terrain ribbon")
        descriptor.positions = .init(positions)
        descriptor.normals = .init(normals)
        descriptor.tangents = .init(tangents)
        descriptor.textureCoordinates = .init(texcoords)
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }
        return ModelEntity(mesh: mesh, materials: [material])
    }

    private static func textureSet(named stem: String) -> TextureSet {
        TextureSet(
            baseColor: loadTexture("\(stem)_diff"),
            roughness: loadTexture("\(stem)_rough"),
            normal: loadTexture("\(stem)_nor")
        )
    }

    private static func loadTexture(_ name: String) -> TextureResource? {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "jpg",
            subdirectory: "JSBSim/visuals/world"
        ) else { return nil }
        return try? TextureResource.load(contentsOf: url, withName: name)
    }

    private static func repeated(_ resource: TextureResource) -> MaterialParameters.Texture {
        var texture = MaterialParameters.Texture(resource)
        texture.sampler.modify { descriptor in
            descriptor.sAddressMode = .repeat
            descriptor.tAddressMode = .repeat
            descriptor.mipFilter = .linear
            descriptor.minFilter = .linear
            descriptor.magFilter = .linear
            descriptor.maxAnisotropy = 8
        }
        return texture
    }

    private static func surfaceMaterial(textures: TextureSet, tint: UIColor) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        if let base = textures.baseColor {
            material.baseColor = .init(tint: tint, texture: repeated(base))
        } else {
            material.baseColor = .init(tint: tint)
        }
        if let roughness = textures.roughness {
            material.roughness = .init(scale: 0.98, texture: repeated(roughness))
        } else {
            material.roughness = .init(floatLiteral: 0.98)
        }
        if let normal = textures.normal {
            material.normal = .init(texture: repeated(normal))
        }
        material.metallic = .init(floatLiteral: 0)
        material.specular = .init(floatLiteral: 0.16)
        return material
    }

    private static func waterMaterial() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.095, green: 0.205, blue: 0.225, alpha: 1))
        material.roughness = .init(floatLiteral: 0.18)
        material.metallic = .init(floatLiteral: 0)
        material.specular = .init(floatLiteral: 0.72)
        material.clearcoat = .init(floatLiteral: 0.34)
        material.clearcoatRoughness = .init(floatLiteral: 0.14)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.76))
        material.faceCulling = .none
        material.writesDepth = false
        return material
    }

    private static func earthyBankMaterial() -> PhysicallyBasedMaterial {
        matteMaterial(
            UIColor(red: 0.225, green: 0.205, blue: 0.155, alpha: 1),
            roughness: 0.99,
            specular: 0.10
        )
    }

    private static func matteMaterial(
        _ color: UIColor,
        roughness: Float,
        specular: Float
    ) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: 0)
        material.specular = .init(floatLiteral: specular)
        return material
    }

    private static func block(
        size: SIMD3<Float>,
        material: PhysicallyBasedMaterial,
        cornerRadius: Float = 0.4
    ) -> ModelEntity {
        ModelEntity(mesh: .generateBox(size: size, cornerRadius: cornerRadius), materials: [material])
    }

    private static func bar(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        radius: Float,
        material: PhysicallyBasedMaterial
    ) -> ModelEntity {
        let delta = end - start
        let length = max(simd_length(delta), 0.001)
        let entity = ModelEntity(mesh: .generateCylinder(height: length, radius: radius), materials: [material])
        entity.position = (start + end) * 0.5
        entity.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(delta))
        return entity
    }

    private static func projectedTangent(_ normal: SIMD3<Float>) -> SIMD3<Float> {
        let xAxis = SIMD3<Float>(1, 0, 0)
        let projected = xAxis - normal * simd_dot(xAxis, normal)
        if simd_length_squared(projected) > 0.000001 {
            return simd_normalize(projected)
        }
        return SIMD3<Float>(0, 0, 1)
    }
}