import Foundation
import RealityKit
import UIKit
import simd

@MainActor
enum Stage2FlightEffects {
    static let attachedRootName = "FA.effects.attached"
    static let trailRootName = "FA.effects.trails"

    private static let lerxLeftName = "FA.effects.vapor.lerx.left"
    private static let lerxRightName = "FA.effects.vapor.lerx.right"
    private static let tipLeftName = "FA.effects.vapor.tip.left"
    private static let tipRightName = "FA.effects.vapor.tip.right"
    private static let leadingLeftName = "FA.effects.vapor.leading.left"
    private static let leadingRightName = "FA.effects.vapor.leading.right"

    private static let transonicShellName = "FA.effects.transonic.shell"
    private static let transonicHaloName = "FA.effects.transonic.halo"

    private static let contrailCoreName = "FA.effects.contrail.core"
    private static let contrailDiffuseName = "FA.effects.contrail.diffuse"
    private static let contrailMatureName = "FA.effects.contrail.mature"

    fileprivate struct TrailSample {
        var position: SIMD3<Float>
        var driftVelocity: SIMD3<Float>
        var simulationTime: TimeInterval
        var strength: Float
        var persistence: Float
        var lifeSeconds: Float
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
            root.findEntity(named: contrailMatureName)?.isEnabled = false
        }
    }

    // MARK: - Scene construction

    static func makeAttachedEffects() -> Entity {
        let root = Entity()
        root.name = attachedRootName

        // Maneuver vapor is intentionally attached geometry rather than free
        // particles. The whole streamer always points down the authored F-16's
        // local -Z (aft) axis, so a roll/yaw can never make the leading-edge
        // vapor shoot sideways or forward across the airplane.
        root.addChild(makeVaporStreamer(
            name: lerxLeftName,
            position: [-1.34, 0.21, 1.45],
            width: 0.48,
            height: 0.20,
            length: 4.6,
            opacity: 0.20
        ))
        root.addChild(makeVaporStreamer(
            name: lerxRightName,
            position: [1.34, 0.21, 1.45],
            width: 0.48,
            height: 0.20,
            length: 4.6,
            opacity: 0.20
        ))
        root.addChild(makeVaporStreamer(
            name: leadingLeftName,
            position: [-2.78, 0.08, 0.38],
            width: 0.62,
            height: 0.14,
            length: 4.2,
            opacity: 0.18
        ))
        root.addChild(makeVaporStreamer(
            name: leadingRightName,
            position: [2.78, 0.08, 0.38],
            width: 0.62,
            height: 0.14,
            length: 4.2,
            opacity: 0.18
        ))
        root.addChild(makeVaporStreamer(
            name: tipLeftName,
            position: [-4.68, -0.04, -1.22],
            width: 0.17,
            height: 0.17,
            length: 6.8,
            opacity: 0.17
        ))
        root.addChild(makeVaporStreamer(
            name: tipRightName,
            position: [4.68, -0.04, -1.22],
            width: 0.17,
            height: 0.17,
            length: 6.8,
            opacity: 0.17
        ))

        // Two nested low-poly cones make the transonic cloud read as a cone
        // rather than the old oval/collar. Both end on the same flat aft plane.
        root.addChild(makeTransonicVaporEntity(
            name: transonicHaloName,
            opacity: 0.025,
            radialScale: 1.09
        ))
        root.addChild(makeTransonicVaporEntity(
            name: transonicShellName,
            opacity: 0.070,
            radialScale: 1.00
        ))

        return root
    }

    static func makeTrailPool() -> Entity {
        let root = Entity()
        root.name = trailRootName

        // The long trail is age-layered. New ice starts as a thin translucent
        // core, then a wider diffuse layer appears, then a mature plume overlays
        // it farther downstream. The overlap is what makes the trail visibly gain
        // opacity and volume as the wake mixes without needing per-vertex alpha.
        let mature = ModelEntity()
        mature.name = contrailMatureName
        mature.isEnabled = false
        root.addChild(mature)

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
        for oldName in [
            PrototypeAircraftFactory.vaporLeftName,
            PrototypeAircraftFactory.vaporRightName,
            PrototypeAircraftFactory.contrailLeftName,
            PrototypeAircraftFactory.contrailRightName
        ] {
            aircraft.findEntity(named: oldName)?.isEnabled = false
        }

        guard let root = aircraft.findEntity(named: attachedRootName) else { return }
        updateWingCondensation(
            root: root,
            state: state,
            simulationTime: simulationTime
        )
        updateTransonicVapor(
            root: root,
            state: state,
            simulationTime: simulationTime
        )
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
        let fuelFlow = state.engineFuelFlowPoundsPerSecond

        // Keep the real Schmidt-Appleman gate as the primary source of long,
        // persistent ice trails, but widen the edge slightly so the synthetic
        // humidity field does not make valid contrails vanish between cells.
        let temperatureFactor = clamp((temperatureMargin + 2.0) / 9.0, 0, 1)
        let humidityFormation = clamp((iceRH - 0.62) / 0.38, 0, 1)
        let exhaustWater = clamp((fuelFlow - 0.010) / 0.62, 0, 1)
        let physicalStrength = temperatureFactor
            * humidityFormation
            * (0.32 + 0.68 * exhaustWater)
        let physicalPersistence = clamp((iceRH - 0.76) / 0.38, 0, 1)

        let formsPersistentContrail = temperatureMargin > -2.0
            && iceRH > 0.62
            && fuelFlow > 0.010
            && physicalStrength > 0.012

        // A short humid exhaust-condensation trail is allowed at high power
        // even below the persistent-contrail layer. It lasts only a few seconds,
        // so it cannot masquerade as a high-altitude ice contrail.
        let highPowerMoisture = clamp((iceRH - 0.54) / 0.38, 0, 1)
        let highPowerSpeed = clamp((state.airspeedMetersPerSecond - 135) / 120, 0, 1)
        let highPowerFuel = clamp((fuelFlow - 0.28) / 0.95, 0, 1)
        let highPowerStrength = highPowerMoisture * highPowerSpeed * highPowerFuel
        let formsShortExhaustTrail = state.afterburnerActive
            && highPowerStrength > 0.04

        let formsTrail = formsPersistentContrail || formsShortExhaustTrail
        let trailStrength = formsPersistentContrail
            ? physicalStrength
            : max(0.26, highPowerStrength * 0.72)
        let trailPersistence = formsPersistentContrail
            ? physicalPersistence
            : clamp(highPowerMoisture * 0.30, 0.05, 0.28)

        // Persistent ice now survives for roughly 80-160 seconds. The sample
        // cap below still bounds geometry, so this turns into a roughly 25-30 km
        // maximum rendered streak at fighter cruise instead of an unbounded mesh.
        let trailLife: Float = formsPersistentContrail
            ? (80.0 + 80.0 * trailPersistence)
            : (4.5 + 4.0 * trailPersistence)

        // F-16 nozzle lip is near z=-7.02 m. A 1.25 m mixing gap keeps the
        // trail from looking like a white plug glued to the engine.
        let exhaustPoint = worldPoint(
            local: [0, -0.04, -8.30],
            state: state
        )

        let wakeDescent = initialWakeDescentRate(state: state)
        let driftVelocity = state.windMetersPerSecond
            + SIMD3<Float>(0, -0.28 * wakeDescent, 0)

        if formsTrail {
            if !runtime.wasForming {
                runtime.segment += 1
                runtime.lastSamplePosition = nil
                runtime.lastSampleTime = -TimeInterval.greatestFiniteMagnitude
            }

            let elapsed = simulationTime - runtime.lastSampleTime
            let distance = runtime.lastSamplePosition.map {
                simd_length(exhaustPoint - $0)
            } ?? .greatestFiniteMagnitude

            // A slightly wider sample spacing buys much more total trail length
            // while remaining visually smooth because the geometry interpolates
            // continuously between samples.
            if elapsed >= 0.075 || distance >= 14.0 {
                runtime.samples.append(TrailSample(
                    position: exhaustPoint,
                    driftVelocity: driftVelocity,
                    simulationTime: simulationTime,
                    strength: trailStrength,
                    persistence: trailPersistence,
                    lifeSeconds: trailLife,
                    segment: runtime.segment
                ))
                runtime.lastSamplePosition = exhaustPoint
                runtime.lastSampleTime = simulationTime
            }
        } else {
            runtime.lastSamplePosition = nil
        }

        runtime.wasForming = formsTrail

        let oldestTime = simulationTime - 160.0
        runtime.samples.removeAll {
            $0.simulationTime < oldestTime
                || Float(simulationTime - $0.simulationTime) > $0.lifeSeconds + 3.0
        }
        if runtime.samples.count > 2_200 {
            runtime.samples.removeFirst(runtime.samples.count - 2_200)
        }

        // Longer history means more vertices, so rebuild the slowly evolving wake
        // at 10 Hz. Aircraft/camera motion remains at display rate.
        if simulationTime - runtime.lastMeshUpdateTime < 0.10 {
            return
        }
        runtime.lastMeshUpdateTime = simulationTime

        // Farther downstream, three overlapping age bands progressively add
        // both cross-section and alpha. This reads like an ice plume blooming
        // and whitening as it mixes instead of a constant-width plastic tube.
        updateTrailEntity(
            root: root,
            name: contrailMatureName,
            samples: runtime.samples,
            simulationTime: simulationTime,
            layerMinAge: 2.0,
            layerMaxAge: 160,
            radialSides: 6,
            baseRadius: 0.38,
            radialGrowthPerSecond: 0.055,
            driftScale: 0.86,
            opacity: 0.105
        )
        updateTrailEntity(
            root: root,
            name: contrailDiffuseName,
            samples: runtime.samples,
            simulationTime: simulationTime,
            layerMinAge: 0.55,
            layerMaxAge: 130,
            radialSides: 6,
            baseRadius: 0.25,
            radialGrowthPerSecond: 0.043,
            driftScale: 0.82,
            opacity: 0.070
        )
        updateTrailEntity(
            root: root,
            name: contrailCoreName,
            samples: runtime.samples,
            simulationTime: simulationTime,
            layerMinAge: 0,
            layerMaxAge: 18,
            radialSides: 6,
            baseRadius: 0.12,
            radialGrowthPerSecond: 0.015,
            driftScale: 0.30,
            opacity: 0.165
        )
    }

    // MARK: - Maneuver vapor

    private static func updateWingCondensation(
        root: Entity,
        state: AircraftState,
        simulationTime: TimeInterval
    ) {
        let iceRH = iceRelativeHumidity(
            positionMeters: state.positionMeters,
            altitudeFeet: state.altitudeFeetMSL
        )

        let absG = abs(state.loadFactorG)
        let absAlpha = abs(state.angleOfAttackDegrees)
        let ambientMoisture = clamp((iceRH - 0.46) / 0.54, 0, 1)
        let gDemand = clamp((absG - 1.7) / 5.6, 0, 1)
        let alphaDemand = clamp((absAlpha - 4.5) / 12.0, 0, 1)
        let qbar = clamp((state.dynamicPressurePSF - 75) / 520.0, 0, 1)
        let liftDemand = max(gDemand, alphaDemand)
        let pressureDrop = clamp(
            liftDemand * (0.36 + 0.64 * qbar),
            0,
            1
        )
        let localSaturation = clamp(
            ambientMoisture + 0.60 * pressureDrop,
            0,
            1
        )

        let lerxIntensity = max(alphaDemand, gDemand * 0.58)
            * (0.32 + 0.68 * pressureDrop)
            * localSaturation
        let leadingIntensity = max(alphaDemand * 0.76, gDemand * 0.64)
            * qbar
            * localSaturation
        let tipIntensity = gDemand
            * qbar
            * localSaturation

        let hardManeuver = absG > 3.8 || absAlpha > 9.5
        let lerx = max(
            lerxIntensity,
            hardManeuver ? localSaturation * 0.26 : 0
        )
        let leading = max(
            leadingIntensity,
            hardManeuver ? localSaturation * 0.22 : 0
        )
        let tip = max(
            tipIntensity,
            absG > 4.3 ? localSaturation * 0.20 : 0
        )

        let lerxOn = state.calibratedAirspeedKnots > 135 && lerx > 0.035
        let leadingOn = state.calibratedAirspeedKnots > 145 && leading > 0.040
        let tipOn = state.calibratedAirspeedKnots > 155 && tip > 0.045

        updateVaporStreamer(
            root: root,
            name: lerxLeftName,
            enabled: lerxOn,
            intensity: lerx,
            simulationTime: simulationTime,
            phase: 0.0
        )
        updateVaporStreamer(
            root: root,
            name: lerxRightName,
            enabled: lerxOn,
            intensity: lerx,
            simulationTime: simulationTime,
            phase: 1.1
        )
        updateVaporStreamer(
            root: root,
            name: leadingLeftName,
            enabled: leadingOn,
            intensity: leading,
            simulationTime: simulationTime,
            phase: 2.0
        )
        updateVaporStreamer(
            root: root,
            name: leadingRightName,
            enabled: leadingOn,
            intensity: leading,
            simulationTime: simulationTime,
            phase: 2.8
        )
        updateVaporStreamer(
            root: root,
            name: tipLeftName,
            enabled: tipOn,
            intensity: tip,
            simulationTime: simulationTime,
            phase: 3.6
        )
        updateVaporStreamer(
            root: root,
            name: tipRightName,
            enabled: tipOn,
            intensity: tip,
            simulationTime: simulationTime,
            phase: 4.4
        )
    }

    private static func makeVaporStreamer(
        name: String,
        position: SIMD3<Float>,
        width: Float,
        height: Float,
        length: Float,
        opacity: Float
    ) -> ModelEntity {
        let entity = ModelEntity()
        entity.name = name
        entity.position = position
        entity.isEnabled = false

        if let mesh = makeVaporStreamerMesh() {
            entity.model = ModelComponent(
                mesh: mesh,
                materials: [makeVaporMaterial(opacity: opacity)]
            )
        }

        entity.scale = [width, height, length]
        return entity
    }

    private static func updateVaporStreamer(
        root: Entity,
        name: String,
        enabled: Bool,
        intensity: Float,
        simulationTime: TimeInterval,
        phase: Float
    ) {
        guard let entity = root.findEntity(named: name) as? ModelEntity else {
            return
        }

        let i = clamp(intensity, 0, 1)
        entity.isEnabled = enabled
        guard enabled else { return }

        let time = Float(simulationTime)
        let shimmer = 1.0
            + 0.025 * sin(time * 8.0 + phase)
            + 0.010 * sin(time * 17.0 + phase * 0.7)

        let isTip = name.contains(".tip.")
        let isLeading = name.contains(".leading.")

        if isTip {
            entity.scale = [
                (0.13 + 0.09 * i) * shimmer,
                (0.13 + 0.07 * i) * shimmer,
                4.6 + 4.8 * i
            ]
        } else if isLeading {
            entity.scale = [
                (0.42 + 0.32 * i) * shimmer,
                (0.095 + 0.055 * i) * shimmer,
                2.5 + 3.6 * i
            ]
        } else {
            entity.scale = [
                (0.34 + 0.28 * i) * shimmer,
                (0.13 + 0.09 * i) * shimmer,
                2.8 + 4.0 * i
            ]
        }

        setVaporOpacity(
            entity: entity,
            opacity: (isTip ? 0.040 : 0.055) + (isTip ? 0.115 : 0.185) * i
        )
    }

    private static func makeVaporStreamerMesh() -> MeshResource? {
        // Unit-length faceted spindle aligned down local -Z. The leading cross
        // section begins almost at zero radius, blooms immediately behind the
        // wing, then tapers out. This gives a clean attached wake with no
        // forward-facing emission vector at all.
        let rings: [(z: Float, rx: Float, ry: Float)] = [
            ( 0.00, 0.025, 0.025),
            (-0.10, 0.58, 0.48),
            (-0.32, 1.00, 0.78),
            (-0.66, 0.60, 0.48),
            (-1.00, 0.025, 0.020)
        ]
        let sides = 12

        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(rings.count * sides)

        for ring in rings {
            for side in 0..<sides {
                let theta = 2 * Float.pi * Float(side) / Float(sides)
                positions.append([
                    cos(theta) * ring.rx,
                    sin(theta) * ring.ry,
                    ring.z
                ])
            }
        }

        for ring in 0..<(rings.count - 1) {
            for side in 0..<sides {
                let next = (side + 1) % sides
                let a = UInt32(ring * sides + side)
                let b = UInt32(ring * sides + next)
                let c = UInt32((ring + 1) * sides + side)
                let d = UInt32((ring + 1) * sides + next)
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }

        var descriptor = MeshDescriptor(name: "FA.maneuver-vapor-streamer")
        descriptor.positions = .init(positions)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    // MARK: - Transonic Mach cone

    private static func updateTransonicVapor(
        root: Entity,
        state: AircraftState,
        simulationTime: TimeInterval
    ) {
        let iceRH = iceRelativeHumidity(
            positionMeters: state.positionMeters,
            altitudeFeet: state.altitudeFeetMSL
        )
        let moisture = clamp((iceRH - 0.43) / 0.52, 0, 1)
        let mach = state.mach
        let machPeak = exp(-pow((mach - 0.995) / 0.040, 2))
        let qbar = clamp((state.dynamicPressurePSF - 85) / 500.0, 0, 1)
        let intensity = clamp(
            machPeak
                * (0.42 + 0.58 * qbar)
                * (0.36 + 0.64 * moisture),
            0,
            1
        )

        let visible = mach > 0.935
            && mach < 1.070
            && intensity > 0.016

        let time = Float(simulationTime)
        let uniformPulse = 1.0 + 0.010 * sin(time * 8.2)

        if let halo = root.findEntity(named: transonicHaloName) {
            halo.isEnabled = visible
            if visible {
                let radial = (1.03 + 0.055 * intensity) * uniformPulse
                halo.scale = [radial, radial, 1.0]
                halo.position = [0, 0.01, -0.08]
                setVaporOpacity(
                    entity: halo,
                    opacity: 0.014 + 0.040 * intensity
                )
            }
        }

        if let shell = root.findEntity(named: transonicShellName) {
            shell.isEnabled = visible
            if visible {
                let radial = (0.97 + 0.035 * intensity) * uniformPulse
                shell.scale = [radial, radial, 1.0]
                shell.position = [0, 0, 0]
                setVaporOpacity(
                    entity: shell,
                    opacity: 0.032 + 0.095 * intensity
                )
            }
        }
    }

    private static func makeTransonicVaporEntity(
        name: String,
        opacity: Float,
        radialScale: Float
    ) -> ModelEntity {
        let entity = ModelEntity()
        entity.name = name
        entity.isEnabled = false

        if let mesh = makeMachConeMesh(radialScale: radialScale) {
            entity.model = ModelComponent(
                mesh: mesh,
                materials: [makeVaporMaterial(opacity: opacity)]
            )
        }
        return entity
    }

    private static func makeMachConeMesh(
        radialScale: Float
    ) -> MeshResource? {
        // Local +Z is forward on the authored F-16. The cone apex therefore
        // begins just ahead of the wing/nose pressure field and expands linearly
        // aft toward a single FLAT cutoff plane. Nothing narrows again behind
        // the base, which is what made the previous mesh look like a balloon.
        let apexZ: Float = 3.85
        let baseZ: Float = -3.65
        let baseRX: Float = 4.15 * radialScale
        let baseRY: Float = 2.22 * radialScale
        let sides = 20
        let ringCount = 6

        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for ring in 0..<ringCount {
            let t = Float(ring) / Float(ringCount - 1)
            // Tiny nonzero apex ring avoids degenerate triangles while still
            // reading as a true cone from chase/side/rear views.
            let radiusT = 0.035 + 0.965 * t
            let z = apexZ + (baseZ - apexZ) * t
            for side in 0..<sides {
                let theta = 2 * Float.pi * Float(side) / Float(sides)
                positions.append([
                    cos(theta) * baseRX * radiusT,
                    sin(theta) * baseRY * radiusT,
                    z
                ])
            }
        }

        for ring in 0..<(ringCount - 1) {
            for side in 0..<sides {
                let next = (side + 1) % sides
                let a = UInt32(ring * sides + side)
                let b = UInt32(ring * sides + next)
                let c = UInt32((ring + 1) * sides + side)
                let d = UInt32((ring + 1) * sides + next)
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }

        // A very thin rear rim on the flat base makes the cutoff read clearly
        // without filling the whole base with a translucent disk.
        let rimStart = positions.count
        let rimDepth: Float = 0.08
        for ringScale in [Float(1.00), Float(0.93)] {
            for side in 0..<sides {
                let theta = 2 * Float.pi * Float(side) / Float(sides)
                positions.append([
                    cos(theta) * baseRX * ringScale,
                    sin(theta) * baseRY * ringScale,
                    baseZ - (ringScale < 1 ? rimDepth : 0)
                ])
            }
        }
        for side in 0..<sides {
            let next = (side + 1) % sides
            let a = UInt32(rimStart + side)
            let b = UInt32(rimStart + next)
            let c = UInt32(rimStart + sides + side)
            let d = UInt32(rimStart + sides + next)
            indices.append(contentsOf: [a, c, b, b, c, d])
        }

        var descriptor = MeshDescriptor(name: "FA.transonic-mach-cone")
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
        layerMinAge: Float,
        layerMaxAge: Float,
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
            let effectiveLife = min(layerMaxAge, $0.lifeSeconds)
            return age >= layerMinAge && age <= effectiveLife
        }

        guard visibleSamples.count >= 2,
              let mesh = makeTrailMesh(
                samples: visibleSamples,
                simulationTime: simulationTime,
                layerMaxAge: layerMaxAge,
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
        layerMaxAge: Float,
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
            let effectiveLife = max(0.5, min(layerMaxAge, sample.lifeSeconds))
            var center = sample.position
                + sample.driftVelocity * age * driftScale
            let meander = min(4.5, 0.020 * powf(age, 1.16))
            let seed = Float(sample.simulationTime.truncatingRemainder(dividingBy: 97.0))
            center.x += sin(age * 0.19 + seed * 0.31) * meander
            center.y += sin(age * 0.13 + seed * 0.17) * meander * 0.24
            center.z += cos(age * 0.16 + seed * 0.23) * meander * 0.72

            // Wake spreading is fast for the first minute, then saturates so a
            // very old trail gets broad without turning into an absurd tunnel.
            let growthAge = min(age, 70.0)
            let growth = 1.0
                + growthAge * radialGrowthPerSecond * (0.55 + 0.45 * sample.persistence)
            let birthRamp = clamp(age / 0.42, 0.20, 1.0)
            let deathRamp = clamp((effectiveLife - age) / 5.0, 0.035, 1.0)
            let strengthRadius = 0.78 + 0.42 * sample.strength
            let textureBreakup = 0.90 + 0.10 * sin(age * 0.23 + seed * 0.41)

            centers.append(center)
            radii.append(
                baseRadius
                    * growth
                    * strengthRadius
                    * birthRamp
                    * deathRamp
                    * textureBreakup
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

            let reference: SIMD3<Float> =
                abs(simd_dot(tangent, SIMD3<Float>(0, 1, 0))) < 0.92
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

    private static func setVaporOpacity(
        entity: Entity,
        opacity: Float
    ) {
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
        return Float(
            -46.46 + 9.43 * logarithm + 0.72 * logarithm * logarithm
        )
    }

    private static func initialWakeDescentRate(
        state: AircraftState
    ) -> Float {
        let wingspan: Float = 9.96
        let b0 = Float.pi * wingspan / 4
        let rhoKgM3 = max(
            0.08,
            state.airDensitySlugsPerCubicFoot * 515.3788
        )
        let speed = max(90, state.airspeedMetersPerSecond)
        let weightN = max(5_000, state.aircraftMassKg) * 9.80665
        let gamma0 = 4 * weightN
            / (Float.pi * rhoKgM3 * speed * wingspan)
        return clamp(
            gamma0 / (2 * Float.pi * b0),
            0.20,
            4.5
        )
    }

    private static func iceRelativeHumidity(
        positionMeters: SIMD3<Float>,
        altitudeFeet: Float
    ) -> Float {
        let x = positionMeters.x
        let z = positionMeters.z
        let h = altitudeFeet

        let upperTroposphereBand = 0.24
            * exp(-pow((h - 34_000) / 9_000, 2))
        let synopticWave = 0.11 * sin(x / 7_400)
            + 0.09 * cos(z / 8_900)
            + 0.07 * sin((x + z) / 5_100)
        let verticalWave = 0.06
            * sin(h / 4_300 + x / 18_000)

        return clamp(
            0.72
                + upperTroposphereBand
                + synopticWave
                + verticalWave,
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
