import Combine
import Foundation
import simd

@MainActor
final class FlightSimulation: ObservableObject {
    enum BackendStatus: Equatable {
        case bridgeReady(version: String)
        case running(model: String)
        case failed(message: String)
    }

    @Published var controls = FlightControls()
    @Published private(set) var state = AircraftState.parked
    @Published private(set) var backendStatus: BackendStatus
    @Published private(set) var simulationTime: TimeInterval = 0

    let fixedStep: TimeInterval = 1.0 / 120.0

    private let bridge: FAJSBSimBridge
    private var accumulator: TimeInterval = 0
    private var activeModel: String?
    private var originLatitudeRadians: Double?
    private var originLongitudeRadians: Double?

    init() {
        let resourceRoot = Bundle.main.resourceURL?
            .appendingPathComponent("JSBSim", isDirectory: true)
            .path ?? Bundle.main.bundlePath

        bridge = FAJSBSimBridge(rootPath: resourceRoot)
        bridge.setDeltaTime(fixedStep)
        backendStatus = .bridgeReady(version: bridge.version)

        // The AH-1S is an upstream JSBSim calibration aircraft. It is staged into
        // CI-built app bundles from the pinned JSBSim submodule and is not our
        // eventual shipping Full Authority aircraft model.
        _ = loadModel(named: "ah1s")
    }

    func loadModel(named modelName: String) -> Bool {
        do {
            try bridge.loadModel(modelName)
            configureInitialConditions(for: modelName)
            configureModelSystems(for: modelName)
            applyControls()
            try bridge.runInitialConditions()
        } catch {
            backendStatus = .failed(message: error.localizedDescription)
            return false
        }

        activeModel = modelName
        state = .parked
        accumulator = 0
        simulationTime = 0
        originLatitudeRadians = bridge.value(forProperty: "position/lat-geod-rad")
        originLongitudeRadians = bridge.value(forProperty: "position/long-gc-rad")
        backendStatus = .running(model: modelName)
        readStateFromJSBSim()
        return true
    }

    /// Advances JSBSim at a fixed 120 Hz regardless of rendering frame rate.
    func advance(realDelta: TimeInterval) {
        guard bridge.isModelLoaded else { return }

        accumulator += min(max(realDelta, 0), 0.20)

        while accumulator >= fixedStep {
            controls.clampToValidRange()
            applyControls()

            do {
                try bridge.step()
            } catch {
                backendStatus = .failed(message: error.localizedDescription)
                accumulator = 0
                return
            }

            readStateFromJSBSim()
            integrateRotorPhases(deltaTime: fixedStep)
            simulationTime += fixedStep
            accumulator -= fixedStep
        }
    }

    private func configureInitialConditions(for modelName: String) {
        bridge.setProperty("ic/terrain-elevation-ft", value: 0)
        bridge.setProperty("ic/h-agl-ft", value: modelName == "ah1s" ? 6.3 : 3.6)
        bridge.setProperty("ic/vg-fps", value: 0)
        bridge.setProperty("ic/phi-deg", value: 0)
        bridge.setProperty("ic/theta-deg", value: 0)
        bridge.setProperty("ic/psi-true-deg", value: 0)
    }

    private func configureModelSystems(for modelName: String) {
        guard modelName == "ah1s" else { return }

        // Match the upstream AH-1S interactive setup rather than bypassing its
        // helicopter-specific control and rotor systems.
        bridge.setProperty("aero/setup/downwash-enable", value: 1)
        bridge.setProperty("aero/setup/Nr_limiter", value: 0.05)
        bridge.setProperty("fcs/adj/collective-profile", value: 1)
        bridge.setProperty("fcs/adj/center-sensitivity", value: 1.65)

        // Use the upstream RPM governor and a moderate amount of its AFCS/SAS.
        // Pilot commands still feed the rotor-control system directly.
        bridge.setProperty("fcs/rpm-governor-active-norm", value: 1)
        bridge.setProperty("ap/afcs/pitch-channel-active-norm", value: 0.45)
        bridge.setProperty("ap/afcs/roll-channel-active-norm", value: 0.45)
        bridge.setProperty("ap/afcs/yaw-channel-active-norm", value: 0.55)
    }

    private func applyControls() {
        bridge.setProperty("fcs/aileron-cmd-norm", value: Double(controls.cyclicRoll))
        bridge.setProperty("fcs/elevator-cmd-norm", value: Double(controls.cyclicPitch))
        bridge.setProperty("fcs/collective-cmd-norm", value: Double(controls.collective))
        bridge.setProperty("fcs/rudder-cmd-norm", value: Double(controls.pedals))

        if activeModel == "ah1s" {
            bridge.setProperty("fcs/rpm-governor-active-norm", value: 1)
        } else {
            bridge.setProperty("fcs/throttle-cmd-norm", value: 1)
            bridge.setProperty("fcs/throttle-cmd-norm[0]", value: 1)
            bridge.setProperty("fcs/throttle-cmd-norm[1]", value: 1)
        }
    }

    private func readStateFromJSBSim() {
        let feetToMeters: Float = 0.3048
        let radiansToDegrees: Float = 180 / .pi

        let roll = Float(bridge.value(forProperty: "attitude/phi-rad"))
        let pitch = Float(bridge.value(forProperty: "attitude/theta-rad"))
        let yaw = Float(bridge.value(forProperty: "attitude/psi-rad"))

        // JSBSim: NED, +X forward, +Y right, +Z down.
        // Full Authority: +Z forward/north, +X right/east, +Y up.
        // Heading is clockwise from north, which is +yaw around RealityKit Y.
        let yawQ = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        let pitchQ = simd_quatf(angle: -pitch, axis: SIMD3<Float>(1, 0, 0))
        let rollQ = simd_quatf(angle: -roll, axis: SIMD3<Float>(0, 0, 1))
        state.orientation = yawQ * pitchQ * rollQ

        let north = Float(bridge.value(forProperty: "velocities/v-north-fps")) * feetToMeters
        let east = Float(bridge.value(forProperty: "velocities/v-east-fps")) * feetToMeters
        let down = Float(bridge.value(forProperty: "velocities/v-down-fps")) * feetToMeters
        state.velocityMetersPerSecond = SIMD3<Float>(east, -down, north)

        state.angularVelocityRadiansPerSecond = SIMD3<Float>(
            Float(bridge.value(forProperty: "velocities/p-rad_sec")),
            Float(bridge.value(forProperty: "velocities/r-rad_sec")),
            Float(bridge.value(forProperty: "velocities/q-rad_sec"))
        )

        state.altitudeMeters = max(0, Float(bridge.value(forProperty: "position/h-agl-ft")) * feetToMeters)
        updateLocalPositionFromGeodetic()
        state.positionMeters.y = max(0.6, state.altitudeMeters)

        state.airspeedMetersPerSecond = max(0, Float(bridge.value(forProperty: "velocities/vtrue-fps")) * feetToMeters)
        state.verticalSpeedMetersPerSecond = -down

        let rawHeading = yaw * radiansToDegrees
        let wrappedHeading = rawHeading.truncatingRemainder(dividingBy: 360)
        state.headingDegrees = wrappedHeading >= 0 ? wrappedHeading : wrappedHeading + 360

        state.mainRotorRPM = max(0, Float(bridge.value(forProperty: "propulsion/engine/rotor-rpm")))
        let reportedTailRPM = max(0, Float(bridge.value(forProperty: "propulsion/engine[1]/rotor-rpm")))
        state.tailRotorRPM = reportedTailRPM > 1 ? reportedTailRPM : state.mainRotorRPM * 6.33
    }

    private func updateLocalPositionFromGeodetic() {
        guard let originLatitudeRadians, let originLongitudeRadians else { return }

        let latitude = bridge.value(forProperty: "position/lat-geod-rad")
        let longitude = bridge.value(forProperty: "position/long-gc-rad")
        guard latitude.isFinite, longitude.isFinite else { return }

        let earthRadiusMeters = 6_371_000.0
        let northMeters = (latitude - originLatitudeRadians) * earthRadiusMeters
        let eastMeters = (longitude - originLongitudeRadians) * earthRadiusMeters * cos(originLatitudeRadians)

        state.positionMeters.x = Float(eastMeters)
        state.positionMeters.z = Float(northMeters)
    }

    private func integrateRotorPhases(deltaTime: TimeInterval) {
        let seconds = Float(deltaTime)
        let revolutionsToRadians = Float.pi * 2 / 60

        state.mainRotorPhaseRadians = wrapAngle(
            state.mainRotorPhaseRadians + state.mainRotorRPM * revolutionsToRadians * seconds
        )
        state.tailRotorPhaseRadians = wrapAngle(
            state.tailRotorPhaseRadians + state.tailRotorRPM * revolutionsToRadians * seconds
        )
    }

    private func wrapAngle(_ angle: Float) -> Float {
        angle.truncatingRemainder(dividingBy: .pi * 2)
    }
}
