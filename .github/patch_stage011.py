from pathlib import Path
import re

factory_path = Path('Aircraft/PrototypeAircraftFactory.swift')
factory = factory_path.read_text()

old_constants = '''    static let afterburnerInnerName = "FA.aircraft.afterburner.inner"
    static let afterburnerOuterName = "FA.aircraft.afterburner.outer"
    static let nozzleName = "FA.aircraft.nozzle"'''
new_constants = '''    static let afterburnerInnerName = "FA.aircraft.afterburner.inner"
    static let afterburnerOuterName = "FA.aircraft.afterburner.outer"
    static let afterburnerCoreName = "FA.aircraft.afterburner.core"
    static let afterburnerHaloName = "FA.aircraft.afterburner.halo"
    static let afterburnerShockPrefix = "FA.aircraft.afterburner.shock."
    static let nozzleName = "FA.aircraft.nozzle"'''
if factory.count(old_constants) != 1:
    raise SystemExit('afterburner constant anchor mismatch')
factory = factory.replace(old_constants, new_constants, 1)

new_afterburner = r'''    private static func addAfterburner(to root: Entity) throws {
        let plumeMesh = try loadAuthoredOBJ("afterburner_plume")
        let plume = Entity()
        plume.name = afterburnerName

        // The visual root and the authored F-16 use the same coordinate frame.
        // The source plume mesh itself begins 0.5 m down its local axis, so each
        // envelope layer gets a +0.5 m Z compensation after rotation. That puts
        // the first luminous texels directly on the physical nozzle lip instead
        // of leaving the half-meter gap visible in the chase camera.
        plume.position = [0, 0, -7.025]
        plume.isEnabled = false

        let aftRotation = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        let meshLipCompensation = SIMD3<Float>(0, 0, 0.50)

        let halo = ModelEntity(
            mesh: plumeMesh,
            materials: [UnlitMaterial(color: UIColor(
                red: 0.22,
                green: 0.12,
                blue: 0.78,
                alpha: 0.13
            ))]
        )
        halo.name = afterburnerHaloName
        halo.orientation = aftRotation
        halo.position = meshLipCompensation
        halo.scale = [1.15, 2.15, 1.15]
        plume.addChild(halo)

        let outer = ModelEntity(
            mesh: plumeMesh,
            materials: [UnlitMaterial(color: UIColor(
                red: 0.08,
                green: 0.28,
                blue: 1.0,
                alpha: 0.28
            ))]
        )
        outer.name = afterburnerOuterName
        outer.orientation = aftRotation
        outer.position = meshLipCompensation
        outer.scale = [0.94, 1.90, 1.02]
        plume.addChild(outer)

        let inner = ModelEntity(
            mesh: plumeMesh,
            materials: [UnlitMaterial(color: UIColor(
                red: 0.42,
                green: 0.76,
                blue: 1.0,
                alpha: 0.50
            ))]
        )
        inner.name = afterburnerInnerName
        inner.orientation = aftRotation
        inner.position = meshLipCompensation
        inner.scale = [0.58, 1.52, 0.66]
        plume.addChild(inner)

        let core = ModelEntity(
            mesh: plumeMesh,
            materials: [UnlitMaterial(color: UIColor(
                red: 0.94,
                green: 0.97,
                blue: 1.0,
                alpha: 0.82
            ))]
        )
        core.name = afterburnerCoreName
        core.orientation = aftRotation
        core.position = meshLipCompensation
        core.scale = [0.24, 1.12, 0.30]
        plume.addChild(core)

        // Thin pressure cells live *inside* the flame envelope. These are not
        // the old detached sphere blobs: from the side they read as soft bands
        // in the plume and disappear with the burner.
        let shockZ: [Float] = [-0.68, -1.36, -2.10, -2.92, -3.82]
        let shockR: [Float] = [0.34, 0.31, 0.27, 0.23, 0.19]
        for index in shockZ.indices {
            let cell = ModelEntity(
                mesh: .generateCylinder(height: 0.055, radius: shockR[index]),
                materials: [UnlitMaterial(color: UIColor(
                    red: 0.82,
                    green: 0.92,
                    blue: 1.0,
                    alpha: max(0.11, 0.30 - Float(index) * 0.038)
                ))]
            )
            cell.name = afterburnerShockPrefix + String(index)
            cell.position = [0, 0, shockZ[index]]
            cell.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
            cell.isEnabled = false
            plume.addChild(cell)
        }

        root.addChild(plume)

        // Keep nozzle incandescence outside the AB hierarchy so high dry power
        // can still show a hot turbine/nozzle core when the flame is off.
        let glow = ModelEntity(
            mesh: .generateCylinder(height: 0.032, radius: 0.455),
            materials: [UnlitMaterial(color: UIColor(
                red: 0.58,
                green: 0.75,
                blue: 1.0,
                alpha: 0.52
            ))]
        )
        glow.name = nozzleGlowName
        glow.position = [0, 0, -7.030]
        glow.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        glow.isEnabled = false
        root.addChild(glow)
    }
'''
pattern = r'    private static func addAfterburner\(to root: Entity\) throws \{.*?\n    \}\n\n(?=    private static func addLandingGear)'
factory, count = re.subn(pattern, new_afterburner + '\n', factory, count=1, flags=re.S)
if count != 1:
    raise SystemExit('addAfterburner replacement mismatch')
factory_path.write_text(factory)

scene_path = Path('App/PrototypeSceneView.swift')
scene = scene_path.read_text()
old_call = 'runtime.jetAudio.update(state: simulation.state, isPaused: simulation.isPaused)'
new_call = 'runtime.jetAudio.update(state: simulation.state, isPaused: simulation.isPaused, isCockpit: cameraMode == .cockpit)'
if scene.count(old_call) != 1:
    raise SystemExit('jet audio call anchor mismatch')
scene = scene.replace(old_call, new_call, 1)

new_update = r'''    @MainActor
    private func updateAfterburner(_ aircraft: Entity, state: AircraftState) {
        let n2 = clamp((state.engineN2Percent - 96.0) / 4.0, 0, 1)
        let fuel = clamp((state.engineFuelFlowPoundsPerSecond - 0.30) / 1.30, 0, 1)
        let intensity = state.afterburnerActive ? clamp(0.48 + 0.40 * n2 + 0.12 * fuel, 0, 1) : 0
        let time = Float(simulation.simulationTime)

        // Lower ambient pressure lets the jet expand more. This is only a visual
        // presentation term; JSBSim remains authoritative for actual thrust.
        let pressureExpansion = clamp(sqrt(2_116.22 / max(state.ambientPressurePSF, 450)), 0.90, 1.62)
        let speedCompression = clamp(1.0 - 0.08 * state.mach, 0.87, 1.0)

        if let plume = aircraft.findEntity(named: PrototypeAircraftFactory.afterburnerName) {
            plume.isEnabled = intensity > 0.01
        }

        if intensity > 0.01 {
            let fast = sin(time * 47.0)
            let mid = sin(time * 19.0 + 1.7)
            let slow = sin(time * 7.2 + 0.6)
            let turbulence = 1.0 + 0.018 * fast + 0.013 * mid + 0.008 * slow
            let width = (0.90 + 0.10 * intensity) * turbulence * (0.94 + 0.06 * pressureExpansion)
            let length = (0.82 + 0.58 * intensity) * pressureExpansion * speedCompression

            if let halo = aircraft.findEntity(named: PrototypeAircraftFactory.afterburnerHaloName) {
                halo.scale = [1.15 * width, 2.15 * length, 1.15 * width]
            }
            if let outer = aircraft.findEntity(named: PrototypeAircraftFactory.afterburnerOuterName) {
                outer.scale = [0.94 * width, 1.90 * length, 1.02 * width]
            }
            if let inner = aircraft.findEntity(named: PrototypeAircraftFactory.afterburnerInnerName) {
                let pulse = 1.0 + 0.016 * sin(time * 61.0 + 0.9)
                inner.scale = [0.58 * width * pulse, 1.52 * length, 0.66 * width * pulse]
            }
            if let core = aircraft.findEntity(named: PrototypeAircraftFactory.afterburnerCoreName) {
                let pulse = 1.0 + 0.026 * sin(time * 73.0 + 0.35)
                core.scale = [0.24 * width * pulse, 1.12 * length, 0.30 * width * pulse]
            }

            for index in 0..<5 {
                if let cell = aircraft.findEntity(named: PrototypeAircraftFactory.afterburnerShockPrefix + String(index)) {
                    let phase = Float(index) * 0.92
                    let pulse = 0.94 + 0.08 * sin(time * 35.0 + phase)
                    let pressureReach = clamp((pressureExpansion - 0.88) * 1.6, 0, 1)
                    cell.scale = [pulse * width, 0.72 + 0.28 * intensity, pulse * width]
                    cell.isEnabled = intensity > 0.30 && pressureReach > Float(index) * 0.16
                }
            }
        }

        if let glow = aircraft.findEntity(named: PrototypeAircraftFactory.nozzleGlowName) {
            let dryHeat = clamp((state.engineN2Percent - 78) / 22, 0, 1)
            let hot = max(dryHeat * 0.32, intensity)
            glow.isEnabled = hot > 0.03
            if glow.isEnabled {
                let flicker = 1.0 + 0.015 * sin(time * 57.0)
                glow.scale = [0.82 + 0.18 * hot, 0.82 + 0.18 * hot, (0.78 + 0.22 * hot) * flicker]
            }
        }
    }
'''
pattern = r'    @MainActor\n    private func updateAfterburner\(_ aircraft: Entity, state: AircraftState\) \{.*?\n    \}\n\n(?=    @MainActor\n    private func updateGear)'
scene, count = re.subn(pattern, new_update + '\n', scene, count=1, flags=re.S)
if count != 1:
    raise SystemExit('updateAfterburner replacement mismatch')

new_audio = r'''@MainActor
private final class Stage0108JetAudio {
    private let engine = AVAudioEngine()
    private let rumble = AVAudioPlayerNode()
    private let turbine = AVAudioPlayerNode()
    private let exhaust = AVAudioPlayerNode()
    private let afterburner = AVAudioPlayerNode()
    private let wind = AVAudioPlayerNode()
    private let ignition = AVAudioPlayerNode()

    private let rumbleRate = AVAudioUnitVarispeed()
    private let turbineRate = AVAudioUnitVarispeed()
    private let exhaustEQ = AVAudioUnitEQ(numberOfBands: 3)
    private let burnerEQ = AVAudioUnitEQ(numberOfBands: 3)
    private let windEQ = AVAudioUnitEQ(numberOfBands: 2)

    private var ignitionBuffer: AVAudioPCMBuffer?
    private var started = false
    private var lastAfterburnerActive = false

    init() {
        engine.attach(rumble)
        engine.attach(turbine)
        engine.attach(exhaust)
        engine.attach(afterburner)
        engine.attach(wind)
        engine.attach(ignition)
        engine.attach(rumbleRate)
        engine.attach(turbineRate)
        engine.attach(exhaustEQ)
        engine.attach(burnerEQ)
        engine.attach(windEQ)
    }

    func update(state: AircraftState, isPaused: Bool, isCockpit: Bool) {
        startIfNeeded()
        guard started else { return }

        let n1 = clamp(state.engineN1Percent / 100, 0, 1.15)
        let n2 = clamp(state.engineN2Percent / 100, 0, 1.15)
        let mach = clamp(state.mach, 0, 1.8)
        let fuel = clamp(state.engineFuelFlowPoundsPerSecond / 1.8, 0, 1.2)
        let live: Float = isPaused ? 0 : 1
        let dryPower = max(n1, fuel)

        // Only the actual rotating components are pitch-shifted. Broadband jet
        // exhaust gets louder/denser with power instead of becoming a giant
        // varispeed fan loop.
        rumbleRate.rate = 0.80 + 0.31 * n1
        turbineRate.rate = 0.60 + 1.14 * n2

        let cockpitRumble: Float = isCockpit ? 0.62 : 1.0
        let cockpitTurbine: Float = isCockpit ? 1.24 : 0.72
        let cockpitExhaust: Float = isCockpit ? 0.28 : 1.0
        let cockpitWind: Float = isCockpit ? 0.38 : 1.0

        rumble.volume = live * cockpitRumble * (0.040 + 0.16 * n1)
        turbine.volume = live * cockpitTurbine * (0.010 + 0.082 * n2 * n2)
        exhaust.volume = live * cockpitExhaust * (0.050 + 0.32 * dryPower)
        afterburner.volume = live * cockpitExhaust * (state.afterburnerActive ? 0.44 + 0.20 * n2 : 0)
        wind.volume = live * cockpitWind * (0.006 + 0.052 * min(powf(mach, 1.55), 1.40))

        if state.afterburnerActive && !lastAfterburnerActive && !isPaused {
            fireIgnitionTransient(isCockpit: isCockpit)
        }
        lastAfterburnerActive = state.afterburnerActive
    }

    private func startIfNeeded() {
        guard !started else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
            configureEQ()

            engine.connect(rumble, to: rumbleRate, format: format)
            engine.connect(rumbleRate, to: engine.mainMixerNode, format: format)
            engine.connect(turbine, to: turbineRate, format: format)
            engine.connect(turbineRate, to: engine.mainMixerNode, format: format)
            engine.connect(exhaust, to: exhaustEQ, format: format)
            engine.connect(exhaustEQ, to: engine.mainMixerNode, format: format)
            engine.connect(afterburner, to: burnerEQ, format: format)
            engine.connect(burnerEQ, to: engine.mainMixerNode, format: format)
            engine.connect(wind, to: windEQ, format: format)
            engine.connect(windEQ, to: engine.mainMixerNode, format: format)
            engine.connect(ignition, to: engine.mainMixerNode, format: format)

            schedule(rumble, buffer: makeRumbleBuffer(format: format, seconds: 8.0))
            schedule(turbine, buffer: makeTurbineBuffer(format: format, seconds: 8.0))
            schedule(exhaust, buffer: makeRoarBuffer(format: format, seconds: 8.0, afterburner: false))
            schedule(afterburner, buffer: makeRoarBuffer(format: format, seconds: 8.0, afterburner: true))
            schedule(wind, buffer: makeWindBuffer(format: format, seconds: 8.0))
            ignitionBuffer = makeIgnitionBuffer(format: format, seconds: 0.78)

            engine.mainMixerNode.outputVolume = 0.92
            try engine.start()
            rumble.play()
            turbine.play()
            exhaust.play()
            afterburner.play()
            wind.play()
            started = true
        } catch {
            started = false
        }
    }

    private func configureEQ() {
        let exhaustBands = exhaustEQ.bands
        exhaustBands[0].filterType = .lowShelf
        exhaustBands[0].frequency = 105
        exhaustBands[0].gain = 7.0
        exhaustBands[0].bypass = false
        exhaustBands[1].filterType = .parametric
        exhaustBands[1].frequency = 720
        exhaustBands[1].bandwidth = 1.25
        exhaustBands[1].gain = -4.5
        exhaustBands[1].bypass = false
        exhaustBands[2].filterType = .highShelf
        exhaustBands[2].frequency = 3_400
        exhaustBands[2].gain = 1.8
        exhaustBands[2].bypass = false

        let burnerBands = burnerEQ.bands
        burnerBands[0].filterType = .lowShelf
        burnerBands[0].frequency = 90
        burnerBands[0].gain = 8.5
        burnerBands[0].bypass = false
        burnerBands[1].filterType = .parametric
        burnerBands[1].frequency = 460
        burnerBands[1].bandwidth = 1.0
        burnerBands[1].gain = 3.5
        burnerBands[1].bypass = false
        burnerBands[2].filterType = .highShelf
        burnerBands[2].frequency = 2_800
        burnerBands[2].gain = 3.8
        burnerBands[2].bypass = false

        let windBands = windEQ.bands
        windBands[0].filterType = .highPass
        windBands[0].frequency = 520
        windBands[0].bandwidth = 0.8
        windBands[0].bypass = false
        windBands[1].filterType = .highShelf
        windBands[1].frequency = 3_000
        windBands[1].gain = -2.0
        windBands[1].bypass = false
    }

    private func schedule(_ node: AVAudioPlayerNode, buffer: AVAudioPCMBuffer) {
        node.scheduleBuffer(buffer, at: nil, options: [.loops])
    }

    private func fireIgnitionTransient(isCockpit: Bool) {
        guard let ignitionBuffer else { return }
        ignition.stop()
        ignition.volume = isCockpit ? 0.18 : 0.54
        ignition.scheduleBuffer(ignitionBuffer, at: nil, options: [])
        ignition.play()
    }

    private func makeRumbleBuffer(format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer {
        makeStereoBuffer(format: format, seconds: seconds) { t, channel, random in
            let phase: Float = channel == 0 ? 0 : 0.19
            let amplitude = 0.82 + 0.12 * sin(2 * .pi * 1.25 * t + phase) + 0.06 * sin(2 * .pi * 3.0 * t)
            let tones =
                0.46 * sin(2 * .pi * 36 * t + phase) +
                0.31 * sin(2 * .pi * 54 * t) +
                0.16 * sin(2 * .pi * 81 * t + 0.7) +
                0.08 * sin(2 * .pi * 108 * t + 1.1)
            return (tones * amplitude + random * 0.055) * 0.55
        }
    }

    private func makeTurbineBuffer(format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer {
        makeStereoBuffer(format: format, seconds: seconds) { t, channel, random in
            let phase: Float = channel == 0 ? 0 : 0.11
            let blade =
                0.52 * sin(2 * .pi * 315 * t + phase) +
                0.27 * sin(2 * .pi * 630 * t + 0.3) +
                0.13 * sin(2 * .pi * 945 * t + 0.9) +
                0.06 * sin(2 * .pi * 1_575 * t + 1.4)
            let shimmer = 0.90 + 0.07 * sin(2 * .pi * 7.0 * t) + 0.03 * sin(2 * .pi * 13.0 * t + phase)
            return (blade * shimmer + random * 0.025) * 0.34
        }
    }

    private func makeRoarBuffer(format: AVAudioFormat, seconds: Double, afterburner: Bool) -> AVAudioPCMBuffer {
        let count = AVAudioFrameCount(format.sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buffer.frameLength = count
        let rate = Float(format.sampleRate)
        let channels = Int(format.channelCount)
        var seeds: [UInt32] = [0x91E1_0DA5, 0xC2A7_3B19]
        var low: [Float] = [0, 0]
        var mid: [Float] = [0, 0]
        var burst: [Float] = [0, 0]

        for i in 0..<Int(count) {
            let t = Float(i) / rate
            for ch in 0..<channels {
                seeds[ch] = 1_664_525 &* seeds[ch] &+ 1_013_904_223
                let raw = Float(Int32(bitPattern: seeds[ch])) / Float(Int32.max)
                low[ch] = 0.992 * low[ch] + 0.008 * raw
                mid[ch] = 0.72 * mid[ch] + 0.28 * raw
                let high = raw - mid[ch]

                if afterburner && abs(raw) > 0.9925 {
                    burst[ch] += raw * 0.85
                }
                burst[ch] *= afterburner ? 0.975 : 0.94

                let combustion =
                    0.12 * sin(2 * .pi * 47 * t + Float(ch) * 0.17) +
                    0.07 * sin(2 * .pi * 73 * t + 0.6)
                let breathing = 0.88 + 0.07 * sin(2 * .pi * 2.0 * t) + 0.05 * sin(2 * .pi * 3.5 * t + 1.2)

                let broadband: Float
                if afterburner {
                    broadband = low[ch] * 1.25 + mid[ch] * 0.78 + high * 0.30 + burst[ch] * 0.36
                } else {
                    broadband = low[ch] * 1.10 + mid[ch] * 0.58 + high * 0.12
                }
                let sample = (broadband * breathing + combustion) * (afterburner ? 0.72 : 0.62)
                buffer.floatChannelData![ch][i] = clamp(sample, -0.98, 0.98)
            }
        }
        return buffer
    }

    private func makeWindBuffer(format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer {
        let count = AVAudioFrameCount(format.sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buffer.frameLength = count
        let channels = Int(format.channelCount)
        var seeds: [UInt32] = [0x48B2_1197, 0xDA09_7FC1]
        var slow: [Float] = [0, 0]
        for i in 0..<Int(count) {
            for ch in 0..<channels {
                seeds[ch] = 1_664_525 &* seeds[ch] &+ 1_013_904_223
                let raw = Float(Int32(bitPattern: seeds[ch])) / Float(Int32.max)
                slow[ch] = 0.965 * slow[ch] + 0.035 * raw
                let high = raw - slow[ch]
                buffer.floatChannelData![ch][i] = high * 0.20
            }
        }
        return buffer
    }

    private func makeIgnitionBuffer(format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer {
        makeStereoBuffer(format: format, seconds: seconds) { t, channel, random in
            let phase = Float(channel) * 0.13
            let thump = sin(2 * .pi * 57 * t + phase) * exp(-7.0 * t)
            let barkEnvelope = min(t * 18.0, 1.0) * exp(-2.0 * t)
            let bark = random * barkEnvelope
            return clamp(thump * 0.62 + bark * 0.50, -0.98, 0.98)
        }
    }

    private func makeStereoBuffer(
        format: AVAudioFormat,
        seconds: Double,
        sample: (_ time: Float, _ channel: Int, _ random: Float) -> Float
    ) -> AVAudioPCMBuffer {
        let count = AVAudioFrameCount(format.sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buffer.frameLength = count
        let rate = Float(format.sampleRate)
        let channels = Int(format.channelCount)
        var seeds: [UInt32] = [0xA17F_16C3, 0x7E31_9B45]
        for i in 0..<Int(count) {
            let t = Float(i) / rate
            for ch in 0..<channels {
                seeds[ch] = 1_664_525 &* seeds[ch] &+ 1_013_904_223
                let random = Float(Int32(bitPattern: seeds[ch])) / Float(Int32.max)
                buffer.floatChannelData![ch][i] = clamp(sample(t, ch, random), -0.98, 0.98)
            }
        }
        return buffer
    }

    private func clamp(_ value: Float, _ low: Float, _ high: Float) -> Float {
        Swift.min(Swift.max(value, low), high)
    }
}
'''
pattern = r'@MainActor\nprivate final class Stage0108JetAudio \{.*\Z'
scene, count = re.subn(pattern, new_audio, scene, count=1, flags=re.S)
if count != 1:
    raise SystemExit('jet audio class replacement mismatch')
scene_path.write_text(scene)
