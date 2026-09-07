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
    private static let transonicCloudPrefix = "FA.effects.transonic"

    // 96 samples at 0.10 s gives just under ten seconds of persistent plume
    // history without creating an unbounded RealityKit entity count.
    private static let trailCount = 96

    final class Runtime {
        fileprivate var coreSegments: [ModelEntity] = []
        fileprivate var hazeSegments: [ModelEntity] = []
        fileprivate var birthTimes = Array(repeating: -10_000.0, count: trailCount)
        fileprivate var lengths = Array(repeating: Float(1), count: trailCount)
        fileprivate var strengths = Array(repeating: Float(0), count: trailCount)
        fileprivate var cursor = 0
        fileprivate var lastTrailSampleTime = -10_000.0
        fileprivate var previousExhaustPoint: SIMD3<Float>?
        fileprivate var lastSimulationTime = 0.0

        fileprivate func bind(to root: Entity) {
            guard coreSegments.count != Self.expectedCount else { return }
            coreSegments = (0..<Stage2FlightEffects.trailCount).compactMap {
                root.findEntity(named: "FA.effects.contrail.core.\($0)") as? ModelEntity
            }
            hazeSegments = (0..<Stage2FlightEffects.trailCount).compactMap {
                root.findEntity(named: "FA.effects.contrail.haze.\($0)") as? ModelEntity
            }
        }

        fileprivate func clear() {
            for entity in coreSegments + hazeSegments {
                entity.isEnabled = false
            }
            birthTimes = Array(repeating: -10_000.0, count: Stage2FlightEffects.trailCount)
            lengths = Array(repeating: 1, count: Stage2FlightEffects.trailCount)
            strengths = Array(repeating: 0, count: Stage2FlightEffects.trailCount)
            cursor = 0
            lastTrailSampleTime = -10_000
            previousExhaustPoint = nil
        }

        private static let expectedCount = Stage2FlightEffects.trailCount
    }

    static func makeAttachedEffects() -> Entity {
        let root = Entity()
        root.name = attachedRootName

        if let leftMesh = makeWingVaporMesh(phase: 0.0) {
            let left = ModelEntity(mesh: leftMesh, materials: [effectMaterial(alpha: 0.0)])
            left.name = leftWingVaporName
            left.position = [-3.55, 0.02, -1.60]
            left.isEnabled = false
            root.addChild(left)
        }

        if let rightMesh = makeWingVaporMesh(phase: 1.7) {
            let right = ModelEntity(mesh: rightMesh, materials: [effectMaterial(alpha: 0.0)])
            right.name = rightWingVaporName
            right.position = [3.55, 0.02, -1.60]
            right.isEnabled = false
            root.addChild(right)
        }

        // A visible "Mach cone" in photography is normally a transonic
        // condensation cloud, not the shock wave itself. Three irregular shell
        // layers avoid the old perfect translucent geometric cone.
        for layer in 0..<3 {
            if let mesh = makeTransonicCondensationMesh(phase: Float(layer) * 1.93) {
                let cloud = ModelEntity(mesh: mesh, materials: [effectMaterial(alpha: 0.0)])
                cloud.name = "\(transonicCloudPrefix).\(layer)"
                cloud.position = [0, 0.05, -0.10 - Float(layer) * 0.18]
                cloud.isEnabled = false
                root.addChild(cloud)
            }
        }

        return root
    }

    static func makeTrailPool() -> Entity {
        let root = Entity()
        root.name = trailRootName
        guard let segmentMesh = makePlumeSegmentMesh() else { return root }

        for index in 0..<trailCount {
            let core = ModelEntity(mesh: segmentMesh, materials: [effectMaterial(alpha: 0.0)])
            core.name = "FA.effects.contrail.core.\(index)"
            core.isEnabled = false
            root.addChild(core)

            let haze = ModelEntity(mesh: segmentMesh, materials: [effectMaterial(alpha: 0.0)])
            haze.name = "FA.effects.contrail.haze.\(index)"
            haze.isEnabled = false
            root.addChild(haze)
        }
        return root
    }

    static func updateAttachedEffects(
        aircraft: Entity,
        state: AircraftState,
        simulationTime: TimeInterval
    ) {
        // Permanently retire the Stage 010 primitive vapor/contrail entities.
        for oldName in [
            PrototypeAircraftFactory.vaporLeftName,
            PrototypeAircraftFactory.vaporRightName,
            PrototypeAircraftFactory.contrailLeftName,
            PrototypeAircraftFactory.contrailRightName
        ] {
            aircraft.findEntity(named: oldName)?.isEnabled = false
        }

        guard let root = aircraft.findEntity(named: attachedRootName) else { return }

        updateWingCondensation(root: root, state: state, simulationTime: simulationTime)
        updateTransonicCondensation(root: root, state: state, simulationTime: simulationTime)
    }

    static func updateWorldTrails(
        root: Entity,
        state: AircraftState,
        simulationTime: TimeInterval,
        runtime: Runtime
    ) {
        runtime.bind(to: root)
        guard runtime.coreSegments.count == trailCount,
              runtime.hazeSegments.count == trailCount else { return }

        if simulationTime + 0.001 < runtime.lastSimulationTime {
            runtime.clear()
        }
        runtime.lastSimulationTime = simulationTime

        // Schmidt-Appleman formation depends on temperature, humidity and engine
        // exhaust. Stage 2 does not have a weather humidity field yet, so use ISA
        // temperature as a conservative formation proxy. This can be replaced by
        // live RH/temperature later without changing the plume renderer.
        let ambientTemperatureC = isaTemperatureC(altitudeFeet: state.altitudeFeetMSL)
        let coldFactor = clamp((-36.0 - ambientTemperatureC) / 14.0, 0, 1)
        let altitudeFactor = clamp((state.altitudeFeetMSL - 23_000) / 9_000, 0, 1)
        let speedFactor = clamp((state.calibratedAirspeedKnots - 210) / 170, 0, 1)
        let formationStrength = coldFactor * max(0.32, altitudeFactor) * speedFactor
        let persistentContrail = formationStrength > 0.10 && state.altitudeFeetMSL > 23_000

        if persistentContrail && simulationTime - runtime.lastTrailSampleTime >= 0.10 {
            // F-16A is single-engine. Emit the persistent plume from the F100
            // nozzle instead of incorrectly drawing permanent wingtip trails.
            // This point is in the aircraft CG/root frame; the visual airframe has
            // its own vertical offset.
            let exhaust = worldPoint(local: [0, -0.20, -7.75], state: state)

            if let previous = runtime.previousExhaustPoint {
                let index = runtime.cursor
                runtime.lengths[index] = configureTrailSegment(
                    runtime.coreSegments[index],
                    from: previous,
                    to: exhaust
                )
                _ = configureTrailSegment(
                    runtime.hazeSegments[index],
                    from: previous,
                    to: exhaust
                )
                runtime.birthTimes[index] = simulationTime
                runtime.strengths[index] = formationStrength
                runtime.cursor = (runtime.cursor + 1) % trailCount
            }

            runtime.previousExhaustPoint = exhaust
            runtime.lastTrailSampleTime = simulationTime
        } else if !persistentContrail {
            runtime.previousExhaustPoint = nil
        }

        let lifetime: Double = 9.4
        for index in 0..<trailCount {
            let age = simulationTime - runtime.birthTimes[index]
            let core = runtime.coreSegments[index]
            let haze = runtime.hazeSegments[index]

            guard age >= 0, age < lifetime else {
                core.isEnabled = false
                haze.isEnabled = false
                continue
            }

            let t = Float(age / lifetime)
            let strength = runtime.strengths[index]

            // Young exhaust is narrow and bright. Wake mixing then broadens the
            // plume and shifts opacity from its core into a diffuse outer haze.
            let ageF = Float(age)
            let coreRadius = 0.12 + 0.095 * ageF + 0.014 * ageF * ageF
            let hazeRadius = 0.28 + 0.19 * ageF + 0.022 * ageF * ageF
            let coreFade = pow(max(0, 1 - t), 1.45)
            let hazeEnvelope = sin(.pi * min(1, t * 1.10)) * pow(max(0, 1 - t), 0.78)

            core.isEnabled = true
            haze.isEnabled = true
            core.scale = [coreRadius, coreRadius, runtime.lengths[index]]
            haze.scale = [hazeRadius, hazeRadius, runtime.lengths[index]]

            // Very small settling/expansion displacement keeps an old plume from
            // reading like a rigid tube attached to the aircraft trajectory.
            let settling = ageF * ageF * 0.007
            core.position.y -= settling * 0.010
            haze.position.y -= settling * 0.018

            setEffectAlpha(core, alpha: 0.17 * strength * coreFade)
            setEffectAlpha(haze, alpha: 0.075 * strength * hazeEnvelope)
        }
    }

    // MARK: - Aerodynamic condensation

    private static func updateWingCondensation(
        root: Entity,
        state: AircraftState,
        simulationTime: TimeInterval
    ) {
        let gIntensity = clamp((abs(state.loadFactorG) - 2.7) / 4.8, 0, 1)
        let alphaIntensity = clamp((abs(state.angleOfAttackDegrees) - 7.5) / 13.0, 0, 1)
        let qbarIntensity = clamp((state.dynamicPressurePSF - 120) / 520.0, 0, 1)
        let vaporIntensity = max(gIntensity, alphaIntensity) * qbarIntensity
        let vaporEnabled = vaporIntensity > 0.055 && state.calibratedAirspeedKnots > 170

        let alpha = state.angleOfAttackDegrees * .pi / 180
        let beta = state.sideslipDegrees * .pi / 180
        let flowOrientation =
            simd_quatf(angle: -beta, axis: [0, 1, 0]) *
            simd_quatf(angle: alpha, axis: [1, 0, 0])

        if let left = root.findEntity(named: leftWingVaporName) as? ModelEntity {
            left.isEnabled = vaporEnabled
            left.orientation = flowOrientation
            left.position = [-3.55, 0.02 + 0.010 * sin(Float(simulationTime) * 24.0), -1.60]
            left.scale = [
                0.76 + vaporIntensity * 0.48,
                0.72 + vaporIntensity * 0.32,
                0.90 + vaporIntensity * 1.25
            ]
            setEffectAlpha(left, alpha: 0.025 + vaporIntensity * 0.16)
        }

        if let right = root.findEntity(named: rightWingVaporName) as? ModelEntity {
            right.isEnabled = vaporEnabled
            right.orientation = flowOrientation
            right.position = [3.55, 0.02 + 0.010 * sin(Float(simulationTime) * 25.0 + 0.8), -1.60]
            right.scale = [
                0.76 + vaporIntensity * 0.48,
                0.72 + vaporIntensity * 0.32,
                0.90 + vaporIntensity * 1.25
            ]
            setEffectAlpha(right, alpha: 0.025 + vaporIntensity * 0.16)
        }
    }

    private static func updateTransonicCondensation(
        root: Entity,
        state: AircraftState,
        simulationTime: TimeInterval
    ) {
        // The pressure wave itself is not a white cone. The visible phenomenon is
        // a short-lived condensation cloud when local pressure/temperature drop
        // enough in humid air. Keep the visual tightly centered around Mach 1.
        let mach = state.mach
        let transonicPeak = exp(-pow((mach - 1.005) / 0.038, 2))
        let qbarFactor = clamp((state.dynamicPressurePSF - 180) / 650.0, 0, 1)
        let altitudeMoistureProxy = 1 - 0.55 * clamp((state.altitudeFeetMSL - 18_000) / 22_000, 0, 1)
        let alphaPenalty = 1 - 0.45 * clamp(abs(state.angleOfAttackDegrees) / 18.0, 0, 1)
        let intensity = transonicPeak * qbarFactor * altitudeMoistureProxy * alphaPenalty
        let visible = mach > 0.955 && mach < 1.085 && intensity > 0.025

        for layer in 0..<3 {
            guard let cloud = root.findEntity(named: "\(transonicCloudPrefix).\(layer)") as? ModelEntity else {
                continue
            }
            let phase = Float(layer) * 1.73
            let flutter = 1 + 0.018 * sin(Float(simulationTime) * (18 + Float(layer) * 2.4) + phase)
            let layerScale = 0.92 + Float(layer) * 0.08
            cloud.isEnabled = visible
            cloud.scale = [
                layerScale * flutter,
                layerScale * (0.94 + 0.02 * sin(Float(simulationTime) * 13 + phase)),
                0.94 + intensity * 0.22
            ]
            cloud.position.y = 0.05 + 0.05 * sin(Float(simulationTime) * 11 + phase)
            setEffectAlpha(cloud, alpha: (0.050 - Float(layer) * 0.010) * intensity)
        }
    }

    // MARK: - Geometry

    private static func makeWingVaporMesh(phase: Float) -> MeshResource? {
        let segments = 22
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        // Crossed tapered sheets give the condensation volume from chase, side
        // and underside views without a primitive sphere/tube.
        for sheet in 0..<3 {
            let base = UInt32(positions.count)
            let sheetAngle = Float(sheet) * (.pi / 3)
            let c = cos(sheetAngle)
            let s = sin(sheetAngle)

            for index in 0..<segments {
                let t = Float(index) / Float(segments - 1)
                let z = -0.10 - 7.4 * t
                let envelope = sin(.pi * min(1, t * 1.16)) * (1 - 0.50 * t)
                let width = 0.08 + 0.56 * envelope
                let ripple = sin(t * 17.0 + phase + Float(sheet)) * 0.045 * t
                let a = SIMD2<Float>(-width, ripple)
                let b = SIMD2<Float>(width, -ripple)
                positions.append([a.x * c - a.y * s, a.x * s + a.y * c, z])
                positions.append([b.x * c - b.y * s, b.x * s + b.y * c, z])
            }

            for index in 0..<(segments - 1) {
                let i0 = base + UInt32(index * 2)
                let i1 = i0 + 1
                let i2 = i0 + 2
                let i3 = i0 + 3
                appendDoubleSidedQuad(&indices, i0, i1, i2, i3)
            }
        }

        var descriptor = MeshDescriptor(name: "Wing condensation volume")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    private static func makeTransonicCondensationMesh(phase: Float) -> MeshResource? {
        let radialSegments = 44
        let axialSegments = 18
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        // Irregular annular cloud envelope around the wing/fuselage pressure-drop
        // region. This intentionally is not a perfect Mach-angle cone: visible
        // transonic vapor photography is a condensation cloud, not the shockwave.
        for axial in 0...axialSegments {
            let t = Float(axial) / Float(axialSegments)
            let z = 2.7 - 6.2 * t
            let center = exp(-pow((t - 0.48) / 0.23, 2))
            let baseRadius = 0.72 + 3.25 * center

            for radial in 0..<radialSegments {
                let angle = Float(radial) / Float(radialSegments) * 2 * .pi
                let irregular = 1
                    + 0.055 * sin(angle * 5 + phase + t * 7)
                    + 0.028 * sin(angle * 11 - phase * 0.7 + t * 13)
                let radius = baseRadius * irregular
                positions.append([
                    cos(angle) * radius,
                    sin(angle) * radius * 0.72,
                    z
                ])
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

        var descriptor = MeshDescriptor(name: "Transonic condensation cloud")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    private static func makePlumeSegmentMesh() -> MeshResource? {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        // Three intersecting ribbon planes approximate a soft volumetric plume
        // from arbitrary viewing angles with far fewer entities than particles.
        for sheet in 0..<3 {
            let angle = Float(sheet) * (.pi / 3)
            let c = cos(angle)
            let s = sin(angle)
            let base = UInt32(positions.count)
            let points: [SIMD2<Float>] = [
                [-0.5, 0], [0.5, 0], [-0.5, 0], [0.5, 0]
            ]
            let z: [Float] = [-0.5, -0.5, 0.5, 0.5]
            for i in 0..<4 {
                let p = points[i]
                positions.append([p.x * c - p.y * s, p.x * s + p.y * c, z[i]])
            }
            appendDoubleSidedQuad(&indices, base, base + 1, base + 2, base + 3)
        }

        var descriptor = MeshDescriptor(name: "Contrail plume segment")
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
        entity.scale = [0.12, 0.12, length]
        entity.isEnabled = true
        return length
    }

    private static func isaTemperatureC(altitudeFeet: Float) -> Float {
        let altitudeMeters = max(0, altitudeFeet * 0.3048)
        if altitudeMeters <= 11_000 {
            return 15.0 - 0.0065 * altitudeMeters
        }
        return -56.5
    }

    private static func worldPoint(local: SIMD3<Float>, state: AircraftState) -> SIMD3<Float> {
        state.positionMeters + simd_act(state.orientation, local)
    }

    private static func setEffectAlpha(_ entity: ModelEntity, alpha: Float) {
        guard var model = entity.model else { return }
        model.materials = [effectMaterial(alpha: clamp(alpha, 0, 0.30))]
        entity.model = model
    }

    private static func effectMaterial(alpha: Float) -> UnlitMaterial {
        UnlitMaterial(color: UIColor(white: 0.985, alpha: CGFloat(clamp(alpha, 0, 1))))
    }

    private static func clamp(_ value: Float, _ minimum: Float, _ maximum: Float) -> Float {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}
