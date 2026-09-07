import Foundation
import RealityKit
import UIKit
import simd

@MainActor
enum PrototypeAircraftFactory {
    static let aircraftName = "FA.aircraft"
    static let visualRootName = "FA.aircraft.visual-root"
    static let meshName = "FA.aircraft.f16.mesh"
    static let afterburnerName = "FA.aircraft.afterburner"
    static let nozzleName = "FA.aircraft.nozzle"
    static let speedbrakeName = "FA.aircraft.speedbrake"
    static let leftAileronName = "FA.aircraft.aileron.left"
    static let rightAileronName = "FA.aircraft.aileron.right"
    static let leftElevatorName = "FA.aircraft.elevator.left"
    static let rightElevatorName = "FA.aircraft.elevator.right"
    static let rudderName = "FA.aircraft.rudder"
    static let noseGearName = "FA.aircraft.gear.nose"
    static let leftGearName = "FA.aircraft.gear.left"
    static let rightGearName = "FA.aircraft.gear.right"
    static let vaporLeftName = "FA.aircraft.vapor.left"
    static let vaporRightName = "FA.aircraft.vapor.right"
    static let contrailLeftName = "FA.aircraft.contrail.left"
    static let contrailRightName = "FA.aircraft.contrail.right"

    /// The source OBJ is centered around its visual bounding box, not the F-16
    /// CG used by JSBSim. JSBSim places the radome only ~0.09 m below the CG,
    /// while the source mesh placed it ~1.02 m below the root. This offset aligns
    /// the visual airframe with the FDM structural/reference coordinates.
    static let visualVerticalOffset: Float = 0.93

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
            let visualRoot = Entity()
            visualRoot.name = visualRootName
            visualRoot.position = [0, visualVerticalOffset, 0]
            root.addChild(visualRoot)

            let mesh = try loadF16Mesh()
            let airframeMaterial = SimpleMaterial(
                color: UIColor(red: 0.39, green: 0.41, blue: 0.42, alpha: 1),
                isMetallic: false
            )
            let model = ModelEntity(mesh: mesh, materials: [airframeMaterial])
            model.name = meshName
            visualRoot.addChild(model)

            addVisualDetail(to: visualRoot)
            addAnimatedSurfaces(to: visualRoot)

            // Landing gear is positioned directly from the F-16 JSBSim contact
            // geometry relative to CG, so it intentionally does not inherit the
            // OBJ-only visualVerticalOffset.
            addLandingGear(to: root)
        } catch {
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
        let canopy = ellipsoid(
            radii: [0.62, 0.38, 1.50],
            color: UIColor(red: 0.045, green: 0.105, blue: 0.135, alpha: 0.94),
            metallic: true
        )
        canopy.name = "FA.aircraft.canopy"
        canopy.position = [0, -0.18, 2.78]
        root.addChild(canopy)

        let radome = ellipsoid(
            radii: [0.34, 0.28, 0.88],
            color: UIColor(red: 0.16, green: 0.18, blue: 0.18, alpha: 1),
            metallic: false
        )
        radome.name = "FA.aircraft.radome"
        radome.position = [0, -1.02, 6.82]
        root.addChild(radome)

        let nozzle = cylinder(
            length: 0.70,
            radius: 0.66,
            color: UIColor(red: 0.16, green: 0.15, blue: 0.14, alpha: 1),
            metallic: true,
            axisAlongZ: true
        )
        nozzle.name = nozzleName
        nozzle.position = [0, -1.14, -7.13]
        root.addChild(nozzle)

        let nozzleCore = cylinder(
            length: 0.80,
            radius: 0.42,
            color: UIColor(red: 0.022, green: 0.022, blue: 0.025, alpha: 1),
            metallic: false,
            axisAlongZ: true
        )
        nozzleCore.position = [0, -1.14, -7.31]
        root.addChild(nozzleCore)

        let afterburner = ellipsoid(
            radii: [0.40, 0.40, 1.65],
            color: UIColor(red: 1.0, green: 0.38, blue: 0.055, alpha: 0.72),
            metallic: false
        )
        afterburner.name = afterburnerName
        afterburner.position = [0, -1.14, -8.45]
        afterburner.isEnabled = false
        root.addChild(afterburner)

        addNavigationLight(
            to: root,
            name: "FA.aircraft.nav.left",
            position: [-5.03, -1.34, -2.35],
            color: UIColor(red: 0.98, green: 0.08, blue: 0.08, alpha: 1)
        )
        addNavigationLight(
            to: root,
            name: "FA.aircraft.nav.right",
            position: [5.03, -1.34, -2.35],
            color: UIColor(red: 0.08, green: 0.96, blue: 0.24, alpha: 1)
        )
        addNavigationLight(
            to: root,
            name: "FA.aircraft.nav.tail",
            position: [0, -0.40, -7.25],
            color: UIColor(white: 0.98, alpha: 1)
        )
    }

    private static func addAnimatedSurfaces(to root: Entity) {
        // Stage 010.6: these overlays are laid out around the rendered OBJ's
        // trailing-edge geometry instead of generic F-16 dimensions. The source
        // OBJ is welded, so the movable panels remain separate hinge children,
        // but their pivots now sit on the visible wing/tail planform.
        let panelColor = UIColor(red: 0.335, green: 0.35, blue: 0.36, alpha: 1)

        let speedbrake = Entity()
        speedbrake.name = speedbrakeName
        speedbrake.position = [0, -0.28, -4.00]
        if let leftMesh = makeHorizontalSurfaceMesh(
            outline: [[-1.10, 0.00], [-0.18, 0.00], [-0.22, -0.78], [-0.98, -0.62]],
            thickness: 0.026
        ) {
            let left = ModelEntity(mesh: leftMesh, materials: [SimpleMaterial(color: panelColor, isMetallic: false)])
            speedbrake.addChild(left)
        }
        if let rightMesh = makeHorizontalSurfaceMesh(
            outline: [[0.18, 0.00], [1.10, 0.00], [0.98, -0.62], [0.22, -0.78]],
            thickness: 0.026
        ) {
            let right = ModelEntity(mesh: rightMesh, materials: [SimpleMaterial(color: panelColor, isMetallic: false)])
            speedbrake.addChild(right)
        }
        root.addChild(speedbrake)

        // Flaperons: the previous hinge at z=-2.12 sat visibly forward of the
        // OBJ trailing edge. Move the hinge aft and use the measured taper of the
        // rendered wing so deflection reads as part of the airplane, not a flap
        // floating over the wing.
        root.addChild(horizontalHingedSurface(
            name: leftAileronName,
            hingePosition: [-3.42, -1.12, -3.58],
            outline: [
                [-0.90, 0.00],
                [0.78, 0.00],
                [0.61, -0.69],
                [-0.82, -0.57]
            ],
            color: panelColor
        ))
        root.addChild(horizontalHingedSurface(
            name: rightAileronName,
            hingePosition: [3.42, -1.12, -3.58],
            outline: [
                [-0.78, 0.00],
                [0.90, 0.00],
                [0.82, -0.57],
                [-0.61, -0.69]
            ],
            color: panelColor
        ))

        // The F-16 uses all-moving horizontal tails. Root the complete tail
        // panels on their hinge line and let the JSBSim differential-tail output
        // rotate the entire surface.
        root.addChild(horizontalHingedSurface(
            name: leftElevatorName,
            hingePosition: [-1.55, -0.94, -5.05],
            outline: [
                [-1.58, 0.00],
                [0.90, 0.00],
                [0.58, -1.60],
                [-1.25, -1.34]
            ],
            color: panelColor
        ))
        root.addChild(horizontalHingedSurface(
            name: rightElevatorName,
            hingePosition: [1.55, -0.94, -5.05],
            outline: [
                [-0.90, 0.00],
                [1.58, 0.00],
                [1.25, -1.34],
                [-0.58, -1.60]
            ],
            color: panelColor
        ))

        root.addChild(verticalHingedSurface(
            name: rudderName,
            hingePosition: [0, 0.02, -5.62],
            outline: [
                [0.04, 0.00],
                [2.00, 0.08],
                [1.70, -1.02],
                [0.18, -1.10]
            ],
            color: panelColor
        ))
    }

    private static func addLandingGear(to root: Entity) {
        let strutColor = UIColor(red: 0.72, green: 0.73, blue: 0.71, alpha: 1)
        let tireColor = UIColor(red: 0.025, green: 0.025, blue: 0.026, alpha: 1)

        // JSBSim F-16 contact geometry, converted from structural inches to
        // visual meters relative to CG. +Z in Full Authority is nose-forward.
        root.addChild(gearAssembly(
            name: noseGearName,
            rootPosition: [0, -0.33, 2.71],
            strutHeight: 1.12,
            wheelRadius: 0.25,
            wheelWidth: 0.20,
            strutColor: strutColor,
            tireColor: tireColor
        ))
        root.addChild(gearAssembly(
            name: leftGearName,
            rootPosition: [-1.22, -0.38, -0.87],
            strutHeight: 1.00,
            wheelRadius: 0.31,
            wheelWidth: 0.24,
            strutColor: strutColor,
            tireColor: tireColor
        ))
        root.addChild(gearAssembly(
            name: rightGearName,
            rootPosition: [1.22, -0.38, -0.87],
            strutHeight: 1.00,
            wheelRadius: 0.31,
            wheelWidth: 0.24,
            strutColor: strutColor,
            tireColor: tireColor
        ))
    }

    private static func horizontalHingedSurface(
        name: String,
        hingePosition: SIMD3<Float>,
        outline: [SIMD2<Float>],
        color: UIColor
    ) -> Entity {
        let hinge = Entity()
        hinge.name = name
        hinge.position = hingePosition
        if let mesh = makeHorizontalSurfaceMesh(outline: outline, thickness: 0.034) {
            let panel = ModelEntity(
                mesh: mesh,
                materials: [SimpleMaterial(color: color, isMetallic: false)]
            )
            hinge.addChild(panel)
        }
        return hinge
    }

    private static func verticalHingedSurface(
        name: String,
        hingePosition: SIMD3<Float>,
        outline: [SIMD2<Float>],
        color: UIColor
    ) -> Entity {
        let hinge = Entity()
        hinge.name = name
        hinge.position = hingePosition
        if let mesh = makeVerticalSurfaceMesh(outline: outline, thickness: 0.034) {
            let panel = ModelEntity(
                mesh: mesh,
                materials: [SimpleMaterial(color: color, isMetallic: false)]
            )
            hinge.addChild(panel)
        }
        return hinge
    }

    /// Outline coordinates are (spanwise X, chordwise Z), with Z=0 on the hinge
    /// and negative Z extending aft. Two faces give the panel visible thickness
    /// without relying on RealityKit primitive boxes.
    private static func makeHorizontalSurfaceMesh(
        outline: [SIMD2<Float>],
        thickness: Float
    ) -> MeshResource? {
        guard outline.count >= 3 else { return nil }
        let half = thickness * 0.5
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for point in outline {
            positions.append([point.x, half, point.y])
            normals.append([0, 1, 0])
        }
        for point in outline {
            positions.append([point.x, -half, point.y])
            normals.append([0, -1, 0])
        }

        let count = UInt32(outline.count)
        for index in 1..<(outline.count - 1) {
            indices.append(contentsOf: [0, UInt32(index), UInt32(index + 1)])
            indices.append(contentsOf: [count, count + UInt32(index + 1), count + UInt32(index)])
        }

        var descriptor = MeshDescriptor(name: "F-16 horizontal control surface")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    /// Outline coordinates are (vertical Y, chordwise Z), with Z=0 on the
    /// vertical hinge. Faces are duplicated on either side of the fin plane.
    private static func makeVerticalSurfaceMesh(
        outline: [SIMD2<Float>],
        thickness: Float
    ) -> MeshResource? {
        guard outline.count >= 3 else { return nil }
        let half = thickness * 0.5
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for point in outline {
            positions.append([half, point.x, point.y])
            normals.append([1, 0, 0])
        }
        for point in outline {
            positions.append([-half, point.x, point.y])
            normals.append([-1, 0, 0])
        }

        let count = UInt32(outline.count)
        for index in 1..<(outline.count - 1) {
            indices.append(contentsOf: [0, UInt32(index), UInt32(index + 1)])
            indices.append(contentsOf: [count, count + UInt32(index + 1), count + UInt32(index)])
        }

        var descriptor = MeshDescriptor(name: "F-16 vertical control surface")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    private static func gearAssembly(
        name: String,
        rootPosition: SIMD3<Float>,
        strutHeight: Float,
        wheelRadius: Float,
        wheelWidth: Float,
        strutColor: UIColor,
        tireColor: UIColor
    ) -> Entity {
        let assembly = Entity()
        assembly.name = name
        assembly.position = rootPosition

        let upperStrut = ModelEntity(
            mesh: .generateCylinder(height: strutHeight, radius: 0.068),
            materials: [SimpleMaterial(color: strutColor, isMetallic: true)]
        )
        upperStrut.position = [0, -strutHeight * 0.5, 0]
        assembly.addChild(upperStrut)

        let fork = ModelEntity(
            mesh: .generateBox(size: [wheelWidth + 0.10, 0.10, 0.10], cornerRadius: 0.03),
            materials: [SimpleMaterial(color: strutColor, isMetallic: true)]
        )
        fork.position = [0, -strutHeight + 0.03, 0]
        assembly.addChild(fork)

        let wheel = ModelEntity(
            mesh: .generateCylinder(height: wheelWidth, radius: wheelRadius),
            materials: [SimpleMaterial(color: tireColor, isMetallic: false)]
        )
        wheel.position = [0, -strutHeight, 0]
        wheel.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        assembly.addChild(wheel)

        return assembly
    }

    private static func addNavigationLight(
        to root: Entity,
        name: String,
        position: SIMD3<Float>,
        color: UIColor
    ) {
        let light = ModelEntity(
            mesh: .generateSphere(radius: 0.085),
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
        metallic: Bool,
        axisAlongZ: Bool
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateCylinder(height: length, radius: radius),
            materials: [SimpleMaterial(color: color, isMetallic: metallic)]
        )
        if axisAlongZ {
            entity.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        }
        return entity
    }

    /// Loads the pinned MIT-licensed F-16 OBJ staged by CI and converts it into
    /// one RealityKit mesh. The mesh is scaled to the real F-16A length.
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
