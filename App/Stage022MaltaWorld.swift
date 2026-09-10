import Foundation
import RealityKit
import UIKit
import simd

// MARK: - Stage 022 streamed OSM2World Malta layer

/// Streams the compact OSM2World LOD2 chunks around the aircraft instead of
/// materializing the full country in RealityKit at once. The source payload
/// stays complete in the app bundle; only nearby 4 km superchunks occupy
/// renderer/GPU memory.
@MainActor
enum Stage022MaltaWorld {
    static let rootName = "FA.world.stage022.malta"

    private static let worldRootName = "FA.world.stage2"
    private static let resourceSubdirectory = "JSBSim/visuals/world/stage022/lod2"
    private static let superchunkMeters: Float = 4_000
    private static let positionScaleXZ: Float = 0.25
    private static let positionScaleY: Float = 0.10
    private static let loadRadiusChunks = 3
    private static let unloadRadiusChunks = 4
    private static let chunkGroupsPerUpdate = 1

    private struct ChunkKey: Hashable {
        let x: Int
        let z: Int
    }

    private struct SourceChunk {
        let url: URL
        let key: ChunkKey
    }

    private struct MaterialRecord {
        let rgba: SIMD4<Float>
        let roughness: Float
        let metallic: Float
        let doubleSided: Bool
    }

    private final class Runtime {
        let root: Entity
        let sourcesByKey: [ChunkKey: [SourceChunk]]
        var loaded: [ChunkKey: [Entity]] = [:]
        var lastCenter: ChunkKey?

        init(root: Entity, sourcesByKey: [ChunkKey: [SourceChunk]]) {
  self.root = root
  self.sourcesByKey = sourcesByKey
        }
    }

    private struct BinaryCursor {
        let data: Data
        var offset = 0

        mutating func readUInt8() -> UInt8? {
  guard offset + 1 <= data.count else { return nil }
  defer { offset += 1 }
  return data[offset]
        }

        mutating func readInt8() -> Int8? {
  guard let value = readUInt8() else { return nil }
  return Int8(bitPattern: value)
        }

        mutating func readUInt16() -> UInt16? {
  guard offset + 2 <= data.count else { return nil }
  let value: UInt16 = data.withUnsafeBytes {
      $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
  }
  offset += 2
  return UInt16(littleEndian: value)
        }

        mutating func readInt16() -> Int16? {
  guard let value = readUInt16() else { return nil }
  return Int16(bitPattern: value)
        }

        mutating func readUInt32() -> UInt32? {
  guard offset + 4 <= data.count else { return nil }
  let value: UInt32 = data.withUnsafeBytes {
      $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
  }
  offset += 4
  return UInt32(littleEndian: value)
        }

        mutating func readFloat() -> Float? {
  guard let bits = readUInt32() else { return nil }
  return Float(bitPattern: bits)
        }

        mutating func readMagic() -> [UInt8]? {
  guard offset + 4 <= data.count else { return nil }
  let result = Array(data[offset..<(offset + 4)])
  offset += 4
  return result
        }
    }

    private static var runtime: Runtime?

    static func make(base: Entity) -> Entity {
        guard base.findEntity(named: rootName) == nil else { return base }

        let sources = discoverSources()
        guard !sources.isEmpty else {
  // Keep the proven Stage 021 path as a development fallback if a
  // local build omits the generated Stage 022 resource folder.
  return Stage021MaltaWorld.make(base: base)
        }

        base.findEntity(named: "FA.world.stage019.professional-environment")?.isEnabled = false
        base.findEntity(named: "FA.world.stage020.procedural-region")?.isEnabled = false
        base.findEntity(named: "FA.world.stage021.malta")?.isEnabled = false

        let root = Entity()
        root.name = rootName
        addMediterranean(to: root)
        base.addChild(root)

        let grouped = Dictionary(grouping: sources, by: \.key)
        runtime = Runtime(root: root, sourcesByKey: grouped)
        update(base: base, center: .zero)
        return base
    }

    static func update(base: Entity, center: SIMD3<Float>) {
        guard base.name == worldRootName || base.findEntity(named: rootName) != nil,
    let runtime,
    runtime.root.parent != nil else { return }

        let centerKey = ChunkKey(
  x: Int(floor(center.x / superchunkMeters)),
  z: Int(floor(center.z / superchunkMeters))
        )

        // Hysteresis avoids unloading/reloading a whole edge of scenery when
        // the aircraft crosses a 4 km chunk boundary.
        for key in Array(runtime.loaded.keys) {
  if chebyshevDistance(key, centerKey) > unloadRadiusChunks {
      runtime.loaded.removeValue(forKey: key)?.forEach { $0.removeFromParent() }
  }
        }

        let missing = runtime.sourcesByKey.keys
  .filter {
      chebyshevDistance($0, centerKey) <= loadRadiusChunks &&
      runtime.loaded[$0] == nil
  }
  .sorted {
      let da = distanceSquared($0, centerKey)
      let db = distanceSquared($1, centerKey)
      if da != db { return da < db }
      if $0.z != $1.z { return $0.z < $1.z }
      return $0.x < $1.x
  }

        for key in missing.prefix(chunkGroupsPerUpdate) {
  guard let sources = runtime.sourcesByKey[key] else { continue }
  var entities: [Entity] = []
  for source in sources.sorted(by: { $0.url.lastPathComponent < $1.url.lastPathComponent }) {
      if let entity = loadChunk(source.url) {
          runtime.root.addChild(entity)
          entities.append(entity)
      }
  }
  // Mark even an empty/invalid group as visited for this runtime so
  // a malformed asset cannot trigger a 60 Hz retry loop.
  runtime.loaded[key] = entities
        }

        runtime.lastCenter = centerKey
    }

    private static func discoverSources() -> [SourceChunk] {
        guard let urls = Bundle.main.urls(
  forResourcesWithExtension: "bin",
  subdirectory: resourceSubdirectory
        ) else { return [] }

        return urls.compactMap { url in
  let stem = url.deletingPathExtension().lastPathComponent
  let parts = stem.split(separator: "_")
  guard parts.count == 4,
        parts[0] == "chunk",
        let x = Int(parts[1]),
        let z = Int(parts[2]),
        parts[3].hasPrefix("s") else { return nil }
  return SourceChunk(url: url, key: ChunkKey(x: x, z: z))
        }
    }

    private static func addMediterranean(to root: Entity) {
        var water = PhysicallyBasedMaterial()
        water.baseColor = .init(tint: UIColor(red: 0.028, green: 0.175, blue: 0.245, alpha: 1))
        water.roughness = .init(floatLiteral: 0.20)
        water.metallic = .init(floatLiteral: 0.0)
        water.specular = .init(floatLiteral: 0.78)

        let sea = ModelEntity(
  mesh: .generatePlane(width: 92_000, depth: 92_000),
  materials: [water]
        )
        sea.name = "FA.world.stage022.mediterranean"
        sea.position = [0, Stage2TerrainProfile.seaLevelMeters + 0.035, 16_000]
        root.addChild(sea)
    }

    private static func loadChunk(_ url: URL) -> ModelEntity? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        var cursor = BinaryCursor(data: data)

        guard cursor.readMagic() == [70, 50, 50, 67], // F22C
    let version = cursor.readUInt16(), version == 1,
    let lod = cursor.readUInt8(), lod == 2,
    cursor.readUInt8() != nil,
    let centerX = cursor.readFloat(),
    let centerZ = cursor.readFloat(),
    let materialCountRaw = cursor.readUInt16(),
    let partCountRaw = cursor.readUInt16() else { return nil }

        let materialCount = Int(materialCountRaw)
        let partCount = Int(partCountRaw)
        guard materialCount > 0, materialCount <= 4_096,
    partCount > 0, partCount <= 16_384 else { return nil }

        var materials: [MaterialRecord] = []
        materials.reserveCapacity(materialCount)
        for _ in 0..<materialCount {
  guard let r = cursor.readUInt8(),
        let g = cursor.readUInt8(),
        let b = cursor.readUInt8(),
        let a = cursor.readUInt8(),
        let roughness = cursor.readUInt8(),
        let metallic = cursor.readUInt8(),
        let flags = cursor.readUInt8(),
        cursor.readUInt8() != nil else { return nil }
  materials.append(MaterialRecord(
      rgba: SIMD4<Float>(Float(r), Float(g), Float(b), Float(a)) / 255,
      roughness: Float(roughness) / 255,
      metallic: Float(metallic) / 255,
      doubleSided: (flags & 1) != 0
  ))
        }

        var descriptors: [MeshDescriptor] = []
        var entityMaterials: [PhysicallyBasedMaterial] = []
        descriptors.reserveCapacity(partCount)
        entityMaterials.reserveCapacity(partCount)

        for partIndex in 0..<partCount {
  guard let materialIndexRaw = cursor.readUInt16(),
        cursor.readUInt16() != nil,
        let vertexCountRaw = cursor.readUInt32(),
        let indexCountRaw = cursor.readUInt32() else { return nil }

  let materialIndex = Int(materialIndexRaw)
  let vertexCount = Int(vertexCountRaw)
  let indexCount = Int(indexCountRaw)
  guard materialIndex >= 0, materialIndex < materials.count,
        vertexCount > 0, vertexCount <= 65_535,
        indexCount >= 3, indexCount % 3 == 0 else { return nil }

  var positions: [SIMD3<Float>] = []
  var normals: [SIMD3<Float>] = []
  positions.reserveCapacity(vertexCount)
  normals.reserveCapacity(vertexCount)

  for _ in 0..<vertexCount {
      guard let qx = cursor.readInt16(),
            let qy = cursor.readInt16(),
            let qz = cursor.readInt16(),
            let nx = cursor.readInt8(),
            let ny = cursor.readInt8(),
            let nz = cursor.readInt8() else { return nil }

      positions.append([
          Float(qx) * positionScaleXZ,
          Float(qy) * positionScaleY,
          Float(qz) * positionScaleXZ
      ])
      let normal = SIMD3<Float>(Float(nx), Float(ny), Float(nz)) / 127
      normals.append(simd_length_squared(normal) > 0.0001 ? simd_normalize(normal) : SIMD3<Float>(0, 1, 0))
  }

  var indices: [UInt32] = []
  indices.reserveCapacity(indexCount)
  for _ in 0..<indexCount {
      guard let index = cursor.readUInt16(), Int(index) < vertexCount else { return nil }
      indices.append(UInt32(index))
  }

  var descriptor = MeshDescriptor(name: "Stage 022 \(url.lastPathComponent) part \(partIndex)")
  descriptor.positions = MeshBuffers.Positions(positions)
  descriptor.normals = MeshBuffers.Normals(normals)
  descriptor.primitives = .triangles(indices)
  descriptors.append(descriptor)
  entityMaterials.append(makeMaterial(materials[materialIndex]))
        }

        guard !descriptors.isEmpty,
    let mesh = try? MeshResource.generate(from: descriptors) else { return nil }

        let entity = ModelEntity(mesh: mesh, materials: entityMaterials)
        entity.name = "FA.world.stage022.chunk.\(url.deletingPathExtension().lastPathComponent)"
        entity.position = [centerX, 0, centerZ]
        return entity
    }

    private static func makeMaterial(_ record: MaterialRecord) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(
  red: CGFloat(record.rgba.x),
  green: CGFloat(record.rgba.y),
  blue: CGFloat(record.rgba.z),
  alpha: CGFloat(record.rgba.w)
        ))
        material.roughness = .init(floatLiteral: record.roughness)
        material.metallic = .init(floatLiteral: record.metallic)
        material.specular = .init(floatLiteral: record.metallic > 0.35 ? 0.62 : 0.20)
        material.faceCulling = record.doubleSided ? .none : .back
        return material
    }

    private static func chebyshevDistance(_ a: ChunkKey, _ b: ChunkKey) -> Int {
        max(abs(a.x - b.x), abs(a.z - b.z))
    }

    private static func distanceSquared(_ a: ChunkKey, _ b: ChunkKey) -> Int {
        let dx = a.x - b.x
        let dz = a.z - b.z
        return dx * dx + dz * dz
    }
}
