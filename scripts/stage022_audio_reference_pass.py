from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}: {old[:120]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


def replace_between(path: str, start_marker: str, end_marker: str, replacement: str) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    start = text.find(start_marker)
    if start < 0:
        raise SystemExit(f'{path}: missing start marker {start_marker!r}')
    end = text.find(end_marker, start)
    if end < 0:
        raise SystemExit(f'{path}: missing end marker {end_marker!r}')
    p.write_text(text[:start] + replacement + text[end:], encoding='utf-8')


# -----------------------------------------------------------------------------
# Stage 022 menu composition + event audio
# -----------------------------------------------------------------------------
menu = 'App/Stage022MainMenu.swift'

replace_once(
    menu,
    '''        if !lowPassAudioPlayed && elapsed >= 118.4 {\n            lowPassAudioPlayed = true\n            audio.playLowPass()\n        }\n''',
    '''        if !lowPassAudioPlayed && elapsed >= 117.35 {\n            lowPassAudioPlayed = true\n            audio.playSupersonicPass()\n        }\n'''
)

replace_once(
    menu,
    '''    static let cameraPosition = SIMD3<Float>(188, 6.6, 720)\n    static let cameraTarget = SIMD3<Float>(0, 7.0, 80)\n''',
    '''    // Move the spectator closer to the departure start so the idle/spool\n    // phase and first few hundred metres of the ground roll are visually legible.\n    static let cameraPosition = SIMD3<Float>(145, 5.8, -190)\n    static let cameraTarget = SIMD3<Float>(0, 4.3, -420)\n'''
)

replace_once(
    menu,
    '''        let eventStart: TimeInterval = 114.1\n''',
    '''        let eventStart: TimeInterval = 116.8\n'''
)

replace_once(
    menu,
    '''        let distanceFromCameraStation = abs(z - cameraPosition.z)\n        setTransonicVapor(jet, visible: distanceFromCameraStation < 620)\n''',
    '''        let distanceFromCameraStation = abs(z - cameraPosition.z)\n        let coneVisible = distanceFromCameraStation < 900\n        let coneIntensity = coneVisible\n            ? min(max(1.0 - distanceFromCameraStation / 900.0, 0), 1)\n            : 0\n        Stage2FlightEffects.setAttractModeTransonicVapor(\n            root: jet,\n            visible: coneVisible,\n            intensity: 0.58 + 0.42 * coneIntensity\n        )\n'''
)

replace_once(
    menu,
    '''            setTransonicVapor(jet, visible: false)\n''',
    '''            Stage2FlightEffects.setAttractModeTransonicVapor(root: jet, visible: false, intensity: 0)\n'''
)

# Remove the old local on/off-only vapor helper; the flight-effects module now owns
# the stronger attract-mode cone treatment.
start = '''    private static func setTransonicVapor(_ jet: Entity, visible: Bool) {\n'''
end = '''}\n\nprivate final class Stage022MenuAudio {\n'''
p = Path(menu)
text = p.read_text(encoding='utf-8')
s = text.find(start)
e = text.find(end, s)
if s < 0 or e < 0:
    raise SystemExit('Stage022MainMenu.swift: failed to locate old transonic helper')
text = text[:s] + '''}\n\nprivate final class Stage022MenuAudio {\n''' + text[e + len(end):]
p.write_text(text, encoding='utf-8')

# Replace menu audio engine with separated DCS/Unity-style layers.
replace_between(
    menu,
    'private final class Stage022MenuAudio {\n',
    '\n    private func makeAmbienceBuffer() -> AVAudioPCMBuffer {\n',
    '''private final class Stage022MenuAudio {\n    private let engine = AVAudioEngine()\n    private let ambience = AVAudioPlayerNode()\n    private let takeoff = AVAudioPlayerNode()\n    private let burner = AVAudioPlayerNode()\n    private let flyby = AVAudioPlayerNode()\n    private let sonicBoom = AVAudioPlayerNode()\n    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!\n\n    private lazy var ambienceBuffer = makeAmbienceBuffer()\n    private lazy var takeoffBuffer = makeTakeoffBuffer()\n    private lazy var burnerBuffer = makeTakeoffAfterburnerBuffer()\n    private lazy var flybyBuffer = makeFlybyBuffer()\n    private lazy var sonicBoomBuffer = makeSonicBoomBuffer()\n\n    init() {\n        do {\n            let session = AVAudioSession.sharedInstance()\n            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])\n            try session.setActive(true)\n\n            for node in [ambience, takeoff, burner, flyby, sonicBoom] {\n                engine.attach(node)\n                engine.connect(node, to: engine.mainMixerNode, format: format)\n            }\n            engine.mainMixerNode.outputVolume = 0.68\n            try engine.start()\n\n            ambience.scheduleBuffer(ambienceBuffer, at: nil, options: .loops)\n            ambience.volume = 0.22\n            ambience.play()\n        } catch {\n            // Menu remains usable if audio is unavailable.\n        }\n    }\n\n    deinit {\n        engine.stop()\n    }\n\n    func playTakeoff() {\n        guard engine.isRunning else { return }\n\n        takeoff.stop()\n        burner.stop()\n\n        takeoff.scheduleBuffer(takeoffBuffer, at: nil, options: .interrupts)\n        burner.scheduleBuffer(burnerBuffer, at: nil, options: .interrupts)\n        takeoff.volume = 0.72\n        burner.volume = 0.88\n        takeoff.play()\n        burner.play()\n    }\n\n    func playSupersonicPass() {\n        guard engine.isRunning else { return }\n\n        flyby.stop()\n        sonicBoom.stop()\n\n        flyby.scheduleBuffer(flybyBuffer, at: nil, options: .interrupts)\n        sonicBoom.scheduleBuffer(sonicBoomBuffer, at: nil, options: .interrupts)\n        flyby.volume = 0.82\n        sonicBoom.volume = 1.0\n        flyby.play()\n        sonicBoom.play()\n    }\n'''
)

# Replace takeoff/flyby generation with low-frequency, independently layered events.
replace_between(
    menu,
    '    private func makeTakeoffBuffer() -> AVAudioPCMBuffer {\n',
    '\n    private func makeBuffer(\n',
    '''    private func makeTakeoffBuffer() -> AVAudioPCMBuffer {\n        // Dry engine / ground-roll bed. Deliberately very little broadband noise:\n        // the afterburner has its own source below, like DCS/Unity-style layering.\n        makeBuffer(seconds: 19.0, seed: 0xF160_0220) { t, _, noise in\n            let spool = min(max(t / 2.8, 0), 1)\n            let roll = min(max((t - 2.5) / 11.5, 0), 1)\n            let departureFade = max(0, 1 - max(0, t - 15.5) / 3.5)\n            let envelope = (0.20 + 0.80 * spool) * departureFade\n            let fundamental = 42 + 22 * spool + 17 * roll\n            let combustion =\n                0.78 * sin(2 * .pi * fundamental * t) +\n                0.31 * sin(2 * .pi * fundamental * 1.47 * t + 0.6) +\n                0.18 * sin(2 * .pi * 31 * t + 1.1)\n            let roughness = 0.012 * noise * (0.25 + 0.75 * roll)\n            return envelope * (0.18 * combustion + roughness)\n        }\n    }\n\n    private func makeTakeoffAfterburnerBuffer() -> AVAudioPCMBuffer {\n        let seconds: Float = 19.0\n        let sampleRate = Float(format.sampleRate)\n        let frames = AVAudioFrameCount(seconds * sampleRate)\n        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!\n        buffer.frameLength = frames\n        guard let channels = buffer.floatChannelData else { return buffer }\n\n        var seeds: [UInt32] = [0xF16A_B001, 0xF16A_B002]\n        var slow: [Float] = [0, 0]\n        var low: [Float] = [0, 0]\n        var body: [Float] = [0, 0]\n\n        for frame in 0..<Int(frames) {\n            let t = Float(frame) / sampleRate\n            let abOn = min(max((t - 3.15) / 0.70, 0), 1)\n            let fade = max(0, 1 - max(0, t - 16.0) / 3.0)\n            let envelope = abOn * fade\n\n            for ch in 0..<2 {\n                seeds[ch] = 1_664_525 &* seeds[ch] &+ 1_013_904_223\n                let raw = Float(Int32(bitPattern: seeds[ch])) / Float(Int32.max)\n                slow[ch] = 0.9982 * slow[ch] + 0.0018 * raw\n                low[ch] = 0.9850 * low[ch] + 0.0150 * raw\n                body[ch] = 0.9350 * body[ch] + 0.0650 * raw\n\n                let lowBand = low[ch] - slow[ch]\n                let bodyBand = body[ch] - low[ch]\n                let phase = Float(ch) * 0.17\n                let pressure =\n                    0.40 * sin(2 * .pi * 53 * t + phase) +\n                    0.24 * sin(2 * .pi * 79 * t + 0.5) +\n                    0.11 * sin(2 * .pi * 106 * t + 1.2)\n                let modulation = 0.90 + 0.07 * sin(2 * .pi * 2.1 * t + phase)\n                let roar = (1.45 * slow[ch] + 1.95 * lowBand + 0.34 * bodyBand) * modulation\n                let sample = envelope * (0.28 * pressure + 0.88 * roar)\n                channels[ch][frame] = min(max(sample, -0.92), 0.92)\n            }\n        }\n        return buffer\n    }\n\n    private func makeFlybyBuffer() -> AVAudioPCMBuffer {\n        let seconds: Float = 5.8\n        let sampleRate = Float(format.sampleRate)\n        let frames = AVAudioFrameCount(seconds * sampleRate)\n        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!\n        buffer.frameLength = frames\n        guard let channels = buffer.floatChannelData else { return buffer }\n\n        var seeds: [UInt32] = [0xFA26_0001, 0xFA26_0002]\n        var low: [Float] = [0, 0]\n        var body: [Float] = [0, 0]\n\n        for frame in 0..<Int(frames) {\n            let t = Float(frame) / sampleRate\n            let closest: Float = 2.65\n            let distance = abs(t - closest)\n            let approach = exp(-powf(distance / 1.05, 2))\n            let doppler = 118 - 46 * min(max(t / seconds, 0), 1)\n            let pan = min(max((t - closest) / 1.55, -1), 1)\n\n            for ch in 0..<2 {\n                seeds[ch] = 1_664_525 &* seeds[ch] &+ 1_013_904_223\n                let raw = Float(Int32(bitPattern: seeds[ch])) / Float(Int32.max)\n                low[ch] = 0.988 * low[ch] + 0.012 * raw\n                body[ch] = 0.925 * body[ch] + 0.075 * raw\n                let turbulent = 1.3 * low[ch] + 0.35 * (body[ch] - low[ch])\n                let engineBody =\n                    0.62 * sin(2 * .pi * doppler * t) +\n                    0.27 * sin(2 * .pi * doppler * 0.52 * t + 0.5)\n                let channelPan: Float = ch == 0 ? (1 - pan) * 0.5 : (1 + pan) * 0.5\n                let gain = sqrt(max(0.08, channelPan))\n                channels[ch][frame] = gain * approach * (0.15 * engineBody + 0.13 * turbulent)\n            }\n        }\n        return buffer\n    }\n\n    private func makeSonicBoomBuffer() -> AVAudioPCMBuffer {\n        // Delayed double shock: two short bipolar pressure impulses plus a low\n        // structural tail. This is intentionally a discrete event, not more hiss.\n        makeBuffer(seconds: 5.8, seed: 0xB00M_0220) { t, channel, _ in\n            let first: Float = 2.42\n            let second: Float = 2.57\n\n            func nWave(_ center: Float, amplitude: Float) -> Float {\n                let x = (t - center) / 0.016\n                return amplitude * x * exp(-x * x * 1.35)\n            }\n\n            let shock = nWave(first, amplitude: 1.0) + nWave(second, amplitude: 0.82)\n            let dt = max(0, t - first)\n            let thump = dt > 0\n                ? (0.55 * sin(2 * .pi * 43 * dt) + 0.24 * sin(2 * .pi * 71 * dt + 0.4)) * exp(-4.6 * dt)\n                : 0\n            let stereo = channel == 0 ? 0.98 : 1.0\n            return min(max(stereo * (0.93 * shock + 0.42 * thump), -0.98), 0.98)\n        }\n    }\n'''
)

# Fix invalid hex literal B00M -> B00D.
replace_once(menu, 'seed: 0xB00M_0220', 'seed: 0xB00D_0220')


# -----------------------------------------------------------------------------
# Stronger menu-only Mach cone helper; normal gameplay vapor remains unchanged.
# -----------------------------------------------------------------------------
fx = 'App/Stage2FlightEffects.swift'
insert_marker = '    private static func makeTransonicVaporEntity(\n'
helper = '''    static func setAttractModeTransonicVapor(\n        root: Entity,\n        visible: Bool,\n        intensity: Float\n    ) {\n        let i = clamp(intensity, 0, 1)\n\n        if let halo = root.findEntity(named: transonicHaloName) {\n            halo.isEnabled = visible\n            if visible {\n                halo.scale = [1.08 + 0.12 * i, 1.08 + 0.12 * i, 1.0]\n                setVaporOpacity(entity: halo, opacity: 0.040 + 0.055 * i)\n            }\n        }\n\n        if let shell = root.findEntity(named: transonicShellName) {\n            shell.isEnabled = visible\n            if visible {\n                shell.scale = [1.00 + 0.08 * i, 1.00 + 0.08 * i, 1.0]\n                setVaporOpacity(entity: shell, opacity: 0.085 + 0.095 * i)\n            }\n        }\n\n        // Keep the menu pass visually transonic, not high-AoA.\n        for name in [\n            lerxLeftName, lerxRightName,\n            leadingLeftName, leadingRightName,\n            tipLeftName, tipRightName\n        ] {\n            root.findEntity(named: name)?.isEnabled = false\n        }\n    }\n\n'''
p = Path(fx)
text = p.read_text(encoding='utf-8')
count = text.count(insert_marker)
if count != 1:
    raise SystemExit(f'{fx}: expected one transonic insert marker, got {count}')
text = text.replace(insert_marker, helper + insert_marker, 1)
p.write_text(text, encoding='utf-8')


# -----------------------------------------------------------------------------
# Gameplay jet mix: demote compressor whine and replace hiss-heavy exhaust bed.
# -----------------------------------------------------------------------------
scene = 'App/PrototypeSceneView.swift'

replace_once(
    scene,
    '''        turbineRate.rate = 0.62 + 0.74 * n2\n''',
    '''        turbineRate.rate = 0.76 + 0.36 * n2\n'''
)

replace_once(
    scene,
    '''        let cockpitRumble: Float = isCockpit ? 0.46 : 1.0\n        let cockpitTurbine: Float = isCockpit ? 0.10 : 0.50\n        let cockpitExhaust: Float = isCockpit ? 0.10 : 1.0\n        let cockpitWind: Float = isCockpit ? 0.17 : 1.0\n\n        rumble.volume = live * cockpitRumble * (0.055 + 0.205 * n1)\n        turbine.volume = live * cockpitTurbine * (0.008 + 0.062 * n2 * n2)\n        exhaust.volume = live * cockpitExhaust * (0.032 + 0.245 * dryPower)\n        afterburner.volume = live * cockpitExhaust * (state.afterburnerActive ? 0.13 + 0.15 * n2 : 0)\n''',
    '''        let cockpitRumble: Float = isCockpit ? 0.52 : 1.0\n        let cockpitTurbine: Float = isCockpit ? 0.025 : 0.14\n        let cockpitExhaust: Float = isCockpit ? 0.12 : 1.0\n        let cockpitWind: Float = isCockpit ? 0.16 : 1.0\n\n        rumble.volume = live * cockpitRumble * (0.070 + 0.235 * n1)\n        turbine.volume = live * cockpitTurbine * (0.004 + 0.030 * n2 * n2)\n        exhaust.volume = live * cockpitExhaust * (0.055 + 0.285 * dryPower)\n        afterburner.volume = live * cockpitExhaust * (state.afterburnerActive ? 0.18 + 0.18 * n2 : 0)\n'''
)

replace_once(
    scene,
    '''        exhaustBands[2].frequency = 1_850\n        exhaustBands[2].gain = -14.5\n''',
    '''        exhaustBands[2].frequency = 1_450\n        exhaustBands[2].gain = -22.0\n'''
)

replace_once(
    scene,
    '''        burnerBands[2].frequency = 2_200\n        burnerBands[2].gain = -15.5\n''',
    '''        burnerBands[2].frequency = 1_650\n        burnerBands[2].gain = -20.0\n'''
)

replace_between(
    scene,
    '    private func makeTurbineBuffer(format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer {\n',
    '\n    private func makeRoarBuffer(format: AVAudioFormat, seconds: Double, afterburner: Bool) -> AVAudioPCMBuffer {\n',
    '''    private func makeTurbineBuffer(format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer {\n        makeStereoBuffer(format: format, seconds: seconds) { t, channel, random in\n            // Compressor is a supporting cue, not the whole engine. Lower partials\n            // and very little noise avoid the electric-motor/bench-grinder read.\n            let phase: Float = channel == 0 ? 0 : 0.09\n            let blade =\n                0.34 * sin(2 * .pi * 178 * t + phase) +\n                0.16 * sin(2 * .pi * 356 * t + 0.28) +\n                0.055 * sin(2 * .pi * 534 * t + 0.82)\n            let shimmer = 0.92 + 0.05 * sin(2 * .pi * 5.2 * t) + 0.02 * sin(2 * .pi * 10.7 * t + phase)\n            return (blade * shimmer + random * 0.0015) * 0.22\n        }\n    }\n'''
)

replace_between(
    scene,
    '    private func makeRoarBuffer(format: AVAudioFormat, seconds: Double, afterburner: Bool) -> AVAudioPCMBuffer {\n',
    '\n    private func makeWindBuffer(format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer {\n',
    '''    private func makeRoarBuffer(format: AVAudioFormat, seconds: Double, afterburner: Bool) -> AVAudioPCMBuffer {\n        let count = AVAudioFrameCount(format.sampleRate * seconds)\n        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!\n        buffer.frameLength = count\n        let rate = Float(format.sampleRate)\n        let channels = Int(format.channelCount)\n\n        var seeds: [UInt32] = [0x91E1_0DA5, 0xC2A7_3B19]\n        var sub: [Float] = [0, 0]\n        var low: [Float] = [0, 0]\n        var body: [Float] = [0, 0]\n        var crackle: [Float] = [0, 0]\n\n        for i in 0..<Int(count) {\n            let t = Float(i) / rate\n            for ch in 0..<channels {\n                seeds[ch] = 1_664_525 &* seeds[ch] &+ 1_013_904_223\n                let raw = Float(Int32(bitPattern: seeds[ch])) / Float(Int32.max)\n\n                // Cascaded low-frequency stochastic bands: this is turbulent\n                // exhaust body, not exposed white noise.\n                sub[ch] = 0.9988 * sub[ch] + 0.0012 * raw\n                low[ch] = 0.9885 * low[ch] + 0.0115 * raw\n                body[ch] = 0.9460 * body[ch] + 0.0540 * raw\n                let lowBand = low[ch] - sub[ch]\n                let bodyBand = body[ch] - low[ch]\n\n                if afterburner && abs(raw) > 0.9982 {\n                    crackle[ch] += raw * 0.32\n                }\n                crackle[ch] *= afterburner ? 0.978 : 0.90\n\n                let phase = Float(ch) * 0.15\n                let combustion =\n                    0.28 * sin(2 * .pi * 43 * t + phase) +\n                    0.17 * sin(2 * .pi * 67 * t + 0.5) +\n                    0.09 * sin(2 * .pi * 91 * t + 1.1)\n                let pressure = afterburner\n                    ? 0.11 * sin(2 * .pi * 121 * t + phase)\n                    : 0.045 * sin(2 * .pi * 116 * t + phase)\n                let breathing = 0.90\n                    + 0.060 * sin(2 * .pi * 1.55 * t + phase)\n                    + 0.028 * sin(2 * .pi * 3.25 * t + 1.0)\n\n                let turbulent: Float\n                if afterburner {\n                    turbulent = 1.55 * sub[ch] + 2.05 * lowBand + 0.42 * bodyBand + 0.055 * crackle[ch]\n                } else {\n                    turbulent = 1.35 * sub[ch] + 1.72 * lowBand + 0.30 * bodyBand\n                }\n\n                let mixed = turbulent * breathing + combustion + pressure\n                let saturated = tanhf(mixed * (afterburner ? 1.65 : 1.42))\n                buffer.floatChannelData![ch][i] = saturated * (afterburner ? 0.56 : 0.50)\n            }\n        }\n        return buffer\n    }\n'''
)

print('Stage 022 DCS/VTOL-inspired audio + pass patch applied')
