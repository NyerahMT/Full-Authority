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

    // Bounded mobile pool: about twenty seconds of spatial history at 0.11 s sampling.
    private static let trailCount = 180

    @MainActor
    final class Runtime {
        fileprivate var coreSegments: [ModelEntity] = []
        fileprivate var hazeSegments: [ModelEntity] = []
        fileprivate var birthTimes = Array(repeating: -10_000.0, count: trailCount)
        fileprivate var lengths = Array(repeating: Float(1), count: trailCount)
        fileprivate var strengths = Array(repeating: Float(0), count: trailCount)
        fileprivate var persistences = Array(repeating: Float(0), count: trailCount)
        fileprivate var driftVelocities = Array(repeating: SIMD3<Float>.zero, count: trailCount)
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
            persistences = Array(repeating: 0, count: Stage2FlightEffects.trailCount)
            driftVelocities = Array(repeating: .zero, count: Stage2FlightEffects.trailCount)
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

        let coreVariants = (0..<4).compactMap {
            makePlumeSegmentMesh(phase: Float($0) * 1.37, haze: false)
        }
        let hazeVariants = (0..<4).compactMap {
            makePlumeSegmentMesh(phase: Float($0) * 1.37 + 0.71, haze: true)
        }
        guard coreVariants.count == 4, hazeVariants.count == 4 else { return root }

        for index in 0..<trailCount {
            let core = ModelEntity(
                mesh: coreVariants[index % coreVariants.count],
                materials: [effectMaterial(alpha: 0.0)]
            )
            core.name = "FA.effects.contrail.core.\(index)"
            core.isEnabled = false
            root.addChild(core)

            let haze = ModelEntity(
                mesh: hazeVariants[index % hazeVariants.count],
                materials: [effectMaterial(alpha: 0.0)]
            )
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

        let frameDelta = Float(max(0, min(simulationTime - runtime.lastSimulationTime, 0.10)))
        runtime.lastSimulationTime = simulationTime

        if frameDelta > 0 {
            for index in 0..<trailCount where runtime.birthTimes[index] > -9_000 {
                let drift = runtime.driftVelocities[index] * frameDelta
                runtime.coreSegments[index].position += drift
                runtime.hazeSegments[index].position += drift
            }
        }

        let iceRH = iceRelativeHumidity(
            positionMeters: state.positionMeters,
            altitudeFeet: state.altitudeFeetMSL
        )
        let criticalTemperatureC = schmidtApplemanCriticalTemperatureC(
            pressurePSF: state.ambientPressurePSF
        )
        let temperatureMargin = criticalTemperatureC - state.ambientTemperatureC
        let temperatureFactor = clamp((temperatureMargin + 1.0) / 8.0, 0, 1)
        let humidityFormationFactor = clamp((iceRH - 0.70) / 0.30, 0, 1)
        let fuelFlow = state.engineFuelFlowPoundsPerSecond
        let exhaustWaterFactor = clamp((fuelFlow - 0.015) / 0.65, 0, 1)
        let formationStrength = temperatureFactor
            * humidityFormationFactor
            * (0.30 + 0.70 * exhaustWaterFactor)
        let persistence = clamp((iceRH - 0.96) / 0.20, 0, 1)
        let formsContrail = temperatureMargin > -0.5
            && iceRH > 0.70
            && fuelFlow > 0.012
            && formationStrength > 0.025

        if formsContrail && simulationTime - runtime.lastTrailSampleTime >= 0.11 {
            let exhaust = worldPoint(local: [0, -0.21, -7.95], state: state)

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
                runtime.persistences[index] = persistence
                let wakeDescent = 0.10 + 0.12 * (1 - persistence)
                runtime.driftVelocities[index] = state.windMetersPerSecond + SIMD3<Float>(0, -wakeDescent, 0)
                runtime.cursor = (runtime.cursor + 1) % trailCount
            }

            runtime.previousExhaustPoint = exhaust
            runtime.lastTrailSampleTime = simulationTime
        } else if !formsContrail {
            runtime.previousExhaustPoint = nil
        }

        for index in 0..<trailCount {
            let age = simulationTime - runtime.birthTimes[index]
            let core = runtime.coreSegments[index]
            let haze = runtime.hazeSegments[index]
            let persistence = runtime.persistences[index]
            let lifetime = 2.4 + 17.4 * Double(persistence)

            guard age >= 0, age < lifetime else {
                core.isEnabled = false
                haze.isEnabled = false
                continue
            }

            let ageF = Float(age)
            let normalizedAge = Float(age / lifetime)
            let strength = runtime.strengths[index]
            let variation = 1
                + 0.10 * sin(Float(index) * 1.71 + ageF * 0.43)
                + 0.04 * sin(Float(index) * 0.37 - ageF * 0.81)
            let coreRadius = (0.11 + 0.075 * ageF + 0.010 * ageF * ageF) * variation
            let hazeRadius = (0.32 + 0.19 * ageF + 0.026 * ageF * ageF) * (2 - variation)
            let coreFade = exp(-ageF / 4.2) * pow(max(0, 1 - normalizedAge), 0.65)
            let hazeBuild = clamp(ageF / 2.0, 0, 1)
            let hazeFade = pow(max(0, 1 - normalizedAge), 0.45)

            core.isEnabled = true
            haze.isEnabled = true
            core.scale = [coreRadius, coreRadius, runtime.lengths[index]]
            haze.scale = [hazeRadius, hazeRadius, runtime.lengths[index]]

            setEffectAlpha(core, alpha: 0.21 * strength * coreFade)
            setEffectAlpha(
                haze,
                alpha: 0.105 * strength * hazeBuild * hazeFade * (0.40 + 0.60 * persistence)
            )
        }
    }

    // MARK: - Aerodynamic condensation

    private static func updateWingCondensation(
        root: Entity,
        state: AircraftState,
        simulationTime: TimeInterval
    ) {
        let iceRH = iceRelativeHumidity(
            positionMeters: state.positionMeters,
            altitudeFeet: state.altitudeFeetMSL
        )
        let moisture = clamp((iceRH - 0.62) / 0.38, 0, 1)
        let gIntensity = clamp((abs(state.loadFactorG) - 2.4) / 4.8, 0, 1)
        let alphaIntensity = clamp((abs(state.angleOfAttackDegrees) - 6.8) / 13.5, 0, 1)
        let qbarIntensity = clamp((state.dynamicPressurePSF - 115) / 560.0, 0, 1)
        let vaporIntensity = max(gIntensity, alphaIntensity) * qbarIntensity * moisture
        let vaporEnabled = vaporIntensity > 0.065 && state.calibratedAirspeedKnots > 165

        let alpha = state.angleOfAttackDegrees * .pi / 180
        let beta = state.sideslipDegrees * .pi / 180
        let flowOrientation =
            simd_quatf(angle: -beta, axis: [0, 1, 0]) *
            simd_quatf(angle: alpha, axis: [1, 0, 0])

        if let left = root.findEntity(named: leftWingVaporName) as? ModelEntity {
            left.isEnabled = vaporEnabled
            left.orientation = flowOrientation
            left.position = [-3.62, -0.08 + 0.008 * sin(Float(simulationTime) * 24.0), -1.72]
            left.scale = [0.68 + vaporIntensity * 0.52, 0.62 + vaporIntensity * 0.34, 0.72 + vaporIntensity * 1.18]
            setEffectAlpha(left, alpha: 0.020 + vaporIntensity * 0.155)
        }

        if let right = root.findEntity(named: rightWingVaporName) as? ModelEntity {
            right.isEnabled = vaporEnabled
            right.orientation = flowOrientation
            right.position = [3.62, -0.08 + 0.008 * sin(Float(simulationTime) * 25.0 + 0.8), -1.72]
            right.scale = [0.68 + vaporIntensity * 0.52, 0.62 + vaporIntensity * 0.34, 0.72 + vaporIntensity * 1.18]
            setEffectAlpha(right, alpha: 0.020 + vaporIntensity * 0.155)
        }
    }

    private static func updateTransonicCondensation(
        root: Entity,
        state: AircraftState,
        simulationTime: TimeInterval
    ) {
        let iceRH = iceRelativeHumidity(
            positionMeters: state.positionMeters,
            altitudeFeet: state.altitudeFeetMSL
        )
        let moisture = clamp((iceRH - 0.64) / 0.40, 0, 1)
        let mach = state.mach
        let transonicPeak = exp(-pow((mach - 1.005) / 0.038, 2))
        let qbarFactor = clamp((state.dynamicPressurePSF - 180) / 650.0, 0, 1)
        let alphaPenalty = 1 - 0.45 * clamp(abs(state.angleOfAttackDegrees) / 18.0, 0, 1)
        let intensity = transonicPeak * qbarFactor * moisture * alphaPenalty
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
            cloud.position.y = -0.02 + 0.04 * sin(Float(simulationTime) * 11 + phase)
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

    private static func makePlumeSegmentMesh(phase: Float, haze: Bool) -> MeshResource? {
        let sheets = haze ? 5 : 4
        let axialStations = 6
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for sheet in 0..<sheets {
            let base = UInt32(positions.count)
            let angle = Float(sheet) / Float(sheets) * .pi
            let c = cos(angle)
            let s = sin(angle)

            for station in 0..<axialStations {
                let t = Float(station) / Float(axialStations - 1)
                let z = t - 0.5
                let envelope = 0.80 + 0.20 * sin(.pi * t)
                let ragged = 1
                    + 0.12 * sin(t * 12.0 + phase + Float(sheet) * 0.91)
                    + 0.05 * sin(t * 27.0 - phase * 0.7)
                let width = (haze ? 1.0 : 0.72) * envelope * ragged
                let offset = (haze ? 0.13 : 0.07) * sin(t * 18.0 + phase * 1.3 + Float(sheet))
                let a = SIMD2<Float>(-width, offset)
                let b = SIMD2<Float>(width, -offset * 0.72)
                positions.append([a.x * c - a.y * s, a.x * s + a.y * c, z])
                positions.append([b.x * c - b.y * s, b.x * s + b.y * c, z])
            }

            for station in 0..<(axialStations - 1) {
                let i0 = base + UInt32(station * 2)
                appendDoubleSidedQuad(&indices, i0, i0 + 1, i0 + 2, i0 + 3)
            }
        }

        var descriptor = MeshDescriptor(name: haze ? "Contrail diffuse ice" : "Contrail ice core")
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

    private static func schmidtApplemanCriticalTemperatureC(pressurePSF: Float) -> Float {
        let pressurePa = max(1_000.0, Double(pressurePSF) * 47.88025898)
        let cp = 1_004.0
        let epsilon = 0.622
        let waterEmissionIndex = 1.25
        let fuelHeat = 43_000_000.0
        let propulsionEfficiency = 0.30
        let g = (pressurePa * cp / epsilon)
            * (waterEmissionIndex / ((1 - propulsionEfficiency) * fuelHeat))
        let argument = max(g - 0.053, 0.001)
        let logarithm = log(argument)
        return Float(-46.46 + 9.43 * logarithm + 0.72 * logarithm * logarithm)
    }

    private static func iceRelativeHumidity(
        positionMeters: SIMD3<Float>,
        altitudeFeet: Float
    ) -> Float {
        // Standard JSBSim atmosphere has no humidity field, so Stage 2 supplies a
        // deterministic world-space moisture layer. It creates coherent ISSR-like
        // pockets without coupling the visual effect back into aircraft dynamics.
        let x = positionMeters.x
        let z = positionMeters.z
        let h = altitudeFeet
        let upperTroposphereBand = 0.24 * exp(-pow((h - 34_000) / 9_000, 2))
        let synopticWave = 0.11 * sin(x / 7_400)
            + 0.09 * cos(z / 8_900)
            + 0.07 * sin((x + z) / 5_100)
        let verticalWave = 0.06 * sin(h / 4_300 + x / 18_000)
        return clamp(0.72 + upperTroposphereBand + synopticWave + verticalWave, 0.42, 1.32)
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
