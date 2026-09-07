from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected 1 match for {old[:100]!r}, got {count}")
    p.write_text(text.replace(old, new, 1))


def replace_between(path, start, end, new):
    p = Path(path)
    text = p.read_text()
    i = text.find(start)
    if i < 0:
        raise SystemExit(f"{path}: missing start marker {start!r}")
    j = text.find(end, i)
    if j < 0:
        raise SystemExit(f"{path}: missing end marker {end!r}")
    p.write_text(text[:i] + new.rstrip() + "\n\n" + text[j:])


effects = "App/Stage2FlightEffects.swift"

replace_once(effects, "        fileprivate var coreSegments: [ModelEntity] = []\n        fileprivate var hazeSegments: [ModelEntity] = []\n", "        fileprivate var coreSegments: [ModelEntity] = []\n        fileprivate var vortexSegments: [ModelEntity] = []\n        fileprivate var secondarySegments: [ModelEntity] = []\n")
replace_once(effects, "        fileprivate var driftVelocities = Array(repeating: SIMD3<Float>.zero, count: trailCount)\n", "        fileprivate var windVelocities = Array(repeating: SIMD3<Float>.zero, count: trailCount)\n        fileprivate var wakeDescentRates = Array(repeating: Float(0), count: trailCount)\n")
replace_once(effects, '''            hazeSegments = (0..<Stage2FlightEffects.trailCount).compactMap {
                root.findEntity(named: "FA.effects.contrail.haze.\($0)") as? ModelEntity
            }''', '''            vortexSegments = (0..<Stage2FlightEffects.trailCount).compactMap {
                root.findEntity(named: "FA.effects.contrail.vortex.\($0)") as? ModelEntity
            }
            secondarySegments = (0..<Stage2FlightEffects.trailCount).compactMap {
                root.findEntity(named: "FA.effects.contrail.secondary.\($0)") as? ModelEntity
            }''')
replace_once(effects, "            for entity in coreSegments + hazeSegments {\n                entity.isEnabled = false\n            }", "            for entity in coreSegments + vortexSegments + secondarySegments {\n                entity.isEnabled = false\n            }")
replace_once(effects, "            driftVelocities = Array(repeating: .zero, count: Stage2FlightEffects.trailCount)\n", "            windVelocities = Array(repeating: .zero, count: Stage2FlightEffects.trailCount)\n            wakeDescentRates = Array(repeating: 0, count: Stage2FlightEffects.trailCount)\n")

replace_between(
    effects,
    "    static func makeTrailPool() -> Entity {",
    "    static func updateAttachedEffects(",
    r'''    static func makeTrailPool() -> Entity {
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
    }'''
)

replace_between(
    effects,
    "    static func updateWorldTrails(",
    "    // MARK: - Aerodynamic condensation",
    r'''    static func updateWorldTrails(
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

        // Preserve Stage 010.6 formation physics: live JSBSim temperature,
        // pressure and F100 fuel flow plus the visual-only ice-RH world field.
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
            let exhaust = worldPoint(local: [0, -0.21, -7.95], state: state)
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
            let jetRadius = 0.10 + 0.055 * min(ageF, 2.4)
            core.isEnabled = jetFade * strength > 0.006
            core.scale = [jetRadius, jetRadius * 0.90, runtime.lengths[index]]
            setEffectAlpha(core, alpha: 0.22 * strength * jetFade)

            // Primary wake: two counter-rotating lobes spread toward rolled-up
            // vortex spacing while descending under mutual induction.
            let rollup = smoothStep(clamp((ageF - 0.45) / 4.8, 0, 1))
            let breakup = clamp((ageF - 8.0) / 8.0, 0, 1)
            let pairWidth = 0.85 + rollup * (wakeVortexSeparation - 0.85) + breakup * 2.2
            let pairDepth = 0.42 + rollup * 1.65 + ageF * (0.045 + 0.055 * persistence)
            let vortexBuild = smoothStep(clamp((ageF - 0.35) / 1.8, 0, 1))
            let vortexFade = pow(max(0, 1 - normalizedAge), 0.52)
            vortex.isEnabled = vortexBuild * vortexFade * strength > 0.005
            vortex.scale = [pairWidth, pairDepth, runtime.lengths[index]]
            setEffectAlpha(vortex, alpha: 0.115 * strength * vortexBuild * vortexFade * (0.55 + 0.45 * persistence))

            // Secondary wake: detrained ice remains near flight level while the
            // primary pair descends, so it is delayed, broad and deliberately wispy.
            let secondaryBuild = smoothStep(clamp((ageF - 2.0) / 4.0, 0, 1))
            let secondaryFade = pow(max(0, 1 - normalizedAge), 0.65)
            let secondaryWidth = 1.0 + ageF * (0.20 + 0.20 * persistence)
            let secondaryDepth = 0.24 + ageF * 0.055
            secondary.isEnabled = secondaryBuild * secondaryFade * strength * persistence > 0.010
            secondary.scale = [secondaryWidth, secondaryDepth, runtime.lengths[index]]
            setEffectAlpha(secondary, alpha: 0.050 * strength * persistence * secondaryBuild * secondaryFade)
        }
    }'''
)

replace_between(
    effects,
    "    private static func makePlumeSegmentMesh(",
    "    private static func appendDoubleSidedQuad(",
    r'''    private static func makeJetCoreSegmentMesh(phase: Float) -> MeshResource? {
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
        for lobe: Float in [-1, 1] {
            for sheet in 0..<3 {
                let base = UInt32(positions.count)
                let angle = Float(sheet) / 3.0 * .pi
                let c = cos(angle), s = sin(angle)
                for station in 0..<stations {
                    let t = Float(station) / Float(stations - 1)
                    let z = t - 0.5
                    let ragged = 1 + 0.13*sin(t*13+phase+Float(sheet)*1.1+lobe) + 0.05*sin(t*29-phase*0.6)
                    let radius = 0.145 * ragged
                    let swirl = 0.035 * sin(t*18+phase+lobe*1.7)
                    let centerX = lobe * 0.39
                    let centerY = -0.055 + lobe * swirl
                    let a = SIMD2<Float>(centerX-radius*c, centerY-radius*s)
                    let b = SIMD2<Float>(centerX+radius*c, centerY+radius*s)
                    positions.append([a.x, a.y, z]); positions.append([b.x, b.y, z])
                }
                for station in 0..<(stations - 1) {
                    let i = base + UInt32(station * 2)
                    appendDoubleSidedQuad(&indices, i, i+1, i+2, i+3)
                }
            }
        }
        var descriptor = MeshDescriptor(name: "Contrail rolled-up vortex pair")
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
    }'''
)
