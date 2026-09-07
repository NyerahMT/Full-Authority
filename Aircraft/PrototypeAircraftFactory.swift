import Foundation
import RealityKit
import UIKit
import simd

@MainActor
enum PrototypeAircraftFactory {
    static let aircraftName = "FA.aircraft"

    private struct OBJVertexKey: Hashable {
        let position: Int
        let normal: Int
    }

    private enum OBJError: Error {
        case missingAsset
        case invalidGeometry
    }

    static func make() -> Entity {
        let root = Entity()
        root.name = aircraftName

        do {
            let mesh = try loadF16Mesh()
            let material = SimpleMaterial(
                color: UIColor(red: 0.45, green: 0.49, blue: 0.52, alpha: 1),
                isMetallic: true
            )
            let model = ModelEntity(mesh: mesh, materials: [material])
            model.name = "FA.aircraft.f16.mesh"
            root.addChild(model)
        } catch {
            // This should only appear if CI failed to stage the pinned mesh.
            // Keep the scene alive and make a missing asset immediately obvious.
            let fallback = ModelEntity(
                mesh: .generateBox(size: [4, 1, 10], cornerRadius: 0.2),
                materials: [SimpleMaterial(color: .red, isMetallic: false)]
            )
            fallback.name = "FA.aircraft.missing-mesh"
            root.addChild(fallback)
        }

        return root
    }

    /// Loads the pinned MIT-licensed F-16 OBJ staged by CI and converts it into
    /// one RealityKit mesh. The OBJ was exported by Blender with Y-up and the
    /// fuselage running along Z, which matches Full Authority's visual axes.
    private static func loadF16Mesh() throws -> MeshResource {
        guard let url = Bundle.main.url(
            forResource: "f16",
            withExtension: "obj",
            subdirectory: "Models"
        ) else {
            throw OBJError.missingAsset
        }

        let source = try String(contentsOf: url, encoding: .utf8)
        let lines = source.split(whereSeparator: \.isNewline)

        var sourcePositions: [SIMD3<Float>] = []
        var sourceNormals: [SIMD3<Float>] = []
        sourcePositions.reserveCapacity(2_500)
        sourceNormals.reserveCapacity(4_000)

        for line in lines {
            if line.hasPrefix("v ") {
                let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard fields.count >= 4,
                      let x = Float(fields[1]),
                      let y = Float(fields[2]),
                      let z = Float(fields[3]) else { continue }
                sourcePositions.append([x, y, z])
            } else if line.hasPrefix("vn ") {
                let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard fields.count >= 4,
                      let x = Float(fields[1]),
                      let y = Float(fields[2]),
                      let z = Float(fields[3]) else { continue }
                let value = SIMD3<Float>(x, y, z)
                sourceNormals.append(simd_length_squared(value) > 0 ? simd_normalize(value) : SIMD3<Float>(0, 1, 0))
            }
        }

        guard !sourcePositions.isEmpty else { throw OBJError.invalidGeometry }

        // The mesh source is unitless. Scale its measured nose-to-tail Z extent
        // to the real F-16A length (49 ft 4 in / 15.03 m). We intentionally keep
        // the source origin because it is already close to the aircraft center.
        var minZ = Float.greatestFiniteMagnitude
        var maxZ = -Float.greatestFiniteMagnitude
        for position in sourcePositions {
            minZ = Swift.min(minZ, position.z)
            maxZ = Swift.max(maxZ, position.z)
        }
        let sourceLength = maxZ - minZ
        guard sourceLength > 0.001 else { throw OBJError.invalidGeometry }
        let scale: Float = 15.03 / sourceLength

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var vertexMap: [OBJVertexKey: UInt32] = [:]

        positions.reserveCapacity(5_000)
        normals.reserveCapacity(5_000)
        indices.reserveCapacity(24_000)

        func resolvedIndex(_ raw: Int, count: Int) -> Int? {
            if raw > 0 {
                let value = raw - 1
                return value < count ? value : nil
            }
            if raw < 0 {
                let value = count + raw
                return value >= 0 && value < count ? value : nil
            }
            return nil
        }

        func vertexIndex(for token: Substring) -> UInt32? {
            let components = token.split(separator: "/", omittingEmptySubsequences: false)
            guard !components.isEmpty,
                  let rawPosition = Int(components[0]),
                  let positionIndex = resolvedIndex(rawPosition, count: sourcePositions.count) else {
                return nil
            }

            var normalIndex = -1
            if components.count >= 3,
               let rawNormal = Int(components[2]),
               let resolvedNormal = resolvedIndex(rawNormal, count: sourceNormals.count) {
                normalIndex = resolvedNormal
            }

            let key = OBJVertexKey(position: positionIndex, normal: normalIndex)
            if let existing = vertexMap[key] {
                return existing
            }

            let newIndex = UInt32(positions.count)
            positions.append(sourcePositions[positionIndex] * scale)
            if normalIndex >= 0 {
                normals.append(sourceNormals[normalIndex])
            } else {
                normals.append([0, 1, 0])
            }
            vertexMap[key] = newIndex
            return newIndex
        }

        for line in lines where line.hasPrefix("f ") {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 4 else { continue }

            var face: [UInt32] = []
            face.reserveCapacity(fields.count - 1)
            for token in fields.dropFirst() {
                guard let index = vertexIndex(for: token) else {
                    face.removeAll(keepingCapacity: true)
                    break
                }
                face.append(index)
            }

            guard face.count >= 3 else { continue }
            for i in 1..<(face.count - 1) {
                indices.append(face[0])
                indices.append(face[i])
                indices.append(face[i + 1])
            }
        }

        guard positions.count >= 3, indices.count >= 3 else {
            throw OBJError.invalidGeometry
        }

        var descriptor = MeshDescriptor(name: "F-16A")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}
