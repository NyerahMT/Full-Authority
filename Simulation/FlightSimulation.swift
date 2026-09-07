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

        _ = loadModel(named: "f15")
    }

    func loadModel(named modelName: String) -> Bool {
        do {
            try bridge.loadModel(modelName)
            activeModel = modelName
            configureInitialConditions(for: modelName)
            configureModelSystems(for: modelName)
            applyControls()
            try bridge.runInitialConditions()
            configureModelSystems(for: modelName)
            applyControls()
        } catch {
            activeModel = nil
            backendStatus = .failed(message: error.localizedDescription)
            return false
        }

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
            simulationTime += fixedStep
            accumulator -= fixedStep
        }
    }

    private func configureInitialConditions(for modelName: String) {
        bridge.setProperty("ic/terrain-elevation-ft", value: 0)
        bridge.setProperty("ic/phi-deg", value: 0)
        bridge.setProperty("ic/psi-true-deg", value: 0)

        if modelName == "f15" {
            // Stage 006 deliberately starts lower and a little slower so nearby
            // terrain produces useful parallax and closure-rate cues on a phone.
            bridge.setProperty("ic/h-agl-ft", value: 900)
            bridge.setProperty("ic/vg-fps", value: 430)
            bridge.setProperty("ic/theta-deg", value: 2)
            bridge.setProperty("ic/gamma-deg", value: 0)
        } else {
            bridge.setProperty("ic/h-agl-ft", value: 1_000)
            bridge.setProperty("ic/vg-fps", value: 350)
            bridge.setProperty("ic/theta-deg", value: 0)
        }
    }

    private func configureModelSystems(for modelName: String) {
        guard modelName == "f15" else { return }

        bridge.setProperty("propulsion/set-running", value: -1)
        bridge.setProperty("gear/gear-cmd-norm", value: 0)
        bridge.setProperty("fcs/flap-cmd-norm", value: 0)
        bridge.setProperty("fcs/speedbrake-cmd-norm", value: 0)
    }

    private func applyControls() {
        // The Stage 005 screen-to-FDM mapping was backwards on both stick axes.
        // Keep the UI conventional (right = right roll, pull down = nose up) and
        // correct the sign at the JSBSim boundary so every future input device
        // shares the same Full Authority control convention.
        bridge.setProperty("fcs/aileron-cmd-norm", value: -Double(controls.roll))
        bridge.setProperty("fcs/elevator-cmd-norm", value: -Double(controls.pitch))
        bridge.setProperty("fcs/rudder-cmd-norm", value: Double(controls.rudder))

        bridge.setProperty("fcs/throttle-cmd-norm", value: Double(controls.throttle))
        bridge.setProperty("fcs/throttle-cmd-norm[0]", value: Double(controls.throttle))
        bridge.setProperty("fcs/throttle-cmd-norm[1]", value: Double(controls.throttle))
    }

    private func readStateFromJSBSim() {
        let feetToMeters: Float = 0.3048
        let radiansToDegrees: Float = 180 / .pi

        let roll = Float(bridge.value(forProperty: "attitude/phi-rad"))
        let pitch = Float(bridge.value(forProperty: "attitude/theta-rad"))
        let yaw = Float(bridge.value(forProperty: "attitude/psi-rad"))

        // JSBSim: NED, +X forward, +Y right, +Z down.
        // Full Authority: +Z forward/north, +X right/east, +Y up.
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

        state.mainRotorRPM = 0
        state.tailRotorRPM = 0
        state.mainRotorPhaseRadians = 0
        state.tailRotorPhaseRadians = 0
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
}
