import Foundation
import Metal
import RealityKit
import UIKit
import simd

// MARK: - Fixed Worldsmith theater

/// Compatibility note: the type name remains `Stage022MaltaWorld` so the rest of
/// the flight presentation does not need a risky project-wide rename. Malta is
/// no longer loaded here. This renderer streams the one fixed Worldsmith seed-1337
/// theater selected for Full Authority.
@MainActor
enum Stage022MaltaWorld {
    static let rootName = "FA.world.worldsmith.1337"

    private static let worldRootName = "FA.world.stage2"
    private static let cloudRootName = "FA.world.cloudscape"
    private static let tileMeters: Float = 8_000
    private static let loadRadiusTiles = 8
    private static let unloadRadiusTiles = 9
    private static let tilesBuiltPerUpdate = 10
    private static let theaterMeters: Float = 150_000
    private static let runwayCenterNorth: Float = 1_800
    private static let siteU: Float = 0.3712567
    private static let siteV: Float = 0.4103772
    private static let mapHeadingRadians: Float = 1.0384709 // 59.5 degrees

    private struct TileKey: Hashable {
        let x: Int
        let z: Int
    }

    private struct LoadedTile {
        let entity: ModelEntity
        let resolution: Int
    }

    private final class Runtime {
        let root: Entity
        let terrainMaterial: PhysicallyBasedMaterial
        var loaded: [TileKey: LoadedTile] = [:]

        init(root: Entity, terrainMaterial: PhysicallyBasedMaterial) {
            self.root = root
            self.terrainMaterial = terrainMaterial
        }
    }

    private static var runtime: Runtime?

    static func make(base: Entity) -> Entity {
        guard base.findEntity(named: rootName) == nil else { return base }

        // Stage2WorldFactory is still used for the proven cloud layer, but every
        // old terrain/road/city/airfield child is removed before this theater is
        // attached. This prevents the former Malta world from z-fighting through
        // the new heightfield while leaving aircraft/camera/HUD systems untouched.
        for child in Array(base.children) where child.name != cloudRootName {
            child.removeFromParent()
        }

        let root = Entity()
        root.name = rootName
        addOcean(to: root)
        addAirbase(to: root)
        base.addChild(root)

        runtime = Runtime(root: root, terrainMaterial: makeTerrainMaterial())
        update(base: base, center: .zero)
        return base
    }

    static func update(base: Entity, center: SIMD3<Float>) {
        guard base.name == worldRootName || base.findEntity(named: rootName) != nil,
              let runtime,
              runtime.root.parent != nil else { return }

        let centerKey = TileKey(
            x: Int(floor((center.x + tileMeters * 0.5) / tileMeters)),
            z: Int(floor((center.z + tileMeters * 0.5) / tileMeters))
        )

        for key in Array(runtime.loaded.keys) {
            if chebyshevDistance(key, centerKey) > unloadRadiusTiles {
                runtime.loaded.removeValue(forKey: key)?.entity.removeFromParent()
            }
        }

        var wanted: [(key: TileKey, resolution: Int, distance: Int)] = []
        wanted.reserveCapacity((loadRadiusTiles * 2 + 1) * (loadRadiusTiles * 2 + 1))
        for dz in -loadRadiusTiles...loadRadiusTiles {
            for dx in -loadRadiusTiles...loadRadiusTiles {
                let key = TileKey(x: centerKey.x + dx, z: centerKey.z + dz)
                let distance = max(abs(dx), abs(dz))
                let resolution = resolutionForDistance(distance)
                if runtime.loaded[key]?.resolution != resolution {
                    wanted.append((key, resolution, distance))
                }
            }
        }

        wanted.sort {
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            let da = distanceSquared($0.key, centerKey)
            let db = distanceSquared($1.key, centerKey)
            if da != db { return da < db }
            if $0.key.z != $1.key.z { return $0.key.z < $1.key.z }
            return $0.key.x < $1.key.x
        }

        for request in wanted.prefix(tilesBuiltPerUpdate) {
            let centerX = Float(request.key.x) * tileMeters
            let centerZ = Float(request.key.z) * tileMeters
            guard let entity = makeTerrainTile(
                centerX: centerX,
                centerZ: centerZ,
                resolution: request.resolution,
                material: runtime.terrainMaterial
            ) else { continue }

            runtime.loaded.removeValue(forKey: request.key)?.entity.removeFromParent()
            runtime.root.addChild(entity)
            runtime.loaded[request.key] = LoadedTile(
                entity: entity,
                resolution: request.resolution
            )
        }
    }

    private static func resolutionForDistance(_ distance: Int) -> Int {
        switch distance {
        case 0...2: return 65
        case 3...4: return 33
        case 5...6: return 17
        default: return 9
        }
    }

    private static func makeTerrainTile(
        centerX: Float,
        centerZ: Float,
        resolution: Int,
        material: PhysicallyBasedMaterial
    ) -> ModelEntity? {
        guard resolution >= 3 else { return nil }

        let count = resolution * resolution
        let half = tileMeters * 0.5
        let step = tileMeters / Float(resolution - 1)
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var texcoords: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(count + resolution * 4)
        normals.reserveCapacity(count + resolution * 4)
        texcoords.reserveCapacity(count + resolution * 4)
        indices.reserveCapacity((resolution - 1) * (resolution - 1) * 6 + resolution * 24)

        for zIndex in 0..<resolution {
            for xIndex in 0..<resolution {
                let localX = -half + Float(xIndex) * step
                let localZ = -half + Float(zIndex) * step
                let worldX = centerX + localX
                let worldZ = centerZ + localZ
                positions.append([
                    localX,
                    Stage2TerrainProfile.heightMeters(east: worldX, north: worldZ),
                    localZ
                ])
                normals.append(Stage2TerrainProfile.normal(east: worldX, north: worldZ))
                texcoords.append(mapUV(east: worldX, north: worldZ))
            }
        }

        for zIndex in 0..<(resolution - 1) {
            for xIndex in 0..<(resolution - 1) {
                let i0 = UInt32(zIndex * resolution + xIndex)
                let i1 = i0 + 1
                let i2 = UInt32((zIndex + 1) * resolution + xIndex)
                let i3 = i2 + 1
                indices.append(contentsOf: [i0, i2, i1, i1, i2, i3])
            }
        }

        // Small downward skirts hide the only visible failure mode when a 65x65
        // tile meets a much cheaper distant LOD. The top edge remains the exact
        // shared JSBSim surface; only the duplicated boundary vertices move down.
        var perimeter: [Int] = []
        perimeter.reserveCapacity((resolution - 1) * 4)
        for x in 0..<resolution { perimeter.append(x) }
        for z in 1..<resolution { perimeter.append(z * resolution + (resolution - 1)) }
        if resolution > 1 {
            for x in stride(from: resolution - 2, through: 0, by: -1) {
                perimeter.append((resolution - 1) * resolution + x)
            }
            if resolution > 2 {
                for z in stride(from: resolution - 2, through: 1, by: -1) {
                    perimeter.append(z * resolution)
                }
            }
        }

        let skirtDepth: Float = 110
        let skirtStart = positions.count
        for original in perimeter {
            var p = positions[original]
            p.y -= skirtDepth
            positions.append(p)
            normals.append(normals[original])
            texcoords.append(texcoords[original])
        }
        if perimeter.count > 1 {
            for pIndex in 0..<perimeter.count {
                let next = (pIndex + 1) % perimeter.count
                let top0 = UInt32(perimeter[pIndex])
                let top1 = UInt32(perimeter[next])
                let low0 = UInt32(skirtStart + pIndex)
                let low1 = UInt32(skirtStart + next)
                indices.append(contentsOf: [top0, low0, top1, top1, low0, low1])
            }
        }

        var descriptor = MeshDescriptor(name: "Worldsmith terrain LOD \(resolution)")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(texcoords)
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "FA.world.worldsmith.tile.\(Int(centerX)).\(Int(centerZ))"
        entity.position = [centerX, 0, centerZ]
        return entity
    }

    private static func mapUV(east: Float, north: Float) -> SIMD2<Float> {
        let localNorth = north - runwayCenterNorth
        let c = cos(mapHeadingRadians)
        let s = sin(mapHeadingRadians)
        let mapEast = c * east + s * localNorth
        let mapNorth = -s * east + c * localNorth
        return [
            siteU + mapEast / theaterMeters,
            siteV - mapNorth / theaterMeters
        ]
    }

    private static func makeTerrainMaterial() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        if let url = Bundle.main.url(
            forResource: "worldsmith_1337_albedo_1024",
            withExtension: "png",
            subdirectory: "JSBSim/visuals/world"
        ), let textureResource = try? TextureResource.load(
            contentsOf: url,
            withName: "Worldsmith 1337 macro albedo"
        ) {
            var texture = MaterialParameters.Texture(textureResource)
            texture.sampler.modify { sampler in
                sampler.sAddressMode = .clampToEdge
                sampler.tAddressMode = .clampToEdge
                sampler.mipFilter = .linear
                sampler.minFilter = .linear
                sampler.magFilter = .linear
                sampler.maxAnisotropy = 8
            }
            material.baseColor = .init(tint: .white, texture: texture)
        } else {
            material.baseColor = .init(
                tint: UIColor(red: 0.30, green: 0.40, blue: 0.22, alpha: 1)
            )
        }
        material.roughness = .init(floatLiteral: 0.93)
        material.metallic = .init(floatLiteral: 0.0)
        material.specular = .init(floatLiteral: 0.23)
        material.faceCulling = .none
        return material
    }

    private static func addOcean(to root: Entity) {
        var water = PhysicallyBasedMaterial()
        water.baseColor = .init(
            tint: UIColor(red: 0.025, green: 0.145, blue: 0.235, alpha: 1)
        )
        water.roughness = .init(floatLiteral: 0.16)
        water.metallic = .init(floatLiteral: 0.0)
        water.specular = .init(floatLiteral: 0.82)

        let sea = ModelEntity(
            mesh: .generatePlane(width: 260_000, depth: 260_000),
            materials: [water]
        )
        sea.name = "FA.world.worldsmith.ocean"
        sea.position = [0, Stage2TerrainProfile.seaLevelMeters + 0.25, 0]
        root.addChild(sea)
    }

    private static func addAirbase(to root: Entity) {
        let airbase = Entity()
        airbase.name = "FA.world.worldsmith.airbase"

        let asphalt = UIColor(red: 0.055, green: 0.060, blue: 0.065, alpha: 1)
        let concrete = UIColor(red: 0.34, green: 0.35, blue: 0.34, alpha: 1)
        let marking = UIColor(white: 0.93, alpha: 1)
        let taxiYellow = UIColor(red: 0.92, green: 0.70, blue: 0.08, alpha: 1)

        let runway = block(size: [58, 0.10, 4_800], color: asphalt)
        runway.position = [0, 0.05, runwayCenterNorth]
        airbase.addChild(runway)

        for z in stride(from: -420, through: 4_020, by: 120) {
            let dash = block(size: [1.25, 0.025, 38], color: marking)
            dash.position = [0, 0.115, Float(z)]
            airbase.addChild(dash)
        }
        for x: Float in [-27.5, 27.5] {
            let edge = block(size: [0.65, 0.022, 4_700], color: marking)
            edge.position = [x, 0.115, runwayCenterNorth]
            airbase.addChild(edge)
        }
        for endZ: Float in [-560, 4_160] {
            for stripe in -3...3 {
                let threshold = block(size: [4.5, 0.026, 30], color: marking)
                threshold.position = [Float(stripe) * 6.5, 0.12, endZ]
                airbase.addChild(threshold)
            }
        }

        let taxiway = block(size: [24, 0.09, 4_400], color: asphalt)
        taxiway.position = [115, 0.047, runwayCenterNorth]
        airbase.addChild(taxiway)
        let taxiCenter = block(size: [0.55, 0.025, 4_360], color: taxiYellow)
        taxiCenter.position = [115, 0.108, runwayCenterNorth]
        airbase.addChild(taxiCenter)

        let apron = block(size: [330, 0.09, 760], color: concrete)
        apron.position = [260, 0.045, 760]
        airbase.addChild(apron)

        for index in 0..<5 {
            let connector = block(size: [92, 0.085, 15], color: asphalt)
            connector.position = [69, 0.05, Float(-120 + index * 900)]
            airbase.addChild(connector)
        }

        for index in 0..<4 {
            let hangar = block(
                size: [68, 15, 46],
                color: UIColor(red: 0.36, green: 0.38, blue: 0.36, alpha: 1)
            )
            hangar.position = [Float(205 + index * 78), 7.5, 530]
            airbase.addChild(hangar)
        }

        let tower = block(
            size: [18, 34, 18],
            color: UIColor(red: 0.30, green: 0.32, blue: 0.32, alpha: 1)
        )
        tower.position = [205, 17, 1_050]
        airbase.addChild(tower)
        let cab = block(
            size: [27, 8, 27],
            color: UIColor(red: 0.16, green: 0.23, blue: 0.27, alpha: 1)
        )
        cab.position = [205, 38, 1_050]
        airbase.addChild(cab)

        root.addChild(airbase)
    }

    private static func block(size: SIMD3<Float>, color: UIColor) -> ModelEntity {
        ModelEntity(
            mesh: .generateBox(size: size),
            materials: [SimpleMaterial(color: color, roughness: 0.94, isMetallic: false)]
        )
    }

    private static func chebyshevDistance(_ a: TileKey, _ b: TileKey) -> Int {
        max(abs(a.x - b.x), abs(a.z - b.z))
    }

    private static func distanceSquared(_ a: TileKey, _ b: TileKey) -> Int {
        let dx = a.x - b.x
        let dz = a.z - b.z
        return dx * dx + dz * dz
    }
}
