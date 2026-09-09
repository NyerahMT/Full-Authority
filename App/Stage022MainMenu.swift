import AVFoundation
import Combine
import Foundation
import RealityKit
import SwiftUI
import UIKit
import simd

@MainActor
private final class Stage022MenuRuntime: ObservableObject {
    private let startDate = Date()
    private let takeoffIntervals: [TimeInterval] = [52, 61, 47, 58]
    private var takeoffIntervalIndex = 0
    private var nextTakeoffAt: TimeInterval = 22
    private var lowPassAudioPlayed = false

    fileprivate private(set) var latestTakeoffStart: TimeInterval?
    fileprivate let audio = Stage022MenuAudio()

    func elapsed(at date: Date) -> TimeInterval {
        max(0, date.timeIntervalSince(startDate))
    }

    func advance(to date: Date) {
        let elapsed = self.elapsed(at: date)

        if elapsed >= nextTakeoffAt {
            latestTakeoffStart = elapsed
            audio.playTakeoff()
            nextTakeoffAt += takeoffIntervals[takeoffIntervalIndex % takeoffIntervals.count]
            takeoffIntervalIndex += 1
        }

        // The flyby crosses the runway-side camera at ~120 seconds. Start the
        // pressure/whoosh transient just before closest approach so the event is
        // heard as something arriving, not as a UI sound effect.
        if !lowPassAudioPlayed && elapsed >= 118.4 {
            lowPassAudioPlayed = true
            audio.playLowPass()
        }
    }
}

struct Stage022MainMenuView: View {
    private enum Panel: String, Identifiable {
        case controls
        case credits

        var id: String { rawValue }
    }

    let onSceneReady: () -> Void
    let onFly: () -> Void

    @StateObject private var runtime = Stage022MenuRuntime()
    @State private var panel: Panel?

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                let elapsed = runtime.elapsed(at: timeline.date)

                RealityView { content in
                    content.camera = .virtual
                    content.environment = .default
                    if let environment = await Stage020SkyEnvironment.load() {
                        content.environment = .skybox(environment)
                    }

                    let world = Stage2WorldFactory.make()
                    world.components.set(EnvironmentLightingConfigurationComponent(
                        environmentLightingWeight: 0.70
                    ))
                    content.add(world)

                    let atmosphere = Stage021Atmosphere.make()
                    Stage021Atmosphere.update(atmosphere, aircraftPosition: [0, 0, 2_000])
                    content.add(atmosphere)

                    let takeoffJet = Stage022MenuScene.makeMenuJet(name: Stage022MenuScene.takeoffJetName)
                    content.add(takeoffJet)

                    let flybyJet = Stage022MenuScene.makeMenuJet(name: Stage022MenuScene.flybyJetName)
                    flybyJet.addChild(Stage2FlightEffects.makeAttachedEffects())
                    content.add(flybyJet)

                    let camera = Entity()
                    camera.name = Stage022MenuScene.cameraName
                    camera.components.set(PerspectiveCameraComponent(
                        near: 0.08,
                        far: 62_000,
                        fieldOfViewInDegrees: 50
                    ))
                    camera.look(
                        at: Stage022MenuScene.cameraTarget,
                        from: Stage022MenuScene.cameraPosition,
                        relativeTo: nil
                    )
                    content.add(camera)

                    let sun = Entity()
                    sun.name = "FA.menu.sun"
                    sun.components.set([
                        DirectionalLightComponent(
                            color: UIColor(red: 1.0, green: 0.965, blue: 0.90, alpha: 1),
                            intensity: 7_800
                        ),
                        DirectionalLightComponent.Shadow()
                    ])
                    sun.look(at: .zero, from: [-9_600, 5_600, -3_200], relativeTo: nil)
                    content.add(sun)

                    let fill = Entity()
                    fill.name = "FA.menu.fill"
                    fill.components.set(DirectionalLightComponent(
                        color: UIColor(red: 0.58, green: 0.66, blue: 0.76, alpha: 1),
                        intensity: 70
                    ))
                    fill.look(at: .zero, from: [6_800, 6_200, 7_600], relativeTo: nil)
                    content.add(fill)

                    onSceneReady()
                } update: { content in
                    Stage022MenuScene.update(
                        content: content,
                        elapsed: elapsed,
                        takeoffStart: runtime.latestTakeoffStart
                    )
                }
                .onChange(of: timeline.date) { _, newDate in
                    runtime.advance(to: newDate)
                }
            }
            .background(menuSky)
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    .black.opacity(0.76),
                    .black.opacity(0.42),
                    .black.opacity(0.10),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            menuChrome

            if let panel {
                panelOverlay(panel)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .preferredColorScheme(.dark)
    }

    private var menuSky: some View {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.018, green: 0.105, blue: 0.260), location: 0.00),
                .init(color: Color(red: 0.060, green: 0.245, blue: 0.470), location: 0.42),
                .init(color: Color(red: 0.285, green: 0.505, blue: 0.665), location: 0.72),
                .init(color: Color(red: 0.640, green: 0.705, blue: 0.730), location: 0.90),
                .init(color: Color(red: 0.750, green: 0.775, blue: 0.770), location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var menuChrome: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 9) {
                        Rectangle()
                            .fill(.white)
                            .frame(width: 34, height: 2)

                        Text("NYERAHWORKS FLIGHT SYSTEMS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    .padding(.bottom, 17)

                    Text("FULL")
                        .font(.system(size: 58, weight: .black, design: .rounded))
                        .tracking(-2.2)
                        .lineLimit(1)

                    Text("AUTHORITY")
                        .font(.system(size: 58, weight: .black, design: .rounded))
                        .tracking(-2.2)
                        .lineLimit(1)
                        .offset(y: -10)

                    HStack(spacing: 9) {
                        Text("F-16A BLOCK 32")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .tracking(1.0)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(.white, in: RoundedRectangle(cornerRadius: 6))

                        Text("LIVE AIRFIELD")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .tracking(1.0)
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    .padding(.bottom, 26)

                    VStack(alignment: .leading, spacing: 9) {
                        menuButton("FLY", systemImage: "airplane", primary: true, action: onFly)
                        menuButton("CONTROLS", systemImage: "slider.horizontal.3", primary: false) {
                            withAnimation(.easeOut(duration: 0.18)) { panel = .controls }
                        }
                        menuButton("CREDITS", systemImage: "text.book.closed", primary: false) {
                            withAnimation(.easeOut(duration: 0.18)) { panel = .credits }
                        }
                    }
                    .frame(width: min(300, geometry.size.width * 0.36), alignment: .leading)

                    Text("JSBSIM DIRECT FDM  •  120 HZ  •  DAY TRAINING RANGE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.45)
                        .foregroundStyle(.white.opacity(0.34))
                        .padding(.top, 18)
                }
                .safeAreaPadding(.leading, 34)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("AIRFIELD / 36")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .tracking(1.2)
                        Text("ATTRACT CAMERA")
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .tracking(1.0)
                            .foregroundStyle(.white.opacity(0.40))
                    }
                    .foregroundStyle(.white.opacity(0.60))
                    .safeAreaPadding(.trailing, 24)
                    .padding(.top, 12)
                }
                Spacer()
            }
        }
    }

    private func menuButton(
        _ title: String,
        systemImage: String,
        primary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .tracking(1.0)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(primary ? 0.75 : 0.36)
            }
            .foregroundStyle(primary ? Color.black : Color.white.opacity(0.90))
            .padding(.horizontal, 15)
            .frame(height: 44)
            .background(
                primary ? AnyShapeStyle(Color.white.opacity(0.96)) : AnyShapeStyle(Color.black.opacity(0.24)),
                in: RoundedRectangle(cornerRadius: 11)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(.white.opacity(primary ? 0.04 : 0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func panelOverlay(_ panel: Panel) -> some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture { dismissPanel() }

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(panel == .controls ? "FLIGHT CONTROLS" : "CREDITS")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .tracking(0.5)
                    Spacer()
                    Button(action: dismissPanel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 32, height: 32)
                            .background(.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                if panel == .controls {
                    VStack(alignment: .leading, spacing: 11) {
                        panelRow("THROTTLE", "Left vertical control")
                        panelRow("RUDDER", "Center horizontal pedal control")
                        panelRow("WHEEL BRAKE", "Hold BRAKE beside rudder")
                        panelRow("STICK", "Right control: pitch + roll")
                        panelRow("CAMERA", "CHASE / CLOSE / COCKPIT selector")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("FULL AUTHORITY")
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                        Text("Created by NyerahWorks")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.76))
                        Text("Flight dynamics: JSBSim. Aircraft geometry and world assets retain their in-repository source/license notices. Stage 022 menu scene reuses the same game renderer rather than a prerecorded background.")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.56))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(22)
            .frame(width: 420)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.12), lineWidth: 1))
        }
    }

    private func panelRow(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(.white.opacity(0.86))
                .frame(width: 100, alignment: .leading)
            Text(detail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
            Spacer()
        }
    }

    private func dismissPanel() {
        withAnimation(.easeOut(duration: 0.16)) { panel = nil }
    }
}

@MainActor
private enum Stage022MenuScene {
    static let cameraName = "FA.menu.camera"
    static let takeoffJetName = "FA.menu.jet.takeoff"
    static let flybyJetName = "FA.menu.jet.flyby"

    static let cameraPosition = SIMD3<Float>(188, 6.6, 1_445)
    static let cameraTarget = SIMD3<Float>(0, 8.0, 1_850)

    static func makeMenuJet(name: String) -> Entity {
        let jet = PrototypeAircraftFactory.make()
        jet.name = name
        jet.components.set(EnvironmentLightingConfigurationComponent(
            environmentLightingWeight: 0.66
        ))
        jet.findEntity(named: PrototypeAircraftFactory.visualRootName)?.isEnabled = true
        jet.findEntity(named: PrototypeAircraftFactory.cockpitRootName)?.isEnabled = false
        jet.findEntity(named: PrototypeAircraftFactory.afterburnerName)?.isEnabled = false
        jet.isEnabled = false
        return jet
    }

    static func update(
        content: RealityViewCameraContent,
        elapsed: TimeInterval,
        takeoffStart: TimeInterval?
    ) {
        if let takeoff = content.entities.first(where: { $0.name == takeoffJetName }) {
            updateTakeoffJet(takeoff, elapsed: elapsed, start: takeoffStart)
        }

        if let flyby = content.entities.first(where: { $0.name == flybyJetName }) {
            updateFlybyJet(flyby, elapsed: elapsed)
        }
    }

    private static func updateTakeoffJet(_ jet: Entity, elapsed: TimeInterval, start: TimeInterval?) {
        guard let start else {
            jet.isEnabled = false
            return
        }

        let t = Float(elapsed - start)
        guard t >= 0, t <= 14.2 else {
            jet.isEnabled = false
            return
        }

        jet.isEnabled = true

        // Longitudinal acceleration is deliberately obvious from the fixed
        // runway-side camera while still using plausible fighter takeoff timing.
        let z = -620 + 34.0 * t * t
        let liftoff: Float = 8.15
        let airborne = max(0, t - liftoff)
        let climb = 1.8 + 2.8 * powf(airborne, 1.72)
        jet.position = [0, climb, z]

        let pitchDegrees = min(12.0, airborne * 3.4)
        jet.orientation = simd_quatf(
            angle: -pitchDegrees * .pi / 180,
            axis: [1, 0, 0]
        )

        setGearVisible(jet, visible: t < 10.4)
        jet.findEntity(named: PrototypeAircraftFactory.afterburnerName)?.isEnabled = t > 4.0
    }

    private static func updateFlybyJet(_ jet: Entity, elapsed: TimeInterval) {
        let eventStart: TimeInterval = 112.0
        let t = Float(elapsed - eventStart)
        guard t >= 0, t <= 16.0 else {
            jet.isEnabled = false
            setTransonicVapor(jet, visible: false)
            return
        }

        jet.isEnabled = true
        setGearVisible(jet, visible: false)
        jet.findEntity(named: PrototypeAircraftFactory.afterburnerName)?.isEnabled = true

        // 340 m/s puts the scripted pass in the transonic neighborhood. The path
        // crosses the camera's runway station almost exactly at two minutes.
        let z = -1_275 + 340 * t
        let y: Float = 34 + 1.2 * sin(t * 0.72)
        jet.position = [22, y, z]
        jet.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])

        let distanceFromCameraStation = abs(z - cameraPosition.z)
        setTransonicVapor(jet, visible: distanceFromCameraStation < 620)
    }

    private static func setGearVisible(_ jet: Entity, visible: Bool) {
        for name in [
            PrototypeAircraftFactory.noseGearName,
            PrototypeAircraftFactory.leftGearName,
            PrototypeAircraftFactory.rightGearName
        ] {
            jet.findEntity(named: name)?.isEnabled = visible
        }
    }

    private static func setTransonicVapor(_ jet: Entity, visible: Bool) {
        let names = [
            "FA.effects.transonic.halo",
            "FA.effects.transonic.shell"
        ]
        for name in names {
            jet.findEntity(named: name)?.isEnabled = visible
        }

        // The low-pass menu event should not accidentally turn on maneuver-vapor
        // streamers that imply high AoA. Only the transonic shell is used here.
        for name in [
            "FA.effects.vapor.lerx.left",
            "FA.effects.vapor.lerx.right",
            "FA.effects.vapor.leading.left",
            "FA.effects.vapor.leading.right",
            "FA.effects.vapor.tip.left",
            "FA.effects.vapor.tip.right"
        ] {
            jet.findEntity(named: name)?.isEnabled = false
        }
    }
}

private final class Stage022MenuAudio {
    private let engine = AVAudioEngine()
    private let ambience = AVAudioPlayerNode()
    private let event = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!

    private lazy var ambienceBuffer = makeAmbienceBuffer()
    private lazy var takeoffBuffer = makeTakeoffBuffer()
    private lazy var lowPassBuffer = makeLowPassBuffer()

    init() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            engine.attach(ambience)
            engine.attach(event)
            engine.connect(ambience, to: engine.mainMixerNode, format: format)
            engine.connect(event, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = 0.62
            try engine.start()

            ambience.scheduleBuffer(ambienceBuffer, at: nil, options: .loops)
            ambience.volume = 0.25
            ambience.play()
        } catch {
            // The menu remains fully functional if the audio session is unavailable.
        }
    }

    deinit {
        engine.stop()
    }

    func playTakeoff() {
        guard engine.isRunning else { return }
        event.stop()
        event.scheduleBuffer(takeoffBuffer, at: nil, options: .interrupts)
        event.volume = 0.74
        event.play()
    }

    func playLowPass() {
        guard engine.isRunning else { return }
        event.stop()
        event.scheduleBuffer(lowPassBuffer, at: nil, options: .interrupts)
        event.volume = 0.92
        event.play()
    }

    private func makeAmbienceBuffer() -> AVAudioPCMBuffer {
        makeBuffer(seconds: 5.0, seed: 0xA17F_0022) { t, _, noise in
            let slow = 0.52 + 0.20 * sin(2 * .pi * 0.13 * t) + 0.10 * sin(2 * .pi * 0.31 * t + 0.9)
            let wind = noise * slow
            let distant = 0.16 * sin(2 * .pi * 47 * t) + 0.08 * sin(2 * .pi * 73 * t + 0.4)
            return 0.035 * wind + 0.018 * distant
        }
    }

    private func makeTakeoffBuffer() -> AVAudioPCMBuffer {
        makeBuffer(seconds: 9.5, seed: 0xF160_0220) { t, _, noise in
            let normalized = min(max(t / 9.5, 0), 1)
            let rise = min(1, normalized * 2.2)
            let depart = max(0, 1 - max(0, normalized - 0.72) / 0.28)
            let envelope = rise * depart
            let rpm = 52 + 42 * normalized
            let rumble =
                0.72 * sin(2 * .pi * rpm * t) +
                0.34 * sin(2 * .pi * rpm * 1.86 * t + 0.8) +
                0.16 * sin(2 * .pi * 31 * t)
            let exhaust = noise * (0.18 + 0.42 * normalized)
            return envelope * (0.16 * rumble + 0.035 * exhaust)
        }
    }

    private func makeLowPassBuffer() -> AVAudioPCMBuffer {
        makeBuffer(seconds: 5.4, seed: 0x0220_BEEF) { t, channel, noise in
            let center: Float = 2.05
            let distance = abs(t - center)
            let approach = exp(-powf(distance / 0.92, 2))
            let pressure = exp(-powf(distance / 0.34, 2))
            let frequency = 78 + 42 * (1 - min(1, t / 5.4))
            let body =
                0.68 * sin(2 * .pi * frequency * t) +
                0.28 * sin(2 * .pi * frequency * 0.51 * t + 0.6)
            let rip = noise * (0.12 + 0.88 * approach)

            let pan = min(max((t - center) / 1.45, -1), 1)
            let channelPan: Float = channel == 0 ? (1 - pan) * 0.5 : (1 + pan) * 0.5
            let gain = sqrt(max(0.08, channelPan))

            return gain * (0.20 * approach * body + 0.060 * rip * approach + 0.11 * pressure)
        }
    }

    private func makeBuffer(
        seconds: Float,
        seed initialSeed: UInt32,
        sample: (Float, Int, Float) -> Float
    ) -> AVAudioPCMBuffer {
        let sampleRate = Float(format.sampleRate)
        let frameCount = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        var seed = initialSeed
        func randomNoise() -> Float {
            seed = 1_664_525 &* seed &+ 1_013_904_223
            let unit = Float(seed & 0x00FF_FFFF) / Float(0x00FF_FFFF)
            return unit * 2 - 1
        }

        guard let channels = buffer.floatChannelData else { return buffer }
        for frame in 0..<Int(frameCount) {
            let t = Float(frame) / sampleRate
            let noise = randomNoise()
            channels[0][frame] = sample(t, 0, noise)
            channels[1][frame] = sample(t, 1, noise)
        }
        return buffer
    }
}
