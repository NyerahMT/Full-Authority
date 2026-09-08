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
    private static let transonicPrefix = "FA.effects.particles.transonic"
    private static let transonicRegionCount = 10
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
        root.addChild(makeAirframeEmitter(
            name: leadingLeftName,
            position: [-2.78, 0.08, 0.38],
            vortexStrength: 7
        ))
        root.addChild(makeAirframeEmitter(
            name: leadingRightName,
            position: [2.78, 0.08, 0.38],
            vortexStrength: -7
        ))

        // A real visible transonic event is a pressure-condensation volume, not
        // a solid geometric cone. Several short-lived emitters distributed over
        // the wing-root/fuselage pressure field make a broken collar that blooms
        // and evaporates instead of spawning a white hat around the airplane.
        let pressureRegions: [SIMD3<Float>] = [
            [-3.05,  0.10, -0.16],
            [-2.35,  0.28, -0.02],
            [-1.55,  0.50,  0.10],
            [-0.70,  0.36,  0.12],
            [-1.45, -0.28, -0.20],
            [ 1.45, -0.28, -0.20],
            [ 0.70,  0.36,  0.12],
            [ 1.55,  0.50,  0.10],
            [ 2.35,  0.28, -0.02],
            [ 3.05,  0.10, -0.16]
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

        // The authored F-16 nozzle lip is around z=-7.02 m. Leave a
        // visible hot-exhaust mixing gap before ice crystals become optically
        // dense; real engine contrails do not start as a white plug at the lip.
        let exhaustPoint = worldPoint(local: [0, -0.04, -11.20], state: state)
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
        // Treat maneuver condensation as local saturation caused by the
        // pressure drop over a loaded wing, not as an ambient-humidity switch.
        // A hard pull can therefore reach saturation in moderately dry air,
        // while a lightly loaded wing still stays clean.
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
            vortexSign: 1
        )
        updateAirframeEmitter(
            root: root,
            name: lerxRightName,
            enabled: lerxOn,
            intensity: max(lerxIntensity, hardManeuver ? localSaturation * 0.28 : 0),
            vortexSign: -1
        )
        updateAirframeEmitter(
            root: root,
            name: leadingLeftName,
            enabled: leadingOn,
            intensity: max(leadingIntensity, hardManeuver ? localSaturation * 0.24 : 0),
            vortexSign: 1
        )
        updateAirframeEmitter(
            root: root,
            name: leadingRightName,
            enabled: leadingOn,
            intensity: max(leadingIntensity, hardManeuver ? localSaturation * 0.24 : 0),
            vortexSign: -1
        )
        updateAirframeEmitter(
            root: root,
            name: tipLeftName,
            enabled: tipOn,
            intensity: tipIntensity * 0.78,
            vortexSign: 1
        )
        updateAirframeEmitter(
            root: root,
            name: tipRightName,
            enabled: tipOn,
            intensity: tipIntensity * 0.78,
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

        // The aircraft's motion through global simulation space makes the wake.
        // Keep particle self-velocity small and strictly aft so the near-field
        // filament stays on the F-16's local -Z axis instead of spraying sideways.
        particles.speed = 0.35 + 1.25 * i
        particles.speedVariation = 0.15 + 0.45 * i
        particles.mainEmitter.birthRate = enabled ? 900 + 4_600 * i : 0
        particles.mainEmitter.lifeSpan = Double(0.42 + 0.88 * i)
        particles.mainEmitter.lifeSpanVariation = Double(0.08 + 0.16 * i)
        particles.mainEmitter.size = 0.085 + 0.145 * i
        particles.mainEmitter.sizeVariation = 0.025 + 0.055 * i
        particles.mainEmitter.sizeMultiplierAtEndOfLifespan = 1.35 + 0.85 * i
        particles.mainEmitter.sizeMultiplierAtEndOfLifespanPower = 1.40
        particles.mainEmitter.noiseStrength = 0.035 + 0.16 * i
        particles.mainEmitter.noiseScale = 0.30 + 0.28 * i
        particles.mainEmitter.noiseAnimationSpeed = 0.55 + 0.70 * i
        particles.mainEmitter.vortexStrength = vortexSign * (3.0 + 13.0 * i)
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
        // A visible transonic cloud is a broad pressure-field event.
        // Keep humidity important, but do not multiply several hard gates until
        // a physically valid Mach-1 pass becomes effectively invisible.
        let moisture = clamp((iceRH - 0.54) / 0.46, 0, 1)
        let mach = state.mach
        let machPeak = exp(-pow((mach - 0.995) / 0.055, 2))
        let qbar = clamp((state.dynamicPressurePSF - 120) / 520.0, 0, 1)
        let alphaFactor = 0.82 + 0.18 * clamp(abs(state.angleOfAttackDegrees) / 12.0, 0, 1)
        let intensity = machPeak
            * (0.22 + 0.78 * qbar)
            * (0.18 + 0.82 * moisture)
            * alphaFactor
        let visible = mach > 0.93 && mach < 1.09 && intensity > 0.016

        for index in 0..<transonicRegionCount {
            let name = "\(transonicPrefix).\(index)"
            guard let entity = root.findEntity(named: name),
                  var particles = entity.components[ParticleEmitterComponent.self] else {
                continue
            }

            // Neighboring pressure regions do not all condense at exactly the
            // same instant. A tiny deterministic phase offset keeps the cloud's
            // edge alive without making it pulse like an animation loop.
            let localBias = 0.96 + 0.04 * sin(Float(index) * 1.71 + Float(simulationTime) * 6.5)
            let i = clamp(intensity * localBias, 0, 1)
            particles.isEmitting = visible
            particles.speed = 0.20 + 1.05 * i
            particles.speedVariation = 0.25 + 0.55 * i
            particles.mainEmitter.birthRate = visible ? 1_000 + 4_100 * i : 0
            particles.mainEmitter.lifeSpan = Double(0.20 + 0.40 * i)
            particles.mainEmitter.lifeSpanVariation = Double(0.045 + 0.085 * i)
            particles.mainEmitter.size = 0.20 + 0.34 * i
            particles.mainEmitter.sizeVariation = 0.075 + 0.14 * i
            particles.mainEmitter.sizeMultiplierAtEndOfLifespan = 1.38 + 0.52 * i
            particles.mainEmitter.sizeMultiplierAtEndOfLifespanPower = 1.20
            particles.mainEmitter.noiseStrength = 0.10 + 0.24 * i
            particles.mainEmitter.noiseScale = 0.34 + 0.28 * i
            particles.mainEmitter.noiseAnimationSpeed = 0.60 + 0.75 * i
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

        var particles = ParticleEmitterComponent()

        // Sweep births through a short streamwise volume. This fills the space
        // between render updates at fighter speeds and removes the bead-necklace
        // artifact produced by a tiny point/sphere emitter. -Z is explicitly
        // aircraft-aft in the authored F-16 coordinate frame.
        let isLERX = name.contains(".lerx.")
        let isTip = name.contains(".tip.")
        particles.emitterShape = .box
        particles.emitterShapeSize = isLERX
            ? SIMD3<Float>(0.16, 0.10, 1.30)
            : (isTip
                ? SIMD3<Float>(0.11, 0.08, 0.82)
                : SIMD3<Float>(0.14, 0.09, 1.08))
        particles.birthLocation = .volume
        particles.birthDirection = .local
        particles.emissionDirection = [0, 0, -1]
        particles.fieldSimulationSpace = .global
        particles.particlesInheritTransform = false
        particles.isEmitting = false
        particles.speed = 2.0
        particles.speedVariation = 1.0

        particles.mainEmitter.birthRate = 0
        particles.mainEmitter.lifeSpan = 0.32
        particles.mainEmitter.lifeSpanVariation = 0.08
        particles.mainEmitter.size = 0.12
        particles.mainEmitter.sizeVariation = 0.045
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
        particles.emitterShapeSize = [1.35, 0.56, 0.42]
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
        particles.mainEmitter.size = 0.27
        particles.mainEmitter.sizeVariation = 0.12
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
        particles.mainEmitter.size = diffuse ? 0.42 : 0.16
        particles.mainEmitter.sizeVariation = diffuse ? 0.20 : 0.065
        particles.mainEmitter.sizeMultiplierAtEndOfLifespan = diffuse ? 5.4 : 2.4
        particles.mainEmitter.sizeMultiplierAtEndOfLifespanPower = diffuse ? 1.75 : 1.35
        // Both layers build instead of appearing at maximum density on birth.
        // The long-lived layer especially should mature downstream before fading.
        particles.mainEmitter.opacityCurve = .gradualFadeInOut
        particles.mainEmitter.noiseStrength = diffuse ? 0.18 : 0.05
        particles.mainEmitter.noiseScale = diffuse ? 0.82 : 0.34
        particles.mainEmitter.noiseAnimationSpeed = diffuse ? 0.24 : 0.40
        particles.mainEmitter.color = .evolving(
            start: .single(UIColor(
                red: 0.97,
                green: 0.985,
                blue: 1.0,
                alpha: diffuse ? 0.13 : 0.42
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
        // Fresh ice stays tight for a few seconds; the older persistent
        // population takes the full wind/wake drift and survives long enough to
        // leave an actual maneuver trace across the sky.
        particles.speed = diffuse
            ? max(0.03, driftSpeed)
            : max(0.02, driftSpeed * 0.22)
        particles.speedVariation = diffuse ? 0.30 + 0.62 * p : 0.06 + 0.16 * p

        if diffuse {
            particles.mainEmitter.birthRate = emitting ? 150 + 500 * s * (0.35 + 0.65 * p) : 0
            particles.mainEmitter.lifeSpan = Double(40 + 80 * p)
            particles.mainEmitter.lifeSpanVariation = Double(5.0 + 12.0 * p)
            particles.mainEmitter.size = 0.34 + 0.30 * s
            particles.mainEmitter.sizeVariation = 0.16 + 0.18 * p
            particles.mainEmitter.sizeMultiplierAtEndOfLifespan = 3.8 + 3.8 * p
            particles.mainEmitter.noiseStrength = 0.08 + 0.22 * p
            particles.mainEmitter.noiseScale = 0.62 + 0.64 * p
            particles.mainEmitter.noiseAnimationSpeed = 0.12 + 0.18 * p
        } else {
            particles.mainEmitter.birthRate = emitting ? 650 + 1_850 * s : 0
            particles.mainEmitter.lifeSpan = Double(7.0 + 13.0 * p)
            particles.mainEmitter.lifeSpanVariation = Double(0.9 + 2.0 * p)
            particles.mainEmitter.size = 0.14 + 0.14 * s
            particles.mainEmitter.sizeVariation = 0.045 + 0.070 * s
            particles.mainEmitter.sizeMultiplierAtEndOfLifespan = 2.0 + 1.8 * p
            particles.mainEmitter.noiseStrength = 0.018 + 0.060 * p
            particles.mainEmitter.noiseScale = 0.34 + 0.28 * p
            particles.mainEmitter.noiseAnimationSpeed = 0.18 + 0.20 * p
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
