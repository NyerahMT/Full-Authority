import AVFoundation
import Combine
import RealityKit
import SwiftUI
import UIKit
import simd

@MainActor
private final class Stage2SceneRuntime: ObservableObject {
    var lastCameraTime: TimeInterval?
    var cameraModeKey = ""
    var cameraInitialized = false
    var lastAirspeed: Float?
    var chasePullbackMeters: Float = 0
    let effects = Stage2FlightEffects.Runtime()
    let jetAudio = Stage0108JetAudio()
}

struct PrototypeSceneView: View {
    @ObservedObject var simulation: FlightSimulation
    @State private var cameraMode: CameraMode = .chase
    @StateObject private var runtime = Stage2SceneRuntime()
    @State private var orbitYawRadians: Float = 0
    @State private var orbitPitchRadians: Float = 0
    @State private var orbitGestureOrigin = SIMD2<Float>.zero
    @State private var orbitGestureActive = false

    private enum CameraMode: String, CaseIterable {
        case chase = "CHASE"
        case close = "CLOSE"
        case cockpit = "COCKPIT"

        var next: CameraMode {
            let all = CameraMode.allCases
            guard let index = all.firstIndex(of: self) else { return .chase }
            return all[(index + 1) % all.count]
        }
    }

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                RealityView { content in
                    content.camera = .virtual
                    content.environment = .default

                    let world = Stage2WorldFactory.make()
                    content.add(world)

                    let aircraft = PrototypeAircraftFactory.make()
                    aircraft.position = simulation.state.positionMeters
                    aircraft.orientation = simulation.state.orientation
                    aircraft.addChild(Stage2FlightEffects.makeAttachedEffects())
                    content.add(aircraft)

                    let trails = Stage2FlightEffects.makeTrailPool()
                    content.add(trails)

                    let camera = Entity()
                    camera.name = "FA.camera"
                    camera.components.set(PerspectiveCameraComponent(
                        near: 0.08,
                        far: 62_000,
                        fieldOfViewInDegrees: 58
                    ))
                    positionCamera(camera, forceSnap: true)
                    content.add(camera)

                    let sun = Entity()
                    sun.name = "FA.sun"
                    sun.components.set([
                        DirectionalLightComponent(
                            color: UIColor(red: 1.0, green: 0.94, blue: 0.84, alpha: 1),
                            intensity: 13_500
                        ),
                        DirectionalLightComponent.Shadow()
                    ])
                    sun.look(at: .zero, from: [-7_000, 10_000, -4_000], relativeTo: nil)
                    content.add(sun)

                    let fill = Entity()
                    fill.name = "FA.fill"
                    fill.components.set(DirectionalLightComponent(
                        color: UIColor(red: 0.58, green: 0.71, blue: 0.91, alpha: 1),
                        intensity: 1_450
                    ))
                    fill.look(at: .zero, from: [6_000, 4_500, 5_500], relativeTo: nil)
                    content.add(fill)
                } update: { content in
                    guard let aircraft = content.entities.first(where: { $0.name == PrototypeAircraftFactory.aircraftName }) else {
                        return
                    }

                    aircraft.position = simulation.state.positionMeters
                    aircraft.orientation = simulation.state.orientation
                    aircraft.isEnabled = cameraMode != .cockpit
                    updateAircraftPresentation(aircraft)
                    runtime.jetAudio.update(state: simulation.state, isPaused: simulation.isPaused)

                    if let trailRoot = content.entities.first(where: { $0.name == Stage2FlightEffects.trailRootName }) {
                        Stage2FlightEffects.updateWorldTrails(
                            root: trailRoot,
                            state: simulation.state,
                            simulationTime: simulation.simulationTime,
                            runtime: runtime.effects
                        )
                    }

                    if let camera = content.entities.first(where: { $0.name == "FA.camera" }) {
                        positionCamera(camera, forceSnap: false)
                    }
                }
                .onChange(of: timeline.date) { oldDate, newDate in
                    simulation.advance(realDelta: newDate.timeIntervalSince(oldDate))
                }
            }
            .background(stage2Sky)

            if !simulation.isPaused && cameraMode != .cockpit {
                orbitGestureSurface
            }

            if !simulation.isPaused {
                cameraSelector
            }

            if cameraMode == .cockpit && !simulation.isPaused {
                CockpitFrameOverlay()
                    .allowsHitTesting(false)
            }

            flightConditionOverlay
        }
    }

    private var stage2Sky: some View {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.030, green: 0.155, blue: 0.39), location: 0.00),
                .init(color: Color(red: 0.10, green: 0.34, blue: 0.62), location: 0.44),
                .init(color: Color(red: 0.49, green: 0.63, blue: 0.73), location: 0.74),
                .init(color: Color(red: 0.71, green: 0.70, blue: 0.62), location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var cameraSelector: some View {
        VStack {
            HStack(spacing: 8) {
                Spacer()

                if cameraHasOrbitOffset && cameraMode != .cockpit {
                    Button {
                        orbitYawRadians = 0
                        orbitPitchRadians = 0
                        orbitGestureActive = false
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "scope")
                                .font(.system(size: 9, weight: .bold))
                            Text("RECENTER")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .tracking(0.45)
                        }
                        .foregroundStyle(.white.opacity(0.90))
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    cameraMode = cameraMode.next
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: cameraMode == .cockpit ? "viewfinder" : "camera.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text(cameraMode.rawValue)
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .tracking(0.45)
                    }
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.09), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .safeAreaPadding(.trailing, 18)
            .padding(.top, 50)
            Spacer()
        }
    }

    private var cameraHasOrbitOffset: Bool {
        abs(orbitYawRadians) > 0.008 || abs(orbitPitchRadians) > 0.008
    }

    private var orbitGestureSurface: some View {
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .frame(width: geometry.size.width * 0.56, height: geometry.size.height * 0.50)
                .position(x: geometry.size.width * 0.50, y: geometry.size.height * 0.48)
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            if !orbitGestureActive {
                                orbitGestureOrigin = SIMD2<Float>(orbitYawRadians, orbitPitchRadians)
                                orbitGestureActive = true
                            }
                            let sensitivity: Float = 0.0045
                            orbitYawRadians = wrappedAngle(
                                orbitGestureOrigin.x - Float(value.translation.width) * sensitivity
                            )
                            orbitPitchRadians = clamp(
                                orbitGestureOrigin.y + Float(value.translation.height) * sensitivity,
                                -0.72,
                                0.62
                            )
                        }
                        .onEnded { _ in orbitGestureActive = false }
                )
        }
        .allowsHitTesting(true)
    }

    private func wrappedAngle(_ value: Float) -> Float {
        var angle = value.truncatingRemainder(dividingBy: 2 * Float.pi)
        if angle > Float.pi { angle -= 2 * Float.pi }
        if angle < -Float.pi { angle += 2 * Float.pi }
        return angle
    }

    @ViewBuilder
    private var flightConditionOverlay: some View {
        switch simulation.flightCondition {
        case .landed(let touchdownFPM):
            VStack {
                Spacer()
                Text(String(format: "TOUCHDOWN  %.0f FPM", touchdownFPM))
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.86))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 9))
                    .padding(.bottom, 155)
            }
            .allowsHitTesting(false)

        case .crashed(let reason):
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()

                VStack(spacing: 8) {
                    Text("AIRCRAFT LOST")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .tracking(0.4)
                    Text(reason)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.62))

                    Button {
                        _ = simulation.resetFlight()
                        simulation.resume()
                        cameraMode = .chase
                        runtime.cameraInitialized = false
                        runtime.cameraModeKey = ""
                        orbitYawRadians = 0
                        orbitPitchRadians = 0
                    } label: {
                        Text("RESET TO RUNWAY")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 18)
                            .frame(height: 42)
                            .background(.white, in: RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 7)
                }
            }

        default:
            EmptyView()
        }
    }

    // MARK: - Camera

    @MainActor
    private func positionCamera(_ camera: Entity, forceSnap: Bool) {
        let state = simulation.state
        let aircraftPosition = state.positionMeters
        let attitude = state.orientation

        let now = ProcessInfo.processInfo.systemUptime
        let dt: Float
        if let last = runtime.lastCameraTime {
            dt = clamp(Float(now - last), 1.0 / 240.0, 1.0 / 20.0)
        } else {
            dt = 1.0 / 60.0
        }
        runtime.lastCameraTime = now

        // The chase rig is intentionally almost rigid. Airframe position and
        // attitude are applied directly every render update so pitch/roll/yaw do
        // not swim behind the JSBSim state. Only the optional longitudinal
        // pullback is filtered, which preserves a tiny acceleration cue without
        // turning the camera into another spring-mass system.
        let airspeed = state.airspeedMetersPerSecond
        if let previousAirspeed = runtime.lastAirspeed {
            let acceleration = max(0, (airspeed - previousAirspeed) / max(dt, 1.0 / 240.0))
            let accelerationPullback = min(acceleration * 0.075, 1.35)
            let highSpeedResidual = clamp((airspeed - 250) / 250, 0, 1) * 0.48
            let targetPullback = accelerationPullback + highSpeedResidual
            let response: Float = targetPullback > runtime.chasePullbackMeters ? 11.0 : 4.8
            let blend = 1 - exp(-response * dt)
            runtime.chasePullbackMeters += (targetPullback - runtime.chasePullbackMeters) * blend
        } else {
            runtime.chasePullbackMeters = 0
        }
        runtime.lastAirspeed = airspeed

        var localCameraOffset: SIMD3<Float>
        let localLookPoint: SIMD3<Float>
        let fieldOfView: Float
        let pullbackScale: Float

        switch cameraMode {
        case .chase:
            localCameraOffset = [0, 4.10, -17.15]
            localLookPoint = [0, 0.72, 4.05]
            fieldOfView = 58
            pullbackScale = 1.0

        case .close:
            localCameraOffset = [0, 3.00, -11.75]
            localLookPoint = [0, 0.62, 4.30]
            fieldOfView = 62
            pullbackScale = 0.55

        case .cockpit:
            // Upstream F-16 eyepoint relative to CG. Cockpit view has no
            // synthetic pullback at all: it is locked to the airframe.
            localCameraOffset = [0, 0.88, 3.64]
            localLookPoint = [0, 0.88, 90]
            fieldOfView = 72
            pullbackScale = 0
        }

        localCameraOffset.z -= runtime.chasePullbackMeters * pullbackScale

        if cameraMode != .cockpit && cameraHasOrbitOffset {
            let yawOrbit = simd_quatf(angle: orbitYawRadians, axis: [0, 1, 0])
            let pitchOrbit = simd_quatf(angle: orbitPitchRadians, axis: [1, 0, 0])
            localCameraOffset = simd_act(yawOrbit * pitchOrbit, localCameraOffset)
        }

        camera.components.set(PerspectiveCameraComponent(
            near: cameraMode == .cockpit ? 0.02 : 0.08,
            far: 62_000,
            fieldOfViewInDegrees: fieldOfView
        ))

        let desiredPosition = aircraftPosition + simd_act(attitude, localCameraOffset)
        let desiredLookTarget = aircraftPosition + simd_act(attitude, localLookPoint)
        let aircraftUp = simd_act(attitude, SIMD3<Float>(0, 1, 0))
        let desiredOrientation = lookRotation(
            forward: desiredLookTarget - desiredPosition,
            up: aircraftUp
        )

        // Rigid means rigid: no exponential position lag and no quaternion
        // spring. JSBSim remains authoritative; the camera simply renders the
        // latest aircraft-relative pose.
        camera.position = desiredPosition
        camera.orientation = desiredOrientation
        runtime.cameraInitialized = true
        runtime.cameraModeKey = cameraMode.rawValue

        _ = forceSnap // retained by the call sites for reset/mode-change semantics
    }

    private func lookRotation(forward: SIMD3<Float>, up: SIMD3<Float>) -> simd_quatf {
        let f = simd_normalize(forward)
        var r = simd_cross(f, up)
        if simd_length_squared(r) < 0.00001 {
            r = SIMD3<Float>(1, 0, 0)
        } else {
            r = simd_normalize(r)
        }
        let correctedUp = simd_normalize(simd_cross(r, f))
        let matrix = simd_float3x3(columns: (r, correctedUp, -f))
        return simd_quatf(matrix)
    }

    // MARK: - Aircraft presentation

    @MainActor
    private func updateAircraftPresentation(_ aircraft: Entity) {
        let state = simulation.state


        // The replacement F-16 is an authored rig. These sign conversions are
        // renderer-boundary conversions between JSBSim's left/right local
        // surface conventions and the source FBX animation convention.
        if let left = aircraft.findEntity(named: PrototypeAircraftFactory.leftAileronName) {
            left.orientation = simd_quatf(
                angle: -state.leftAileronRadians,
                axis: PrototypeAircraftFactory.leftAileronVisualAxis
            )
        }
        if let right = aircraft.findEntity(named: PrototypeAircraftFactory.rightAileronName) {
            right.orientation = simd_quatf(
                angle: -state.rightAileronRadians,
                axis: PrototypeAircraftFactory.rightAileronVisualAxis
            )
        }
        if let left = aircraft.findEntity(named: PrototypeAircraftFactory.leftElevatorName) {
            // JSBSim defines left differential-tail angle with the opposite local
            // sign to the right tail. The authored FBX uses the same +X hinge
            // direction on both stabilators, hence the left-side sign conversion.
            left.orientation = simd_quatf(
                angle: -state.leftStabilatorRadians,
                axis: PrototypeAircraftFactory.leftStabilatorVisualAxis
            )
        }
        if let right = aircraft.findEntity(named: PrototypeAircraftFactory.rightElevatorName) {
            right.orientation = simd_quatf(
                angle: state.rightStabilatorRadians,
                axis: PrototypeAircraftFactory.rightStabilatorVisualAxis
            )
        }
        if let rudder = aircraft.findEntity(named: PrototypeAircraftFactory.rudderName) {
            // vazgriz's authored Rudder channel uses -rudder influence.
            rudder.orientation = simd_quatf(
                angle: -state.rudderRadians,
                axis: PrototypeAircraftFactory.rudderVisualAxis
            )
        }

        let speedbrakeAngle = clamp(state.speedbrakePosition, 0, 1) * PrototypeAircraftFactory.authoredSpeedbrakeLimitRadians
        for name in [PrototypeAircraftFactory.speedbrakeLeftUpperName, PrototypeAircraftFactory.speedbrakeRightUpperName] {
            aircraft.findEntity(named: name)?.orientation = simd_quatf(
                angle: speedbrakeAngle,
                axis: PrototypeAircraftFactory.speedbrakeUpperVisualAxis
            )
        }
        for name in [PrototypeAircraftFactory.speedbrakeLeftLowerName, PrototypeAircraftFactory.speedbrakeRightLowerName] {
            aircraft.findEntity(named: name)?.orientation = simd_quatf(
                angle: speedbrakeAngle,
                axis: PrototypeAircraftFactory.speedbrakeLowerVisualAxis
            )
        }

        updateAfterburner(aircraft, state: state)
        updateGear(aircraft, position: state.gearPosition)
        Stage2FlightEffects.updateAttachedEffects(
            aircraft: aircraft,
            state: state,
            simulationTime: simulation.simulationTime
        )
    }

    @MainActor
    private func updateAfterburner(_ aircraft: Entity, state: AircraftState) {
        let n2 = clamp((state.engineN2Percent - 97.0) / 3.5, 0, 1)
        let fuel = clamp((state.engineFuelFlowPoundsPerSecond - 0.35) / 1.25, 0, 1)
        let intensity = state.afterburnerActive ? clamp(0.50 + 0.38 * n2 + 0.12 * fuel, 0, 1) : 0

        if let plume = aircraft.findEntity(named: PrototypeAircraftFactory.afterburnerName) {
            plume.isEnabled = intensity > 0.01
            if plume.isEnabled {
                let pulse = 1.0 + 0.035 * sin(Float(simulation.simulationTime) * 43.0)
                plume.scale = [
                    0.82 + 0.18 * intensity,
                    0.82 + 0.18 * intensity,
                    (0.64 + 0.52 * intensity) * pulse
                ]
            }
        }
        if let glow = aircraft.findEntity(named: PrototypeAircraftFactory.nozzleGlowName) {
            let hot = clamp((state.engineN2Percent - 72) / 28, 0, 1)
            glow.isEnabled = hot > 0.02
            glow.scale = [0.68 + 0.32 * hot, 0.68 + 0.32 * hot, 0.16 + 0.20 * hot]
        }
    }

    @MainActor
    private func updateGear(_ aircraft: Entity, position: Float) {
        let gear = max(0, min(1, position))
        let retract = 1 - gear

        if let nose = aircraft.findEntity(named: PrototypeAircraftFactory.noseGearName) {
            nose.isEnabled = gear > 0.015
            nose.orientation = simd_quatf(angle: retract * 1.15, axis: [1, 0, 0])
        }
        if let left = aircraft.findEntity(named: PrototypeAircraftFactory.leftGearName) {
            left.isEnabled = gear > 0.015
            left.orientation = simd_quatf(angle: -retract * 1.05, axis: [0, 0, 1])
        }
        if let right = aircraft.findEntity(named: PrototypeAircraftFactory.rightGearName) {
            right.isEnabled = gear > 0.015
            right.orientation = simd_quatf(angle: retract * 1.05, axis: [0, 0, 1])
        }
    }

    private func clamp(_ value: Float, _ minimum: Float, _ maximum: Float) -> Float {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}

private struct CockpitFrameOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CockpitBowShape()
                    .stroke(.black.opacity(0.80), style: StrokeStyle(lineWidth: 13, lineCap: .round))
                CockpitBowShape()
                    .stroke(.white.opacity(0.055), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.black.opacity(0.78))
                        .frame(width: geometry.size.width * 0.58, height: 54)
                        .offset(y: 27)
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct CockpitBowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = CGPoint(x: rect.midX, y: rect.minY - 12)
        path.move(to: top)
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY * 0.82),
            control1: CGPoint(x: rect.midX - rect.width * 0.10, y: rect.height * 0.22),
            control2: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.height * 0.55)
        )
        path.move(to: top)
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.maxY * 0.82),
            control1: CGPoint(x: rect.midX + rect.width * 0.10, y: rect.height * 0.22),
            control2: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.height * 0.55)
        )
        return path
    }
}


@MainActor
private final class Stage0108JetAudio {
    private let engine = AVAudioEngine()
    private let core = AVAudioPlayerNode()
    private let whine = AVAudioPlayerNode()
    private let exhaust = AVAudioPlayerNode()
    private let afterburner = AVAudioPlayerNode()
    private let wind = AVAudioPlayerNode()
    private let coreRate = AVAudioUnitVarispeed()
    private let whineRate = AVAudioUnitVarispeed()
    private var started = false

    init() {
        engine.attach(core)
        engine.attach(whine)
        engine.attach(exhaust)
        engine.attach(afterburner)
        engine.attach(wind)
        engine.attach(coreRate)
        engine.attach(whineRate)
    }

    func update(state: AircraftState, isPaused: Bool) {
        startIfNeeded()
        guard started else { return }

        let n1 = clamp(state.engineN1Percent / 100, 0, 1.15)
        let n2 = clamp(state.engineN2Percent / 100, 0, 1.15)
        let speed = clamp(state.airspeedMetersPerSecond / 340, 0, 1.7)
        let fuel = clamp(state.engineFuelFlowPoundsPerSecond / 1.8, 0, 1.2)
        let live: Float = isPaused ? 0 : 1

        coreRate.rate = 0.68 + 0.58 * n1
        whineRate.rate = 0.64 + 1.18 * n2
        core.volume = live * (0.06 + 0.19 * n1)
        whine.volume = live * (0.018 + 0.105 * n2 * n2)
        exhaust.volume = live * (0.025 + 0.22 * max(n1, fuel))
        afterburner.volume = live * (state.afterburnerActive ? 0.34 + 0.22 * n2 : 0)
        wind.volume = live * 0.18 * min(speed * speed, 1.0)
    }

    private func startIfNeeded() {
        guard !started else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
            engine.connect(core, to: coreRate, format: format)
            engine.connect(coreRate, to: engine.mainMixerNode, format: format)
            engine.connect(whine, to: whineRate, format: format)
            engine.connect(whineRate, to: engine.mainMixerNode, format: format)
            engine.connect(exhaust, to: engine.mainMixerNode, format: format)
            engine.connect(afterburner, to: engine.mainMixerNode, format: format)
            engine.connect(wind, to: engine.mainMixerNode, format: format)

            schedule(core, buffer: makeToneBuffer(format: format, seconds: 2.0, frequencies: [54, 82, 109], gains: [0.58, 0.28, 0.14]))
            schedule(whine, buffer: makeToneBuffer(format: format, seconds: 2.0, frequencies: [215, 430, 645], gains: [0.62, 0.27, 0.11]))
            schedule(exhaust, buffer: makeNoiseBuffer(format: format, seconds: 3.0, smoothing: 0.76, crackle: 0.015))
            schedule(afterburner, buffer: makeNoiseBuffer(format: format, seconds: 3.0, smoothing: 0.46, crackle: 0.095))
            schedule(wind, buffer: makeNoiseBuffer(format: format, seconds: 3.0, smoothing: 0.90, crackle: 0.0))

            try engine.start()
            [core, whine, exhaust, afterburner, wind].forEach { $0.play() }
            started = true
        } catch {
            started = false
        }
    }

    private func schedule(_ node: AVAudioPlayerNode, buffer: AVAudioPCMBuffer) {
        node.scheduleBuffer(buffer, at: nil, options: [.loops])
    }

    private func makeToneBuffer(
        format: AVAudioFormat,
        seconds: Double,
        frequencies: [Float],
        gains: [Float]
    ) -> AVAudioPCMBuffer {
        let count = AVAudioFrameCount(format.sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buffer.frameLength = count
        let data = buffer.floatChannelData![0]
        let rate = Float(format.sampleRate)
        for i in 0..<Int(count) {
            let t = Float(i) / rate
            var sample: Float = 0
            for (f, g) in zip(frequencies, gains) {
                sample += sin(2 * .pi * f * t) * g
            }
            data[i] = sample * 0.42
        }
        return buffer
    }

    private func makeNoiseBuffer(
        format: AVAudioFormat,
        seconds: Double,
        smoothing: Float,
        crackle: Float
    ) -> AVAudioPCMBuffer {
        let count = AVAudioFrameCount(format.sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buffer.frameLength = count
        let data = buffer.floatChannelData![0]
        var seed: UInt32 = 0xA17F_16C3
        var filtered: Float = 0
        for i in 0..<Int(count) {
            seed = 1_664_525 &* seed &+ 1_013_904_223
            let raw = Float(Int32(bitPattern: seed)) / Float(Int32.max)
            filtered = smoothing * filtered + (1 - smoothing) * raw
            let transient: Float = abs(raw) > 0.985 ? raw * crackle * 5.5 : 0
            data[i] = max(-1, min(1, filtered * 0.72 + transient))
        }
        return buffer
    }

    private func clamp(_ value: Float, _ low: Float, _ high: Float) -> Float {
        Swift.min(Swift.max(value, low), high)
    }
}
