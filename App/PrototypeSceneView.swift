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
                    if let environment = await Stage020SkyEnvironment.load() {
                        content.environment = .skybox(environment)
                    }

                    let world = Stage2WorldFactory.make()
                    // Stage 016 cinematic lighting: reduce the flat default IBL so
                    // directional sunlight and material roughness can actually shape terrain.
                    world.components.set(EnvironmentLightingConfigurationComponent(
                        environmentLightingWeight: 0.70
                    ))
                    content.add(world)

                    let atmosphere = Stage021Atmosphere.make()
                    content.add(atmosphere)

                    let aircraft = PrototypeAircraftFactory.make()
                    aircraft.components.set(EnvironmentLightingConfigurationComponent(
                        environmentLightingWeight: 0.66
                    ))
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
                            color: UIColor(red: 1.0, green: 0.965, blue: 0.90, alpha: 1),
                            intensity: 7_800
                        ),
                        DirectionalLightComponent.Shadow()
                    ])
                    sun.look(at: .zero, from: [-9_600, 5_600, -3_200], relativeTo: nil)
                    content.add(sun)

                    let fill = Entity()
                    fill.name = "FA.fill"
                    fill.components.set(DirectionalLightComponent(
                        color: UIColor(red: 0.58, green: 0.66, blue: 0.76, alpha: 1),
                        intensity: 70
                    ))
                    fill.look(at: .zero, from: [6_800, 6_200, 7_600], relativeTo: nil)
                    content.add(fill)
                } update: { content in
                    guard let aircraft = content.entities.first(where: { $0.name == PrototypeAircraftFactory.aircraftName }) else {
                        return
                    }

                    aircraft.position = simulation.state.positionMeters
                    aircraft.orientation = simulation.state.orientation
                    aircraft.isEnabled = true
                    updateAircraftPresentation(aircraft)

                    if let atmosphere = content.entities.first(where: { $0.name == Stage021Atmosphere.rootName }) {
                        Stage021Atmosphere.update(atmosphere, aircraftPosition: simulation.state.positionMeters)
                    }

                    let cockpitMode = cameraMode == .cockpit
                    aircraft.findEntity(named: PrototypeAircraftFactory.visualRootName)?.isEnabled = !cockpitMode
                    aircraft.findEntity(named: PrototypeAircraftFactory.cockpitRootName)?.isEnabled = cockpitMode
                    aircraft.findEntity(named: Stage2FlightEffects.attachedRootName)?.isEnabled = !cockpitMode
                    if cockpitMode {
                        for name in [
                            PrototypeAircraftFactory.noseGearName,
                            PrototypeAircraftFactory.leftGearName,
                            PrototypeAircraftFactory.rightGearName
                        ] {
                            aircraft.findEntity(named: name)?.isEnabled = false
                        }
                    }
                    runtime.jetAudio.update(
                        state: simulation.state,
                        isPaused: simulation.isPaused,
                        isCockpit: cameraMode == .cockpit
                    )

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

            // The same free-look surface is now available in cockpit. External
            // cameras orbit the airplane; cockpit mode rotates the pilot's head
            // while keeping the eyepoint fixed in the seat.
            if !simulation.isPaused {
                orbitGestureSurface
            }

            if !simulation.isPaused {
                cameraSelector
            }

            flightConditionOverlay
        }
    }

    private var stage2Sky: some View {
        // Stage 016 cinematic sky. The zenith-to-horizon progression follows the
        // aerial-perspective structure described by Bruneton & Neyret, while the
        // warmer low horizon is intentionally pushed for a readable game palette.
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
    }

    private var cameraSelector: some View {
        VStack {
            HStack(spacing: 8) {
                Spacer()

                if cameraHasOrbitOffset {
                    Button {
                        recenterView()
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
                    recenterView()
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

                            let sensitivity: Float = cameraMode == .cockpit ? 0.0040 : 0.0045
                            let candidateYaw = orbitGestureOrigin.x
                                - Float(value.translation.width) * sensitivity
                            let candidatePitch = orbitGestureOrigin.y
                                + Float(value.translation.height) * sensitivity

                            if cameraMode == .cockpit {
                                // Rough human head/helmet limits. This is deliberately
                                // wide enough to check six while preventing the view
                                // from rolling through impossible camera orientations.
                                orbitYawRadians = clamp(candidateYaw, -2.62, 2.62)
                                orbitPitchRadians = clamp(candidatePitch, -1.02, 0.82)
                            } else {
                                orbitYawRadians = wrappedAngle(candidateYaw)
                                orbitPitchRadians = clamp(candidatePitch, -0.72, 0.62)
                            }
                        }
                        .onEnded { _ in orbitGestureActive = false }
                )
        }
        .allowsHitTesting(true)
    }

    private func recenterView() {
        orbitYawRadians = 0
        orbitPitchRadians = 0
        orbitGestureActive = false
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
                        recenterView()
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
            // Pilot eyepoint sits near the top of the seat/headrest, not up against
            // the instrument panel. Free-look rotates the head around this fixed
            // seated position so the cockpit has believable depth and parallax.
            localCameraOffset = [0, 1.08, 3.05]
            localLookPoint = [0, 1.08, 90]
            fieldOfView = 66
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
        let desiredLookTarget: SIMD3<Float>
        let cameraUp: SIMD3<Float>

        if cameraMode == .cockpit && cameraHasOrbitOffset {
            let yaw = simd_quatf(angle: orbitYawRadians, axis: [0, 1, 0])
            let pitch = simd_quatf(angle: orbitPitchRadians, axis: [1, 0, 0])
            let headRotation = yaw * pitch
            let headForwardLocal = simd_act(headRotation, SIMD3<Float>(0, 0, 1))
            let headUpLocal = simd_act(headRotation, SIMD3<Float>(0, 1, 0))

            desiredLookTarget = desiredPosition
                + simd_act(attitude, headForwardLocal) * 90
            cameraUp = simd_act(attitude, headUpLocal)
        } else {
            desiredLookTarget = aircraftPosition + simd_act(attitude, localLookPoint)
            cameraUp = simd_act(attitude, SIMD3<Float>(0, 1, 0))
        }

        let desiredOrientation = lookRotation(
            forward: desiredLookTarget - desiredPosition,
            up: cameraUp
        )

        camera.position = desiredPosition
        camera.orientation = desiredOrientation
        runtime.cameraInitialized = true
        runtime.cameraModeKey = cameraMode.rawValue

        _ = forceSnap
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
            rudder.orientation = simd_quatf(
                angle: -state.rudderRadians,
                axis: PrototypeAircraftFactory.rudderVisualAxis
            )
        }
        let pedalCommand = clamp(simulation.controls.rudder, -1, 1)
        aircraft.findEntity(named: Stage020CockpitDetails.leftPedalName)?.orientation = simd_quatf(
            angle: pedalCommand * 0.16, axis: [1, 0, 0]
        )
        aircraft.findEntity(named: Stage020CockpitDetails.rightPedalName)?.orientation = simd_quatf(
            angle: -pedalCommand * 0.16, axis: [1, 0, 0]
        )
        if let beacon = aircraft.findEntity(named: Stage020AircraftDetails.antiCollisionName) {
            beacon.isEnabled = simulation.simulationTime.truncatingRemainder(dividingBy: 1.20) < 0.11
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
                halo.scale = [1.04 * width, 1.82 * length, 1.04 * width]
                halo.position = [0, 0, 0.5 * halo.scale.y]
            }
            if let outer = aircraft.findEntity(named: PrototypeAircraftFactory.afterburnerOuterName) {
                outer.scale = [0.84 * width, 1.64 * length, 0.90 * width]
                outer.position = [0, 0, 0.5 * outer.scale.y]
            }
            if let inner = aircraft.findEntity(named: PrototypeAircraftFactory.afterburnerInnerName) {
                let pulse = 1.0 + 0.016 * sin(time * 61.0 + 0.9)
                inner.scale = [0.50 * width * pulse, 1.34 * length, 0.56 * width * pulse]
                inner.position = [0, 0, 0.5 * inner.scale.y]
            }
            if let core = aircraft.findEntity(named: PrototypeAircraftFactory.afterburnerCoreName) {
                let pulse = 1.0 + 0.026 * sin(time * 73.0 + 0.35)
                core.scale = [0.19 * width * pulse, 0.96 * length, 0.23 * width * pulse]
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
                // Keep the canopy framing at the extreme edges. The previous
                // center-mounted V occupied most of the forward view and looked
                // like two giant bars instead of an F-16 bubble canopy.
                CockpitCanopyEdgeShape()
                    .stroke(
                        .black.opacity(0.66),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)
                    )
                CockpitCanopyEdgeShape()
                    .stroke(
                        .white.opacity(0.045),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )

                VStack(spacing: 0) {
                    Spacer()

                    // A restrained glareshield gives the eye a cockpit reference
                    // without pretending we have a full 3D interior yet.
                    RoundedRectangle(cornerRadius: 30)
                        .fill(.black.opacity(0.72))
                        .frame(width: geometry.size.width * 0.70, height: 76)
                        .overlay(alignment: .top) {
                            Capsule()
                                .fill(.white.opacity(0.055))
                                .frame(width: geometry.size.width * 0.48, height: 2)
                                .padding(.top, 9)
                        }
                        .offset(y: 42)
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct CockpitCanopyEdgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let leftBottom = CGPoint(x: rect.minX + rect.width * 0.025, y: rect.maxY * 0.91)
        let leftUpper = CGPoint(x: rect.minX + rect.width * 0.095, y: rect.minY + rect.height * 0.12)
        let leftTop = CGPoint(x: rect.minX + rect.width * 0.24, y: rect.minY + rect.height * 0.015)

        path.move(to: leftBottom)
        path.addCurve(
            to: leftUpper,
            control1: CGPoint(x: rect.minX + rect.width * 0.020, y: rect.height * 0.62),
            control2: CGPoint(x: rect.minX + rect.width * 0.045, y: rect.height * 0.24)
        )
        path.addCurve(
            to: leftTop,
            control1: CGPoint(x: rect.minX + rect.width * 0.13, y: rect.height * 0.055),
            control2: CGPoint(x: rect.minX + rect.width * 0.19, y: rect.height * 0.020)
        )

        let rightBottom = CGPoint(x: rect.maxX - rect.width * 0.025, y: rect.maxY * 0.91)
        let rightUpper = CGPoint(x: rect.maxX - rect.width * 0.095, y: rect.minY + rect.height * 0.12)
        let rightTop = CGPoint(x: rect.maxX - rect.width * 0.24, y: rect.minY + rect.height * 0.015)

        path.move(to: rightBottom)
        path.addCurve(
            to: rightUpper,
            control1: CGPoint(x: rect.maxX - rect.width * 0.020, y: rect.height * 0.62),
            control2: CGPoint(x: rect.maxX - rect.width * 0.045, y: rect.height * 0.24)
        )
        path.addCurve(
            to: rightTop,
            control1: CGPoint(x: rect.maxX - rect.width * 0.13, y: rect.height * 0.055),
            control2: CGPoint(x: rect.maxX - rect.width * 0.19, y: rect.height * 0.020)
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
        let aoaBuffet = clamp((abs(state.angleOfAttackDegrees) - 7.5) / 11.0, 0, 1)
        let betaBuffet = clamp((abs(state.sideslipDegrees) - 2.0) / 8.0, 0, 1)
        let buffet = max(aoaBuffet, betaBuffet)

        rumbleRate.rate = 0.72 + 0.30 * n1
        turbineRate.rate = 0.76 + 0.36 * n2

        // Stage 021 is referenced against public-domain F-16 burner/test-cell
        // recordings: outside is exhaust-body dominant; cockpit is strongly
        // attenuated and never becomes a constant compressor whistle.
        let cockpitRumble: Float = isCockpit ? 0.52 : 1.0
        let cockpitTurbine: Float = isCockpit ? 0.025 : 0.14
        let cockpitExhaust: Float = isCockpit ? 0.12 : 1.0
        let cockpitWind: Float = isCockpit ? 0.16 : 1.0

        rumble.volume = live * cockpitRumble * (0.070 + 0.235 * n1)
        turbine.volume = live * cockpitTurbine * (0.004 + 0.030 * n2 * n2)
        exhaust.volume = live * cockpitExhaust * (0.055 + 0.285 * dryPower)
        afterburner.volume = live * cockpitExhaust * (state.afterburnerActive ? 0.18 + 0.18 * n2 : 0)
        let baseWind = 0.003 + 0.024 * min(powf(mach, 1.55), 1.40)
        wind.volume = live * cockpitWind * baseWind * (1.0 + 1.65 * buffet)

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
        exhaustBands[0].frequency = 120
        exhaustBands[0].gain = 6.5
        exhaustBands[0].bypass = false
        exhaustBands[1].filterType = .parametric
        exhaustBands[1].frequency = 340
        exhaustBands[1].bandwidth = 1.15
        exhaustBands[1].gain = 1.5
        exhaustBands[1].bypass = false
        exhaustBands[2].filterType = .highShelf
        exhaustBands[2].frequency = 1_450
        exhaustBands[2].gain = -22.0
        exhaustBands[2].bypass = false

        let burnerBands = burnerEQ.bands
        burnerBands[0].filterType = .lowShelf
        burnerBands[0].frequency = 105
        burnerBands[0].gain = 7.5
        burnerBands[0].bypass = false
        burnerBands[1].filterType = .parametric
        burnerBands[1].frequency = 260
        burnerBands[1].bandwidth = 1.0
        burnerBands[1].gain = 2.5
        burnerBands[1].bypass = false
        burnerBands[2].filterType = .highShelf
        burnerBands[2].frequency = 1_650
        burnerBands[2].gain = -20.0
        burnerBands[2].bypass = false

        let windBands = windEQ.bands
        windBands[0].filterType = .highPass
        windBands[0].frequency = 620
        windBands[0].bandwidth = 0.8
        windBands[0].bypass = false
        windBands[1].filterType = .highShelf
        windBands[1].frequency = 2_800
        windBands[1].gain = -4.0
        windBands[1].bypass = false
    }

    private func schedule(_ node: AVAudioPlayerNode, buffer: AVAudioPCMBuffer) {
        node.scheduleBuffer(buffer, at: nil, options: [.loops])
    }

    private func fireIgnitionTransient(isCockpit: Bool) {
        guard let ignitionBuffer else { return }
        ignition.stop()
        ignition.volume = isCockpit ? 0.11 : 0.38
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
            return (tones * amplitude + random * 0.018) * 0.55
        }
    }

    private func makeTurbineBuffer(format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer {
        makeStereoBuffer(format: format, seconds: seconds) { t, channel, random in
            // Compressor is a supporting cue, not the whole engine. Lower partials
            // and very little noise avoid the electric-motor/bench-grinder read.
            let phase: Float = channel == 0 ? 0 : 0.09
            let blade =
                0.34 * sin(2 * .pi * 178 * t + phase) +
                0.16 * sin(2 * .pi * 356 * t + 0.28) +
                0.055 * sin(2 * .pi * 534 * t + 0.82)
            let shimmer = 0.92 + 0.05 * sin(2 * .pi * 5.2 * t) + 0.02 * sin(2 * .pi * 10.7 * t + phase)
            return (blade * shimmer + random * 0.0015) * 0.22
        }
    }

    private func makeRoarBuffer(format: AVAudioFormat, seconds: Double, afterburner: Bool) -> AVAudioPCMBuffer {
        let count = AVAudioFrameCount(format.sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buffer.frameLength = count
        let rate = Float(format.sampleRate)
        let channels = Int(format.channelCount)

        var seeds: [UInt32] = [0x91E1_0DA5, 0xC2A7_3B19]
        var sub: [Float] = [0, 0]
        var low: [Float] = [0, 0]
        var body: [Float] = [0, 0]
        var crackle: [Float] = [0, 0]

        for i in 0..<Int(count) {
            let t = Float(i) / rate
            for ch in 0..<channels {
                seeds[ch] = 1_664_525 &* seeds[ch] &+ 1_013_904_223
                let raw = Float(Int32(bitPattern: seeds[ch])) / Float(Int32.max)

                // Cascaded low-frequency stochastic bands: this is turbulent
                // exhaust body, not exposed white noise.
                sub[ch] = 0.9988 * sub[ch] + 0.0012 * raw
                low[ch] = 0.9885 * low[ch] + 0.0115 * raw
                body[ch] = 0.9460 * body[ch] + 0.0540 * raw
                let lowBand = low[ch] - sub[ch]
                let bodyBand = body[ch] - low[ch]

                if afterburner && abs(raw) > 0.9982 {
                    crackle[ch] += raw * 0.32
                }
                crackle[ch] *= afterburner ? 0.978 : 0.90

                let phase = Float(ch) * 0.15
                let combustion =
                    0.28 * sin(2 * .pi * 43 * t + phase) +
                    0.17 * sin(2 * .pi * 67 * t + 0.5) +
                    0.09 * sin(2 * .pi * 91 * t + 1.1)
                let pressure = afterburner
                    ? 0.11 * sin(2 * .pi * 121 * t + phase)
                    : 0.045 * sin(2 * .pi * 116 * t + phase)
                let breathing = 0.90
                    + 0.060 * sin(2 * .pi * 1.55 * t + phase)
                    + 0.028 * sin(2 * .pi * 3.25 * t + 1.0)

                let turbulent: Float
                if afterburner {
                    turbulent = 1.55 * sub[ch] + 2.05 * lowBand + 0.42 * bodyBand + 0.055 * crackle[ch]
                } else {
                    turbulent = 1.35 * sub[ch] + 1.72 * lowBand + 0.30 * bodyBand
                }

                let mixed = turbulent * breathing + combustion + pressure
                let saturated = tanhf(mixed * (afterburner ? 1.65 : 1.42))
                buffer.floatChannelData![ch][i] = saturated * (afterburner ? 0.56 : 0.50)
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
                buffer.floatChannelData![ch][i] = high * 0.14
            }
        }
        return buffer
    }

    private func makeIgnitionBuffer(format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer {
        makeStereoBuffer(format: format, seconds: seconds) { t, channel, random in
            let phase = Float(channel) * 0.13
            let thump = sin(2 * .pi * 57 * t + phase) * expf(-7.0 * t)
            let secondary = 0.42 * sin(2 * .pi * 92 * t + 0.5) * expf(-5.5 * t)
            let barkEnvelope = min(t * 14.0, 1.0) * expf(-3.2 * t)
            let bark = random * barkEnvelope
            return clamp(thump * 0.68 + secondary + bark * 0.12, -0.92, 0.92)
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
