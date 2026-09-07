import Foundation
import RealityKit
import UIKit
import simd

@MainActor
enum PrototypeAircraftFactory {
    static let aircraftName = "FA.aircraft"
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
                color: UIColor(red: 0.46, green: 0.48, blue: 0.48, alpha: 1),
                isMetallic: false
            )
            let model = ModelEntity(mesh: mesh, materials: [airframeMaterial])
            model.name = meshName
            root.addChild(model)

            addVisualDetail(to: root)
            addAnimatedSurfaces(to: root)
            addLandingGear(to: root)
            addFlightEffects(to: root)
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
        let panelColor = UIColor(red: 0.37, green: 0.39, blue: 0.39, alpha: 1)

        let speedbrake = ModelEntity(
            mesh: .generateBox(size: [1.12, 0.055, 1.25], cornerRadius: 0.06),
            materials: [SimpleMaterial(color: panelColor, isMetallic: false)]
        )
        speedbrake.name = speedbrakeName
        speedbrake.position = [0, 0.08, -2.38]
        root.addChild(speedbrake)

        let leftAileron = surfacePanel(
            name: leftAileronName,
            size: [1.85, 0.05, 0.52],
            position: [-3.55, -1.02, -2.55],
            color: panelColor
        )
        root.addChild(leftAileron)

        let rightAileron = surfacePanel(
            name: rightAileronName,
            size: [1.85, 0.05, 0.52],
            position: [3.55, -1.02, -2.55],
            color: panelColor
        )
        root.addChild(rightAileron)

        let leftElevator = surfacePanel(
            name: leftElevatorName,
            size: [1.95, 0.055, 0.72],
            position: [-1.72, -0.88, -5.02],
            color: panelColor
        )
        root.addChild(leftElevator)

        let rightElevator = surfacePanel(
            name: rightElevatorName,
            size: [1.95, 0.055, 0.72],
            position: [1.72, -0.88, -5.02],
            color: panelColor
        )
        root.addChild(rightElevator)

        let rudder = ModelEntity(
            mesh: .generateBox(size: [0.07, 1.45, 0.78], cornerRadius: 0.04),
            materials: [SimpleMaterial(color: panelColor, isMetallic: false)]
        )
        rudder.name = rudderName
        rudder.position = [0, 0.12, -5.45]
        root.addChild(rudder)
    }

    private static func addLandingGear(to root: Entity) {
        let strutColor = UIColor(red: 0.68, green: 0.69, blue: 0.67, alpha: 1)
        let tireColor = UIColor(red: 0.035, green: 0.035, blue: 0.035, alpha: 1)

        root.addChild(gearAssembly(
            name: noseGearName,
            rootPosition: [0, -0.45, 3.45],
            strutHeight: 1.12,
            wheelRadius: 0.25,
            strutColor: strutColor,
            tireColor: tireColor
        ))
        root.addChild(gearAssembly(
            name: leftGearName,
            rootPosition: [-1.35, -0.48, -1.05],
            strutHeight: 1.00,
            wheelRadius: 0.31,
            strutColor: strutColor,
            tireColor: tireColor
        ))
        root.addChild(gearAssembly(
            name: rightGearName,
            rootPosition: [1.35, -0.48, -1.05],
            strutHeight: 1.00,
            wheelRadius: 0.31,
            strutColor: strutColor,
            tireColor: tireColor
        ))
    }

    private static func addFlightEffects(to root: Entity) {
        let vaporColor = UIColor(red: 0.92, green: 0.96, blue: 1.0, alpha: 0.24)

        let leftVapor = ellipsoid(radii: [0.22, 0.08, 2.4], color: vaporColor, metallic: false)
        leftVapor.name = vaporLeftName
        leftVapor.position = [-3.75, -1.0, -4.5]
        leftVapor.isEnabled = false
        root.addChild(leftVapor)

        let rightVapor = ellipsoid(radii: [0.22, 0.08, 2.4], color: vaporColor, metallic: false)
        rightVapor.name = vaporRightName
        rightVapor.position = [3.75, -1.0, -4.5]
        rightVapor.isEnabled = false
        root.addChild(rightVapor)

        let contrailColor = UIColor(red: 0.95, green: 0.97, blue: 1.0, alpha: 0.18)
        let leftContrail = ellipsoid(radii: [0.12, 0.12, 7.0], color: contrailColor, metallic: false)
        leftContrail.name = contrailLeftName
        leftContrail.position = [-1.15, -1.10, -13.3]
        leftContrail.isEnabled = false
        root.addChild(leftContrail)

        let rightContrail = ellipsoid(radii: [0.12, 0.12, 7.0], color: contrailColor, metallic: false)
        rightContrail.name = contrailRightName
        rightContrail.position = [1.15, -1.10, -13.3]
        rightContrail.isEnabled = false
        root.addChild(rightContrail)
    }

    private static func surfacePanel(
        name: String,
        size: SIMD3<Float>,
        position: SIMD3<Float>,
        color: UIColor
    ) -> ModelEntity {
        let panel = ModelEntity(
            mesh: .generateBox(size: size, cornerRadius: 0.04),
            materials: [SimpleMaterial(color: color, isMetallic: false)]
        )
        panel.name = name
        panel.position = position
        return panel
    }

    private static func gearAssembly(
        name: String,
        rootPosition: SIMD3<Float>,
        strutHeight: Float,
        wheelRadius: Float,
        strutColor: UIColor,
        tireColor: UIColor
    ) -> Entity {
        let assembly = Entity()
        assembly.name = name
        assembly.position = rootPosition

        let strut = ModelEntity(
            mesh: .generateCylinder(height: strutHeight, radius: 0.055),
            materials: [SimpleMaterial(color: strutColor, isMetallic: true)]
        )
        strut.position = [0, -strutHeight * 0.5, 0]
        assembly.addChild(strut)

        let wheel = ModelEntity(
            mesh: .generateCylinder(height: 0.18, radius: wheelRadius),
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
