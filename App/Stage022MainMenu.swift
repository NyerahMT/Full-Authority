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
    // A first departure happens soon enough to make the menu feel alive.
    // The longer second gap intentionally leaves the two-minute transonic event clear.
    private let takeoffIntervals: [TimeInterval] = [50, 75, 54, 62]
    private var takeoffIntervalIndex = 0
    private var nextTakeoffAt: TimeInterval = 12
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
        if !lowPassAudioPlayed && elapsed >= 117.55 {
            lowPassAudioPlayed = true
            audio.playSupersonicPass()
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
    @State private var lookYawRadians: Float = 0
    @State private var lookPitchRadians: Float = 0
    @State private var lookGestureOrigin = SIMD2<Float>.zero
    @State private var lookGestureActive = false

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
                        takeoffStart: runtime.latestTakeoffStart,
                        cameraLookYaw: lookYawRadians,
                        cameraLookPitch: lookPitchRadians
                    )
                }
                .onChange(of: timeline.date) { _, newDate in
                    runtime.advance(to: newDate)
                }
            }
            .background(menuSky)
            .ignoresSafeArea()

            if panel == nil {
                menuLookSurface
            }

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

    private var menuLookSurface: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Spacer(minLength: 0)

                Rectangle()
                    // Nearly transparent instead of Color.clear so the view remains
                    // hit-testable without visibly tinting the menu scene.
                    .fill(Color.black.opacity(0.001))
                    .frame(width: geometry.size.width * 0.54)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if !lookGestureActive {
                                    lookGestureActive = true
                                    lookGestureOrigin = [lookYawRadians, lookPitchRadians]
                                }

                                let sensitivity: Float = 0.0042
                                let yaw = lookGestureOrigin.x - Float(value.translation.width) * sensitivity
                                let pitch = lookGestureOrigin.y + Float(value.translation.height) * sensitivity
                                lookYawRadians = min(max(yaw, -2.35), 2.35)
                                lookPitchRadians = min(max(pitch, -0.68), 0.58)
                            }
                            .onEnded { _ in
                                lookGestureActive = false
                            }
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .zIndex(1)
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
                        Text("DRAG RIGHT SIDE TO LOOK")
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

    // Start beside the runway looking toward the departure end so the
    // takeoff roll is visible before the jet reaches the camera station.
    // Move the spectator closer to the departure start so the idle/spool
    // phase and first few hundred metres of the ground roll are visually legible.
    static let cameraPosition = SIMD3<Float>(145, 5.8, -190)
    static let cameraTarget = SIMD3<Float>(0, 4.3, -420)

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
        takeoffStart: TimeInterval?,
        cameraLookYaw: Float,
        cameraLookPitch: Float
    ) {
        if let camera = content.entities.first(where: { $0.name == cameraName }) {
            updateCamera(camera, yawOffset: cameraLookYaw, pitchOffset: cameraLookPitch)
        }

        if let takeoff = content.entities.first(where: { $0.name == takeoffJetName }) {
            updateTakeoffJet(takeoff, elapsed: elapsed, start: takeoffStart)
        }

        if let flyby = content.entities.first(where: { $0.name == flybyJetName }) {
            updateFlybyJet(flyby, elapsed: elapsed)
        }
    }

    private static func updateCamera(_ camera: Entity, yawOffset: Float, pitchOffset: Float) {
        let base = simd_normalize(cameraTarget - cameraPosition)
        let baseYaw = atan2(base.x, base.z)
        let basePitch = asin(min(max(base.y, -1), 1))
        let yaw = baseYaw + yawOffset
        let pitch = min(max(basePitch + pitchOffset, -1.15), 0.82)
        let cp = cos(pitch)
        let direction = SIMD3<Float>(sin(yaw) * cp, sin(pitch), cos(yaw) * cp)
        camera.look(at: cameraPosition + direction * 1_000, from: cameraPosition, relativeTo: nil)
    }

    private static func updateTakeoffJet(_ jet: Entity, elapsed: TimeInterval, start: TimeInterval?) {
        guard let start else {
            jet.isEnabled = false
            return
        }

        let t = Float(elapsed - start)
        guard t >= 0, t <= 23.0 else {
            jet.isEnabled = false
            return
        }

        jet.isEnabled = true

        // The menu departure is intentionally phase-based instead of using the
        // old z = a*t^2 shortcut, which made the jet effectively supersonic while
        // still on the runway and sent it behind the default camera.
        let startZ: Float = -420
        let spoolEnd: Float = 2.5
        let liftoff: Float = 14.0
        let groundRollDuration = liftoff - spoolEnd
        let groundAcceleration: Float = 7.5
        let groundTime = min(max(t - spoolEnd, 0), groundRollDuration)
        let groundDistance = 0.5 * groundAcceleration * groundTime * groundTime
        let rotationZ = startZ + 0.5 * groundAcceleration * groundRollDuration * groundRollDuration
        let rotationSpeed = groundAcceleration * groundRollDuration

        let airborne = max(0, t - liftoff)
        let z = t <= liftoff
            ? startZ + groundDistance
            : rotationZ + rotationSpeed * airborne + 3.8 * airborne * airborne
        let climb = t <= liftoff ? 1.8 : 1.8 + 3.2 * powf(airborne, 1.50)
        jet.position = [0, climb, z]

        let pitchDegrees = t < liftoff
            ? max(0, (t - (liftoff - 1.0)) * 5.0)
            : min(13.0, 5.0 + airborne * 2.0)
        jet.orientation = simd_quatf(
            angle: -pitchDegrees * .pi / 180,
            axis: [1, 0, 0]
        )

        setGearVisible(jet, visible: t < 16.4)
        jet.findEntity(named: PrototypeAircraftFactory.afterburnerName)?.isEnabled = t > 3.2
    }

    private static func updateFlybyJet(_ jet: Entity, elapsed: TimeInterval) {
        // With the runway-side camera moved downfield, this start time keeps
        // closest approach centered at essentially the two-minute mark.
        let eventStart: TimeInterval = 117.03
        let t = Float(elapsed - eventStart)
        guard t >= 0, t <= 16.0 else {
            jet.isEnabled = false
            Stage2FlightEffects.setAttractModeTransonicVapor(root: jet, visible: false, intensity: 0)
            return
        }

        jet.isEnabled = true
        setGearVisible(jet, visible: false)
        jet.findEntity(named: PrototypeAircraftFactory.afterburnerName)?.isEnabled = true

        // 365 m/s is a deliberately low-supersonic pass at this altitude: fast
        // enough to support a real shock/boom event without turning this into an
        // arcade high-Mach flyby. It crosses the camera at essentially 2:00.
        let z = -1_275 + 365 * t
        let y: Float = 34 + 1.2 * sin(t * 0.72)
        jet.position = [22, y, z]
        jet.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])

        let distanceFromCameraStation = abs(z - cameraPosition.z)
        let coneVisible = distanceFromCameraStation < 900
        let coneIntensity = coneVisible
            ? min(max(1.0 - distanceFromCameraStation / 900.0, 0), 1)
            : 0
        Stage2FlightEffects.setAttractModeTransonicVapor(
            root: jet,
            visible: coneVisible,
            intensity: 0.58 + 0.42 * coneIntensity
        )
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

}

private final class Stage022MenuAudio {
    private let engine = AVAudioEngine()
    private let ambience = AVAudioPlayerNode()
    private let takeoff = AVAudioPlayerNode()
    private let burner = AVAudioPlayerNode()
    private let flyby = AVAudioPlayerNode()
    private let sonicBoom = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!

    private lazy var ambienceBuffer = makeAmbienceBuffer()
    private lazy var takeoffBuffer = makeTakeoffBuffer()
    private lazy var burnerBuffer = makeTakeoffAfterburnerBuffer()
    private lazy var flybyBuffer = makeFlybyBuffer()
    private lazy var sonicBoomBuffer = makeSonicBoomBuffer()

    init() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            for node in [ambience, takeoff, burner, flyby, sonicBoom] {
                engine.attach(node)
                engine.connect(node, to: engine.mainMixerNode, format: format)
            }
            engine.mainMixerNode.outputVolume = 0.68
            try engine.start()

            ambience.scheduleBuffer(ambienceBuffer, at: nil, options: .loops)
            ambience.volume = 0.22
            ambience.play()
        } catch {
            // Menu remains usable if audio is unavailable.
        }
    }

    deinit {
        engine.stop()
    }

    func playTakeoff() {
        guard engine.isRunning else { return }

        takeoff.stop()
        burner.stop()

        takeoff.scheduleBuffer(takeoffBuffer, at: nil, options: .interrupts)
        burner.scheduleBuffer(burnerBuffer, at: nil, options: .interrupts)
        takeoff.volume = 0.72
        burner.volume = 0.88
        takeoff.play()
        burner.play()
    }

    func playSupersonicPass() {
        guard engine.isRunning else { return }

        flyby.stop()
        sonicBoom.stop()

        flyby.scheduleBuffer(flybyBuffer, at: nil, options: .interrupts)
        sonicBoom.scheduleBuffer(sonicBoomBuffer, at: nil, options: .interrupts)
        flyby.volume = 0.82
        sonicBoom.volume = 1.0
        flyby.play()
        sonicBoom.play()
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
        // Dry engine / ground-roll bed. Deliberately very little broadband noise:
        // the afterburner has its own source below, like DCS/Unity-style layering.
        makeBuffer(seconds: 19.0, seed: 0xF160_0220) { t, _, noise in
            let spool = min(max(t / 2.8, 0), 1)
            let roll = min(max((t - 2.5) / 11.5, 0), 1)
            let departureFade = max(0, 1 - max(0, t - 15.5) / 3.5)
            let envelope = (0.20 + 0.80 * spool) * departureFade
            let fundamental = 42 + 22 * spool + 17 * roll
            let combustion =
                0.78 * sin(2 * .pi * fundamental * t) +
                0.31 * sin(2 * .pi * fundamental * 1.47 * t + 0.6) +
                0.18 * sin(2 * .pi * 31 * t + 1.1)
            let roughness = 0.012 * noise * (0.25 + 0.75 * roll)
            return envelope * (0.18 * combustion + roughness)
        }
    }

    private func makeTakeoffAfterburnerBuffer() -> AVAudioPCMBuffer {
        let seconds: Float = 19.0
        let sampleRate = Float(format.sampleRate)
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        guard let channels = buffer.floatChannelData else { return buffer }

        var seeds: [UInt32] = [0xF16A_B001, 0xF16A_B002]
        var slow: [Float] = [0, 0]
        var low: [Float] = [0, 0]
        var body: [Float] = [0, 0]

        for frame in 0..<Int(frames) {
            let t = Float(frame) / sampleRate
            let abOn = min(max((t - 3.15) / 0.70, 0), 1)
            let fade = max(0, 1 - max(0, t - 16.0) / 3.0)
            let envelope = abOn * fade

            for ch in 0..<2 {
                seeds[ch] = 1_664_525 &* seeds[ch] &+ 1_013_904_223
                let raw = Float(Int32(bitPattern: seeds[ch])) / Float(Int32.max)
                slow[ch] = 0.9982 * slow[ch] + 0.0018 * raw
                low[ch] = 0.9850 * low[ch] + 0.0150 * raw
                body[ch] = 0.9350 * body[ch] + 0.0650 * raw

                let lowBand = low[ch] - slow[ch]
                let bodyBand = body[ch] - low[ch]
                let phase = Float(ch) * 0.17
                let pressure =
                    0.40 * sin(2 * .pi * 53 * t + phase) +
                    0.24 * sin(2 * .pi * 79 * t + 0.5) +
                    0.11 * sin(2 * .pi * 106 * t + 1.2)
                let modulation = 0.90 + 0.07 * sin(2 * .pi * 2.1 * t + phase)
                let roar = (1.45 * slow[ch] + 1.95 * lowBand + 0.34 * bodyBand) * modulation
                let sample = envelope * (0.28 * pressure + 0.88 * roar)
                channels[ch][frame] = min(max(sample, -0.92), 0.92)
            }
        }
        return buffer
    }

    private func makeFlybyBuffer() -> AVAudioPCMBuffer {
        let seconds: Float = 5.8
        let sampleRate = Float(format.sampleRate)
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        guard let channels = buffer.floatChannelData else { return buffer }

        var seeds: [UInt32] = [0xFA26_0001, 0xFA26_0002]
        var low: [Float] = [0, 0]
        var body: [Float] = [0, 0]

        for frame in 0..<Int(frames) {
            let t = Float(frame) / sampleRate
            let closest: Float = 2.65
            let distance = abs(t - closest)
            let approach = exp(-powf(distance / 1.05, 2))
            let doppler = 118 - 46 * min(max(t / seconds, 0), 1)
            let pan = min(max((t - closest) / 1.55, -1), 1)

            for ch in 0..<2 {
                seeds[ch] = 1_664_525 &* seeds[ch] &+ 1_013_904_223
                let raw = Float(Int32(bitPattern: seeds[ch])) / Float(Int32.max)
                low[ch] = 0.988 * low[ch] + 0.012 * raw
                body[ch] = 0.925 * body[ch] + 0.075 * raw
                let turbulent = 1.3 * low[ch] + 0.35 * (body[ch] - low[ch])
                let engineBody =
                    0.62 * sin(2 * .pi * doppler * t) +
                    0.27 * sin(2 * .pi * doppler * 0.52 * t + 0.5)
                let channelPan: Float = ch == 0 ? (1 - pan) * 0.5 : (1 + pan) * 0.5
                let gain = sqrt(max(0.08, channelPan))
                channels[ch][frame] = gain * approach * (0.15 * engineBody + 0.13 * turbulent)
            }
        }
        return buffer
    }

    private func makeSonicBoomBuffer() -> AVAudioPCMBuffer {
        // Delayed double shock: two short bipolar pressure impulses plus a low
        // structural tail. This is intentionally a discrete event, not more hiss.
        makeBuffer(seconds: 5.8, seed: 0xB00D_0220) { t, channel, _ in
            let first: Float = 2.42
            let second: Float = 2.57

            func nWave(_ center: Float, amplitude: Float) -> Float {
                let x = (t - center) / 0.016
                return amplitude * x * exp(-x * x * 1.35)
            }

            let shock = nWave(first, amplitude: 1.0) + nWave(second, amplitude: 0.82)
            let dt = max(0, t - first)
            let thump = dt > 0
                ? (0.55 * sin(2 * .pi * 43 * dt) + 0.24 * sin(2 * .pi * 71 * dt + 0.4)) * exp(-4.6 * dt)
                : 0
            let stereo: Float = channel == 0 ? 0.98 : 1.0
            let pressureMix: Float = 0.93 * shock + 0.42 * thump
            let output: Float = stereo * pressureMix
            return Swift.min(Swift.max(output, -0.98), 0.98)
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
