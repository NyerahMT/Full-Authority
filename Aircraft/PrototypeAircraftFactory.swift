import Foundation
import RealityKit
import UIKit
import simd

@MainActor
enum PrototypeAircraftFactory {
    static let aircraftName = "FA.aircraft"
    static let afterburnerName = "FA.aircraft.afterburner"
    static let nozzleName = "FA.aircraft.nozzle"

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
            let airframeMaterial = SimpleMaterial(
                color: UIColor(red: 0.43, green: 0.46, blue: 0.47, alpha: 1),
                isMetallic: false
            )
            let model = ModelEntity(mesh: mesh, materials: [airframeMaterial])
            model.name = "FA.aircraft.f16.mesh"
            root.addChild(model)

            addVisualDetail(to: root)
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

    private static func addVisualDetail(to root: Entity) {
        // The source OBJ has a strong silhouette but no material separation. These
        // inexpensive overlays restore the features that matter most from chase view.
        let canopy = ellipsoid(
            radii: [0.62, 0.38, 1.50],
            color: UIColor(red: 0.055, green: 0.12, blue: 0.15, alpha: 0.93),
            metallic: true
        )
        canopy.name = "FA.aircraft.canopy"
        canopy.position = [0, -0.18, 2.78]
        root.addChild(canopy)

        let radome = ellipsoid(
            radii: [0.34, 0.28, 0.88],
            color: UIColor(red: 0.18, green: 0.20, blue: 0.20, alpha: 1),
            metallic: false
        )
        radome.name = "FA.aircraft.radome"
        radome.position = [0, -1.02, 6.82]
        root.addChild(radome)

        let nozzle = cylinder(
            length: 0.70,
            radius: 0.66,
            color: UIColor(red: 0.17, green: 0.16, blue: 0.15, alpha: 1),
            metallic: true
        )
        nozzle.name = nozzleName
        nozzle.position = [0, -1.14, -7.13]
        root.addChild(nozzle)

        let nozzleCore = cylinder(
            length: 0.76,
            radius: 0.43,
            color: UIColor(red: 0.025, green: 0.025, blue: 0.028, alpha: 1),
            metallic: false
        )
        nozzleCore.position = [0, -1.14, -7.27]
        root.addChild(nozzleCore)

        // This is deliberately geometry rather than a fake force effect. The scene
        // controller only scales it from the real throttle command.
        let afterburner = ellipsoid(
            radii: [0.40, 0.40, 1.65],
            color: UIColor(red: 1.0, green: 0.43, blue: 0.08, alpha: 0.72),
            metallic: false
        )
        afterburner.name = afterburnerName
        afterburner.position = [0, -1.14, -8.25]
        afterburner.isEnabled = false
        root.addChild(afterburner)

        addNavigationLight(
            to: root,
            name: "FA.aircraft.nav.left",
            position: [-5.03, -1.34, -2.35],
            color: UIColor(red: 0.96, green: 0.12, blue: 0.10, alpha: 1)
        )
        addNavigationLight(
            to: root,
            name: "FA.aircraft.nav.right",
            position: [5.03, -1.34, -2.35],
            color: UIColor(red: 0.14, green: 0.95, blue: 0.30, alpha: 1)
        )
        addNavigationLight(
            to: root,
            name: "FA.aircraft.nav.tail",
            position: [0, -0.40, -7.25],
            color: UIColor(white: 0.98, alpha: 1)
        )
    }

    private static func addNavigationLight(
        to root: Entity,
        name: String,
        position: SIMD3<Float>,
        color: UIColor
    ) {
        let light = ModelEntity(
            mesh: .generateSphere(radius: 0.11),
            materials: [SimpleMaterial(color: color, isMetallic: false)]
        )
        light.name = name
        light.position = position
        root.addChild(light)
    }

    private static func ellipsoid(
        radii: SIMD3<Float>,
        color: UIColor,
        metallic: Bool
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateSphere(radius: 1),
            materials: [SimpleMaterial(color: color, isMetallic: metallic)]
        )
        entity.scale = radii
        return entity
    }

    private static func cylinder(
        length: Float,
        radius: Float,
        color: UIColor,
        metallic: Bool
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateCylinder(height: length, radius: radius),
            materials: [SimpleMaterial(color: color, isMetallic: metallic)]
        )
        entity.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        return entity
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
        // to the real F-16A length (49 ft 4 in / 15.03 m).
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
