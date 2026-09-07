from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one match for {old[:80]!r}, found {count}")
    p.write_text(text.replace(old, new, 1))


def replace_between(path: str, start: str, end: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    i = text.find(start)
    if i < 0:
        raise SystemExit(f"{path}: start marker not found: {start!r}")
    j = text.find(end, i)
    if j < 0:
        raise SystemExit(f"{path}: end marker not found: {end!r}")
    p.write_text(text[:i] + new.rstrip() + "\n\n" + text[j:])


replace_once(
    "Simulation/AircraftState.swift",
    "    var dynamicPressurePSF: Float = 0\n",
    "    var dynamicPressurePSF: Float = 0\n"
    "\n"
    "    /// Atmospheric/propulsion telemetry used by weather-dependent visual effects.\n"
    "    /// JSBSim remains authoritative for aircraft forces; these values only drive rendering.\n"
    "    var ambientTemperatureC: Float = 15\n"
    "    var ambientPressurePSF: Float = 2_116.22\n"
    "    var airDensitySlugsPerCubicFoot: Float = 0.0023769\n"
    "    var engineFuelFlowPoundsPerSecond: Float = 0\n"
    "    var windMetersPerSecond: SIMD3<Float> = .zero\n",
)

replace_once(
    "Simulation/FlightSimulation.swift",
    "        state.dynamicPressurePSF = max(0, finiteFloat(\"aero/qbar-psf\", fallback: 0))\n",
    "        state.dynamicPressurePSF = max(0, finiteFloat(\"aero/qbar-psf\", fallback: 0))\n"
    "\n"
    "        // Feed presentation the atmosphere JSBSim is actually using.\n"
    "        let temperatureRankine = finiteFloat(\"atmosphere/T-R\", fallback: 518.67)\n"
    "        state.ambientTemperatureC = temperatureRankine / 1.8 - 273.15\n"
    "        state.ambientPressurePSF = max(0, finiteFloat(\"atmosphere/P-psf\", fallback: 2_116.22))\n"
    "        state.airDensitySlugsPerCubicFoot = max(0, finiteFloat(\"atmosphere/rho-slugs_ft3\", fallback: 0.0023769))\n"
    "        state.engineFuelFlowPoundsPerSecond = max(0, finiteFloat(\"propulsion/engine[0]/fuel-flow-rate-pps\", fallback: 0))\n"
    "        let windNorth = finiteFloat(\"atmosphere/total-wind-north-fps\", fallback: 0) * feetToMeters\n"
    "        let windEast = finiteFloat(\"atmosphere/total-wind-east-fps\", fallback: 0) * feetToMeters\n"
    "        let windDown = finiteFloat(\"atmosphere/total-wind-down-fps\", fallback: 0) * feetToMeters\n"
    "        state.windMetersPerSecond = SIMD3<Float>(windEast, -windDown, windNorth)\n",
)

effects_path = Path("App/Stage2FlightEffects.swift")
effects = effects_path.read_text()
old_count = "    // 96 samples at 0.10 s gives just under ten seconds of persistent plume\n    // history without creating an unbounded RealityKit entity count.\n    private static let trailCount = 96\n"
new_count = "    // Bounded mobile pool: about twenty seconds of spatial history at 0.11 s sampling.\n    private static let trailCount = 180\n"
if effects.count(old_count) != 1:
    raise SystemExit("Stage2FlightEffects: trail-count block did not match")
effects = effects.replace(old_count, new_count, 1)
effects = effects.replace("    final class Runtime {\n", "    @MainActor\n    final class Runtime {\n", 1)
effects = effects.replace(
    "        fileprivate var strengths = Array(repeating: Float(0), count: trailCount)\n",
    "        fileprivate var strengths = Array(repeating: Float(0), count: trailCount)\n"
    "        fileprivate var persistences = Array(repeating: Float(0), count: trailCount)\n"
    "        fileprivate var driftVelocities = Array(repeating: SIMD3<Float>.zero, count: trailCount)\n",
    1,
)
effects = effects.replace(
    "            strengths = Array(repeating: 0, count: Stage2FlightEffects.trailCount)\n",
    "            strengths = Array(repeating: 0, count: Stage2FlightEffects.trailCount)\n"
    "            persistences = Array(repeating: 0, count: Stage2FlightEffects.trailCount)\n"
    "            driftVelocities = Array(repeating: .zero, count: Stage2FlightEffects.trailCount)\n",
    1,
)
effects_path.write_text(effects)

replace_between(
    "App/Stage2FlightEffects.swift",
    "    static func makeTrailPool() -> Entity {",
    "    static func updateAttachedEffects(",
    '''    static func makeTrailPool() -> Entity {
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
            core.name = "FA.effects.contrail.core.\\(index)"
            core.isEnabled = false
            root.addChild(core)

            let haze = ModelEntity(
                mesh: hazeVariants[index % hazeVariants.count],
                materials: [effectMaterial(alpha: 0.0)]
            )
            haze.name = "FA.effects.contrail.haze.\\(index)"
            haze.isEnabled = false
            root.addChild(haze)
        }
        return root
    }''',
)

replace_between(
    "App/Stage2FlightEffects.swift",
    "    static func updateWorldTrails(",
    "    // MARK: - Aerodynamic condensation",
    '''    static func updateWorldTrails(
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
    }''',
)

replace_between(
    "App/Stage2FlightEffects.swift",
    "    private static func updateWingCondensation(",
    "    private static func updateTransonicCondensation(",
    '''    private static func updateWingCondensation(
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
    }''',
)

replace_between(
    "App/Stage2FlightEffects.swift",
    "    private static func updateTransonicCondensation(",
    "    // MARK: - Geometry",
    '''    private static func updateTransonicCondensation(
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
            guard let cloud = root.findEntity(named: "\\(transonicCloudPrefix).\\(layer)") as? ModelEntity else {
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
    }''',
)

replace_between(
    "App/Stage2FlightEffects.swift",
    "    private static func makePlumeSegmentMesh() -> MeshResource? {",
    "    private static func appendDoubleSidedQuad(",
    '''    private static func makePlumeSegmentMesh(phase: Float, haze: Bool) -> MeshResource? {
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
    }''',
)

replace_between(
    "App/Stage2FlightEffects.swift",
    "    private static func isaTemperatureC(altitudeFeet: Float) -> Float {",
    "    private static func worldPoint(",
    '''    private static func schmidtApplemanCriticalTemperatureC(pressurePSF: Float) -> Float {
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
    }''',
)

surface = Path("Aircraft/PrototypeAircraftFactory.swift")
surface_text = surface.read_text()
for old, new in {
    "speedbrake.position = [0, -0.16, -4.00]": "speedbrake.position = [0, -0.28, -4.00]",
    "hingePosition: [-3.42, -1.00, -3.58]": "hingePosition: [-3.42, -1.12, -3.58]",
    "hingePosition: [3.42, -1.00, -3.58]": "hingePosition: [3.42, -1.12, -3.58]",
    "hingePosition: [-1.55, -0.82, -5.05]": "hingePosition: [-1.55, -0.94, -5.05]",
    "hingePosition: [1.55, -0.82, -5.05]": "hingePosition: [1.55, -0.94, -5.05]",
    "hingePosition: [0, 0.14, -5.62]": "hingePosition: [0, 0.02, -5.62]",
}.items():
    if surface_text.count(old) != 1:
        raise SystemExit(f"surface placement match failure: {old}")
    surface_text = surface_text.replace(old, new, 1)
surface_text = surface_text.replace("Stage 010.5:", "Stage 010.6:", 1)
surface.write_text(surface_text)

print("Stage 010.6 source patch applied")
