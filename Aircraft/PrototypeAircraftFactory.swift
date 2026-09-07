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
    static let afterburnerInnerName = "FA.aircraft.afterburner.inner"
    static let afterburnerOuterName = "FA.aircraft.afterburner.outer"
    static let nozzleName = "FA.aircraft.nozzle"
    static let nozzleGlowName = "FA.aircraft.nozzle.glow"
    static let speedbrakeName = "FA.aircraft.speedbrake"
    static let speedbrakeLeftUpperName = "FA.aircraft.speedbrake.left.upper"
    static let speedbrakeLeftLowerName = "FA.aircraft.speedbrake.left.lower"
    static let speedbrakeRightUpperName = "FA.aircraft.speedbrake.right.upper"
    static let speedbrakeRightLowerName = "FA.aircraft.speedbrake.right.lower"
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

    // vazgriz/FlightSim_F16 source FBX is already essentially full scale.
    // Unlike the retired R4 OBJ, it has a sensible authored origin and exact
    // skinned control-surface pivots, so no visual CG fudge offset is required.
    static let visualVerticalOffset: Float = 0

    // These axes come from the source FBX's actual neutral -> deflected animation
    // transforms, not bone display vectors and not inferred geometry.
    static let leftAileronVisualAxis = simd_normalize(SIMD3<Float>(0.991671, 0.0, 0.128796))
    static let rightAileronVisualAxis = simd_normalize(SIMD3<Float>(0.991671, 0.0, -0.128796))
    static let leftStabilatorVisualAxis = SIMD3<Float>(1, 0, 0)
    static let rightStabilatorVisualAxis = SIMD3<Float>(1, 0, 0)
    static let rudderVisualAxis = simd_normalize(SIMD3<Float>(-0.002254, 0.842883, -0.538092))
    static let speedbrakeUpperVisualAxis = SIMD3<Float>(-1, 0, 0)
    static let speedbrakeLowerVisualAxis = SIMD3<Float>(1, 0, 0)

    static let authoredAileronLimitRadians: Float = 0.37524614
    static let authoredStabilatorLimitRadians: Float = 0.43633232
    static let authoredRudderLimitRadians: Float = 0.52360028
    static let authoredSpeedbrakeLimitRadians: Float = 0.78539801

    private enum AssetError: Error {
        case missing(String)
        case invalid(String)
    }

    private struct ParsedVertex {
        let position: SIMD3<Float>
        let normal: SIMD3<Float>
    }

    static func make() -> Entity {
        let aircraft = Entity()
        aircraft.name = aircraftName

        do {
            let visualRoot = Entity()
            visualRoot.name = visualRootName
            visualRoot.position = [0, visualVerticalOffset, 0]
            aircraft.addChild(visualRoot)

            let airframeMaterial = SimpleMaterial(
                color: UIColor(red: 0.47, green: 0.49, blue: 0.50, alpha: 1),
                roughness: 0.63,
                isMetallic: false
            )
            let controlMaterial = SimpleMaterial(
                color: UIColor(red: 0.455, green: 0.475, blue: 0.485, alpha: 1),
                roughness: 0.66,
                isMetallic: false
            )

            let body = ModelEntity(mesh: try loadAuthoredOBJ("f16_static"), materials: [airframeMaterial])
            body.name = meshName
            visualRoot.addChild(body)

            try addMovingPart(
                to: visualRoot,
                name: leftAileronName,
                file: "left_flaperon",
                pivot: [-2.437150, 0.0, -2.113479],
                material: controlMaterial
            )
            try addMovingPart(
                to: visualRoot,
                name: rightAileronName,
                file: "right_flaperon",
                pivot: [2.437146, 0.0, -2.113479],
                material: controlMaterial
            )
            try addMovingPart(
                to: visualRoot,
                name: leftElevatorName,
                file: "left_stabilator",
                pivot: [-1.103110, 0.0, -5.102210],
                material: controlMaterial
            )
            try addMovingPart(
                to: visualRoot,
                name: rightElevatorName,
                file: "right_stabilator",
                pivot: [1.103107, 0.0, -5.102214],
                material: controlMaterial
            )
            try addMovingPart(
                to: visualRoot,
                name: rudderName,
                file: "rudder",
                pivot: [0.0, 2.250000, -5.737493],
                material: controlMaterial
            )

            try addMovingPart(
                to: visualRoot,
                name: speedbrakeLeftUpperName,
                file: "airbrake_left_upper",
                pivot: [-0.926553, 0.0, -5.227214],
                material: controlMaterial
            )
            try addMovingPart(
                to: visualRoot,
                name: speedbrakeLeftLowerName,
                file: "airbrake_left_lower",
                pivot: [-0.926553, 0.0, -5.227214],
                material: controlMaterial
            )
            try addMovingPart(
                to: visualRoot,
                name: speedbrakeRightUpperName,
                file: "airbrake_right_upper",
                pivot: [0.926553, 0.0, -5.227214],
                material: controlMaterial
            )
            try addMovingPart(
                to: visualRoot,
                name: speedbrakeRightLowerName,
                file: "airbrake_right_lower",
                pivot: [0.926553, 0.0, -5.227214],
                material: controlMaterial
            )

            // The authored static F-16 mesh already contains the exhaust/nozzle.
            // Do not cover it with a generated cylinder or sphere overlay.
            try addAfterburner(to: visualRoot)
            addLandingGear(to: aircraft)
        } catch {
            let fallback = ModelEntity(
                mesh: .generateBox(size: [4, 1, 10], cornerRadius: 0.2),
                materials: [SimpleMaterial(color: .red, isMetallic: false)]
            )
            fallback.name = "FA.aircraft.authored-f16-load-failed"
            aircraft.addChild(fallback)
        }

        return aircraft
    }

    private static func addMovingPart(
        to root: Entity,
        name: String,
        file: String,
        pivot: SIMD3<Float>,
        material: SimpleMaterial
    ) throws {
        let hinge = Entity()
        hinge.name = name
        hinge.position = pivot
        let model = ModelEntity(mesh: try loadAuthoredOBJ(file), materials: [material])
        model.name = "\(name).mesh"
        hinge.addChild(model)
        root.addChild(hinge)
    }

    private static func addAfterburner(to root: Entity) throws {
        let plumeMesh = try loadAuthoredOBJ("afterburner_plume")
        let plume = Entity()
        plume.name = afterburnerName
        plume.position = [0, -0.16, -7.03]
        plume.isEnabled = false

        // The authored afterburner FBX's long axis imports as local +Y while
        // Full Authority's aircraft points forward along +Z. Rotate the mesh
        // children so +Y becomes -Z (dead aft) while leaving the plume parent
        // unrotated; the runtime can then continue using parent Z scale as its
        // longitudinal intensity/length axis.
        let aftRotation = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))

        let outer = ModelEntity(
            mesh: plumeMesh,
            materials: [SimpleMaterial(
                color: UIColor(red: 0.16, green: 0.40, blue: 1.0, alpha: 0.26),
                isMetallic: false
            )]
        )
        outer.name = afterburnerOuterName
        outer.orientation = aftRotation
        plume.addChild(outer)

        let inner = ModelEntity(
            mesh: plumeMesh,
            materials: [SimpleMaterial(
                color: UIColor(red: 0.73, green: 0.88, blue: 1.0, alpha: 0.43),
                isMetallic: false
            )]
        )
        inner.name = afterburnerInnerName
        inner.orientation = aftRotation
        inner.scale = [0.55, 0.72, 0.55]
        plume.addChild(inner)

        // No generated sphere "shock diamonds" here. The authored plume envelope
        // is the only afterburner geometry, so chase view cannot expose round blobs.
        root.addChild(plume)
    }

    private static func addLandingGear(to root: Entity) {
        let strutColor = UIColor(red: 0.72, green: 0.73, blue: 0.71, alpha: 1)
        let tireColor = UIColor(red: 0.025, green: 0.025, blue: 0.026, alpha: 1)
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

        let strut = ModelEntity(
            mesh: .generateCylinder(height: strutHeight, radius: 0.068),
            materials: [SimpleMaterial(color: strutColor, isMetallic: true)]
        )
        strut.position = [0, -strutHeight * 0.5, 0]
        assembly.addChild(strut)

        let wheel = ModelEntity(
            mesh: .generateCylinder(height: wheelWidth, radius: wheelRadius),
            materials: [SimpleMaterial(color: tireColor, isMetallic: false)]
        )
        wheel.position = [0, -strutHeight, 0]
        wheel.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        assembly.addChild(wheel)
        return assembly
    }

    private static func loadAuthoredOBJ(_ name: String) throws -> MeshResource {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "obj",
            subdirectory: "JSBSim/visuals/f16"
        ) else {
            throw AssetError.missing(name)
        }

        let source = try String(contentsOf: url, encoding: .utf8)
        let lines = source.split(whereSeparator: \.isNewline)
        var sourcePositions: [SIMD3<Float>] = []
        var sourceNormals: [SIMD3<Float>] = []
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for line in lines {
            if line.hasPrefix("v ") {
                let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if f.count >= 4, let x = Float(f[1]), let y = Float(f[2]), let z = Float(f[3]) {
                    sourcePositions.append([x, y, z])
                }
            } else if line.hasPrefix("vn ") {
                let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if f.count >= 4, let x = Float(f[1]), let y = Float(f[2]), let z = Float(f[3]) {
                    let n = SIMD3<Float>(x, y, z)
                    sourceNormals.append(simd_length_squared(n) > 0 ? simd_normalize(n) : SIMD3<Float>(0, 1, 0))
                }
            }
        }

        func resolved(_ raw: Int, count: Int) -> Int? {
            if raw > 0 { let i = raw - 1; return i < count ? i : nil }
            if raw < 0 { let i = count + raw; return i >= 0 && i < count ? i : nil }
            return nil
        }

        func vertex(_ token: Substring) -> ParsedVertex? {
            let c = token.split(separator: "/", omittingEmptySubsequences: false)
            guard let rawP = c.first.flatMap({ Int($0) }),
                  let pi = resolved(rawP, count: sourcePositions.count) else { return nil }
            var normal = SIMD3<Float>(0, 1, 0)
            if c.count >= 3, let rawN = Int(c[2]), let ni = resolved(rawN, count: sourceNormals.count) {
                normal = sourceNormals[ni]
            }
            return ParsedVertex(position: sourcePositions[pi], normal: normal)
        }

        for line in lines where line.hasPrefix("f ") {
            let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard f.count >= 4 else { continue }
            let face = f.dropFirst().compactMap(vertex)
            guard face.count == f.count - 1, face.count >= 3 else { continue }
            for i in 1..<(face.count - 1) {
                for v in [face[0], face[i], face[i + 1]] {
                    indices.append(UInt32(positions.count))
                    positions.append(v.position)
                    normals.append(v.normal)
                }
            }
        }

        guard positions.count >= 3, indices.count >= 3 else {
            throw AssetError.invalid(name)
        }

        var descriptor = MeshDescriptor(name: "Authored F-16 \(name)")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}
