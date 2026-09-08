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
    static let afterburnerCoreName = "FA.aircraft.afterburner.core"
    static let afterburnerHaloName = "FA.aircraft.afterburner.halo"
    static let afterburnerShockPrefix = "FA.aircraft.afterburner.shock."
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

    static let visualVerticalOffset: Float = 0

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

    private enum Paint: UInt32 {
        case upper = 0
        case lower = 1
        case radome = 2
        case canopy = 3
        case exhaust = 4
        case intake = 5
    }

    private struct ParsedVertex {
        let position: SIMD3<Float>
        let normal: SIMD3<Float>
        let uv: SIMD2<Float>
    }

    static func make() -> Entity {
        let aircraft = Entity()
        aircraft.name = aircraftName

        do {
            let visualRoot = Entity()
            visualRoot.name = visualRootName
            visualRoot.position = [0, visualVerticalOffset, 0]
            aircraft.addChild(visualRoot)

            let materials = try makeF16Materials()
            let body = ModelEntity(
                mesh: try loadAuthoredOBJ("f16_static", classifyF16Paint: true),
                materials: materials
            )
            body.name = meshName
            visualRoot.addChild(body)

            let controlMaterial = materials[Int(Paint.upper.rawValue)]
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

    private static func makeF16Materials() throws -> [PhysicallyBasedMaterial] {
        // The bundled 32x32 f16.png is mostly transparent alpha. Feeding it
        // directly into RealityKit's PBR base color makes most exterior texels
        // transparent, which exposes the inside/back faces of the aircraft.
        // Keep the authored UVs in the mesh for a future real livery, but use
        // fully opaque zoned materials until we have an opaque texture atlas.
        func material(
            _ tint: UIColor,
            roughness: Float,
            metallic: Float
        ) -> PhysicallyBasedMaterial {
            var result = PhysicallyBasedMaterial()
            result.baseColor = .init(tint: tint)
            result.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: roughness)
            result.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: metallic)
            return result
        }

        return [
            material(UIColor(red: 0.33, green: 0.35, blue: 0.36, alpha: 1), roughness: 0.74, metallic: 0.02),
            material(UIColor(red: 0.50, green: 0.52, blue: 0.53, alpha: 1), roughness: 0.78, metallic: 0.01),
            material(UIColor(red: 0.22, green: 0.23, blue: 0.23, alpha: 1), roughness: 0.82, metallic: 0.00),
            material(UIColor(red: 0.075, green: 0.105, blue: 0.125, alpha: 1), roughness: 0.10, metallic: 0.24),
            material(UIColor(red: 0.20, green: 0.19, blue: 0.17, alpha: 1), roughness: 0.34, metallic: 0.92),
            material(UIColor(red: 0.42, green: 0.44, blue: 0.45, alpha: 1), roughness: 0.68, metallic: 0.02)
        ]
    }

    private static func addMovingPart(
        to root: Entity,
        name: String,
        file: String,
        pivot: SIMD3<Float>,
        material: PhysicallyBasedMaterial
    ) throws {
        let hinge = Entity()
        hinge.name = name
        hinge.position = pivot

        let model = ModelEntity(
            mesh: try loadAuthoredOBJ(file),
            materials: [material]
        )
        model.name = "\(name).mesh"
        hinge.addChild(model)
        root.addChild(hinge)
    }

    private static func addAfterburner(to root: Entity) throws {
        let plumeMesh = try loadAuthoredOBJ("afterburner_plume")
        let plume = Entity()
        plume.name = afterburnerName

        // The visual root and the authored F-16 use the same coordinate frame.
        // The source plume mesh itself begins 0.5 m down its local axis, so each
        // envelope layer gets a +0.5 m Z compensation after rotation. That puts
        // the first luminous texels directly on the physical nozzle lip instead
        // of leaving the half-meter gap visible in the chase camera.
        plume.position = [0, 0, -7.025]
        plume.isEnabled = false

        let aftRotation = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        let halo = ModelEntity(
            mesh: plumeMesh,
            materials: [UnlitMaterial(color: UIColor(
                red: 0.82,
                green: 0.10,
                blue: 0.025,
                alpha: 0.15
            ))]
        )
        halo.name = afterburnerHaloName
        halo.orientation = aftRotation
        halo.scale = [1.15, 2.15, 1.15]
        halo.position = [0, 0, 0.5 * halo.scale.y]
        plume.addChild(halo)

        let outer = ModelEntity(
            mesh: plumeMesh,
            materials: [UnlitMaterial(color: UIColor(
                red: 1.0,
                green: 0.24,
                blue: 0.035,
                alpha: 0.34
            ))]
        )
        outer.name = afterburnerOuterName
        outer.orientation = aftRotation
        outer.scale = [0.94, 1.90, 1.02]
        outer.position = [0, 0, 0.5 * outer.scale.y]
        plume.addChild(outer)

        let inner = ModelEntity(
            mesh: plumeMesh,
            materials: [UnlitMaterial(color: UIColor(
                red: 1.0,
                green: 0.52,
                blue: 0.075,
                alpha: 0.56
            ))]
        )
        inner.name = afterburnerInnerName
        inner.orientation = aftRotation
        inner.scale = [0.58, 1.52, 0.66]
        inner.position = [0, 0, 0.5 * inner.scale.y]
        plume.addChild(inner)

        let core = ModelEntity(
            mesh: plumeMesh,
            materials: [UnlitMaterial(color: UIColor(
                red: 1.0,
                green: 0.88,
                blue: 0.48,
                alpha: 0.86
            ))]
        )
        core.name = afterburnerCoreName
        core.orientation = aftRotation
        core.scale = [0.24, 1.12, 0.30]
        core.position = [0, 0, 0.5 * core.scale.y]
        plume.addChild(core)

        // Thin pressure cells live *inside* the flame envelope. These are not
        // the old detached sphere blobs: from the side they read as soft bands
        // in the plume and disappear with the burner.
        let shockZ: [Float] = [-0.68, -1.36, -2.10, -2.92, -3.82]
        let shockR: [Float] = [0.24, 0.215, 0.19, 0.165, 0.14]
        for index in shockZ.indices {
            let cell = ModelEntity(
                mesh: .generateCylinder(height: 0.030, radius: shockR[index]),
                materials: [UnlitMaterial(color: UIColor(
                    red: 1.0,
                    green: 0.66,
                    blue: 0.20,
                    alpha: CGFloat(max(0.055, 0.15 - Float(index) * 0.020))
                ))]
            )
            cell.name = afterburnerShockPrefix + String(index)
            cell.position = [0, 0, shockZ[index]]
            cell.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
            cell.isEnabled = false
            plume.addChild(cell)
        }

        root.addChild(plume)

        // Keep nozzle incandescence outside the AB hierarchy so high dry power
        // can still show a hot turbine/nozzle core when the flame is off.
        let glow = ModelEntity(
            mesh: .generateCylinder(height: 0.032, radius: 0.455),
            materials: [UnlitMaterial(color: UIColor(
                red: 1.0,
                green: 0.30,
                blue: 0.055,
                alpha: 0.56
            ))]
        )
        glow.name = nozzleGlowName
        glow.position = [0, 0, -7.030]
        glow.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        glow.isEnabled = false
        root.addChild(glow)
    }

    private static func addLandingGear(to root: Entity) {
        let strutColor = UIColor(red: 0.74, green: 0.75, blue: 0.73, alpha: 1)
        let chromeColor = UIColor(red: 0.88, green: 0.90, blue: 0.91, alpha: 1)
        let tireColor = UIColor(red: 0.022, green: 0.022, blue: 0.024, alpha: 1)
        let rimColor = UIColor(red: 0.48, green: 0.50, blue: 0.50, alpha: 1)
        let doorColor = UIColor(red: 0.43, green: 0.45, blue: 0.45, alpha: 1)

        root.addChild(gearAssembly(
            name: noseGearName,
            rootPosition: [0, -0.30, 2.78],
            strutHeight: 1.14,
            wheelRadius: 0.245,
            wheelWidth: 0.18,
            side: 0,
            isNose: true,
            strutColor: strutColor,
            chromeColor: chromeColor,
            tireColor: tireColor,
            rimColor: rimColor,
            doorColor: doorColor
        ))
        root.addChild(gearAssembly(
            name: leftGearName,
            rootPosition: [-1.08, -0.34, -0.80],
            strutHeight: 1.04,
            wheelRadius: 0.315,
            wheelWidth: 0.235,
            side: -1,
            isNose: false,
            strutColor: strutColor,
            chromeColor: chromeColor,
            tireColor: tireColor,
            rimColor: rimColor,
            doorColor: doorColor
        ))
        root.addChild(gearAssembly(
            name: rightGearName,
            rootPosition: [1.08, -0.34, -0.80],
            strutHeight: 1.04,
            wheelRadius: 0.315,
            wheelWidth: 0.235,
            side: 1,
            isNose: false,
            strutColor: strutColor,
            chromeColor: chromeColor,
            tireColor: tireColor,
            rimColor: rimColor,
            doorColor: doorColor
        ))
    }

    private static func gearAssembly(
        name: String,
        rootPosition: SIMD3<Float>,
        strutHeight: Float,
        wheelRadius: Float,
        wheelWidth: Float,
        side: Float,
        isNose: Bool,
        strutColor: UIColor,
        chromeColor: UIColor,
        tireColor: UIColor,
        rimColor: UIColor,
        doorColor: UIColor
    ) -> Entity {
        let assembly = Entity()
        assembly.name = name
        assembly.position = rootPosition

        let upperLength = strutHeight * (isNose ? 0.42 : 0.46)
        let lowerLength = strutHeight * (isNose ? 0.54 : 0.50)
        let wheelY = -strutHeight

        let upperStrut = ModelEntity(
            mesh: .generateCylinder(height: upperLength, radius: isNose ? 0.064 : 0.078),
            materials: [SimpleMaterial(color: strutColor, isMetallic: true)]
        )
        upperStrut.position = [0, -upperLength * 0.5, 0]
        assembly.addChild(upperStrut)

        let lowerStrut = ModelEntity(
            mesh: .generateCylinder(height: lowerLength, radius: isNose ? 0.038 : 0.046),
            materials: [SimpleMaterial(color: chromeColor, isMetallic: true)]
        )
        lowerStrut.position = [0, -upperLength - lowerLength * 0.5 + 0.035, 0]
        assembly.addChild(lowerStrut)

        let braceStart = SIMD3<Float>(
            isNose ? 0.0 : -side * 0.08,
            -strutHeight * 0.24,
            isNose ? -0.18 : 0.10
        )
        let braceEnd = SIMD3<Float>(
            isNose ? 0.0 : side * 0.18,
            wheelY + wheelRadius * 0.36,
            isNose ? 0.22 : -0.20
        )
        assembly.addChild(gearLink(
            from: braceStart,
            to: braceEnd,
            radius: isNose ? 0.027 : 0.034,
            color: strutColor
        ))

        let axle = ModelEntity(
            mesh: .generateCylinder(height: wheelWidth * 1.42, radius: isNose ? 0.030 : 0.038),
            materials: [SimpleMaterial(color: strutColor, isMetallic: true)]
        )
        axle.position = [0, wheelY, 0]
        axle.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        assembly.addChild(axle)

        let wheel = ModelEntity(
            mesh: .generateCylinder(height: wheelWidth, radius: wheelRadius),
            materials: [SimpleMaterial(color: tireColor, isMetallic: false)]
        )
        wheel.position = [0, wheelY, 0]
        wheel.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        assembly.addChild(wheel)

        let rim = ModelEntity(
            mesh: .generateCylinder(height: wheelWidth * 1.035, radius: wheelRadius * 0.46),
            materials: [SimpleMaterial(color: rimColor, isMetallic: true)]
        )
        rim.position = [0, wheelY, 0]
        rim.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        assembly.addChild(rim)

        let hub = ModelEntity(
            mesh: .generateCylinder(height: wheelWidth * 1.08, radius: wheelRadius * 0.17),
            materials: [SimpleMaterial(color: chromeColor, isMetallic: true)]
        )
        hub.position = [0, wheelY, 0]
        hub.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        assembly.addChild(hub)

        if isNose {
            for x in [-wheelWidth * 0.62, wheelWidth * 0.62] {
                assembly.addChild(gearLink(
                    from: [x, -strutHeight * 0.58, 0.02],
                    to: [x, wheelY + wheelRadius * 0.12, 0.0],
                    radius: 0.024,
                    color: strutColor
                ))
            }

            let door = ModelEntity(
                mesh: .generateBox(size: [0.34, 0.034, 0.88], cornerRadius: 0.015),
                materials: [SimpleMaterial(color: doorColor, isMetallic: false)]
            )
            door.position = [0.28, -0.11, -0.08]
            door.orientation = simd_quatf(angle: 0.10, axis: [0, 0, 1])
            assembly.addChild(door)
        } else {
            assembly.addChild(gearLink(
                from: [-side * 0.18, -strutHeight * 0.18, -0.12],
                to: [side * 0.12, -strutHeight * 0.72, 0.06],
                radius: 0.030,
                color: strutColor
            ))

            let door = ModelEntity(
                mesh: .generateBox(size: [0.52, 0.036, 0.78], cornerRadius: 0.018),
                materials: [SimpleMaterial(color: doorColor, isMetallic: false)]
            )
            door.position = [-side * 0.34, -0.13, 0.02]
            door.orientation = simd_quatf(angle: side * 0.13, axis: [0, 0, 1])
            assembly.addChild(door)
        }

        return assembly
    }

    private static func gearLink(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        radius: Float,
        color: UIColor
    ) -> Entity {
        let delta = end - start
        let length = max(simd_length(delta), 0.001)
        let link = ModelEntity(
            mesh: .generateCylinder(height: length, radius: radius),
            materials: [SimpleMaterial(color: color, isMetallic: true)]
        )
        link.position = (start + end) * 0.5
        link.orientation = simd_quatf(
            from: SIMD3<Float>(0, 1, 0),
            to: simd_normalize(delta)
        )
        return link
    }

    private static func loadAuthoredOBJ(
        _ name: String,
        classifyF16Paint: Bool = false
    ) throws -> MeshResource {
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
        var sourceUVs: [SIMD2<Float>] = []

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        var faceMaterials: [UInt32] = []
        var parsedTriangles: [[ParsedVertex]] = []

        for line in lines {
            if line.hasPrefix("v ") {
                let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if f.count >= 4,
                   let x = Float(f[1]),
                   let y = Float(f[2]),
                   let z = Float(f[3]) {
                    sourcePositions.append([x, y, z])
                }
            } else if line.hasPrefix("vt ") {
                let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if f.count >= 3,
                   let u = Float(f[1]),
                   let v = Float(f[2]) {
                    sourceUVs.append([u, v])
                }
            } else if line.hasPrefix("vn ") {
                let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if f.count >= 4,
                   let x = Float(f[1]),
                   let y = Float(f[2]),
                   let z = Float(f[3]) {
                    let n = SIMD3<Float>(x, y, z)
                    sourceNormals.append(
                        simd_length_squared(n) > 0 ? simd_normalize(n) : SIMD3<Float>(0, 1, 0)
                    )
                }
            }
        }

        func resolved(_ raw: Int, count: Int) -> Int? {
            if raw > 0 {
                let i = raw - 1
                return i < count ? i : nil
            }
            if raw < 0 {
                let i = count + raw
                return i >= 0 && i < count ? i : nil
            }
            return nil
        }

        func vertex(_ token: Substring) -> ParsedVertex? {
            let c = token.split(separator: "/", omittingEmptySubsequences: false)
            guard let rawP = c.first.flatMap({ Int($0) }),
                  let pi = resolved(rawP, count: sourcePositions.count) else {
                return nil
            }

            var uv = SIMD2<Float>.zero
            if c.count >= 2,
               !c[1].isEmpty,
               let rawUV = Int(c[1]),
               let ui = resolved(rawUV, count: sourceUVs.count) {
                uv = sourceUVs[ui]
            }

            var normal = SIMD3<Float>(0, 1, 0)
            if c.count >= 3,
               !c[2].isEmpty,
               let rawN = Int(c[2]),
               let ni = resolved(rawN, count: sourceNormals.count) {
                normal = sourceNormals[ni]
            }

            return ParsedVertex(
                position: sourcePositions[pi],
                normal: normal,
                uv: uv
            )
        }

        for line in lines where line.hasPrefix("f ") {
            let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard f.count >= 4 else { continue }

            let face = f.dropFirst().compactMap(vertex)
            guard face.count == f.count - 1, face.count >= 3 else { continue }

            for i in 1..<(face.count - 1) {
                // The authored FBX conversion swaps source Y/Z, which changes handedness.
                // Reverse winding so RealityKit front-face culling still sees the exterior shell.
                let triangle = [face[0], face[i + 1], face[i]]
                for v in triangle {
                    indices.append(UInt32(positions.count))
                    positions.append(v.position)
                    normals.append(v.normal)
                    uvs.append(v.uv)
                }

                if classifyF16Paint {
                    parsedTriangles.append(triangle)
                }
            }
        }

        guard positions.count >= 3, indices.count >= 3 else {
            throw AssetError.invalid(name)
        }

        if classifyF16Paint {
            let canopyFaces = canopyFaceIndices(in: parsedTriangles)
            faceMaterials = parsedTriangles.enumerated().map { index, triangle in
                f16MaterialIndex(
                    triangle[0],
                    triangle[1],
                    triangle[2],
                    isCanopy: canopyFaces.contains(index)
                )
            }
        }

        var descriptor = MeshDescriptor(name: "Authored F-16 \(name)")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)

        if classifyF16Paint {
            descriptor.materials = .perFace(faceMaterials)
        } else {
            descriptor.materials = .allFaces(0)
        }

        return try MeshResource.generate(from: [descriptor])
    }

    private struct WeldedVertexKey: Hashable {
        let x: Int
        let y: Int
        let z: Int

        init(_ position: SIMD3<Float>) {
            let scale: Float = 10_000
            x = Int((position.x * scale).rounded())
            y = Int((position.y * scale).rounded())
            z = Int((position.z * scale).rounded())
        }
    }

    private struct WeldedEdgeKey: Hashable {
        let a: WeldedVertexKey
        let b: WeldedVertexKey

        init(_ p0: SIMD3<Float>, _ p1: SIMD3<Float>) {
            let k0 = WeldedVertexKey(p0)
            let k1 = WeldedVertexKey(p1)
            let k0First = k0.x < k1.x ||
                (k0.x == k1.x && k0.y < k1.y) ||
                (k0.x == k1.x && k0.y == k1.y && k0.z <= k1.z)

            if k0First {
                a = k0
                b = k1
            } else {
                a = k1
                b = k0
            }
        }
    }

    private static func canopyFaceIndices(in triangles: [[ParsedVertex]]) -> Set<Int> {
        guard !triangles.isEmpty else { return [] }

        var centroids = Array(repeating: SIMD3<Float>.zero, count: triangles.count)
        var geometricNormals = Array(repeating: SIMD3<Float>(0, 1, 0), count: triangles.count)
        var edgeFaces: [WeldedEdgeKey: [Int]] = [:]

        for (index, triangle) in triangles.enumerated() where triangle.count == 3 {
            let a = triangle[0].position
            let b = triangle[1].position
            let c = triangle[2].position
            centroids[index] = (a + b + c) / 3

            let cross = simd_cross(b - a, c - a)
            if simd_length_squared(cross) > 0.00000001 {
                geometricNormals[index] = simd_normalize(cross)
            }

            for edge in [
                WeldedEdgeKey(a, b),
                WeldedEdgeKey(b, c),
                WeldedEdgeKey(c, a)
            ] {
                edgeFaces[edge, default: []].append(index)
            }
        }

        // Use position only to pick the canopy crown seed and keep the flood in
        // the cockpit neighborhood. The border itself comes from the authored
        // mesh tangent discontinuity at the canopy sill/frame.
        let seedCandidates = triangles.indices.filter { index in
            let p = centroids[index]
            return abs(p.x) < 0.80 &&
                p.z > 1.65 && p.z < 4.55 &&
                p.y > 0.60
        }

        guard let seed = seedCandidates.max(by: { centroids[$0].y < centroids[$1].y }) else {
            return []
        }

        // Adjacent canopy facets can be coarse, so allow up to 36 degrees of
        // local curvature. The hard sill tangent is sharper and stops the flood.
        let smoothTangentCosine = cos(Float.pi * 36.0 / 180.0)
        var selected: Set<Int> = [seed]
        var queue: [Int] = [seed]
        var cursor = 0

        while cursor < queue.count {
            let current = queue[cursor]
            cursor += 1
            let triangle = triangles[current]
            guard triangle.count == 3 else { continue }

            let a = triangle[0].position
            let b = triangle[1].position
            let c = triangle[2].position
            let edges = [
                WeldedEdgeKey(a, b),
                WeldedEdgeKey(b, c),
                WeldedEdgeKey(c, a)
            ]

            for edge in edges {
                for neighbor in edgeFaces[edge] ?? [] where neighbor != current {
                    guard !selected.contains(neighbor) else { continue }

                    let p = centroids[neighbor]
                    guard abs(p.x) < 1.18,
                          p.z > 1.35, p.z < 4.85,
                          p.y > 0.34 else {
                        continue
                    }

                    let tangentCosine = simd_dot(
                        geometricNormals[current],
                        geometricNormals[neighbor]
                    )

                    // The front of the coarse canopy turns through a steeper
                    // facet than the side glass. Let that local crown continue
                    // while the hard sill still blocks the flood elsewhere.
                    let forwardBubble = p.z > 3.00 && p.y > 0.40 && abs(p.x) < 0.80
                    let localTangentCosine = forwardBubble
                        ? cos(Float.pi * 64.0 / 180.0)
                        : smoothTangentCosine
                    guard tangentCosine >= localTangentCosine else {
                        continue
                    }

                    selected.insert(neighbor)
                    queue.append(neighbor)
                }
            }
        }

        // The coarse authored canopy has a second, steeper windshield cap in
        // front of the smooth crown. A pure dihedral flood intentionally stops
        // at that break, which is why the last few windshield triangles stayed
        // gray even when we kept raising the tangent threshold.
        //
        // Close that cap topologically instead: start from the already-known
        // front rim of the canopy, then walk only the connected faces above the
        // rim. The lower nose faces are separated by the windshield sill and by
        // a clear drop in Y, so the walk terminates there without painting the
        // fuselage. This follows the mesh's actual canopy loop instead of
        // inventing another ellipsoid/height mask.
        var frontClosureQueue = Array(selected.filter { index in
            let p = centroids[index]
            return abs(p.x) < 0.55 && p.z > 4.72 && p.y > 0.28
        })
        var frontClosureCursor = 0

        while frontClosureCursor < frontClosureQueue.count {
            let current = frontClosureQueue[frontClosureCursor]
            frontClosureCursor += 1
            let triangle = triangles[current]
            guard triangle.count == 3 else { continue }

            let a = triangle[0].position
            let b = triangle[1].position
            let c = triangle[2].position
            let edges = [
                WeldedEdgeKey(a, b),
                WeldedEdgeKey(b, c),
                WeldedEdgeKey(c, a)
            ]

            for edge in edges {
                for neighbor in edgeFaces[edge] ?? [] where neighbor != current {
                    guard !selected.contains(neighbor) else { continue }

                    let p = centroids[neighbor]
                    guard abs(p.x) < 0.60,
                          p.z > 4.55, p.z < 5.62,
                          p.y > 0.18 else {
                        continue
                    }

                    selected.insert(neighbor)
                    frontClosureQueue.append(neighbor)
                }
            }
        }

        return selected
    }

    private static func f16MaterialIndex(
        _ a: ParsedVertex,
        _ b: ParsedVertex,
        _ c: ParsedVertex,
        isCanopy: Bool
    ) -> UInt32 {
        let centroid = (a.position + b.position + c.position) / 3
        let averageNormal = simd_normalize(a.normal + b.normal + c.normal)

        if isCanopy {
            return Paint.canopy.rawValue
        }

        // Characteristic darker radome.
        if abs(centroid.x) < 1.35,
           centroid.z > 5.15,
           centroid.y > -0.85,
           centroid.y < 0.95 {
            return Paint.radome.rawValue
        }

        // Metallic F100 nozzle and tailpipe.
        if abs(centroid.x) < 0.90,
           abs(centroid.y) < 0.90,
           centroid.z < -5.45 {
            return Paint.exhaust.rawValue
        }

        // Intake lip / lower inlet area.
        if abs(centroid.x) < 1.30,
           centroid.y < -0.42,
           centroid.z > -0.15,
           centroid.z < 3.35 {
            return Paint.intake.rawValue
        }

        // Hill Gray-style darker upper surfaces and lighter lower surfaces.
        if centroid.y < -0.10 || averageNormal.y < -0.28 {
            return Paint.lower.rawValue
        }

        return Paint.upper.rawValue
    }

}
