import Foundation
import RealityKit
import UIKit
import simd

@MainActor
enum Stage2FlightEffects {
    static let attachedRootName = "FA.effects.attached"
    static let trailRootName = "FA.effects.trails"

    private static let leftWingVaporName = "FA.effects.vapor.left"
    private static let rightWingVaporName = "FA.effects.vapor.right"
    private static let shockOuterName = "FA.effects.shock.outer"
    private static let shockInnerName = "FA.effects.shock.inner"
    private static let trailCount = 36

    final class Runtime {
        fileprivate var leftSegments: [ModelEntity] = []
        fileprivate var rightSegments: [ModelEntity] = []
        fileprivate var birthTimes = Array(repeating: -10_000.0, count: trailCount)
        fileprivate var leftLengths = Array(repeating: Float(1), count: trailCount)
        fileprivate var rightLengths = Array(repeating: Float(1), count: trailCount)
        fileprivate var cursor = 0
        fileprivate var lastTrailSampleTime = -10_000.0
        fileprivate var previousLeft: SIMD3<Float>?
        fileprivate var previousRight: SIMD3<Float>?
        fileprivate var lastSimulationTime = 0.0

        fileprivate func bind(to root: Entity) {
            guard leftSegments.count != Self.expectedCount else { return }
            leftSegments = (0..<Stage2FlightEffects.trailCount).compactMap {
                root.findEntity(named: "FA.effects.trail.left.\($0)") as? ModelEntity
            }
            rightSegments = (0..<Stage2FlightEffects.trailCount).compactMap {
                root.findEntity(named: "FA.effects.trail.right.\($0)") as? ModelEntity
            }
        }

        fileprivate func clear() {
            for entity in leftSegments + rightSegments {
                entity.isEnabled = false
            }
            birthTimes = Array(repeating: -10_000.0, count: Stage2FlightEffects.trailCount)
            leftLengths = Array(repeating: 1, count: Stage2FlightEffects.trailCount)
            rightLengths = Array(repeating: 1, count: Stage2FlightEffects.trailCount)
            cursor = 0
            lastTrailSampleTime = -10_000
            previousLeft = nil
            previousRight = nil
        }

        private static let expectedCount = Stage2FlightEffects.trailCount
    }

    static func makeAttachedEffects() -> Entity {
        let root = Entity()
        root.name = attachedRootName

        if let leftMesh = makeWingVaporMesh(phase: 0.0) {
            let left = ModelEntity(mesh: leftMesh, materials: [effectMaterial(alpha: 0.0)])
            left.name = leftWingVaporName
            left.position = [-3.65, -0.02, -1.85]
            left.isEnabled = false
            root.addChild(left)
        }

        if let rightMesh = makeWingVaporMesh(phase: 1.7) {
            let right = ModelEntity(mesh: rightMesh, materials: [effectMaterial(alpha: 0.0)])
            right.name = rightWingVaporName
            right.position = [3.65, -0.02, -1.85]
            right.isEnabled = false
            root.addChild(right)
        }

        if let shockMesh = makeShockConeMesh(radialSegments: 32, axialSegments: 8) {
            let outer = ModelEntity(mesh: shockMesh, materials: [effectMaterial(alpha: 0.0)])
            outer.name = shockOuterName
            outer.position = [0, 0.02, 5.55]
            outer.isEnabled = false
            root.addChild(outer)

            let inner = ModelEntity(mesh: shockMesh, materials: [effectMaterial(alpha: 0.0)])
            inner.name = shockInnerName
            inner.position = [0, 0.02, 5.35]
            inner.isEnabled = false
            root.addChild(inner)
        }

        return root
    }

    static func makeTrailPool() -> Entity {
        let root = Entity()
        root.name = trailRootName
        guard let segmentMesh = makeUnitCrossRibbonMesh() else { return root }

        for index in 0..<trailCount {
            let left = ModelEntity(mesh: segmentMesh, materials: [effectMaterial(alpha: 0.0)])
            left.name = "FA.effects.trail.left.\(index)"
            left.isEnabled = false
            root.addChild(left)

            let right = ModelEntity(mesh: segmentMesh, materials: [effectMaterial(alpha: 0.0)])
            right.name = "FA.effects.trail.right.\(index)"
            right.isEnabled = false
            root.addChild(right)
        }
        return root
    }

    static func updateAttachedEffects(
        aircraft: Entity,
        state: AircraftState,
        simulationTime: TimeInterval
    ) {
        // Retire the Stage 010 primitive ellipsoids. They remain in the factory
        // only for backwards asset compatibility and are never rendered here.
        for oldName in [
            PrototypeAircraftFactory.vaporLeftName,
            PrototypeAircraftFactory.vaporRightName,
            PrototypeAircraftFactory.contrailLeftName,
            PrototypeAircraftFactory.contrailRightName
        ] {
            aircraft.findEntity(named: oldName)?.isEnabled = false
        }

        guard let root = aircraft.findEntity(named: attachedRootName) else { return }

        let gIntensity = clamp((abs(state.loadFactorG) - 2.6) / 4.8, 0, 1)
        let alphaIntensity = clamp((abs(state.angleOfAttackDegrees) - 7.0) / 14.0, 0, 1)
        let qbarIntensity = clamp(state.dynamicPressurePSF / 550.0, 0, 1)
        let vaporIntensity = max(gIntensity, alphaIntensity) * qbarIntensity
        let vaporEnabled = vaporIntensity > 0.045 && state.calibratedAirspeedKnots > 165

        let alpha = state.angleOfAttackDegrees * .pi / 180
        let beta = state.sideslipDegrees * .pi / 180
        let flowOrientation =
            simd_quatf(angle: -beta, axis: [0, 1, 0]) *
            simd_quatf(angle: alpha, axis: [1, 0, 0])

        if let left = root.findEntity(named: leftWingVaporName) as? ModelEntity {
            left.isEnabled = vaporEnabled
            left.orientation = flowOrientation
            left.position = [-3.65, -0.02 + 0.018 * sin(Float(simulationTime) * 31.0), -1.85]
            left.scale = [
                0.72 + vaporIntensity * 0.55,
                0.70 + vaporIntensity * 0.38,
                0.78 + vaporIntensity * 1.15
            ]
            setEffectAlpha(left, alpha: 0.035 + vaporIntensity * 0.19)
        }

        if let right = root.findEntity(named: rightWingVaporName) as? ModelEntity {
            right.isEnabled = vaporEnabled
            right.orientation = flowOrientation
            right.position = [3.65, -0.02 + 0.018 * sin(Float(simulationTime) * 33.0 + 1.1), -1.85]
            right.scale = [
                0.72 + vaporIntensity * 0.55,
                0.70 + vaporIntensity * 0.38,
                0.78 + vaporIntensity * 1.15
            ]
            setEffectAlpha(right, alpha: 0.035 + vaporIntensity * 0.19)
        }

        updateShockCone(root: root, state: state, simulationTime: simulationTime)
    }

    static func updateWorldTrails(
        root: Entity,
        state: AircraftState,
        simulationTime: TimeInterval,
        runtime: Runtime
    ) {
        runtime.bind(to: root)
        guard runtime.leftSegments.count == trailCount,
              runtime.rightSegments.count == trailCount else { return }

        if simulationTime + 0.001 < runtime.lastSimulationTime {
            runtime.clear()
        }
        runtime.lastSimulationTime = simulationTime

        let persistentContrail = state.altitudeFeetMSL > 23_000 && state.calibratedAirspeedKnots > 250
        let loadedWingtipTrail = state.altitudeFeetMSL > 12_000 && abs(state.loadFactorG) > 4.8 && state.calibratedAirspeedKnots > 240
        let active = persistentContrail || loadedWingtipTrail

        if active && simulationTime - runtime.lastTrailSampleTime >= 0.09 {
            let left = worldPoint(local: [-4.75, 0.02, -2.15], state: state)
            let right = worldPoint(local: [4.75, 0.02, -2.15], state: state)

            if let previousLeft = runtime.previousLeft,
               let previousRight = runtime.previousRight {
                let index = runtime.cursor
                runtime.leftLengths[index] = configureTrailSegment(
                    runtime.leftSegments[index],
                    from: previousLeft,
                    to: left
                )
                runtime.rightLengths[index] = configureTrailSegment(
                    runtime.rightSegments[index],
                    from: previousRight,
                    to: right
                )
                runtime.birthTimes[index] = simulationTime
                runtime.cursor = (runtime.cursor + 1) % trailCount
            }

            runtime.previousLeft = left
            runtime.previousRight = right
            runtime.lastTrailSampleTime = simulationTime
        } else if !active {
            runtime.previousLeft = nil
            runtime.previousRight = nil
        }

        let lifetime: Double = persistentContrail ? 8.0 : 4.2
        for index in 0..<trailCount {
            let birth = runtime.birthTimes[index]
            let age = simulationTime - birth
            let left = runtime.leftSegments[index]
            let right = runtime.rightSegments[index]

            guard age >= 0, age < lifetime else {
                left.isEnabled = false
                right.isEnabled = false
                continue
            }

            let normalizedAge = Float(age / lifetime)
            let fade = pow(max(0, 1 - normalizedAge), 1.55)
            let spread = 0.19 + Float(age) * (persistentContrail ? 0.075 : 0.045)
            let alpha = (persistentContrail ? Float(0.13) : Float(0.10)) * fade

            left.isEnabled = true
            right.isEnabled = true
            left.scale = [spread, spread, runtime.leftLengths[index]]
            right.scale = [spread, spread, runtime.rightLengths[index]]
            setEffectAlpha(left, alpha: alpha)
            setEffectAlpha(right, alpha: alpha)
        }
    }

    // MARK: - Mach shock

    private static func updateShockCone(
        root: Entity,
        state: AircraftState,
        simulationTime: TimeInterval
    ) {
        let mach = state.mach
        let visible = mach > 0.965 && mach < 1.65 && state.calibratedAirspeedKnots > 300
        let effectiveMach = max(mach, 1.01)
        let machAngle = asin(clamp(1 / effectiveMach, 0.02, 0.995))
        let axialLength: Float = 4.7
        let baseRadius = min(6.4, max(2.0, axialLength * tan(machAngle)))

        let peak = exp(-pow((mach - 1.035) / 0.13, 2))
        let supersonicPersistence: Float = mach > 1.0 ? 0.16 : 0
        let pulse = 0.92 + 0.08 * sin(Float(simulationTime) * 27.0)
        let intensity = clamp((peak + supersonicPersistence) * pulse, 0, 1)

        if let outer = root.findEntity(named: shockOuterName) as? ModelEntity {
            outer.isEnabled = visible && intensity > 0.035
            outer.scale = [baseRadius, baseRadius, axialLength]
            setEffectAlpha(outer, alpha: 0.018 + intensity * 0.105)
        }

        if let inner = root.findEntity(named: shockInnerName) as? ModelEntity {
            inner.isEnabled = visible && intensity > 0.08
            inner.scale = [baseRadius * 0.82, baseRadius * 0.82, axialLength * 0.76]
            setEffectAlpha(inner, alpha: 0.012 + intensity * 0.055)
        }
    }

    // MARK: - Geometry

    private static func makeWingVaporMesh(phase: Float) -> MeshResource? {
        let segments = 18
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        // Two crossed, tapered sheets make a soft ribbon that reads from above,
        // below and behind without using a sphere/ellipsoid primitive.
        for sheet in 0..<2 {
            let base = UInt32(positions.count)
            for index in 0..<segments {
                let t = Float(index) / Float(segments - 1)
                let z = -0.12 - 6.8 * t
                let envelope = sin(.pi * min(1, t * 1.18)) * (1 - 0.48 * t)
                let width = 0.12 + 0.58 * envelope
                let ripple = sin(t * 16.0 + phase) * 0.055 * t

                if sheet == 0 {
                    positions.append([-width, ripple, z])
                    positions.append([width, -ripple, z])
                } else {
                    positions.append([ripple, -width * 0.34, z])
                    positions.append([-ripple, width * 0.34, z])
                }
            }

            for index in 0..<(segments - 1) {
                let i0 = base + UInt32(index * 2)
                let i1 = i0 + 1
                let i2 = i0 + 2
                let i3 = i0 + 3
                appendDoubleSidedQuad(&indices, i0, i1, i2, i3)
            }
        }

        var descriptor = MeshDescriptor(name: "Wing condensation ribbon")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    private static func makeShockConeMesh(radialSegments: Int, axialSegments: Int) -> MeshResource? {
        guard radialSegments >= 8, axialSegments >= 2 else { return nil }
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for axial in 0...axialSegments {
            let t = max(0.025, Float(axial) / Float(axialSegments))
            let z = -t
            let radius = t
            for radial in 0..<radialSegments {
                let angle = Float(radial) / Float(radialSegments) * 2 * .pi
                positions.append([cos(angle) * radius, sin(angle) * radius, z])
            }
        }

        for axial in 0..<axialSegments {
            let row = axial * radialSegments
            let nextRow = (axial + 1) * radialSegments
            for radial in 0..<radialSegments {
                let next = (radial + 1) % radialSegments
                let i0 = UInt32(row + radial)
                let i1 = UInt32(row + next)
                let i2 = UInt32(nextRow + radial)
                let i3 = UInt32(nextRow + next)
                appendDoubleSidedQuad(&indices, i0, i1, i2, i3)
            }
        }

        var descriptor = MeshDescriptor(name: "Mach shock cone")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    private static func makeUnitCrossRibbonMesh() -> MeshResource? {
        let positions: [SIMD3<Float>] = [
            [-0.5, 0, -0.5], [0.5, 0, -0.5], [-0.5, 0, 0.5], [0.5, 0, 0.5],
            [0, -0.5, -0.5], [0, 0.5, -0.5], [0, -0.5, 0.5], [0, 0.5, 0.5]
        ]
        var indices: [UInt32] = []
        appendDoubleSidedQuad(&indices, 0, 1, 2, 3)
        appendDoubleSidedQuad(&indices, 4, 5, 6, 7)

        var descriptor = MeshDescriptor(name: "Contrail ribbon segment")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    private static func appendDoubleSidedQuad(
        _ indices: inout [UInt32],
        _ i0: UInt32,
        _ i1: UInt32,
        _ i2: UInt32,
        _ i3: UInt32
    ) {
        indices.append(contentsOf: [i0, i2, i1, i1, i2, i3])
        indices.append(contentsOf: [i0, i1, i2, i1, i3, i2])
    }

    // MARK: - Helpers

    private static func configureTrailSegment(
        _ entity: ModelEntity,
        from start: SIMD3<Float>,
        to end: SIMD3<Float>
    ) -> Float {
        let delta = end - start
        let length = simd_length(delta)
        guard length > 0.01 else {
            entity.isEnabled = false
            return 0.01
        }

        entity.position = (start + end) * 0.5
        entity.orientation = simd_quatf(
            from: SIMD3<Float>(0, 0, 1),
            to: delta / length
        )
        entity.scale = [0.19, 0.19, length]
        entity.isEnabled = true
        return length
    }

    private static func worldPoint(local: SIMD3<Float>, state: AircraftState) -> SIMD3<Float> {
        state.positionMeters + simd_act(state.orientation, local)
    }

    private static func setEffectAlpha(_ entity: ModelEntity, alpha: Float) {
        guard var model = entity.model else { return }
        model.materials = [effectMaterial(alpha: clamp(alpha, 0, 0.32))]
        entity.model = model
    }

    private static func effectMaterial(alpha: Float) -> UnlitMaterial {
        UnlitMaterial(color: UIColor(white: 0.985, alpha: CGFloat(clamp(alpha, 0, 1))))
    }

    private static func clamp(_ value: Float, _ minimum: Float, _ maximum: Float) -> Float {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}