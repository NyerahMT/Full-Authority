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

    // Bounded mobile pool: world-space exhaust history that is advected by the live wind field.
    private static let trailCount = 180

    @MainActor
    final class Runtime {
        fileprivate var coreSegments: [ModelEntity] = []
        fileprivate var vortexSegments: [ModelEntity] = []
        fileprivate var secondarySegments: [ModelEntity] = []
        fileprivate var birthTimes = Array(repeating: -10_000.0, count: trailCount)
        fileprivate var lengths = Array(repeating: Float(1), count: trailCount)
        fileprivate var strengths = Array(repeating: Float(0), count: trailCount)
        fileprivate var persistences = Array(repeating: Float(0), count: trailCount)
        fileprivate var windVelocities = Array(repeating: SIMD3<Float>.zero, count: trailCount)
        fileprivate var wakeDescentRates = Array(repeating: Float(0), count: trailCount)
        fileprivate var cursor = 0
        fileprivate var lastTrailSampleTime = -10_000.0
        fileprivate var previousExhaustPoint: SIMD3<Float>?
        fileprivate var lastSimulationTime = 0.0

        fileprivate func bind(to root: Entity) {
            guard coreSegments.count != Self.expectedCount else { return }
            coreSegments = (0..<Stage2FlightEffects.trailCount).compactMap {
                root.findEntity(named: "FA.effects.contrail.core.\($0)") as? ModelEntity
            }
            vortexSegments = (0..<Stage2FlightEffects.trailCount).compactMap {
                root.findEntity(named: "FA.effects.contrail.vortex.\($0)") as? ModelEntity
            }
            secondarySegments = (0..<Stage2FlightEffects.trailCount).compactMap {
                root.findEntity(named: "FA.effects.contrail.secondary.\($0)") as? ModelEntity
            }
        }

        fileprivate func clear() {
            for entity in coreSegments + vortexSegments + secondarySegments {
                entity.isEnabled = false
            }
            birthTimes = Array(repeating: -10_000.0, count: Stage2FlightEffects.trailCount)
            lengths = Array(repeating: 1, count: Stage2FlightEffects.trailCount)
            strengths = Array(repeating: 0, count: Stage2FlightEffects.trailCount)
            persistences = Array(repeating: 0, count: Stage2FlightEffects.trailCount)
            windVelocities = Array(repeating: .zero, count: Stage2FlightEffects.trailCount)
            wakeDescentRates = Array(repeating: 0, count: Stage2FlightEffects.trailCount)
            cursor = 0
            lastTrailSampleTime = -10_000
            previousExhaustPoint = nil
        }

        private static let expectedCount = Stage2FlightEffects.trailCount
    }

    static func makeAttachedEffects() -> Entity {
        let root = Entity()
        root.name = attachedRootName

        if let leftMesh = makeWingVaporMesh(phase: 0.0, side: -1) {
            let left = ModelEntity(mesh: leftMesh, materials: [effectMaterial(alpha: 0.0)])
            left.name = leftWingVaporName
            left.position = [-4.55, -0.06, -1.55]
            left.isEnabled = false
            root.addChild(left)
        }

        if let rightMesh = makeWingVaporMesh(phase: 1.7, side: 1) {
            let right = ModelEntity(mesh: rightMesh, materials: [effectMaterial(alpha: 0.0)])
            right.name = rightWingVaporName
            right.position = [4.55, -0.06, -1.55]
            right.isEnabled = false
            root.addChild(right)
        }

        // The visible transonic effect is a thin pressure-condensation collar
        // around the wing-root/fuselage region. It is deliberately NOT a cone
        // primitive and not a filled ball of white vapor.
        for layer in 0..<2 {
            if let mesh = makeTransonicCondensationMesh(phase: Float(layer) * 1.93) {
                let cloud = ModelEntity(mesh: mesh, materials: [effectMaterial(alpha: 0.0)])
                cloud.name = "\(transonicCloudPrefix).\(layer)"
                cloud.position = [0, 0.00, -0.22 - Float(layer) * 0.12]
                cloud.isEnabled = false
                root.addChild(cloud)
            }
        }

        return root
    }

    static func makeTrailPool() -> Entity {
        let root = Entity()
        root.name = trailRootName

        let coreVariants = (0..<4).compactMap { makeJetCoreSegmentMesh(phase: Float($0) * 1.31) }
        let vortexVariants = (0..<4).compactMap { makeVortexPairSegmentMesh(phase: Float($0) * 1.57) }
        let secondaryVariants = (0..<4).compactMap { makeSecondaryWakeSegmentMesh(phase: Float($0) * 1.83) }
        guard coreVariants.count == 4, vortexVariants.count == 4, secondaryVariants.count == 4 else { return root }

        for index in 0..<trailCount {
            let core = ModelEntity(mesh: coreVariants[index % 4], materials: [effectMaterial(alpha: 0.0)])
            core.name = "FA.effects.contrail.core.\(index)"
            core.isEnabled = false
            root.addChild(core)

            let vortex = ModelEntity(mesh: vortexVariants[index % 4], materials: [effectMaterial(alpha: 0.0)])
            vortex.name = "FA.effects.contrail.vortex.\(index)"
            vortex.isEnabled = false
            root.addChild(vortex)

            let secondary = ModelEntity(mesh: secondaryVariants[index % 4], materials: [effectMaterial(alpha: 0.0)])
            secondary.name = "FA.effects.contrail.secondary.\(index)"
            secondary.isEnabled = false
            root.addChild(secondary)
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
              runtime.vortexSegments.count == trailCount,
              runtime.secondarySegments.count == trailCount else { return }

        if simulationTime + 0.001 < runtime.lastSimulationTime { runtime.clear() }
        let frameDelta = Float(max(0, min(simulationTime - runtime.lastSimulationTime, 0.10)))
        runtime.lastSimulationTime = simulationTime

        if frameDelta > 0 {
            for index in 0..<trailCount where runtime.birthTimes[index] > -9_000 {
                let age = Float(max(0, simulationTime - runtime.birthTimes[index]))
                let wind = runtime.windVelocities[index] * frameDelta
                let wake = runtime.wakeDescentRates[index]
                let downwashEnvelope = exp(-age / 7.5)
                runtime.coreSegments[index].position += wind + [0, -0.16 * wake * downwashEnvelope * frameDelta, 0]
                runtime.vortexSegments[index].position += wind + [0, -wake * downwashEnvelope * frameDelta, 0]
                runtime.secondarySegments[index].position += wind
            }
        }

        // Formation physics uses live JSBSim temperature, pressure and F100 fuel
        // flow plus a deterministic visual-only ice-relative-humidity world field.
        let iceRH = iceRelativeHumidity(positionMeters: state.positionMeters, altitudeFeet: state.altitudeFeetMSL)
        let criticalTemperatureC = schmidtApplemanCriticalTemperatureC(pressurePSF: state.ambientPressurePSF)
        let temperatureMargin = criticalTemperatureC - state.ambientTemperatureC
        let temperatureFactor = clamp((temperatureMargin + 1.0) / 8.0, 0, 1)
        let humidityFormationFactor = clamp((iceRH - 0.70) / 0.30, 0, 1)
        let fuelFlow = state.engineFuelFlowPoundsPerSecond
        let exhaustWaterFactor = clamp((fuelFlow - 0.015) / 0.65, 0, 1)
        let formationStrength = temperatureFactor * humidityFormationFactor * (0.30 + 0.70 * exhaustWaterFactor)
        let persistence = clamp((iceRH - 0.96) / 0.20, 0, 1)
        let formsContrail = temperatureMargin > -0.5 && iceRH > 0.70 && fuelFlow > 0.012 && formationStrength > 0.025

        if formsContrail && simulationTime - runtime.lastTrailSampleTime >= 0.11 {
            // The current authored nozzle lip is about z = -7.02 m. Contrails
            // begin after a short hot exhaust mixing region instead of appearing
            // as if they are painted directly on the nozzle.
            let exhaust = worldPoint(local: [0, -0.04, -7.58], state: state)
            if let previous = runtime.previousExhaustPoint {
                let index = runtime.cursor
                runtime.lengths[index] = configureTrailSegment(runtime.coreSegments[index], from: previous, to: exhaust)
                _ = configureTrailSegment(runtime.vortexSegments[index], from: previous, to: exhaust)
                _ = configureTrailSegment(runtime.secondarySegments[index], from: previous, to: exhaust)
                runtime.birthTimes[index] = simulationTime
                runtime.strengths[index] = formationStrength
                runtime.persistences[index] = persistence
                runtime.windVelocities[index] = state.windMetersPerSecond
                runtime.wakeDescentRates[index] = initialWakeDescentRate(state: state)
                runtime.cursor = (runtime.cursor + 1) % trailCount
            }
            runtime.previousExhaustPoint = exhaust
            runtime.lastTrailSampleTime = simulationTime
        } else if !formsContrail {
            runtime.previousExhaustPoint = nil
        }

        // CoCiP/Schumann rolled-up vortex spacing b0 = pi*b/4. F-16A span
        // 9.96m gives roughly 7.82m between primary wake-vortex cores.
        let wakeVortexSeparation = Float.pi * 9.96 / 4.0

        for index in 0..<trailCount {
            let age = simulationTime - runtime.birthTimes[index]
            let core = runtime.coreSegments[index]
            let vortex = runtime.vortexSegments[index]
            let secondary = runtime.secondarySegments[index]
            let persistence = runtime.persistences[index]
            let lifetime = 2.4 + 17.4 * Double(persistence)
            guard age >= 0, age < lifetime else {
                core.isEnabled = false; vortex.isEnabled = false; secondary.isEnabled = false
                continue
            }

            let ageF = Float(age)
            let normalizedAge = Float(age / lifetime)
            let strength = runtime.strengths[index]

            // Jet regime: narrow engine-exhaust core, quickly rolled into wake.
            let jetFade = exp(-ageF / 1.65) * pow(max(0, 1 - normalizedAge), 0.5)
            let jetRadius = 0.070 + 0.030 * min(ageF, 3.0)
            core.isEnabled = jetFade * strength > 0.006
            core.scale = [jetRadius, jetRadius * 0.90, runtime.lengths[index]]
            setEffectAlpha(core, alpha: 0.13 * strength * jetFade)

            // Primary wake: two counter-rotating lobes spread toward rolled-up
            // vortex spacing while descending under mutual induction.
            let rollup = smoothStep(clamp((ageF - 0.45) / 4.8, 0, 1))
            let breakup = clamp((ageF - 8.0) / 8.0, 0, 1)
            let pairWidth = 0.85 + rollup * (wakeVortexSeparation - 0.85) + breakup * 2.2
            let pairDepth = 0.90 + rollup * 0.30 + ageF * 0.025
            let vortexBuild = smoothStep(clamp((ageF - 0.35) / 1.8, 0, 1))
            let vortexFade = pow(max(0, 1 - normalizedAge), 0.52)
            vortex.isEnabled = vortexBuild * vortexFade * strength > 0.005
            vortex.scale = [pairWidth, pairDepth, runtime.lengths[index]]
            setEffectAlpha(vortex, alpha: 0.052 * strength * vortexBuild * vortexFade * (0.55 + 0.45 * persistence))

            // Secondary wake: detrained ice remains near flight level while the
            // primary pair descends, so it is delayed, broad and deliberately wispy.
            let secondaryBuild = smoothStep(clamp((ageF - 2.0) / 4.0, 0, 1))
            let secondaryFade = pow(max(0, 1 - normalizedAge), 0.65)
            let secondaryWidth = 0.80 + ageF * (0.12 + 0.12 * persistence)
            let secondaryDepth = 0.18 + ageF * 0.030
            secondary.isEnabled = secondaryBuild * secondaryFade * strength * persistence > 0.010
            secondary.scale = [secondaryWidth, secondaryDepth, runtime.lengths[index]]
            setEffectAlpha(secondary, alpha: 0.020 * strength * persistence * secondaryBuild * secondaryFade)
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

        // Wing-tip vapor is driven by a lift/circulation proxy, not by speed
        // alone. It takes humid air plus meaningful G/AoA and dynamic pressure.
        let moisture = clamp((iceRH - 0.72) / 0.30, 0, 1)
        let gIntensity = clamp((abs(state.loadFactorG) - 3.0) / 4.8, 0, 1)
        let alphaIntensity = clamp((abs(state.angleOfAttackDegrees) - 8.0) / 10.5, 0, 1)
        let qbarIntensity = clamp((state.dynamicPressurePSF - 145) / 650.0, 0, 1)
        let circulation = max(gIntensity, alphaIntensity * 0.90) * qbarIntensity
        let vaporIntensity = circulation * moisture
        let vaporEnabled = vaporIntensity > 0.10 && state.calibratedAirspeedKnots > 175

        let alpha = state.angleOfAttackDegrees * .pi / 180
        let beta = state.sideslipDegrees * .pi / 180
        let flowOrientation =
            simd_quatf(angle: -beta, axis: [0, 1, 0]) *
            simd_quatf(angle: alpha, axis: [1, 0, 0])

        let flicker = 1.0 + 0.035 * sin(Float(simulationTime) * 17.0)
        let streamwiseScale = (0.82 + 0.30 * vaporIntensity) * flicker
        let transverseScale = 0.82 + 0.22 * vaporIntensity
        let alphaValue = 0.010 + 0.075 * vaporIntensity

        if let left = root.findEntity(named: leftWingVaporName) as? ModelEntity {
            left.isEnabled = vaporEnabled
            left.orientation = flowOrientation
            left.position = [-4.55, -0.06, -1.55]
            left.scale = [transverseScale, transverseScale, streamwiseScale]
            setEffectAlpha(left, alpha: alphaValue)
        }

        if let right = root.findEntity(named: rightWingVaporName) as? ModelEntity {
            right.isEnabled = vaporEnabled
            right.orientation = flowOrientation
            right.position = [4.55, -0.06, -1.55]
            right.scale = [transverseScale, transverseScale, streamwiseScale]
            setEffectAlpha(right, alpha: alphaValue)
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
        let moisture = clamp((iceRH - 0.76) / 0.26, 0, 1)
        let mach = state.mach

        // Condensation is localized to the transonic pressure field. The visible
        // cloud peaks very near Mach 1 and falls away rapidly either side.
        let transonicPeak = exp(-pow((mach - 0.995) / 0.030, 2))
        let qbarFactor = clamp((state.dynamicPressurePSF - 220) / 720.0, 0, 1)
        let alphaFactor = 0.72 + 0.28 * clamp(abs(state.angleOfAttackDegrees) / 10.0, 0, 1)
        let intensity = transonicPeak * qbarFactor * moisture * alphaFactor
        let visible = mach > 0.965 && mach < 1.045 && intensity > 0.055

        let alpha = state.angleOfAttackDegrees * .pi / 180
        let beta = state.sideslipDegrees * .pi / 180
        let flowOrientation =
            simd_quatf(angle: -beta * 0.45, axis: [0, 1, 0]) *
            simd_quatf(angle: alpha * 0.35, axis: [1, 0, 0])

        for layer in 0..<2 {
            guard let cloud = root.findEntity(named: "\(transonicCloudPrefix).\(layer)") as? ModelEntity else {
                continue
            }
            let phase = Float(layer) * 1.61
            let breathe = 1.0 + 0.018 * sin(Float(simulationTime) * 12.0 + phase)
            cloud.isEnabled = visible
            cloud.orientation = flowOrientation
            cloud.position = [0, -0.01 + 0.012 * sin(Float(simulationTime) * 9.0 + phase), -0.18 - Float(layer) * 0.10]
            cloud.scale = [
                (0.96 + 0.08 * intensity) * breathe,
                0.88 + 0.10 * intensity,
                0.92 + 0.06 * intensity
            ]
            setEffectAlpha(cloud, alpha: (0.030 - Float(layer) * 0.010) * intensity)
        }
    }

    // MARK: - Geometry

    private static func makeWingVaporMesh(phase: Float, side: Float) -> MeshResource? {
        let segments = 20
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        // A real fighter wing-tip vortex reads as a thin, slightly wandering
        // filament. Two narrow crossed ribbons keep it visible from arbitrary
        // camera angles without turning it into a bulb or spear.
        for sheet in 0..<2 {
            let base = UInt32(positions.count)
            let sheetAngle = Float(sheet) * (.pi / 2)
            let c = cos(sheetAngle)
            let s = sin(sheetAngle)

            for index in 0..<segments {
                let t = Float(index) / Float(segments - 1)
                let z = -0.04 - 2.65 * t
                let fadeEnvelope = sin(.pi * min(1, t * 1.05)) * (1 - 0.58 * t)
                let width = 0.020 + 0.060 * fadeEnvelope
                let inwardCurl = -side * 0.11 * t * t
                let downwash = -0.035 * t - 0.018 * t * t
                let wander = 0.012 * sin(t * 18.0 + phase + Float(sheet) * 1.7)
                let centerX = inwardCurl
                let centerY = downwash + wander
                let ax = width * c
                let ay = width * s
                positions.append([centerX - ax, centerY - ay, z])
                positions.append([centerX + ax, centerY + ay, z])
            }

            for index in 0..<(segments - 1) {
                let i0 = base + UInt32(index * 2)
                let i1 = i0 + 1
                let i2 = i0 + 2
                let i3 = i0 + 3
                appendDoubleSidedQuad(&indices, i0, i1, i2, i3)
            }
        }

        var descriptor = MeshDescriptor(name: "Wing-tip vortex condensation filament")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    private static func makeTransonicCondensationMesh(phase: Float) -> MeshResource? {
        let radialSegments = 52
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        // Thin elliptical annulus centered on the wing-root pressure field. The
        // empty center leaves the fuselage readable and the tiny streamwise
        // ripple gives the collar a vapor edge instead of a geometric disk.
        for radial in 0..<radialSegments {
            let angle = Float(radial) / Float(radialSegments) * 2 * .pi
            let irregular = 1.0
                + 0.050 * sin(angle * 5.0 + phase)
                + 0.024 * sin(angle * 11.0 - phase * 0.6)

            let innerX = 0.72 * cos(angle)
            let innerY = 0.30 * sin(angle)
            let outerX = 3.35 * irregular * cos(angle)
            let outerY = 0.92 * irregular * sin(angle)
            let zRipple = 0.08 * sin(angle * 3.0 + phase) + 0.035 * sin(angle * 9.0 - phase)

            positions.append([innerX, innerY, zRipple * 0.35])
            positions.append([outerX, outerY, zRipple])
        }

        for radial in 0..<radialSegments {
            let next = (radial + 1) % radialSegments
            let i0 = UInt32(radial * 2)
            let i1 = i0 + 1
            let i2 = UInt32(next * 2)
            let i3 = i2 + 1
            appendDoubleSidedQuad(&indices, i0, i1, i2, i3)
        }

        var descriptor = MeshDescriptor(name: "Transonic pressure condensation collar")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    private static func makeJetCoreSegmentMesh(phase: Float) -> MeshResource? {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let sheets = 4
        let stations = 7
        for sheet in 0..<sheets {
            let base = UInt32(positions.count)
            let angle = Float(sheet) / Float(sheets) * .pi
            let c = cos(angle), s = sin(angle)
            for station in 0..<stations {
                let t = Float(station) / Float(stations - 1)
                let z = t - 0.5
                let pulse = 1 + 0.10 * sin(t * 16 + phase + Float(sheet))
                let width = 0.47 * pulse
                let offset = 0.035 * sin(t * 23 - phase + Float(sheet) * 0.7)
                let a = SIMD2<Float>(-width, offset), b = SIMD2<Float>(width, -offset)
                positions.append([a.x*c-a.y*s, a.x*s+a.y*c, z])
                positions.append([b.x*c-b.y*s, b.x*s+b.y*c, z])
            }
            for station in 0..<(stations - 1) {
                let i = base + UInt32(station * 2)
                appendDoubleSidedQuad(&indices, i, i+1, i+2, i+3)
            }
        }
        var descriptor = MeshDescriptor(name: "Contrail jet-regime core")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    private static func makeVortexPairSegmentMesh(phase: Float) -> MeshResource? {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let stations = 7

        // The wake-vortex centers may separate by meters, but the visible ice
        // filaments themselves stay thin. Keep center spacing and filament
        // thickness independent so the trail never becomes two giant sausages.
        for lobe: Float in [-1, 1] {
            for sheet in 0..<2 {
                let base = UInt32(positions.count)
                let angle = Float(sheet) * (.pi / 2)
                let c = cos(angle), s = sin(angle)
                for station in 0..<stations {
                    let t = Float(station) / Float(stations - 1)
                    let z = t - 0.5
                    let ragged = 1 + 0.10 * sin(t * 13 + phase + Float(sheet) + lobe)
                    let radius = 0.028 * ragged
                    let swirl = 0.020 * sin(t * 18 + phase + lobe * 1.7)
                    let centerX = lobe * 0.47
                    let centerY = -0.020 + lobe * swirl
                    let a = SIMD2<Float>(centerX - radius * c, centerY - radius * s)
                    let b = SIMD2<Float>(centerX + radius * c, centerY + radius * s)
                    positions.append([a.x, a.y, z])
                    positions.append([b.x, b.y, z])
                }
                for station in 0..<(stations - 1) {
                    let i = base + UInt32(station * 2)
                    appendDoubleSidedQuad(&indices, i, i + 1, i + 2, i + 3)
                }
            }
        }
        var descriptor = MeshDescriptor(name: "Contrail rolled-up vortex filaments")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    private static func makeSecondaryWakeSegmentMesh(phase: Float) -> MeshResource? {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let stations = 8
        for station in 0..<stations {
            let t = Float(station) / Float(stations - 1)
            let z = t - 0.5
            let ragged = 1 + 0.18*sin(t*17+phase) + 0.07*sin(t*31-phase)
            let halfWidth = 0.50 * ragged
            let y0 = 0.04 * sin(t*19+phase)
            positions.append([-halfWidth, y0, z]); positions.append([halfWidth, -y0*0.7, z])
        }
        for station in 0..<(stations - 1) {
            let i = UInt32(station * 2)
            appendDoubleSidedQuad(&indices, i, i+1, i+2, i+3)
        }
        var descriptor = MeshDescriptor(name: "Contrail secondary wake")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    private static func initialWakeDescentRate(state: AircraftState) -> Float {
        let wingspan: Float = 9.96
        let b0 = Float.pi * wingspan / 4
        let rhoKgM3 = max(0.08, state.airDensitySlugsPerCubicFoot * 515.3788)
        let speed = max(90, state.airspeedMetersPerSecond)
        let weightN = max(5_000, state.aircraftMassKg) * 9.80665
        let gamma0 = 4 * weightN / (Float.pi * rhoKgM3 * speed * wingspan)
        return clamp(gamma0 / (2 * Float.pi * b0), 0.20, 4.5)
    }

    private static func smoothStep(_ value: Float) -> Float {
        let t = clamp(value, 0, 1)
        return t * t * (3 - 2 * t)
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
        UnlitMaterial(color: UIColor(red: 0.86, green: 0.92, blue: 0.98, alpha: CGFloat(clamp(alpha, 0, 1))))
    }

    private static func clamp(_ value: Float, _ minimum: Float, _ maximum: Float) -> Float {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}
