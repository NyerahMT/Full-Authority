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
    var cameraPosition = SIMD3<Float>.zero
    var cameraVelocity = SIMD3<Float>.zero
    var cameraOrientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
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
                    // Stage 016 cinematic lighting: reduce the flat default IBL so
                    // directional sunlight and material roughness can actually shape terrain.
                    world.components.set(EnvironmentLightingConfigurationComponent(
                        environmentLightingWeight: 0.32
                    ))
                    content.add(world)

                    let aircraft = PrototypeAircraftFactory.make()
                    aircraft.components.set(EnvironmentLightingConfigurationComponent(
                        environmentLightingWeight: 0.43
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
                            color: UIColor(red: 1.0, green: 0.935, blue: 0.825, alpha: 1),
                            intensity: 13_200
                        ),
                        DirectionalLightComponent.Shadow()
                    ])
                    sun.look(at: .zero, from: [-11_400, 7_900, -4_900], relativeTo: nil)
                    content.add(sun)

                    let fill = Entity()
                    fill.name = "FA.fill"
                    fill.components.set(DirectionalLightComponent(
                        color: UIColor(red: 0.39, green: 0.55, blue: 0.82, alpha: 1),
                        intensity: 145
                    ))
                    fill.look(at: .zero, from: [7_600, 6_800, 8_900], relativeTo: nil)
                    content.add(fill)

                    // A restrained cool rim gives the matte jet a clean silhouette
                    // against bright cloud banks without flattening the fuselage.
                    let rim = Entity()
                    rim.name = "FA.rim"
                    rim.components.set(DirectionalLightComponent(
                        color: UIColor(red: 0.62, green: 0.76, blue: 1.0, alpha: 1),
                        intensity: 275
                    ))
                    rim.look(at: .zero, from: [9_400, 3_900, -10_200], relativeTo: nil)
                    content.add(rim)
                } update: { content in
                    guard let aircraft = content.entities.first(where: { $0.name == PrototypeAircraftFactory.aircraftName }) else {
                        return
                    }

                    aircraft.position = simulation.state.positionMeters
                    aircraft.orientation = simulation.state.orientation
                    aircraft.isEnabled = true
                    updateAircraftPresentation(aircraft)

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

            cinematicImageOverlay
                .allowsHitTesting(false)

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

    private var cinematicImageOverlay: some View {
        GeometryReader { geometry in
            let radius = max(geometry.size.width, geometry.size.height)
            ZStack {
                // Barely-there edge falloff keeps the eye on the aircraft without
                // turning the view into a fake camera-filter effect.
                RadialGradient(
                    stops: [
                        .init(color: .clear, location: 0.00),
                        .init(color: .clear, location: 0.67),
                        .init(color: .black.opacity(0.085), location: 1.00)
                    ],
                    center: .center,
                    startRadius: radius * 0.12,
                    endRadius: radius * 0.78
                )

                // Very soft forward-scatter/glare around the authored sun direction.
                // It is intentionally subtle: the aircraft and atmosphere create the
                // drama, not screen-space gimmicks.
                RadialGradient(
                    stops: [
                        .init(color: .white.opacity(0.075), location: 0.00),
                        .init(color: Color(red: 1.0, green: 0.78, blue: 0.52).opacity(0.030), location: 0.32),
                        .init(color: .clear, location: 1.00)
                    ],
                    center: UnitPoint(x: 0.16, y: 0.27),
                    startRadius: 1,
                    endRadius: radius * 0.42
                )
            }
        }
        .ignoresSafeArea()
    }

    private var stage2Sky: some View {
        let altitudeBlend = Double(clamp(simulation.state.altitudeFeetMSL / 42_000, 0, 1))
        let zenith = Color(
            red: 0.008 + 0.012 * altitudeBlend,
            green: 0.050 + 0.030 * altitudeBlend,
            blue: 0.165 + 0.075 * altitudeBlend
        )
        let upperSky = Color(
            red: 0.020 + 0.010 * altitudeBlend,
            green: 0.185 + 0.015 * altitudeBlend,
            blue: 0.430 + 0.035 * altitudeBlend
        )
        let lowerSky = Color(
            red: 0.245 + 0.050 * altitudeBlend,
            green: 0.455 + 0.020 * altitudeBlend,
            blue: 0.635 + 0.025 * altitudeBlend
        )
        let horizon = Color(
            red: 0.735 - 0.115 * altitudeBlend,
            green: 0.665 - 0.080 * altitudeBlend,
            blue: 0.555 - 0.010 * altitudeBlend
        )

        return ZStack {
            // Hillaire/Bruneton-inspired structure: dark Rayleigh-rich zenith,
            // saturated mid-sky, then a desaturated aerosol-heavy horizon.
            LinearGradient(
                stops: [
                    .init(color: zenith, location: 0.00),
                    .init(color: upperSky, location: 0.34),
                    .init(color: lowerSky, location: 0.70),
                    .init(color: horizon, location: 0.93),
                    .init(color: Color(red: 0.70, green: 0.62, blue: 0.50), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Broad solar aureole: this is atmospheric forward scattering, not bloom.
            RadialGradient(
                stops: [
                    .init(color: Color(red: 1.0, green: 0.965, blue: 0.88).opacity(0.60), location: 0.00),
                    .init(color: Color(red: 1.0, green: 0.72, blue: 0.43).opacity(0.18), location: 0.20),
                    .init(color: .clear, location: 1.00)
                ],
                center: UnitPoint(x: 0.16, y: 0.27),
                startRadius: 2,
                endRadius: 300
            )

            // Aerial-perspective wash near the horizon makes distant terrain and
            // cloud banks read in kilometres rather than as a painted backdrop.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.54),
                    .init(color: Color(red: 0.60, green: 0.68, blue: 0.72).opacity(0.08), location: 0.76),
                    .init(color: Color(red: 0.78, green: 0.70, blue: 0.59).opacity(0.13), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
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

        // Acceleration changes framing, but only by metres and a couple degrees.
        // This is a physical camera rig response, not arcade speed-FOV pumping.
        let airspeed = state.airspeedMetersPerSecond
        if let previousAirspeed = runtime.lastAirspeed {
            let acceleration = max(0, (airspeed - previousAirspeed) / max(dt, 1.0 / 240.0))
            let accelerationPullback = min(acceleration * 0.060, 1.10)
            let highSpeedResidual = clamp((airspeed - 260) / 280, 0, 1) * 0.42
            let targetPullback = accelerationPullback + highSpeedResidual
            let response: Float = targetPullback > runtime.chasePullbackMeters ? 8.5 : 3.8
            let blend = 1 - exp(-response * dt)
            runtime.chasePullbackMeters += (targetPullback - runtime.chasePullbackMeters) * blend
        } else {
            runtime.chasePullbackMeters = 0
        }
        runtime.lastAirspeed = airspeed

        var localCameraOffset: SIMD3<Float>
        let localLookPoint: SIMD3<Float>
        let baseFieldOfView: Float
        let pullbackScale: Float

        switch cameraMode {
        case .chase:
            localCameraOffset = [0, 4.25, -17.80]
            localLookPoint = [0, 0.72, 4.30]
            baseFieldOfView = 56.5
            pullbackScale = 1.0

        case .close:
            localCameraOffset = [0, 3.10, -11.95]
            localLookPoint = [0, 0.66, 4.50]
            baseFieldOfView = 60.0
            pullbackScale = 0.52

        case .cockpit:
            localCameraOffset = [0, 1.08, 3.05]
            localLookPoint = [0, 1.08, 90]
            baseFieldOfView = 66.0
            pullbackScale = 0
        }

        localCameraOffset.z -= runtime.chasePullbackMeters * pullbackScale

        if cameraMode != .cockpit && cameraHasOrbitOffset {
            let yawOrbit = simd_quatf(angle: orbitYawRadians, axis: [0, 1, 0])
            let pitchOrbit = simd_quatf(angle: orbitPitchRadians, axis: [1, 0, 0])
            localCameraOffset = simd_act(yawOrbit * pitchOrbit, localCameraOffset)
        }

        let speedFov = cameraMode == .cockpit ? 0 : clamp((airspeed - 190) / 310, 0, 1) * 1.45
        let maneuverFov = cameraMode == .cockpit ? 0 : clamp((abs(state.loadFactorG) - 1.0) / 8.0, 0, 1) * 0.65
        let fieldOfView = baseFieldOfView + speedFov + maneuverFov
        camera.components.set(PerspectiveCameraComponent(
            near: cameraMode == .cockpit ? 0.02 : 0.08,
            far: 72_000,
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

            desiredLookTarget = desiredPosition + simd_act(attitude, headForwardLocal) * 90
            cameraUp = simd_act(attitude, headUpLocal)
        } else if cameraMode == .cockpit {
            desiredLookTarget = aircraftPosition + simd_act(attitude, localLookPoint)
            cameraUp = simd_act(attitude, SIMD3<Float>(0, 1, 0))
        } else {
            desiredLookTarget = aircraftPosition + simd_act(attitude, localLookPoint)

            // The rig follows most of the aircraft bank, but not all of it. This
            // tiny amount of inertial horizon stability lets hard rolls read as
            // violent aircraft motion without faking shake or removing orientation.
            let aircraftUp = simd_act(attitude, SIMD3<Float>(0, 1, 0))
            let worldUp = SIMD3<Float>(0, 1, 0)
            let bankFollow: Float = cameraMode == .close ? 0.84 : 0.72
            cameraUp = simd_normalize(worldUp * (1 - bankFollow) + aircraftUp * bankFollow)
        }

        let desiredOrientation = lookRotation(
            forward: desiredLookTarget - desiredPosition,
            up: cameraUp
        )

        let modeChanged = runtime.cameraModeKey != cameraMode.rawValue
        if forceSnap || modeChanged || !runtime.cameraInitialized || cameraMode == .cockpit {
            runtime.cameraPosition = desiredPosition
            runtime.cameraVelocity = .zero
            runtime.cameraOrientation = desiredOrientation
        } else {
            // Critically damped translational spring. Position gets believable mass
            // while orientation stays tight enough for serious flight-sim control.
            let frequency: Float = cameraMode == .close ? 8.8 : 6.4
            let displacement = runtime.cameraPosition - desiredPosition
            let springAcceleration =
                -2 * frequency * runtime.cameraVelocity
                - (frequency * frequency) * displacement
            runtime.cameraVelocity += springAcceleration * dt
            runtime.cameraPosition += runtime.cameraVelocity * dt

            let orientationResponse: Float = cameraMode == .close ? 10.5 : 8.0
            let orientationBlend = 1 - exp(-orientationResponse * dt)
            runtime.cameraOrientation = simd_slerp(
                runtime.cameraOrientation,
                desiredOrientation,
                orientationBlend
            )
        }

        camera.position = runtime.cameraPosition
        camera.orientation = runtime.cameraOrientation
        runtime.cameraInitialized = true
        runtime.cameraModeKey = cameraMode.rawValue
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
            let length = (0.95 + 0.82 * intensity) * pressureExpansion * speedCompression

            if let halo = aircraft.findEntity(named: PrototypeAircraftFactory.afterburnerHaloName) {
                halo.scale = [1.26 * width, 2.55 * length, 1.26 * width]
                halo.position = [0, 0, 0.5 * halo.scale.y]
            }
            if let outer = aircraft.findEntity(named: PrototypeAircraftFactory.afterburnerOuterName) {
                outer.scale = [0.98 * width, 2.28 * length, 1.05 * width]
                outer.position = [0, 0, 0.5 * outer.scale.y]
            }
            if let inner = aircraft.findEntity(named: PrototypeAircraftFactory.afterburnerInnerName) {
                let pulse = 1.0 + 0.016 * sin(time * 61.0 + 0.9)
                inner.scale = [0.60 * width * pulse, 1.78 * length, 0.68 * width * pulse]
                inner.position = [0, 0, 0.5 * inner.scale.y]
            }
            if let core = aircraft.findEntity(named: PrototypeAircraftFactory.afterburnerCoreName) {
                let pulse = 1.0 + 0.026 * sin(time * 73.0 + 0.35)
                core.scale = [0.23 * width * pulse, 1.24 * length, 0.29 * width * pulse]
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

        rumbleRate.rate = 0.78 + 0.33 * n1
        turbineRate.rate = 0.70 + 1.00 * n2

        // The persistent high-pitched whir is the synthetic compressor/turbine
        // layer, not an APU. In the cockpit it was actually louder than outside.
        // Helmet/canopy attenuation now knocks that layer down hard while leaving
        // enough low-frequency engine body to know the jet is alive.
        let cockpitRumble: Float = isCockpit ? 0.52 : 1.0
        let cockpitTurbine: Float = isCockpit ? 0.30 : 0.82
        let cockpitExhaust: Float = isCockpit ? 0.18 : 1.0
        let cockpitWind: Float = isCockpit ? 0.22 : 1.0

        rumble.volume = live * cockpitRumble * (0.050 + 0.18 * n1)
        turbine.volume = live * cockpitTurbine * (0.014 + 0.095 * n2 * n2)
        exhaust.volume = live * cockpitExhaust * (0.025 + 0.20 * dryPower)
        afterburner.volume = live * cockpitExhaust * (state.afterburnerActive ? 0.16 + 0.14 * n2 : 0)
        wind.volume = live * cockpitWind * (0.004 + 0.030 * min(powf(mach, 1.55), 1.40))

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
        exhaustBands[0].gain = 4.5
        exhaustBands[0].bypass = false
        exhaustBands[1].filterType = .parametric
        exhaustBands[1].frequency = 340
        exhaustBands[1].bandwidth = 1.15
        exhaustBands[1].gain = 1.5
        exhaustBands[1].bypass = false
        exhaustBands[2].filterType = .highShelf
        exhaustBands[2].frequency = 1_850
        exhaustBands[2].gain = -11.0
        exhaustBands[2].bypass = false

        let burnerBands = burnerEQ.bands
        burnerBands[0].filterType = .lowShelf
        burnerBands[0].frequency = 105
        burnerBands[0].gain = 6.0
        burnerBands[0].bypass = false
        burnerBands[1].filterType = .parametric
        burnerBands[1].frequency = 260
        burnerBands[1].bandwidth = 1.0
        burnerBands[1].gain = 2.5
        burnerBands[1].bypass = false
        burnerBands[2].filterType = .highShelf
        burnerBands[2].frequency = 2_200
        burnerBands[2].gain = -12.5
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
            let phase: Float = channel == 0 ? 0 : 0.11
            let blade =
                0.52 * sin(2 * .pi * 315 * t + phase) +
                0.27 * sin(2 * .pi * 630 * t + 0.3) +
                0.13 * sin(2 * .pi * 945 * t + 0.9) +
                0.06 * sin(2 * .pi * 1_575 * t + 1.4)
            let shimmer = 0.90 + 0.07 * sin(2 * .pi * 7.0 * t) + 0.03 * sin(2 * .pi * 13.0 * t + phase)
            return (blade * shimmer + random * 0.006) * 0.34
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
        var presence: [Float] = [0, 0]
        var crackle: [Float] = [0, 0]

        for i in 0..<Int(count) {
            let t = Float(i) / rate
            for ch in 0..<channels {
                seeds[ch] = 1_664_525 &* seeds[ch] &+ 1_013_904_223
                let raw = Float(Int32(bitPattern: seeds[ch])) / Float(Int32.max)

                sub[ch] = 0.9985 * sub[ch] + 0.0015 * raw
                low[ch] = 0.9880 * low[ch] + 0.0120 * raw
                body[ch] = 0.9100 * body[ch] + 0.0900 * raw
                presence[ch] = 0.6200 * presence[ch] + 0.3800 * raw

                let lowBand = low[ch] - sub[ch]
                let bodyBand = body[ch] - low[ch]
                let edge = raw - presence[ch]

                if afterburner && abs(raw) > 0.9970 {
                    crackle[ch] += raw * 0.55
                }
                crackle[ch] *= afterburner ? 0.984 : 0.94

                let phase = Float(ch) * 0.16
                let combustion =
                    0.10 * sin(2 * .pi * 46 * t + phase) +
                    0.065 * sin(2 * .pi * 69 * t + 0.55) +
                    0.035 * sin(2 * .pi * 92 * t + 1.05)
                let pressurePulse = afterburner
                    ? 0.045 * sin(2 * .pi * 118 * t + phase)
                    : 0.020 * sin(2 * .pi * 118 * t + phase)
                let breathing = 0.90
                    + 0.055 * sin(2 * .pi * 1.7 * t + phase)
                    + 0.035 * sin(2 * .pi * 3.1 * t + 1.2)

                let colored: Float
                if afterburner {
                    colored =
                        1.20 * sub[ch] +
                        1.55 * lowBand +
                        0.58 * bodyBand +
                        0.020 * edge +
                        0.15 * crackle[ch]
                } else {
                    colored =
                        1.00 * sub[ch] +
                        1.28 * lowBand +
                        0.44 * bodyBand +
                        0.010 * edge
                }

                let sample = (colored * breathing + combustion + pressurePulse)
                    * (afterburner ? 0.62 : 0.52)
                buffer.floatChannelData![ch][i] = clamp(sample, -0.92, 0.92)
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
