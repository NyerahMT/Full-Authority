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
    private static let transonicPrefix = "FA.effects.particles.transonic"
    private static let contrailCoreName = "FA.effects.particles.contrail.core"
    private static let contrailDiffuseName = "FA.effects.particles.contrail.diffuse"

    @MainActor
    final class Runtime {
        fileprivate var previousExhaustPoint: SIMD3<Float>?
        fileprivate var lastSimulationTime: TimeInterval = 0

        fileprivate func reset(root: Entity) {
            previousExhaustPoint = nil
            lastSimulationTime = 0

            for name in [contrailCoreName, contrailDiffuseName] {
                guard let entity = root.findEntity(named: name),
                      var particles = entity.components[ParticleEmitterComponent.self] else {
                    continue
                }
                particles.isEmitting = false
                particles.restart()
                entity.components.set(particles)
            }
        }
    }

    // MARK: - Scene construction

    static func makeAttachedEffects() -> Entity {
        let root = Entity()
        root.name = attachedRootName

        // These are programmatic airframe locators. No baked animation is used:
        // JSBSim decides when condensation exists and RealityKit creates the vapor.
        root.addChild(makeAirframeEmitter(
            name: lerxLeftName,
            position: [-1.34, 0.21, 1.45],
            vortexStrength: 14
        ))
        root.addChild(makeAirframeEmitter(
            name: lerxRightName,
            position: [1.34, 0.21, 1.45],
            vortexStrength: -14
        ))
        root.addChild(makeAirframeEmitter(
            name: tipLeftName,
            position: [-4.68, -0.04, -1.22],
            vortexStrength: 8
        ))
        root.addChild(makeAirframeEmitter(
            name: tipRightName,
            position: [4.68, -0.04, -1.22],
            vortexStrength: -8
        ))

        // A real visible transonic event is a pressure-condensation volume, not
        // a solid geometric cone. Several short-lived emitters distributed over
        // the wing-root/fuselage pressure field make a broken collar that blooms
        // and evaporates instead of spawning a white hat around the airplane.
        let pressureRegions: [SIMD3<Float>] = [
            [-2.75,  0.15, -0.12],
            [-1.55,  0.48,  0.05],
            [-1.70, -0.26, -0.18],
            [ 1.70, -0.26, -0.18],
            [ 1.55,  0.48,  0.05],
            [ 2.75,  0.15, -0.12]
        ]
        for (index, position) in pressureRegions.enumerated() {
            root.addChild(makeTransonicEmitter(
                name: "\(transonicPrefix).\(index)",
                position: position
            ))
        }

        return root
    }

    static func makeTrailPool() -> Entity {
        let root = Entity()
        root.name = trailRootName

        // The long contrail remains a real history of the flight path, but the
        // path itself is now invisible. A tight fresh-ice emitter plus a broader
        // persistent-ice emitter leave world-space particles behind as the nozzle
        // moves through the atmosphere. Nothing here draws a tube or spline.
        root.addChild(makeContrailEmitter(name: contrailCoreName, diffuse: false))
        root.addChild(makeContrailEmitter(name: contrailDiffuseName, diffuse: true))
        return root
    }

    // MARK: - Live updates

    static func updateAttachedEffects(
        aircraft: Entity,
        state: AircraftState,
        simulationTime: TimeInterval
    ) {
        // Permanently retire the old Stage 010 primitive vapor entities.
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
        updateTransonicCondensation(root: root, state: state, simulationTime: simulationTime)
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
        let persistence = clamp((iceRH - 0.96) / 0.20, 0, 1)
        let formsContrail = temperatureMargin > -0.5
            && iceRH > 0.70
            && fuelFlow > 0.012
            && formationStrength > 0.025

        // The authored F-16 nozzle lip is around z=-7.02 m. Condensation starts
        // downstream after the hot exhaust has mixed enough with ambient air.
        let exhaustPoint = worldPoint(local: [0, -0.04, -7.58], state: state)
        let previous = runtime.previousExhaustPoint

        let wakeDescent = initialWakeDescentRate(state: state)
        let driftVelocity = state.windMetersPerSecond + SIMD3<Float>(0, -0.30 * wakeDescent, 0)
        let driftSpeed = simd_length(driftVelocity)
        let driftDirection = driftSpeed > 0.02
            ? driftVelocity / driftSpeed
            : SIMD3<Float>(0, -1, 0)

        configureContrailEmitter(
            root: root,
            name: contrailCoreName,
            from: previous,
            to: exhaustPoint,
            emitting: formsContrail,
            strength: formationStrength,
            persistence: persistence,
            driftDirection: driftDirection,
            driftSpeed: driftSpeed,
            diffuse: false
        )
        configureContrailEmitter(
            root: root,
            name: contrailDiffuseName,
            from: previous,
            to: exhaustPoint,
            emitting: formsContrail && persistence > 0.08,
            strength: formationStrength,
            persistence: persistence,
            driftDirection: driftDirection,
            driftSpeed: driftSpeed,
            diffuse: true
        )

        runtime.previousExhaustPoint = formsContrail ? exhaustPoint : nil
    }

    // MARK: - Wing / LERX condensation

    private static func updateWingCondensation(root: Entity, state: AircraftState) {
        let iceRH = iceRelativeHumidity(
            positionMeters: state.positionMeters,
            altitudeFeet: state.altitudeFeetMSL
        )
        let moisture = clamp((iceRH - 0.70) / 0.30, 0, 1)
        let g = clamp((abs(state.loadFactorG) - 2.4) / 5.3, 0, 1)
        let alpha = clamp((abs(state.angleOfAttackDegrees) - 7.0) / 11.0, 0, 1)
        let qbar = clamp((state.dynamicPressurePSF - 125) / 650.0, 0, 1)

        // LERX vapor is mostly separation/alpha driven. Wingtip vapor tracks
        // circulation/loading more strongly. Both require moisture and qbar.
        let lerxIntensity = alpha * (0.34 + 0.66 * g) * qbar * moisture
        let tipIntensity = g * (0.42 + 0.58 * qbar) * moisture
        let lerxOn = lerxIntensity > 0.045 && state.calibratedAirspeedKnots > 145
        let tipOn = tipIntensity > 0.055 && state.calibratedAirspeedKnots > 165

        updateAirframeEmitter(
            root: root,
            name: lerxLeftName,
            enabled: lerxOn,
            intensity: lerxIntensity,
            vortexSign: 1
        )
        updateAirframeEmitter(
            root: root,
            name: lerxRightName,
            enabled: lerxOn,
            intensity: lerxIntensity,
            vortexSign: -1
        )
        updateAirframeEmitter(
            root: root,
            name: tipLeftName,
            enabled: tipOn,
            intensity: tipIntensity * 0.72,
            vortexSign: 1
        )
        updateAirframeEmitter(
            root: root,
            name: tipRightName,
            enabled: tipOn,
            intensity: tipIntensity * 0.72,
            vortexSign: -1
        )
    }

    private static func updateAirframeEmitter(
        root: Entity,
        name: String,
        enabled: Bool,
        intensity: Float,
        vortexSign: Float
    ) {
        guard let entity = root.findEntity(named: name),
              var particles = entity.components[ParticleEmitterComponent.self] else {
            return
        }

        let i = clamp(intensity, 0, 1)
        particles.isEmitting = enabled
        particles.speed = 1.4 + 4.8 * i
        particles.speedVariation = 0.7 + 1.7 * i
        particles.mainEmitter.birthRate = enabled ? 120 + 1_350 * i : 0
        particles.mainEmitter.lifeSpan = Double(0.18 + 0.42 * i)
        particles.mainEmitter.lifeSpanVariation = Double(0.04 + 0.10 * i)
        particles.mainEmitter.size = 0.025 + 0.055 * i
        particles.mainEmitter.sizeVariation = 0.010 + 0.025 * i
        particles.mainEmitter.sizeMultiplierAtEndOfLifespan = 1.25 + 0.70 * i
        particles.mainEmitter.sizeMultiplierAtEndOfLifespanPower = 1.35
        particles.mainEmitter.noiseStrength = 0.08 + 0.30 * i
        particles.mainEmitter.noiseScale = 0.22 + 0.24 * i
        particles.mainEmitter.noiseAnimationSpeed = 0.8 + 1.0 * i
        particles.mainEmitter.vortexStrength = vortexSign * (7 + 30 * i)
        entity.components.set(particles)
    }

    // MARK: - Transonic pressure condensation

    private static func updateTransonicCondensation(
        root: Entity,
        state: AircraftState,
        simulationTime: TimeInterval
    ) {
        let iceRH = iceRelativeHumidity(
            positionMeters: state.positionMeters,
            altitudeFeet: state.altitudeFeetMSL
        )
        let moisture = clamp((iceRH - 0.74) / 0.28, 0, 1)
        let mach = state.mach
        let machPeak = exp(-pow((mach - 0.995) / 0.030, 2))
        let qbar = clamp((state.dynamicPressurePSF - 180) / 760.0, 0, 1)
        let alphaAssist = 0.78 + 0.22 * clamp(abs(state.angleOfAttackDegrees) / 10.0, 0, 1)
        let intensity = machPeak * qbar * moisture * alphaAssist
        let visible = mach > 0.955 && mach < 1.055 && intensity > 0.035

        for index in 0..<6 {
            let name = "\(transonicPrefix).\(index)"
            guard let entity = root.findEntity(named: name),
                  var particles = entity.components[ParticleEmitterComponent.self] else {
                continue
            }

            // Neighboring pressure regions do not all condense at exactly the
            // same instant. A tiny deterministic phase offset keeps the cloud's
            // edge alive without making it pulse like an animation loop.
            let localBias = 0.88 + 0.12 * sin(Float(index) * 1.71 + Float(simulationTime) * 8.5)
            let i = clamp(intensity * localBias, 0, 1)
            particles.isEmitting = visible
            particles.speed = 0.5 + 2.0 * i
            particles.speedVariation = 0.7 + 1.2 * i
            particles.mainEmitter.birthRate = visible ? 90 + 520 * i : 0
            particles.mainEmitter.lifeSpan = Double(0.10 + 0.18 * i)
            particles.mainEmitter.lifeSpanVariation = Double(0.025 + 0.050 * i)
            particles.mainEmitter.size = 0.085 + 0.15 * i
            particles.mainEmitter.sizeVariation = 0.045 + 0.070 * i
            particles.mainEmitter.sizeMultiplierAtEndOfLifespan = 1.30 + 0.38 * i
            particles.mainEmitter.sizeMultiplierAtEndOfLifespanPower = 1.20
            particles.mainEmitter.noiseStrength = 0.20 + 0.38 * i
            particles.mainEmitter.noiseScale = 0.28 + 0.26 * i
            particles.mainEmitter.noiseAnimationSpeed = 0.9 + 1.1 * i
            entity.components.set(particles)
        }
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

        // Local +Y is rotated into aircraft-aft (-Z). The default vortex axis is
        // +Y too, so vortexStrength curls the droplets around the streamwise axis.
        entity.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])

        var particles = ParticleEmitterComponent()
        particles.emitterShape = .sphere
        particles.emitterShapeSize = [0.065, 0.065, 0.065]
        particles.birthLocation = .volume
        particles.birthDirection = .local
        particles.emissionDirection = [0, 1, 0]
        particles.fieldSimulationSpace = .global
        particles.particlesInheritTransform = false
        particles.isEmitting = false
        particles.speed = 2.0
        particles.speedVariation = 1.0

        particles.mainEmitter.birthRate = 0
        particles.mainEmitter.lifeSpan = 0.32
        particles.mainEmitter.lifeSpanVariation = 0.08
        particles.mainEmitter.size = 0.05
        particles.mainEmitter.sizeVariation = 0.02
        particles.mainEmitter.sizeMultiplierAtEndOfLifespan = 1.45
        particles.mainEmitter.sizeMultiplierAtEndOfLifespanPower = 1.30
        particles.mainEmitter.opacityCurve = .gradualFadeInOut
        particles.mainEmitter.noiseStrength = 0.16
        particles.mainEmitter.noiseScale = 0.30
        particles.mainEmitter.noiseAnimationSpeed = 0.90
        particles.mainEmitter.vortexStrength = vortexStrength
        particles.mainEmitter.color = .evolving(
            start: .single(UIColor(white: 0.98, alpha: 0.66)),
            end: .single(UIColor(red: 0.80, green: 0.87, blue: 0.92, alpha: 0.0))
        )
        entity.components.set(particles)
        return entity
    }

    private static func makeTransonicEmitter(
        name: String,
        position: SIMD3<Float>
    ) -> Entity {
        let entity = Entity()
        entity.name = name
        entity.position = position

        var particles = ParticleEmitterComponent()
        particles.emitterShape = .box
        particles.emitterShapeSize = [1.05, 0.40, 0.26]
        particles.birthLocation = .volume
        particles.birthDirection = .local
        particles.emissionDirection = [0, 0, -1]
        particles.fieldSimulationSpace = .global
        particles.particlesInheritTransform = false
        particles.isEmitting = false
        particles.speed = 1.0
        particles.speedVariation = 1.0

        particles.mainEmitter.birthRate = 0
        particles.mainEmitter.lifeSpan = 0.18
        particles.mainEmitter.lifeSpanVariation = 0.05
        particles.mainEmitter.size = 0.13
        particles.mainEmitter.sizeVariation = 0.06
        particles.mainEmitter.sizeMultiplierAtEndOfLifespan = 1.50
        particles.mainEmitter.sizeMultiplierAtEndOfLifespanPower = 1.20
        particles.mainEmitter.opacityCurve = .quickFadeInOut
        particles.mainEmitter.noiseStrength = 0.30
        particles.mainEmitter.noiseScale = 0.42
        particles.mainEmitter.noiseAnimationSpeed = 1.20
        particles.mainEmitter.color = .evolving(
            start: .single(UIColor(red: 0.94, green: 0.97, blue: 1.0, alpha: 0.48)),
            end: .single(UIColor(red: 0.80, green: 0.86, blue: 0.91, alpha: 0.0))
        )
        entity.components.set(particles)
        return entity
    }

    private static func makeContrailEmitter(name: String, diffuse: Bool) -> Entity {
        let entity = Entity()
        entity.name = name

        var particles = ParticleEmitterComponent()
        particles.emitterShape = .box
        particles.emitterShapeSize = diffuse
            ? SIMD3<Float>(0.40, 0.40, 0.40)
            : SIMD3<Float>(0.16, 0.16, 0.16)
        particles.birthLocation = .volume
        particles.birthDirection = .world
        particles.emissionDirection = [0, -1, 0]
        particles.fieldSimulationSpace = .global
        particles.particlesInheritTransform = false
        particles.isEmitting = false
        particles.speed = 0.15
        particles.speedVariation = diffuse ? 0.55 : 0.18

        particles.mainEmitter.birthRate = 0
        particles.mainEmitter.lifeSpan = diffuse ? 22.0 : 6.0
        particles.mainEmitter.lifeSpanVariation = diffuse ? 4.0 : 1.0
        particles.mainEmitter.size = diffuse ? 0.24 : 0.085
        particles.mainEmitter.sizeVariation = diffuse ? 0.13 : 0.035
        particles.mainEmitter.sizeMultiplierAtEndOfLifespan = diffuse ? 5.4 : 2.4
        particles.mainEmitter.sizeMultiplierAtEndOfLifespanPower = diffuse ? 1.75 : 1.35
        particles.mainEmitter.opacityCurve = diffuse ? .easeFadeOut : .gradualFadeInOut
        particles.mainEmitter.noiseStrength = diffuse ? 0.18 : 0.05
        particles.mainEmitter.noiseScale = diffuse ? 0.82 : 0.34
        particles.mainEmitter.noiseAnimationSpeed = diffuse ? 0.24 : 0.40
        particles.mainEmitter.color = .evolving(
            start: .single(UIColor(
                red: 0.97,
                green: 0.985,
                blue: 1.0,
                alpha: diffuse ? 0.20 : 0.62
            )),
            end: .single(UIColor(red: 0.78, green: 0.84, blue: 0.90, alpha: 0.0))
        )
        entity.components.set(particles)
        return entity
    }

    // MARK: - Contrail path placement

    private static func configureContrailEmitter(
        root: Entity,
        name: String,
        from start: SIMD3<Float>?,
        to end: SIMD3<Float>,
        emitting: Bool,
        strength: Float,
        persistence: Float,
        driftDirection: SIMD3<Float>,
        driftSpeed: Float,
        diffuse: Bool
    ) {
        guard let entity = root.findEntity(named: name),
              var particles = entity.components[ParticleEmitterComponent.self] else {
            return
        }

        let s = clamp(strength, 0, 1)
        let p = clamp(persistence, 0, 1)

        if let start {
            let delta = end - start
            let length = simd_length(delta)
            if length > 0.02 {
                entity.position = (start + end) * 0.5
                entity.orientation = simd_quatf(
                    from: SIMD3<Float>(0, 0, 1),
                    to: delta / length
                )
                particles.emitterShapeSize = diffuse
                    ? SIMD3<Float>(0.42 + 0.25 * p, 0.42 + 0.25 * p, max(length, 0.42))
                    : SIMD3<Float>(0.15 + 0.08 * s, 0.15 + 0.08 * s, max(length, 0.15))
            } else {
                entity.position = end
            }
        } else {
            entity.position = end
        }

        particles.isEmitting = emitting
        particles.birthDirection = .world
        particles.emissionDirection = driftDirection
        particles.speed = max(0.03, driftSpeed)
        particles.speedVariation = diffuse ? 0.35 + 0.70 * p : 0.12 + 0.22 * p

        if diffuse {
            particles.mainEmitter.birthRate = emitting ? 34 + 130 * s * (0.35 + 0.65 * p) : 0
            particles.mainEmitter.lifeSpan = Double(10 + 24 * p)
            particles.mainEmitter.lifeSpanVariation = Double(1.5 + 4.5 * p)
            particles.mainEmitter.size = 0.18 + 0.16 * s
            particles.mainEmitter.sizeVariation = 0.09 + 0.10 * p
            particles.mainEmitter.sizeMultiplierAtEndOfLifespan = 3.6 + 3.6 * p
            particles.mainEmitter.noiseStrength = 0.10 + 0.24 * p
            particles.mainEmitter.noiseScale = 0.58 + 0.60 * p
            particles.mainEmitter.noiseAnimationSpeed = 0.16 + 0.22 * p
        } else {
            particles.mainEmitter.birthRate = emitting ? 180 + 480 * s : 0
            particles.mainEmitter.lifeSpan = Double(3.2 + 5.8 * p)
            particles.mainEmitter.lifeSpanVariation = Double(0.45 + 1.0 * p)
            particles.mainEmitter.size = 0.070 + 0.070 * s
            particles.mainEmitter.sizeVariation = 0.025 + 0.035 * s
            particles.mainEmitter.sizeMultiplierAtEndOfLifespan = 1.8 + 1.8 * p
            particles.mainEmitter.noiseStrength = 0.025 + 0.080 * p
            particles.mainEmitter.noiseScale = 0.30 + 0.30 * p
            particles.mainEmitter.noiseAnimationSpeed = 0.24 + 0.24 * p
        }

        entity.components.set(particles)
    }

    // MARK: - Atmosphere / wake physics

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
        // JSBSim's standard atmosphere does not provide a humidity field here,
        // so Full Authority supplies a deterministic world-space moisture field.
        // It creates coherent humid/dry air masses while remaining visual-only.
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

    private static func clamp(_ value: Float, _ minimum: Float, _ maximum: Float) -> Float {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}
