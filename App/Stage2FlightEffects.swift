import Foundation
import RealityKit
import UIKit
import simd

@MainActor
enum Stage2FlightEffects {
    static let attachedRootName = "FA.effects.attached"
    static let trailRootName = "FA.effects.trails"

    private static let lerxLeftName = "FA.effects.particles.lerx.left"
    private static let lerxRightName = "FA.effects.particles.lerx.right"
    private static let tipLeftName = "FA.effects.particles.tip.left"
    private static let tipRightName = "FA.effects.particles.tip.right"
    private static let leadingLeftName = "FA.effects.particles.leading.left"
    private static let leadingRightName = "FA.effects.particles.leading.right"

    private static let transonicShellName = "FA.effects.transonic.shell"
    private static let transonicHaloName = "FA.effects.transonic.halo"

    private static let contrailCoreName = "FA.effects.contrail.core"
    private static let contrailDiffuseName = "FA.effects.contrail.diffuse"

    private struct TrailSample {
        var position: SIMD3<Float>
        var driftVelocity: SIMD3<Float>
        var simulationTime: TimeInterval
        var strength: Float
        var persistence: Float
        var segment: Int
    }

    @MainActor
    final class Runtime {
        fileprivate var samples: [TrailSample] = []
        fileprivate var lastSimulationTime: TimeInterval = 0
        fileprivate var lastSampleTime: TimeInterval = -TimeInterval.greatestFiniteMagnitude
        fileprivate var lastMeshUpdateTime: TimeInterval = -TimeInterval.greatestFiniteMagnitude
        fileprivate var lastSamplePosition: SIMD3<Float>?
        fileprivate var segment = 0
        fileprivate var wasForming = false

        fileprivate func reset(root: Entity) {
            samples.removeAll(keepingCapacity: true)
            lastSimulationTime = 0
            lastSampleTime = -TimeInterval.greatestFiniteMagnitude
            lastMeshUpdateTime = -TimeInterval.greatestFiniteMagnitude
            lastSamplePosition = nil
            segment = 0
            wasForming = false

            root.findEntity(named: contrailCoreName)?.isEnabled = false
            root.findEntity(named: contrailDiffuseName)?.isEnabled = false
        }
    }

    // MARK: - Scene construction

    static func makeAttachedEffects() -> Entity {
        let root = Entity()
        root.name = attachedRootName

        root.addChild(makeAirframeEmitter(
            name: lerxLeftName,
            position: [-1.34, 0.21, 1.45],
            vortexStrength: 3.4
        ))
        root.addChild(makeAirframeEmitter(
            name: lerxRightName,
            position: [1.34, 0.21, 1.45],
            vortexStrength: -3.4
        ))
        root.addChild(makeAirframeEmitter(
            name: tipLeftName,
            position: [-4.68, -0.04, -1.22],
            vortexStrength: 5.2
        ))
        root.addChild(makeAirframeEmitter(
            name: tipRightName,
            position: [4.68, -0.04, -1.22],
            vortexStrength: -5.2
        ))
        root.addChild(makeAirframeEmitter(
            name: leadingLeftName,
            position: [-2.78, 0.08, 0.38],
            vortexStrength: 2.5
        ))
        root.addChild(makeAirframeEmitter(
            name: leadingRightName,
            position: [2.78, 0.08, 0.38],
            vortexStrength: -2.5
        ))

        root.addChild(makeTransonicVaporEntity(
            name: transonicHaloName,
            opacity: 0.03
        ))
        root.addChild(makeTransonicVaporEntity(
            name: transonicShellName,
            opacity: 0.08
        ))

        return root
    }

    static func makeTrailPool() -> Entity {
        let root = Entity()
        root.name = trailRootName

        let diffuse = ModelEntity()
        diffuse.name = contrailDiffuseName
        diffuse.isEnabled = false
        root.addChild(diffuse)

        let core = ModelEntity()
        core.name = contrailCoreName
        core.isEnabled = false
        root.addChild(core)

        return root
    }

    // MARK: - Live updates

    static func updateAttachedEffects(
        aircraft: Entity,
        state: AircraftState,
        simulationTime: TimeInterval
    ) {
        // Permanently retire the old primitive Stage 010 vapor geometry.
        for oldName in [
            PrototypeAircraftFactory.vaporLeftName,
            PrototypeAircraftFactory.vaporRightName,
            PrototypeAircraftFactory.contrailLeftName,
            PrototypeAircraftFactory.contrailRightName
        ] {
            aircraft.findEntity(named: oldName)?.isEnabled = false
        }

        guard let root = aircraft.findEntity(named: attachedRootName) else { return }
        updateWingCondensation(root: root, state: state)
        updateTransonicVapor(root: root, state: state, simulationTime: simulationTime)
    }

    static func updateWorldTrails(
        root: Entity,
        state: AircraftState,
        simulationTime: TimeInterval,
        runtime: Runtime
    ) {
        if simulationTime + 0.001 < runtime.lastSimulationTime {
            runtime.reset(root: root)
        }
        runtime.lastSimulationTime = simulationTime

        let iceRH = iceRelativeHumidity(
            positionMeters: state.positionMeters,
            altitudeFeet: state.altitudeFeetMSL
        )
        let criticalTemperatureC = schmidtApplemanCriticalTemperatureC(
            pressurePSF: state.ambientPressurePSF
        )
        let temperatureMargin = criticalTemperatureC - state.ambientTemperatureC
        let temperatureFactor = clamp((temperatureMargin + 1.0) / 8.0, 0, 1)
        let humidityFormation = clamp((iceRH - 0.70) / 0.30, 0, 1)
        let fuelFlow = state.engineFuelFlowPoundsPerSecond
        let exhaustWater = clamp((fuelFlow - 0.015) / 0.65, 0, 1)
        let formationStrength = temperatureFactor
            * humidityFormation
            * (0.30 + 0.70 * exhaustWater)
        let persistence = clamp((iceRH - 0.82) / 0.35, 0, 1)

        let formsContrail = temperatureMargin > -0.5
            && iceRH > 0.70
            && fuelFlow > 0.012
            && formationStrength > 0.025

        // Start the ice trail behind the nozzle so there is a clean hot-mixing
        // gap instead of a white plug attached directly to the airplane.
        let exhaustPoint = worldPoint(local: [0, -0.04, -8.55], state: state)

        let wakeDescent = initialWakeDescentRate(state: state)
        let driftVelocity = state.windMetersPerSecond
            + SIMD3<Float>(0, -0.30 * wakeDescent, 0)

        if formsContrail {
            if !runtime.wasForming {
                runtime.segment += 1
                runtime.lastSamplePosition = nil
                runtime.lastSampleTime = -TimeInterval.greatestFiniteMagnitude
            }

            let elapsed = simulationTime - runtime.lastSampleTime
            let distance = runtime.lastSamplePosition.map {
                simd_length(exhaustPoint - $0)
            } ?? .greatestFiniteMagnitude

            // The mesh connects samples, so it does not need particle-density
            // hacks at fighter speed. 12 m / 0.07 s keeps turns smooth without
            // rebuilding thousands of vertices every frame on an iPhone.
            if elapsed >= 0.07 || distance >= 12.0 {
                runtime.samples.append(TrailSample(
                    position: exhaustPoint,
                    driftVelocity: driftVelocity,
                    simulationTime: simulationTime,
                    strength: formationStrength,
                    persistence: persistence,
                    segment: runtime.segment
                ))
                runtime.lastSamplePosition = exhaustPoint
                runtime.lastSampleTime = simulationTime
            }
        } else {
            runtime.lastSamplePosition = nil
        }

        runtime.wasForming = formsContrail

        // Keep enough history to make a real maneuvering trail while bounding
        // the dynamic mesh cost. Old samples taper before they are discarded.
        let oldestTime = simulationTime - 42.0
        runtime.samples.removeAll { $0.simulationTime < oldestTime }
        if runtime.samples.count > 700 {
            runtime.samples.removeFirst(runtime.samples.count - 700)
        }

        // Dynamic MeshResource generation is substantially cheaper than a
        // dense particle cloud, but it still does real geometry work. Refresh
        // the slow-moving vapor geometry at ~12.5 Hz instead of every display
        // frame; the aircraft/camera remain 60 Hz.
        if simulationTime - runtime.lastMeshUpdateTime < 0.08 {
            return
        }
        runtime.lastMeshUpdateTime = simulationTime

        updateTrailEntity(
            root: root,
            name: contrailDiffuseName,
            samples: runtime.samples,
            simulationTime: simulationTime,
            maxAge: 42,
            radialSides: 6,
            baseRadius: 0.40,
            radialGrowthPerSecond: 0.052,
            driftScale: 0.72,
            opacity: 0.115
        )
        updateTrailEntity(
            root: root,
            name: contrailCoreName,
            samples: runtime.samples,
            simulationTime: simulationTime,
            maxAge: 13,
            radialSides: 6,
            baseRadius: 0.16,
            radialGrowthPerSecond: 0.026,
            driftScale: 0.22,
            opacity: 0.34
        )
    }

    // MARK: - Wing / LERX condensation

    private static func updateWingCondensation(root: Entity, state: AircraftState) {
        let iceRH = iceRelativeHumidity(
            positionMeters: state.positionMeters,
            altitudeFeet: state.altitudeFeetMSL
        )
        let absG = abs(state.loadFactorG)
        let absAlpha = abs(state.angleOfAttackDegrees)
        let ambientMoisture = clamp((iceRH - 0.50) / 0.50, 0, 1)
        let gDemand = clamp((absG - 1.8) / 5.8, 0, 1)
        let alphaDemand = clamp((absAlpha - 5.0) / 12.0, 0, 1)
        let qbar = clamp((state.dynamicPressurePSF - 80) / 520.0, 0, 1)
        let liftDemand = max(gDemand, alphaDemand)
        let pressureDrop = clamp(liftDemand * (0.38 + 0.62 * qbar), 0, 1)
        let localSaturation = clamp(ambientMoisture + 0.58 * pressureDrop, 0, 1)

        let lerxDemand = max(alphaDemand, gDemand * 0.58)
        let lerxIntensity = lerxDemand * (0.34 + 0.66 * pressureDrop) * localSaturation
        let leadingIntensity = max(alphaDemand * 0.78, gDemand * 0.62) * qbar * localSaturation
        let tipIntensity = gDemand * qbar * localSaturation
        let hardManeuver = absG > 4.0 || absAlpha > 10.0

        let lerxOn = state.calibratedAirspeedKnots > 135
            && (lerxIntensity > 0.025 || (hardManeuver && localSaturation > 0.20))
        let leadingOn = state.calibratedAirspeedKnots > 145
            && (leadingIntensity > 0.030 || (hardManeuver && localSaturation > 0.24))
        let tipOn = state.calibratedAirspeedKnots > 155
            && (tipIntensity > 0.035 || (absG > 4.5 && localSaturation > 0.25))

        updateAirframeEmitter(
            root: root,
            name: lerxLeftName,
            enabled: lerxOn,
            intensity: max(lerxIntensity, hardManeuver ? localSaturation * 0.28 : 0),
            vortexSign: 1,
            state: state
        )
        updateAirframeEmitter(
            root: root,
            name: lerxRightName,
            enabled: lerxOn,
            intensity: max(lerxIntensity, hardManeuver ? localSaturation * 0.28 : 0),
            vortexSign: -1,
            state: state
        )
        updateAirframeEmitter(
            root: root,
            name: leadingLeftName,
            enabled: leadingOn,
            intensity: max(leadingIntensity, hardManeuver ? localSaturation * 0.24 : 0),
            vortexSign: 1,
            state: state
        )
        updateAirframeEmitter(
            root: root,
            name: leadingRightName,
            enabled: leadingOn,
            intensity: max(leadingIntensity, hardManeuver ? localSaturation * 0.24 : 0),
            vortexSign: -1,
            state: state
        )
        updateAirframeEmitter(
            root: root,
            name: tipLeftName,
            enabled: tipOn,
            intensity: tipIntensity * 0.78,
            vortexSign: 1,
            state: state
        )
        updateAirframeEmitter(
            root: root,
            name: tipRightName,
            enabled: tipOn,
            intensity: tipIntensity * 0.78,
            vortexSign: -1,
            state: state
        )
    }

    private static func updateAirframeEmitter(
        root: Entity,
        name: String,
        enabled: Bool,
        intensity: Float,
        vortexSign: Float,
        state: AircraftState
    ) {
        guard let entity = root.findEntity(named: name),
              var particles = entity.components[ParticleEmitterComponent.self] else {
            return
        }

        let i = clamp(intensity, 0, 1)
        particles.isEmitting = enabled

        let worldAft = simd_normalize(
            simd_act(state.orientation, SIMD3<Float>(0, 0, -1))
        )
        particles.birthDirection = .world
        particles.emissionDirection = worldAft
        particles.speed = 0.06 + 0.24 * i
        particles.speedVariation = 0.03 + 0.08 * i

        particles.mainEmitter.birthRate = enabled ? 520 + 2_450 * i : 0
        particles.mainEmitter.lifeSpan = Double(0.26 + 0.54 * i)
        particles.mainEmitter.lifeSpanVariation = Double(0.04 + 0.10 * i)
        particles.mainEmitter.size = 0.052 + 0.078 * i
        particles.mainEmitter.sizeVariation = 0.018 + 0.034 * i
        particles.mainEmitter.sizeMultiplierAtEndOfLifespan = 1.55 + 0.55 * i
        particles.mainEmitter.sizeMultiplierAtEndOfLifespanPower = 1.35
        particles.mainEmitter.noiseStrength = 0.018 + 0.045 * i
        particles.mainEmitter.noiseScale = 0.24 + 0.18 * i
        particles.mainEmitter.noiseAnimationSpeed = 0.50 + 0.45 * i

        let isLeading = name.contains(".leading.")
        let isTip = name.contains(".tip.")
        let vortexMagnitude: Float = isLeading
            ? (0.20 + 0.90 * i)
            : (isTip ? (0.75 + 3.2 * i) : (0.45 + 1.8 * i))
        particles.mainEmitter.vortexStrength = vortexSign * vortexMagnitude
        entity.components.set(particles)
    }

    // MARK: - Transonic condensation shell

    private static func updateTransonicVapor(
        root: Entity,
        state: AircraftState,
        simulationTime: TimeInterval
    ) {
        let iceRH = iceRelativeHumidity(
            positionMeters: state.positionMeters,
            altitudeFeet: state.altitudeFeetMSL
        )
        let moisture = clamp((iceRH - 0.45) / 0.50, 0, 1)
        let mach = state.mach
        let machPeak = exp(-pow((mach - 0.995) / 0.058, 2))
        let qbar = clamp((state.dynamicPressurePSF - 90) / 500.0, 0, 1)
        let alphaFactor = 0.88
            + 0.12 * clamp(abs(state.angleOfAttackDegrees) / 12.0, 0, 1)
        let intensity = clamp(
            machPeak
                * (0.40 + 0.60 * qbar)
                * (0.34 + 0.66 * moisture)
                * alphaFactor,
            0,
            1
        )
        let visible = mach > 0.90 && mach < 1.11 && intensity > 0.018
        let time = Float(simulationTime)

        if let halo = root.findEntity(named: transonicHaloName) {
            halo.isEnabled = visible
            if visible {
                let pulse = 1.0 + 0.030 * sin(time * 7.3)
                halo.scale = [
                    (1.055 + 0.055 * intensity) * pulse,
                    (1.08 + 0.040 * intensity) * pulse,
                    1.02 + 0.08 * intensity
                ]
                halo.position = [0, 0.02, -0.12]
                setVaporOpacity(
                    entity: halo,
                    opacity: 0.018 + 0.055 * intensity
                )
            }
        }

        if let shell = root.findEntity(named: transonicShellName) {
            shell.isEnabled = visible
            if visible {
                let pulse = 1.0 + 0.018 * sin(time * 10.7 + 0.8)
                shell.scale = [
                    (0.98 + 0.045 * intensity) * pulse,
                    (1.00 + 0.035 * intensity) * pulse,
                    0.96 + 0.09 * intensity
                ]
                shell.position = [0, 0, 0]
                setVaporOpacity(
                    entity: shell,
                    opacity: 0.055 + 0.145 * intensity
                )
            }
        }
    }

    private static func makeTransonicVaporEntity(
        name: String,
        opacity: Float
    ) -> ModelEntity {
        let entity = ModelEntity()
        entity.name = name
        entity.isEnabled = false

        if let mesh = makeTransonicShellMesh() {
            entity.model = ModelComponent(
                mesh: mesh,
                materials: [makeVaporMaterial(opacity: opacity)]
            )
        }
        return entity
    }

    private static func makeTransonicShellMesh() -> MeshResource? {
        // A faceted, hollow pressure-condensation collar. It deliberately has
        // no end caps: the viewer sees a thin translucent shell, not a white cone
        // or a stack of opaque particle billboards.
        let rings: [(z: Float, rx: Float, ry: Float)] = [
            ( 2.20, 0.42, 0.24),
            ( 1.25, 1.45, 0.78),
            ( 0.30, 3.15, 1.72),
            (-0.65, 4.05, 2.22),
            (-1.55, 3.65, 1.95),
            (-2.55, 2.40, 1.20),
            (-3.35, 0.95, 0.46)
        ]
        let sides = 18

        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(rings.count * sides)

        for (ringIndex, ring) in rings.enumerated() {
            for side in 0..<sides {
                let theta = 2 * Float.pi * Float(side) / Float(sides)
                let ripple = 1.0
                    + 0.045 * sin(theta * 3.0 + Float(ringIndex) * 0.9)
                    + 0.020 * sin(theta * 7.0 - Float(ringIndex) * 0.6)
                positions.append([
                    cos(theta) * ring.rx * ripple,
                    sin(theta) * ring.ry * ripple,
                    ring.z
                ])
            }
        }

        for ring in 0..<(rings.count - 1) {
            for side in 0..<sides {
                let nextSide = (side + 1) % sides
                let a = UInt32(ring * sides + side)
                let b = UInt32(ring * sides + nextSide)
                let c = UInt32((ring + 1) * sides + side)
                let d = UInt32((ring + 1) * sides + nextSide)
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }

        var descriptor = MeshDescriptor(name: "FA.transonic-vapor-shell")
        descriptor.positions = .init(positions)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    // MARK: - Contrail mesh

    private static func updateTrailEntity(
        root: Entity,
        name: String,
        samples: [TrailSample],
        simulationTime: TimeInterval,
        maxAge: Float,
        radialSides: Int,
        baseRadius: Float,
        radialGrowthPerSecond: Float,
        driftScale: Float,
        opacity: Float
    ) {
        guard let entity = root.findEntity(named: name) as? ModelEntity else {
            return
        }

        let visibleSamples = samples.filter {
            let age = Float(simulationTime - $0.simulationTime)
            return age >= 0 && age <= maxAge
        }

        guard visibleSamples.count >= 2,
              let mesh = makeTrailMesh(
                samples: visibleSamples,
                simulationTime: simulationTime,
                maxAge: maxAge,
                radialSides: radialSides,
                baseRadius: baseRadius,
                radialGrowthPerSecond: radialGrowthPerSecond,
                driftScale: driftScale
              ) else {
            entity.isEnabled = false
            return
        }

        entity.model = ModelComponent(
            mesh: mesh,
            materials: [makeVaporMaterial(opacity: opacity)]
        )
        entity.isEnabled = true
    }

    private static func makeTrailMesh(
        samples: [TrailSample],
        simulationTime: TimeInterval,
        maxAge: Float,
        radialSides: Int,
        baseRadius: Float,
        radialGrowthPerSecond: Float,
        driftScale: Float
    ) -> MeshResource? {
        guard samples.count >= 2, radialSides >= 3 else { return nil }

        var centers: [SIMD3<Float>] = []
        var radii: [Float] = []
        centers.reserveCapacity(samples.count)
        radii.reserveCapacity(samples.count)

        for sample in samples {
            let age = max(0, Float(simulationTime - sample.simulationTime))
            let center = sample.position
                + sample.driftVelocity * age * driftScale
            let growth = 1.0
                + age * radialGrowthPerSecond * (0.55 + 0.45 * sample.persistence)
            let birthRamp = clamp(age / 0.45, 0.20, 1.0)
            let deathRamp = clamp((maxAge - age) / 3.5, 0.06, 1.0)
            let strengthRadius = 0.72 + 0.45 * sample.strength
            centers.append(center)
            radii.append(
                baseRadius
                    * growth
                    * strengthRadius
                    * birthRamp
                    * deathRamp
            )
        }

        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(samples.count * radialSides)

        for index in samples.indices {
            let tangent: SIMD3<Float>
            if index > 0,
               samples[index - 1].segment == samples[index].segment {
                if index + 1 < samples.count,
                   samples[index + 1].segment == samples[index].segment {
                    tangent = safeNormalize(
                        centers[index + 1] - centers[index - 1],
                        fallback: [0, 0, -1]
                    )
                } else {
                    tangent = safeNormalize(
                        centers[index] - centers[index - 1],
                        fallback: [0, 0, -1]
                    )
                }
            } else if index + 1 < samples.count,
                      samples[index + 1].segment == samples[index].segment {
                tangent = safeNormalize(
                    centers[index + 1] - centers[index],
                    fallback: [0, 0, -1]
                )
            } else {
                tangent = [0, 0, -1]
            }

            let reference: SIMD3<Float> = abs(simd_dot(tangent, SIMD3<Float>(0, 1, 0))) < 0.92
                ? SIMD3<Float>(0, 1, 0)
                : SIMD3<Float>(1, 0, 0)
            let side = safeNormalize(
                simd_cross(tangent, reference),
                fallback: [1, 0, 0]
            )
            let up = safeNormalize(
                simd_cross(side, tangent),
                fallback: [0, 1, 0]
            )

            for radial in 0..<radialSides {
                let theta = 2 * Float.pi * Float(radial) / Float(radialSides)
                let offset = side * cos(theta) + up * sin(theta)
                positions.append(centers[index] + offset * radii[index])
            }
        }

        for index in 0..<(samples.count - 1) {
            guard samples[index].segment == samples[index + 1].segment else {
                continue
            }

            for radial in 0..<radialSides {
                let next = (radial + 1) % radialSides
                let a = UInt32(index * radialSides + radial)
                let b = UInt32(index * radialSides + next)
                let c = UInt32((index + 1) * radialSides + radial)
                let d = UInt32((index + 1) * radialSides + next)

                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }

        guard !indices.isEmpty else { return nil }

        var descriptor = MeshDescriptor(name: "FA.contrail-volume")
        descriptor.positions = .init(positions)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    // MARK: - Particle presets

    private static func makeAirframeEmitter(
        name: String,
        position: SIMD3<Float>,
        vortexStrength: Float
    ) -> Entity {
        let entity = Entity()
        entity.name = name
        entity.position = position

        var particles = ParticleEmitterComponent()

        let isLERX = name.contains(".lerx.")
        let isTip = name.contains(".tip.")
        particles.emitterShape = .box
        particles.emitterShapeSize = isLERX
            ? SIMD3<Float>(0.15, 0.075, 0.82)
            : (isTip
                ? SIMD3<Float>(0.075, 0.060, 0.55)
                : SIMD3<Float>(0.13, 0.070, 0.72))
        particles.birthLocation = .volume
        particles.birthDirection = .local
        particles.emissionDirection = [0, 0, -1]
        particles.fieldSimulationSpace = .global
        particles.particlesInheritTransform = false
        particles.isEmitting = false
        particles.speed = 0.20
        particles.speedVariation = 0.08

        particles.mainEmitter.birthRate = 0
        particles.mainEmitter.lifeSpan = 0.30
        particles.mainEmitter.lifeSpanVariation = 0.06
        particles.mainEmitter.size = 0.065
        particles.mainEmitter.sizeVariation = 0.020
        particles.mainEmitter.sizeMultiplierAtEndOfLifespan = 1.65
        particles.mainEmitter.sizeMultiplierAtEndOfLifespanPower = 1.30
        particles.mainEmitter.opacityCurve = .gradualFadeInOut
        particles.mainEmitter.noiseStrength = 0.05
        particles.mainEmitter.noiseScale = 0.25
        particles.mainEmitter.noiseAnimationSpeed = 0.75
        particles.mainEmitter.vortexStrength = vortexStrength
        particles.mainEmitter.color = .evolving(
            start: .single(UIColor(white: 0.98, alpha: 0.48)),
            end: .single(UIColor(red: 0.82, green: 0.88, blue: 0.92, alpha: 0.0))
        )
        entity.components.set(particles)
        return entity
    }

    // MARK: - Materials

    private static func makeVaporMaterial(opacity: Float) -> UnlitMaterial {
        var material = UnlitMaterial(color: UIColor(
            red: 0.94,
            green: 0.975,
            blue: 1.0,
            alpha: 1
        ))
        let alpha = clamp(opacity, 0, 1)
        material.blending = .transparent(
            opacity: PhysicallyBasedMaterial.Opacity(floatLiteral: alpha)
        )
        material.faceCulling = .none
        material.writesDepth = false
        return material
    }

    private static func setVaporOpacity(entity: Entity, opacity: Float) {
        guard let modelEntity = entity as? ModelEntity,
              var model = modelEntity.model else {
            return
        }
        model.materials = [makeVaporMaterial(opacity: opacity)]
        modelEntity.model = model
    }

    // MARK: - Atmosphere / wake physics

    private static func schmidtApplemanCriticalTemperatureC(
        pressurePSF: Float
    ) -> Float {
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

    private static func initialWakeDescentRate(state: AircraftState) -> Float {
        let wingspan: Float = 9.96
        let b0 = Float.pi * wingspan / 4
        let rhoKgM3 = max(0.08, state.airDensitySlugsPerCubicFoot * 515.3788)
        let speed = max(90, state.airspeedMetersPerSecond)
        let weightN = max(5_000, state.aircraftMassKg) * 9.80665
        let gamma0 = 4 * weightN / (Float.pi * rhoKgM3 * speed * wingspan)
        return clamp(gamma0 / (2 * Float.pi * b0), 0.20, 4.5)
    }

    private static func iceRelativeHumidity(
        positionMeters: SIMD3<Float>,
        altitudeFeet: Float
    ) -> Float {
        // JSBSim's standard atmosphere does not provide humidity here, so Full
        // Authority keeps a deterministic visual-only moisture field.
        let x = positionMeters.x
        let z = positionMeters.z
        let h = altitudeFeet
        let upperTroposphereBand = 0.24 * exp(-pow((h - 34_000) / 9_000, 2))
        let synopticWave = 0.11 * sin(x / 7_400)
            + 0.09 * cos(z / 8_900)
            + 0.07 * sin((x + z) / 5_100)
        let verticalWave = 0.06 * sin(h / 4_300 + x / 18_000)
        return clamp(
            0.72 + upperTroposphereBand + synopticWave + verticalWave,
            0.42,
            1.32
        )
    }

    private static func worldPoint(
        local: SIMD3<Float>,
        state: AircraftState
    ) -> SIMD3<Float> {
        state.positionMeters + simd_act(state.orientation, local)
    }

    private static func safeNormalize(
        _ value: SIMD3<Float>,
        fallback: SIMD3<Float>
    ) -> SIMD3<Float> {
        let lengthSquared = simd_length_squared(value)
        guard lengthSquared > 0.000001 else { return fallback }
        return value / sqrt(lengthSquared)
    }

    private static func clamp(
        _ value: Float,
        _ minimum: Float,
        _ maximum: Float
    ) -> Float {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}
