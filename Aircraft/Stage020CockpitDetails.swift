import RealityKit
import UIKit
import simd

/// Adds the pieces that make the existing low-poly cockpit read as a working
/// fighter cockpit rather than a collection of dark boxes. It intentionally
/// avoids fake live avionics; the existing HUD remains the source of flight data.
@MainActor
enum Stage020CockpitDetails {
    static let rootName = "FA.aircraft.cockpit.stage020"
    static let leftPedalName = "FA.aircraft.cockpit.pedal.left"
    static let rightPedalName = "FA.aircraft.cockpit.pedal.right"

    static func make() -> Entity {
        let root = Entity()
        root.name = rootName

        let panel = pbr(
            UIColor(red: 0.055, green: 0.060, blue: 0.060, alpha: 1),
            roughness: 0.89,
            metallic: 0.02,
            specular: 0.20
        )
        let bezel = pbr(
            UIColor(red: 0.105, green: 0.110, blue: 0.108, alpha: 1),
            roughness: 0.78,
            metallic: 0.05,
            specular: 0.24
        )
        let glass = pbr(
            UIColor(red: 0.012, green: 0.026, blue: 0.024, alpha: 1),
            roughness: 0.13,
            metallic: 0.0,
            specular: 0.62
        )
        let metal = pbr(
            UIColor(red: 0.31, green: 0.32, blue: 0.31, alpha: 1),
            roughness: 0.52,
            metallic: 0.62,
            specular: 0.42
        )

        addStandbyInstrumentCluster(to: root, panel: panel, bezel: bezel, glass: glass)
        addPedals(to: root, metal: metal, panel: panel)
        addEjectionHandle(to: root)
        addConsoleFasteners(to: root, material: metal)
        addCautionPanel(to: root, panel: panel)
        addCanopyGlassHints(to: root)

        return root
    }

    private static func addStandbyInstrumentCluster(
        to root: Entity,
        panel: PhysicallyBasedMaterial,
        bezel: PhysicallyBasedMaterial,
        glass: PhysicallyBasedMaterial
    ) {
        let backplate = ModelEntity(
            mesh: .generateBox(size: [0.34, 0.29, 0.030], cornerRadius: 0.015),
            materials: [panel]
        )
        backplate.position = [0, 0.435, 4.045]
        backplate.orientation = simd_quatf(angle: -0.16, axis: [1, 0, 0])
        root.addChild(backplate)

        let positions: [SIMD2<Float>] = [
            [-0.105, 0.055], [0.105, 0.055], [0, -0.075]
        ]
        for (index, point) in positions.enumerated() {
            let rim = ModelEntity(
                mesh: .generateCylinder(height: 0.018, radius: index == 2 ? 0.052 : 0.058),
                materials: [bezel]
            )
            rim.position = [point.x, 0.435 + point.y, 4.022]
            rim.orientation = simd_quatf(angle: .pi / 2 - 0.16, axis: [1, 0, 0])
            root.addChild(rim)

            let face = ModelEntity(
                mesh: .generateCylinder(height: 0.006, radius: index == 2 ? 0.044 : 0.050),
                materials: [glass]
            )
            face.position = [point.x, 0.435 + point.y, 4.009]
            face.orientation = simd_quatf(angle: .pi / 2 - 0.16, axis: [1, 0, 0])
            root.addChild(face)

            let needle = ModelEntity(
                mesh: .generateBox(size: [0.006, 0.002, index == 2 ? 0.032 : 0.038], cornerRadius: 0.001),
                materials: [UnlitMaterial(color: UIColor(white: 0.74, alpha: 0.72))]
            )
            needle.position = [point.x, 0.435 + point.y, 3.999]
            needle.orientation = simd_quatf(angle: Float(index) * 0.64 - 0.36, axis: [0, 0, 1])
                * simd_quatf(angle: -0.16, axis: [1, 0, 0])
            root.addChild(needle)
        }
    }

    private static func addPedals(
        to root: Entity,
        metal: PhysicallyBasedMaterial,
        panel: PhysicallyBasedMaterial
    ) {
        for side: Float in [-1, 1] {
            let name = side < 0 ? leftPedalName : rightPedalName
            let assembly = Entity()
            assembly.name = name
            assembly.position = [side * 0.235, 0.12, 3.92]

            let arm = bar(
                from: [0, 0, 0],
                to: [side * 0.025, 0.24, 0.18],
                radius: 0.016,
                material: metal
            )
            assembly.addChild(arm)

            let pedal = ModelEntity(
                mesh: .generateBox(size: [0.19, 0.055, 0.10], cornerRadius: 0.012),
                materials: [panel]
            )
            pedal.position = [side * 0.025, 0.255, 0.19]
            pedal.orientation = simd_quatf(angle: -0.30, axis: [1, 0, 0])
            assembly.addChild(pedal)
            root.addChild(assembly)
        }
    }

    private static func addEjectionHandle(to root: Entity) {
        var yellow = PhysicallyBasedMaterial()
        yellow.baseColor = .init(tint: UIColor(red: 0.91, green: 0.72, blue: 0.08, alpha: 1))
        yellow.roughness = .init(floatLiteral: 0.64)
        yellow.metallic = .init(floatLiteral: 0.0)
        yellow.specular = .init(floatLiteral: 0.25)

        root.addChild(bar(from: [-0.105, 0.27, 3.02], to: [-0.05, 0.34, 3.05], radius: 0.012, material: yellow))
        root.addChild(bar(from: [0.105, 0.27, 3.02], to: [0.05, 0.34, 3.05], radius: 0.012, material: yellow))
        root.addChild(bar(from: [-0.05, 0.34, 3.05], to: [0.05, 0.34, 3.05], radius: 0.012, material: yellow))
    }

    private static func addConsoleFasteners(to root: Entity, material: PhysicallyBasedMaterial) {
        for side: Float in [-1, 1] {
            for row in 0..<7 {
                let z = 3.04 + Float(row) * 0.20
                for column in 0..<2 {
                    let x = side * (0.34 + Float(column) * 0.14)
                    let fastener = ModelEntity(mesh: .generateSphere(radius: 0.009), materials: [material])
                    fastener.position = [x, 0.365, z]
                    root.addChild(fastener)
                }
            }
        }
    }

    private static func addCautionPanel(to root: Entity, panel: PhysicallyBasedMaterial) {
        let housing = ModelEntity(
            mesh: .generateBox(size: [0.20, 0.18, 0.022], cornerRadius: 0.012),
            materials: [panel]
        )
        housing.position = [0.44, 0.73, 4.065]
        housing.orientation = simd_quatf(angle: -0.16, axis: [1, 0, 0])
        root.addChild(housing)

        let colors = [
            UIColor(red: 0.68, green: 0.36, blue: 0.04, alpha: 0.50),
            UIColor(red: 0.50, green: 0.12, blue: 0.055, alpha: 0.40),
            UIColor(red: 0.28, green: 0.43, blue: 0.16, alpha: 0.32)
        ]
        for row in 0..<4 {
            for column in 0..<3 {
                let lamp = ModelEntity(
                    mesh: .generateBox(size: [0.045, 0.024, 0.006], cornerRadius: 0.004),
                    materials: [UnlitMaterial(color: colors[(row + column) % colors.count])]
                )
                lamp.position = [
                    0.395 + Float(column) * 0.046,
                    0.775 - Float(row) * 0.036,
                    4.046
                ]
                lamp.orientation = simd_quatf(angle: -0.16, axis: [1, 0, 0])
                root.addChild(lamp)
            }
        }
    }

    private static func addCanopyGlassHints(to root: Entity) {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.11, green: 0.20, blue: 0.22, alpha: 1))
        material.roughness = .init(floatLiteral: 0.035)
        material.metallic = .init(floatLiteral: 0.0)
        material.specular = .init(floatLiteral: 0.82)
        material.clearcoat = .init(floatLiteral: 0.75)
        material.clearcoatRoughness = .init(floatLiteral: 0.025)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.055))
        material.faceCulling = .none
        material.writesDepth = false

        for side: Float in [-1, 1] {
            let pane = ModelEntity(
                mesh: .generatePlane(width: 0.68, height: 1.25),
                materials: [material]
            )
            pane.position = [side * 0.66, 0.95, 3.43]
            pane.orientation = simd_quatf(angle: side * 0.23, axis: [0, 1, 0])
                * simd_quatf(angle: -0.08, axis: [1, 0, 0])
            root.addChild(pane)
        }
    }

    private static func pbr(
        _ color: UIColor,
        roughness: Float,
        metallic: Float,
        specular: Float
    ) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: metallic)
        material.specular = .init(floatLiteral: specular)
        return material
    }

    private static func bar(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        radius: Float,
        material: PhysicallyBasedMaterial
    ) -> ModelEntity {
        let delta = end - start
        let length = max(simd_length(delta), 0.001)
        let entity = ModelEntity(mesh: .generateCylinder(height: length, radius: radius), materials: [material])
        entity.position = (start + end) * 0.5
        entity.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(delta))
        return entity
    }
}