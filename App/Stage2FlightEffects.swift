import Foundation
import RealityKit
import UIKit
import simd

@MainActor
enum Stage2FlightEffects {
    static let attachedRootName = "FA.effects.attached"
    static let trailRootName = "FA.effects.trails"

    private static let afterburnerRootName = "FA.effects.afterburner"
    private static let afterburnerOuterName = "FA.effects.afterburner.outer"
    private static let afterburnerInnerName = "FA.effects.afterburner.inner"
    private static let afterburnerCoreName = "FA.effects.afterburner.core"
    private static let afterburnerGlowName = "FA.effects.afterburner.glow"
    private static let stockExhaustName = "FA.aircraft.exhaust.stock"

    /// Stage 010.8 intentionally retires the world-space smoke/contrail pool.
    /// Keep the runtime type so the scene wiring remains stable while the visual
    /// effect itself is gone.
    @MainActor
    final class Runtime {}

    static func makeAttachedEffects() -> Entity {
        let root = Entity()
        root.name = attachedRootName

        let afterburner = Entity()
        afterburner.name = afterburnerRootName

        // Aircraft coordinates are +Z nose-forward, so exhaust must extend in -Z.
        // This point is the actual F-16 tailpipe center in aircraft-local space.
        afterburner.position = [0, -0.21, -7.52]
        afterburner.isEnabled = false

        if let outerMesh = makeTaperedPlumeMesh(frontRadius: 0.43, rearRadius: 0.10) {
            let outer = ModelEntity(
                mesh: outerMesh,
                materials: [UnlitMaterial(color: UIColor(
                    red: 0.20,
                    green: 0.38,
                    blue: 1.00,
                    alpha: 0.23
                ))]
            )
            outer.name = afterburnerOuterName
            afterburner.addChild(outer)
        }

        if let innerMesh = makeTaperedPlumeMesh(frontRadius: 0.29, rearRadius: 0.045) {
            let inner = ModelEntity(
                mesh: innerMesh,
                materials: [UnlitMaterial(color: UIColor(
                    red: 0.55,
                    green: 0.78,
                    blue: 1.00,
                    alpha: 0.56
                ))]
            )
            inner.name = afterburnerInnerName
            afterburner.addChild(inner)
        }

        if let coreMesh = makeTaperedPlumeMesh(frontRadius: 0.18, rearRadius: 0.025) {
            let core = ModelEntity(
                mesh: coreMesh,
                materials: [UnlitMaterial(color: UIColor(
                    red: 0.96,
                    green: 0.985,
                    blue: 1.00,
                    alpha: 0.90
                ))]
            )
            core.name = afterburnerCoreName
            afterburner.addChild(core)
        }

        // Small luminous source at the nozzle mouth. This is attached to the
        // engine and never becomes a detached particle/blob trail.
        let glow = ModelEntity(
            mesh: .generateSphere(radius: 0.34),
            materials: [UnlitMaterial(color: UIColor(
                red: 0.82,
                green: 0.91,
                blue: 1.00,
                alpha: 0.82
            ))]
        )
        glow.name = afterburnerGlowName
        glow.position = [0, 0, -0.05]
        glow.scale = [1.0, 1.0, 0.18]
        afterburner.addChild(glow)

        root.addChild(afterburner)
        return root
    }

    /// No smoke balls, exhaust bubbles, or world-space contrail segments.
    /// The placeholder root remains only so existing scene code does not need
    /// special-case wiring.
    static func makeTrailPool() -> Entity {
        let root = Entity()
        root.name = trailRootName
        root.isEnabled = false
        return root
    }

    static func updateAttachedEffects(
        aircraft: Entity,
        state: AircraftState,
        simulationTime: TimeInterval
    ) {
        // Kill every legacy vapor/contrail primitive if an older scene instance
        // is still alive during a hot reload.
        for oldName in [
            PrototypeAircraftFactory.vaporLeftName,
            PrototypeAircraftFactory.vaporRightName,
            PrototypeAircraftFactory.contrailLeftName,
            PrototypeAircraftFactory.contrailRightName,
            "FA.effects.vapor.left",
            "FA.effects.vapor.right"
        ] {
            aircraft.findEntity(named: oldName)?.isEnabled = false
        }

        updateStockExhaustMaterial(aircraft)

        guard let attachedRoot = aircraft.findEntity(named: attachedRootName),
              let afterburner = attachedRoot.findEntity(named: afterburnerRootName) else {
            return
        }

        // JSBSim fuel flow is authoritative. The high-flow portion of the F100
        // schedule corresponds to the augmented/afterburning range. A smooth
        // ramp avoids a hard visual pop while keeping MIL power effectively dark.
        let fuelFlow = max(0, state.engineFuelFlowPoundsPerSecond)
        let intensity = clamp((fuelFlow - 0.55) / 0.70, 0, 1)
        let visible = intensity > 0.025
        afterburner.isEnabled = visible
        guard visible else { return }

        // Subtle high-frequency length movement reads as a living exhaust plume
        // without changing its axis. It can only grow straight aft in local -Z.
        let flicker = 1.0 + 0.035 * sin(Float(simulationTime) * 37.0)
        let widthPulse = 1.0 + 0.020 * sin(Float(simulationTime) * 29.0 + 0.8)

        if let outer = afterburner.findEntity(named: afterburnerOuterName) {
            let radiusScale = (0.72 + 0.28 * intensity) * widthPulse
            let length = (1.55 + 2.10 * intensity) * flicker
            outer.scale = [radiusScale, radiusScale, length]
        }

        if let inner = afterburner.findEntity(named: afterburnerInnerName) {
            let radiusScale = 0.74 + 0.24 * intensity
            let length = (1.10 + 1.55 * intensity) * (2.0 - flicker)
            inner.scale = [radiusScale, radiusScale, length]
        }

        if let core = afterburner.findEntity(named: afterburnerCoreName) {
            let radiusScale = 0.76 + 0.18 * intensity
            let length = 0.72 + 0.90 * intensity
            core.scale = [radiusScale, radiusScale, length]
        }

        if let glow = afterburner.findEntity(named: afterburnerGlowName) {
            let radiusScale = 0.74 + 0.24 * intensity
            glow.scale = [radiusScale, radiusScale, 0.14 + 0.07 * intensity]
        }
    }

    static func updateWorldTrails(
        root: Entity,
        state: AircraftState,
        simulationTime: TimeInterval,
        runtime: Runtime
    ) {
        // Intentionally disabled. The previous pooled trail mesh is the source of
        // the detached translucent blobs visible behind the aircraft.
        root.isEnabled = false
        _ = state
        _ = simulationTime
        _ = runtime
    }

    /// The R4 F-16 source mesh already contains the actual exhaust/nozzle faces.
    /// Keep that geometry and give it a readable hot-metal/gunmetal finish rather
    /// than covering it with the old black procedural cylinder.
    private static func updateStockExhaustMaterial(_ aircraft: Entity) {
        guard let exhaust = aircraft.findEntity(named: stockExhaustName) as? ModelEntity,
              var model = exhaust.model else {
            return
        }

        model.materials = [SimpleMaterial(
            color: UIColor(red: 0.32, green: 0.30, blue: 0.275, alpha: 1.0),
            isMetallic: true
        )]
        exhaust.model = model
    }

    /// Unit-length, double-sided tapered plume aligned explicitly with local -Z.
    /// Scaling only the entity's Z component changes flame length without ever
    /// rotating the exhaust away from the aircraft centerline.
    private static func makeTaperedPlumeMesh(
        frontRadius: Float,
        rearRadius: Float,
        sides: Int = 18
    ) -> MeshResource? {
        guard sides >= 3 else { return nil }

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(sides * 2)
        normals.reserveCapacity(sides * 2)
        indices.reserveCapacity(sides * 12)

        let taper = frontRadius - rearRadius
        for index in 0..<sides {
            let angle = Float(index) / Float(sides) * 2 * Float.pi
            let c = cos(angle)
            let s = sin(angle)
            let normal = simd_normalize(SIMD3<Float>(c, s, taper))

            positions.append([c * frontRadius, s * frontRadius, 0])
            positions.append([c * rearRadius, s * rearRadius, -1])
            normals.append(normal)
            normals.append(normal)
        }

        for index in 0..<sides {
            let next = (index + 1) % sides
            let a = UInt32(index * 2)
            let b = a + 1
            let c = UInt32(next * 2)
            let d = c + 1

            // Front-facing winding.
            indices.append(contentsOf: [a, b, c, c, b, d])
            // Reverse winding keeps the transparent plume visible from any
            // chase/orbit angle without relying on material culling behavior.
            indices.append(contentsOf: [c, b, a, d, b, c])
        }

        var descriptor = MeshDescriptor(name: "F-16 afterburner plume")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    private static func clamp(_ value: Float, _ minimum: Float, _ maximum: Float) -> Float {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}
