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

enum FlightCameraMode: String, CaseIterable {
    case chase = "CHASE"
    case close = "CLOSE"
    case cockpit = "COCKPIT"

    var next: FlightCameraMode {
        let all = FlightCameraMode.allCases
        guard let index = all.firstIndex(of: self) else { return .chase }
        return all[(index + 1) % all.count]
    }
}

struct PrototypeSceneView: View {
    @ObservedObject var simulation: FlightSimulation
    @Binding var cameraMode: FlightCameraMode
    @StateObject private var runtime = Stage2SceneRuntime()
    @State private var orbitYawRadians: Float = 0
    @State private var orbitPitchRadians: Float = 0
    @State private var orbitGestureOrigin = SIMD2<Float>.zero
    @State private var orbitGestureActive = false


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

                    // A stronger side-key and restrained sky fill keep the F-16's
                    // real facets readable. The previous opposing lights filled nearly
                    // every shadow and made the authored frame look flatter than it is.
                    let sun = Entity()
                    sun.name = "FA.sun"
                    sun.components.set([
                        DirectionalLightComponent(
                            color: UIColor(red: 1.0, green: 0.95, blue: 0.87, alpha: 1),
                            intensity: 7_800
                        ),
                        DirectionalLightComponent.Shadow()
                    ])
                    sun.look(at: .zero, from: [-8_800, 9_600, -2_300], relativeTo: nil)
                    content.add(sun)

                    let fill = Entity()
                    fill.name = "FA.fill"
                    fill.components.set(DirectionalLightComponent(
                        color: UIColor(red: 0.50, green: 0.66, blue: 0.90, alpha: 1),
                        intensity: 340
                    ))
                    fill.look(at: .zero, from: [6_500, 5_200, 6_200], relativeTo: nil)
                    content.add(fill)
                } update: { content in
                    guard let aircraft = content.entities.first(where: { $0.name == PrototypeAircraftFactory.aircraftName }) else {
                        return
                    }

                    aircraft.position = simulation.state.positionMeters
                    aircraft.orientation = simulation.state.orientation
                    aircraft.isEnabled = cameraMode != .cockpit
                    updateAircraftPresentation(aircraft)
                    runtime.jetAudio.update(state: simulation.state, isPaused: simulation.isPaused, isCockpit: cameraMode == .cockpit)

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
                .init(color: Color(red: 0.022, green: 0.125, blue: 0.34), location: 0.00),
                .init(color: Color(red: 0.075, green: 0.285, blue: 0.56), location: 0.44),
                .init(color: Color(red: 0.42, green: 0.57, blue: 0.69), location: 0.74),
                .init(color: Color(red: 0.68, green: 0.68, blue: 0.62), location: 1.00)
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
        let n2 = clamp((state.engineN2Percent - 96.0) / 4.0, 0, 1)
        let fuel = clamp((state.engineFuelFlowPoundsPerSecond - 0.30) / 1.30, 0, 1)
        let intensity = state.afterburnerActive ? clamp(0.48 + 0.40 * n2 + 0.12 * fuel, 0, 1) : 0
        let time = Float(simulation.simulationTime)

        // Lower ambient pressure lets the jet expand more. This is only a visual
        // presentation term; JSBSim remains authoritative for actual thrust.
        let pressureExpansion = clamp(sqrtf(2_116.22 / max(state.ambientPressurePSF, 450)), 0.90, 1.62)
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
                halo.position = [0, 0, 0.5 * halo.scale.y]
            }
            if let outer = aircraft.findEntity(named: PrototypeAircraftFactory.afterburnerOuterName) {
                outer.scale = [0.94 * width, 1.90 * length, 1.02 * width]
                outer.position = [0, 0, 0.5 * outer.scale.y]
            }
            if let inner = aircraft.findEntity(named: PrototypeAircraftFactory.afterburnerInnerName) {
                let pulse = 1.0 + 0.016 * sin(time * 61.0 + 0.9)
                inner.scale = [0.58 * width * pulse, 1.52 * length, 0.66 * width * pulse]
                inner.position = [0, 0, 0.5 * inner.scale.y]
            }
            if let core = aircraft.findEntity(named: PrototypeAircraftFactory.afterburnerCoreName) {
                let pulse = 1.0 + 0.026 * sin(time * 73.0 + 0.35)
                core.scale = [0.24 * width * pulse, 1.12 * length, 0.30 * width * pulse]
                core.position = [0, 0, 0.5 * core.scale.y]
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
            let thump = sin(2 * .pi * 57 * t + phase) * expf(-7.0 * t)
            let barkEnvelope = min(t * 18.0, 1.0) * expf(-2.0 * t)
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
