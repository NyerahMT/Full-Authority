import Foundation
import RealityKit
import UIKit
import simd

/// Full Authority's F-16 presentation layer.
///
/// JSBSim remains the source of truth for flight dynamics. The visual is the
/// CC-BY Pan_Ar4ik NATO GameReady F-16, converted into Full Authority's compact
/// FAM2 mesh format. The supplied source FBX has a modeled cockpit and separate
/// canopy, but no armature, animation stacks, or pilot mesh.
@MainActor
enum PrototypeAircraftFactory {
    static let aircraftName = "FA.aircraft"
    static let visualRootName = "FA.aircraft.visual-root"
    static let cockpitRootName = PrototypeCockpitFactory.rootName
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

    private static let assetSubdirectory = "JSBSim/visuals/f16_nato"
    private static let leftStabilatorPivot = SIMD3<Float>(-1.842414, 0.089497, -5.102210)
    private static let rightStabilatorPivot = SIMD3<Float>(1.858911, 0.089497, -5.102210)

    private enum AssetError: Error {
        case missing(String)
        case invalid(String)
    }

    static func make() -> Entity {
        let aircraft = Entity()
        aircraft.name = aircraftName

        do {
            let bodyMesh = try loadFAMesh("f16_nato_body")
            let canopyMesh = try loadFAMesh("f16_nato_canopy")
            let cockpitMesh = try loadFAMesh("f16_nato_cockpit")
            let leftTailMesh = try loadFAMesh("f16_nato_stabilator_left")
            let rightTailMesh = try loadFAMesh("f16_nato_stabilator_right")

            let bodyMaterial = try makeExteriorMaterial()
            let canopyMaterial = try makeCanopyMaterial()
            let cockpitMaterial = try makeCockpitMaterial()

            let visualRoot = Entity()
            visualRoot.name = visualRootName
            visualRoot.position = [0, visualVerticalOffset, 0]
            aircraft.addChild(visualRoot)

            let body = ModelEntity(mesh: bodyMesh, materials: [bodyMaterial])
            body.name = meshName
            visualRoot.addChild(body)

            addStabilator(
                to: visualRoot,
                name: leftElevatorName,
                mesh: leftTailMesh,
                pivot: leftStabilatorPivot,
                material: bodyMaterial
            )
            addStabilator(
                to: visualRoot,
                name: rightElevatorName,
                mesh: rightTailMesh,
                pivot: rightStabilatorPivot,
                material: bodyMaterial
            )

            let exteriorCockpit = ModelEntity(mesh: cockpitMesh, materials: [cockpitMaterial])
            exteriorCockpit.name = "FA.aircraft.f16.cockpit.external"
            visualRoot.addChild(exteriorCockpit)

            let canopy = ModelEntity(mesh: canopyMesh, materials: [canopyMaterial])
            canopy.name = "FA.aircraft.f16.canopy.external"
            visualRoot.addChild(canopy)

            addAfterburner(to: visualRoot)

            // Keep PrototypeSceneView's existing cockpit toggle contract while
            // replacing the procedural tub with the source model's real interior.
            let cockpitRoot = Entity()
            cockpitRoot.name = cockpitRootName
            cockpitRoot.isEnabled = false

            let cockpitShell = ModelEntity(mesh: bodyMesh, materials: [bodyMaterial])
            cockpitShell.name = "FA.aircraft.f16.cockpit.shell"
            cockpitRoot.addChild(cockpitShell)

            let cockpitInterior = ModelEntity(mesh: cockpitMesh, materials: [cockpitMaterial])
            cockpitInterior.name = "FA.aircraft.f16.cockpit.interior"
            cockpitRoot.addChild(cockpitInterior)

            let cockpitCanopy = ModelEntity(mesh: canopyMesh, materials: [canopyMaterial])
            cockpitCanopy.name = "FA.aircraft.f16.cockpit.canopy"
            cockpitRoot.addChild(cockpitCanopy)

            // Static tail copies make look-back views complete without creating
            // duplicate JSBSim-controlled entity names.
            let cockpitLeftTail = ModelEntity(mesh: leftTailMesh, materials: [bodyMaterial])
            cockpitLeftTail.position = leftStabilatorPivot
            cockpitLeftTail.name = "FA.aircraft.f16.cockpit.tail.left"
            cockpitRoot.addChild(cockpitLeftTail)

            let cockpitRightTail = ModelEntity(mesh: rightTailMesh, materials: [bodyMaterial])
            cockpitRightTail.position = rightStabilatorPivot
            cockpitRightTail.name = "FA.aircraft.f16.cockpit.tail.right"
            cockpitRoot.addChild(cockpitRightTail)

            aircraft.addChild(cockpitRoot)

            // The downloaded FBX has no authored landing gear objects. Keep a
            // lightweight functional gear set for ground operations until a
            // matching high-detail gear asset is authored/sourced.
            addLandingGear(to: aircraft)
        } catch {
            let fallback = ModelEntity(
                mesh: .generateBox(size: [4, 1, 10], cornerRadius: 0.2),
                materials: [SimpleMaterial(color: .red, isMetallic: false)]
            )
            fallback.name = "FA.aircraft.nato-f16-load-failed"
            aircraft.addChild(fallback)
            aircraft.addChild(PrototypeCockpitFactory.make())
        }

        return aircraft
    }

    private static func addStabilator(
        to root: Entity,
        name: String,
        mesh: MeshResource,
        pivot: SIMD3<Float>,
        material: PhysicallyBasedMaterial
    ) {
        let hinge = Entity()
        hinge.name = name
        hinge.position = pivot
        let model = ModelEntity(mesh: mesh, materials: [material])
        model.name = "\(name).mesh"
        hinge.addChild(model)
        root.addChild(hinge)
    }

    // MARK: - FAM2 mesh loading

    /// FAM2 stores Float32 positions, normals, tangents, UV0 and UInt32 indices.
    private static func loadFAMesh(_ name: String) throws -> MeshResource {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "famesh",
            subdirectory: assetSubdirectory
        ) else { throw AssetError.missing(name) }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 12 else { throw AssetError.invalid(name) }
        let header = [UInt8](data.prefix(12))
        guard header[0] == 0x46, header[1] == 0x41,
              header[2] == 0x4D, header[3] == 0x32 else {
            throw AssetError.invalid(name)
        }

        func u32(_ offset: Int) -> UInt32 {
            UInt32(header[offset]) |
                (UInt32(header[offset + 1]) << 8) |
                (UInt32(header[offset + 2]) << 16) |
                (UInt32(header[offset + 3]) << 24)
        }

        let vertexCount = Int(u32(4))
        let indexCount = Int(u32(8))
        guard vertexCount > 0,
              indexCount >= 3,
              indexCount % 3 == 0,
              vertexCount < 2_000_000,
              indexCount < 6_000_000 else {
            throw AssetError.invalid(name)
        }

        let pBytes = vertexCount * 3 * 4
        let nBytes = vertexCount * 3 * 4
        let tBytes = vertexCount * 3 * 4
        let uvBytes = vertexCount * 2 * 4
        let iBytes = indexCount * 4
        guard data.count == 12 + pBytes + nBytes + tBytes + uvBytes + iBytes else {
            throw AssetError.invalid(name)
        }

        func floats(count: Int, offset: inout Int) -> [Float] {
            let byteCount = count * 4
            var result = [Float](repeating: 0, count: count)
            result.withUnsafeMutableBufferPointer { buffer in
                data.copyBytes(
                    to: UnsafeMutableRawBufferPointer(buffer),
                    from: offset..<(offset + byteCount)
                )
            }
            offset += byteCount
            return result
        }

        var offset = 12
        let p = floats(count: vertexCount * 3, offset: &offset)
        let n = floats(count: vertexCount * 3, offset: &offset)
        let t = floats(count: vertexCount * 3, offset: &offset)
        let uv = floats(count: vertexCount * 2, offset: &offset)

        var indices = [UInt32](repeating: 0, count: indexCount)
        indices.withUnsafeMutableBufferPointer { buffer in
            data.copyBytes(
                to: UnsafeMutableRawBufferPointer(buffer),
                from: offset..<(offset + iBytes)
            )
        }
        guard indices.allSatisfy({ Int($0) < vertexCount }) else {
            throw AssetError.invalid(name)
        }

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var tangents: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        positions.reserveCapacity(vertexCount)
        normals.reserveCapacity(vertexCount)
        tangents.reserveCapacity(vertexCount)
        uvs.reserveCapacity(vertexCount)

        for i in 0..<vertexCount {
            positions.append([p[i * 3], p[i * 3 + 1], p[i * 3 + 2]])
            normals.append([n[i * 3], n[i * 3 + 1], n[i * 3 + 2]])
            tangents.append([t[i * 3], t[i * 3 + 1], t[i * 3 + 2]])
            uvs.append([uv[i * 2], uv[i * 2 + 1]])
        }

        var descriptor = MeshDescriptor(name: "Full Authority NATO F-16 \(name)")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.tangents = MeshBuffers.Tangents(tangents)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        descriptor.materials = .allFaces(0)
        return try MeshResource.generate(from: [descriptor])
    }

    // MARK: - PBR materials

    private static func texture(_ name: String) throws -> TextureResource {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "png",
            subdirectory: assetSubdirectory
        ) else { throw AssetError.missing(name) }
        return try TextureResource.load(contentsOf: url, withName: name)
    }

    private static func makeExteriorMaterial() throws -> PhysicallyBasedMaterial {
        let base = MaterialParameters.Texture(try texture("f16_nato_body_basecolor"))
        let roughness = MaterialParameters.Texture(try texture("f16_nato_body_roughness"))
        let metallic = MaterialParameters.Texture(try texture("f16_nato_body_metallic"))
        let normal = MaterialParameters.Texture(try texture("f16_nato_body_normal"))
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .white, texture: base)
        material.roughness = .init(texture: roughness)
        material.metallic = .init(texture: metallic)
        material.normal = .init(texture: normal)
        material.specular = .init(floatLiteral: 0.34)
        material.clearcoat = .init(floatLiteral: 0.035)
        material.clearcoatRoughness = .init(floatLiteral: 0.58)
        return material
    }

    private static func makeCanopyMaterial() throws -> PhysicallyBasedMaterial {
        let base = MaterialParameters.Texture(try texture("f16_nato_body_basecolor"))
        let roughness = MaterialParameters.Texture(try texture("f16_nato_body_roughness"))
        let metallic = MaterialParameters.Texture(try texture("f16_nato_body_metallic"))
        let normal = MaterialParameters.Texture(try texture("f16_nato_body_normal"))
        let alpha = MaterialParameters.Texture(try texture("f16_nato_body_alpha"))
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(
            tint: UIColor(red: 0.58, green: 0.68, blue: 0.71, alpha: 1),
            texture: base
        )
        material.roughness = .init(texture: roughness)
        material.metallic = .init(texture: metallic)
        material.normal = .init(texture: normal)
        material.specular = .init(floatLiteral: 0.92)
        material.clearcoat = .init(floatLiteral: 1.0)
        material.clearcoatRoughness = .init(floatLiteral: 0.035)
        material.blending = .transparent(opacity: .init(scale: 0.72, texture: alpha))
        material.faceCulling = .none
        return material
    }

    private static func makeCockpitMaterial() throws -> PhysicallyBasedMaterial {
        let base = MaterialParameters.Texture(try texture("f16_nato_cockpit_basecolor"))
        let roughness = MaterialParameters.Texture(try texture("f16_nato_cockpit_roughness"))
        let metallic = MaterialParameters.Texture(try texture("f16_nato_cockpit_metallic"))
        let normal = MaterialParameters.Texture(try texture("f16_nato_cockpit_normal"))
        let emission = MaterialParameters.Texture(try texture("f16_nato_cockpit_emission"))
        let alpha = MaterialParameters.Texture(try texture("f16_nato_cockpit_alpha"))
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .white, texture: base)
        material.roughness = .init(texture: roughness)
        material.metallic = .init(texture: metallic)
        material.normal = .init(texture: normal)
        material.specular = .init(floatLiteral: 0.36)
        material.emissiveColor = .init(texture: emission)
        material.emissiveIntensity = 1.15
        material.blending = .transparent(opacity: .init(scale: 1.0, texture: alpha))
        material.opacityThreshold = 0.05
        material.faceCulling = .none
        return material
    }

    // MARK: - Engine presentation

    private static func addAfterburner(to root: Entity) {
        let plume = Entity()
        plume.name = afterburnerName
        plume.position = [0, 0, -7.20]
        plume.isEnabled = false
        let aft = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))

        func flame(
            name: String,
            length: Float,
            radius: Float,
            color: UIColor
        ) -> ModelEntity {
            let e = ModelEntity(
                mesh: .generateCone(height: length, radius: radius),
                materials: [UnlitMaterial(color: color)]
            )
            e.name = name
            e.orientation = aft
            e.position = [0, 0, -length * 0.5]
            return e
        }

        plume.addChild(flame(
            name: afterburnerHaloName,
            length: 2.15,
            radius: 0.47,
            color: UIColor(red: 0.72, green: 0.13, blue: 0.025, alpha: 0.08)
        ))
        plume.addChild(flame(
            name: afterburnerOuterName,
            length: 1.90,
            radius: 0.37,
            color: UIColor(red: 1.0, green: 0.30, blue: 0.045, alpha: 0.24)
        ))
        plume.addChild(flame(
            name: afterburnerInnerName,
            length: 1.55,
            radius: 0.24,
            color: UIColor(red: 1.0, green: 0.62, blue: 0.13, alpha: 0.42)
        ))
        plume.addChild(flame(
            name: afterburnerCoreName,
            length: 1.12,
            radius: 0.12,
            color: UIColor(red: 1.0, green: 0.90, blue: 0.58, alpha: 0.64)
        ))

        let shockZ: [Float] = [-0.38, -0.76, -1.17, -1.60]
        let shockR: [Float] = [0.18, 0.16, 0.135, 0.105]
        for i in shockZ.indices {
            let cell = ModelEntity(
                mesh: .generateCylinder(height: 0.022, radius: shockR[i]),
                materials: [UnlitMaterial(color: UIColor(
                    red: 1.0,
                    green: 0.74,
                    blue: 0.34,
                    alpha: CGFloat(max(0.035, 0.10 - Float(i) * 0.018))
                ))]
            )
            cell.name = afterburnerShockPrefix + String(i)
            cell.position = [0, 0, shockZ[i]]
            cell.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
            cell.isEnabled = false
            plume.addChild(cell)
        }
        root.addChild(plume)

        let glow = ModelEntity(
            mesh: .generateCylinder(height: 0.025, radius: 0.43),
            materials: [UnlitMaterial(color: UIColor(red: 1.0, green: 0.30, blue: 0.055, alpha: 0.42))]
        )
        glow.name = nozzleGlowName
        glow.position = [0, 0, -7.20]
        glow.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        glow.isEnabled = false
        root.addChild(glow)
    }

    // MARK: - Functional landing gear

    private static func addLandingGear(to root: Entity) {
        root.addChild(gearAssembly(
            name: noseGearName,
            rootPosition: [0, -0.42, 3.25],
            strutHeight: 1.40,
            wheelRadius: 0.245,
            wheelWidth: 0.18,
            side: 0,
            isNose: true
        ))
        root.addChild(gearAssembly(
            name: leftGearName,
            rootPosition: [-1.05, -0.48, -0.45],
            strutHeight: 1.26,
            wheelRadius: 0.315,
            wheelWidth: 0.235,
            side: -1,
            isNose: false
        ))
        root.addChild(gearAssembly(
            name: rightGearName,
            rootPosition: [1.05, -0.48, -0.45],
            strutHeight: 1.26,
            wheelRadius: 0.315,
            wheelWidth: 0.235,
            side: 1,
            isNose: false
        ))
    }

    private static func gearAssembly(
        name: String,
        rootPosition: SIMD3<Float>,
        strutHeight: Float,
        wheelRadius: Float,
        wheelWidth: Float,
        side: Float,
        isNose: Bool
    ) -> Entity {
        let root = Entity()
        root.name = name
        root.position = rootPosition

        let strut = ModelEntity(
            mesh: .generateCylinder(height: strutHeight, radius: isNose ? 0.045 : 0.058),
            materials: [SimpleMaterial(color: UIColor(white: 0.78, alpha: 1), isMetallic: true)]
        )
        strut.position = [0, -strutHeight * 0.5, 0]
        root.addChild(strut)

        let wheelY = -strutHeight
        let tire = ModelEntity(
            mesh: .generateCylinder(height: wheelWidth, radius: wheelRadius),
            materials: [SimpleMaterial(color: UIColor(white: 0.025, alpha: 1), isMetallic: false)]
        )
        tire.position = [0, wheelY, 0]
        tire.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        root.addChild(tire)

        let rim = ModelEntity(
            mesh: .generateCylinder(height: wheelWidth * 1.03, radius: wheelRadius * 0.46),
            materials: [SimpleMaterial(color: UIColor(white: 0.62, alpha: 1), isMetallic: true)]
        )
        rim.position = [0, wheelY, 0]
        rim.orientation = tire.orientation
        root.addChild(rim)

        let door = ModelEntity(
            mesh: .generateBox(
                size: isNose ? SIMD3<Float>(0.34, 0.035, 0.90) : SIMD3<Float>(0.52, 0.035, 0.82),
                cornerRadius: 0.015
            ),
            materials: [SimpleMaterial(color: UIColor(white: 0.42, alpha: 1), isMetallic: false)]
        )
        door.position = isNose ? [0.27, -0.15, -0.05] : [-side * 0.34, -0.16, 0.02]
        door.orientation = simd_quatf(angle: isNose ? 0.10 : side * 0.13, axis: [0, 0, 1])
        root.addChild(door)
        return root
    }
}
