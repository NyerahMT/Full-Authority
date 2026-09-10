import RealityKit
import UIKit
import simd

/// Small, reference-driven details that survive close/chase views without turning
/// the F-16 into a noisy panel-line texture. The base FlightSim_F16 geometry and
/// Stage 017 matte material hierarchy remain authoritative.
@MainActor
enum Stage020AircraftDetails {
    static let rootName = "FA.aircraft.stage020.details"
    static let antiCollisionName = "FA.aircraft.stage020.anti-collision"

    static func make() -> Entity {
        let root = Entity()
        root.name = rootName

        addNavigationLights(to: root)
        addFormationLights(to: root)
        addNoseProbe(to: root)

        return root
    }

    private static func addNavigationLights(to root: Entity) {
        let red = UnlitMaterial(color: UIColor(red: 1.0, green: 0.055, blue: 0.035, alpha: 0.92))
        let green = UnlitMaterial(color: UIColor(red: 0.08, green: 0.90, blue: 0.30, alpha: 0.92))
        let white = UnlitMaterial(color: UIColor(white: 0.96, alpha: 0.90))

        let left = ModelEntity(mesh: .generateSphere(radius: 0.055), materials: [red])
        left.position = [-4.78, 0.015, -1.12]
        root.addChild(left)

        let right = ModelEntity(mesh: .generateSphere(radius: 0.055), materials: [green])
        right.position = [4.78, 0.015, -1.12]
        root.addChild(right)

        let tail = ModelEntity(mesh: .generateSphere(radius: 0.048), materials: [white])
        tail.position = [0, 2.56, -5.72]
        root.addChild(tail)

        let antiCollision = ModelEntity(
            mesh: .generateSphere(radius: 0.052),
            materials: [UnlitMaterial(color: UIColor(red: 1.0, green: 0.08, blue: 0.045, alpha: 0.92))]
        )
        antiCollision.name = antiCollisionName
        antiCollision.position = [0, 0.68, -2.55]
        root.addChild(antiCollision)
    }

    private static func addFormationLights(to root: Entity) {
        let slime = UnlitMaterial(color: UIColor(red: 0.64, green: 0.78, blue: 0.34, alpha: 0.30))
        let strips: [(SIMD3<Float>, SIMD3<Float>, Float)] = [
            ([-0.86, 0.34, 1.10], [0.045, 0.018, 0.72], -0.10),
            ([0.86, 0.34, 1.10], [0.045, 0.018, 0.72], 0.10),
            ([-2.18, 0.11, -2.20], [0.70, 0.018, 0.045], 0.08),
            ([2.18, 0.11, -2.20], [0.70, 0.018, 0.045], -0.08),
            ([-0.12, 1.80, -4.86], [0.045, 0.62, 0.020], 0),
            ([0.12, 1.80, -4.86], [0.045, 0.62, 0.020], 0)
        ]

        for (position, size, yaw) in strips {
            let strip = ModelEntity(mesh: .generateBox(size: size, cornerRadius: 0.015), materials: [slime])
            strip.position = position
            strip.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            root.addChild(strip)
        }
    }

    private static func addNoseProbe(to root: Entity) {
        var metal = PhysicallyBasedMaterial()
        metal.baseColor = .init(tint: UIColor(red: 0.42, green: 0.43, blue: 0.42, alpha: 1))
        metal.roughness = .init(floatLiteral: 0.42)
        metal.metallic = .init(floatLiteral: 0.74)
        metal.specular = .init(floatLiteral: 0.45)

        let probe = cylinder(
            from: [0, 0.03, 6.72],
            to: [0, 0.03, 7.45],
            radius: 0.018,
            material: metal
        )
        root.addChild(probe)
    }

    private static func cylinder(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        radius: Float,
        material: PhysicallyBasedMaterial
    ) -> ModelEntity {
        let delta = end - start
        let length = max(simd_length(delta), 0.001)
        let entity = ModelEntity(
            mesh: .generateCylinder(height: length, radius: radius),
            materials: [material]
        )
        entity.position = (start + end) * 0.5
        entity.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(delta))
        return entity
    }
}