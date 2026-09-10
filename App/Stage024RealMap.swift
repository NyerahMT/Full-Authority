import Foundation
import RealityKit
import UIKit
import simd

// Stage 024 benchmark world: a direct mobile repack of the City of Helsinki's
// CC BY 4.0 2017 photogrammetry reality mesh. Unlike the discarded Reno/OSM
// experiment, roads, buildings, trees, vehicles, shoreline and ground are not
// reconstructed from GIS primitives; they are already part of the scanned mesh.
final class Stage024RealMapData {
    static let shared = Stage024RealMapData()

    struct Tile: Decodable {
        let code: String
        let lod: Int
        let mesh: String
        let texture: String
        let vertices: Int
        let triangles: Int
    }

    struct MapDocument: Decodable {
        let name: String
        let source: String
        let license: String
        let sourceURL: String
        let coordinateSystem: String
        let minX: Float
        let minZ: Float
        let maxX: Float
        let maxZ: Float
        let referenceElevationMeters: Float
        let runwayLengthMeters: Float
        let runwayHeadingTrueDegrees: Float
        let tiles: [Tile]
    }

    private(set) var map: MapDocument?
    private(set) var gridWidth = 0
    private(set) var gridHeight = 0
    private(set) var cellMeters: Float = 50
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
        guard let manifestURL = Bundle.main.url(
            forResource: "helsinki_manifest",
            withExtension: "json",
            subdirectory: "JSBSim/visuals/world/helsinki"
        ), let terrainURL = Bundle.main.url(
            forResource: "helsinki_ground",
            withExtension: "bin",
            subdirectory: "JSBSim/visuals/world/helsinki"
        ) else {
            return
        }

        if let json = try? Data(contentsOf: manifestURL) {
            map = try? JSONDecoder().decode(MapDocument.self, from: json)
        }
        guard let binary = try? Data(contentsOf: terrainURL), binary.count >= 32 else { return }

        func uint32(_ offset: Int) -> UInt32 {
            guard offset + 4 <= binary.count else { return 0 }
            return UInt32(binary[offset]) |
                (UInt32(binary[offset + 1]) << 8) |
                (UInt32(binary[offset + 2]) << 16) |
                (UInt32(binary[offset + 3]) << 24)
        }
        func float32(_ offset: Int) -> Float {
            Float(bitPattern: uint32(offset))
        }

        guard String(data: binary.prefix(4), encoding: .ascii) == "FAM2",
              uint32(4) == 1 else { return }

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
        guard isLoaded else { return referenceElevationMeters }

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
        let n = SIMD3<Float>(-dhdx, 1, -dhdz)
        return simd_length_squared(n) > 0 ? simd_normalize(n) : SIMD3<Float>(0, 1, 0)
    }
}

@MainActor
enum Stage024RealMapWorld {
    static let rootName = "FA.world.stage024.helsinki-reality-mesh"

    static func make() -> Entity {
        let root = Entity()
        root.name = rootName

        let data = Stage024RealMapData.shared
        guard data.isLoaded, let map = data.map else { return root }

        for tile in map.tiles {
            if let entity = loadRealityMeshTile(tile, referenceElevation: data.referenceElevationMeters) {
                root.addChild(entity)
            }
        }
        return root
    }

    private static func loadRealityMeshTile(
        _ tile: Stage024RealMapData.Tile,
        referenceElevation: Float
    ) -> ModelEntity? {
        guard let meshURL = Bundle.main.url(
            forResource: (tile.mesh as NSString).deletingPathExtension,
            withExtension: (tile.mesh as NSString).pathExtension,
            subdirectory: "JSBSim/visuals/world/helsinki"
        ), let textureURL = Bundle.main.url(
            forResource: (tile.texture as NSString).deletingPathExtension,
            withExtension: (tile.texture as NSString).pathExtension,
            subdirectory: "JSBSim/visuals/world/helsinki"
        ), let binary = try? Data(contentsOf: meshURL), binary.count >= 20 else {
            return nil
        }

        func uint32(_ offset: Int) -> UInt32 {
            guard offset + 4 <= binary.count else { return 0 }
            return UInt32(binary[offset]) |
                (UInt32(binary[offset + 1]) << 8) |
                (UInt32(binary[offset + 2]) << 16) |
                (UInt32(binary[offset + 3]) << 24)
        }
        func float32(_ offset: Int) -> Float {
            Float(bitPattern: uint32(offset))
        }

        guard String(data: binary.prefix(4), encoding: .ascii) == "FHM1",
              uint32(4) == 1 else { return nil }

        let vertexCount = Int(uint32(8))
        let indexCount = Int(uint32(12))
        let faceCount = Int(uint32(16))
        guard vertexCount > 0,
              indexCount > 0,
              indexCount % 3 == 0,
              faceCount == indexCount / 3 else { return nil }

        let vertexOffset = 20
        let vertexStride = 5 * MemoryLayout<Float>.size
        let indexOffset = vertexOffset + vertexCount * vertexStride
        let materialOffset = indexOffset + indexCount * MemoryLayout<UInt32>.size
        guard materialOffset + faceCount <= binary.count else { return nil }

        var positions: [SIMD3<Float>] = []
        var texcoords: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        var faceMaterials: [UInt32] = []
        positions.reserveCapacity(vertexCount)
        texcoords.reserveCapacity(vertexCount)
        indices.reserveCapacity(indexCount)
        faceMaterials.reserveCapacity(faceCount)

        for vertex in 0..<vertexCount {
            let o = vertexOffset + vertex * vertexStride
            positions.append([
                float32(o),
                float32(o + 4) - referenceElevation,
                float32(o + 8)
            ])
            texcoords.append([float32(o + 12), float32(o + 16)])
        }
        for index in 0..<indexCount {
            indices.append(uint32(indexOffset + index * 4))
        }
        for face in 0..<faceCount {
            faceMaterials.append(UInt32(binary[materialOffset + face]))
        }

        var descriptor = MeshDescriptor(name: "Helsinki reality mesh \(tile.code) L\(tile.lod)")
        descriptor.positions = .init(positions)
        descriptor.textureCoordinates = .init(texcoords)
        descriptor.primitives = .triangles(indices)
        descriptor.materials = .perFace(faceMaterials)
        guard let mesh = try? MeshResource.generate(from: [descriptor]),
              let image = try? TextureResource.load(contentsOf: textureURL, withName: "Helsinki \(tile.code)") else {
            return nil
        }

        var texture = MaterialParameters.Texture(image)
        texture.sampler.modify { sampler in
            sampler.sAddressMode = .clampToEdge
            sampler.tAddressMode = .clampToEdge
            sampler.minFilter = .linear
            sampler.magFilter = .linear
            sampler.mipFilter = .linear
            sampler.maxAnisotropy = 4
        }

        // Photogrammetry already contains the captured daylight/shadow response.
        // Keeping the benchmark unlit prevents RealityKit from adding a second
        // lighting pass and, critically, removes the plastic terrain sheen that
        // made the generated worlds look synthetic from altitude.
        var photographed = UnlitMaterial()
        photographed.color = .init(tint: .white, texture: texture)
        photographed.readsDepth = true
        photographed.writesDepth = true

        var untextured = UnlitMaterial(color: UIColor(white: 0.46, alpha: 1))
        untextured.readsDepth = true
        untextured.writesDepth = true

        let entity = ModelEntity(mesh: mesh, materials: [photographed, untextured])
        entity.name = "FA.stage024.helsinki.\(tile.code).L\(tile.lod)"
        return entity
    }
}
