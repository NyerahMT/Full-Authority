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

    init() {
        let resourceRoot = Bundle.main.resourceURL?
            .appendingPathComponent("JSBSim", isDirectory: true)
            .path ?? Bundle.main.bundlePath

        bridge = FAJSBSimBridge(rootPath: resourceRoot)
        bridge.setDeltaTime(fixedStep)
        backendStatus = .bridgeReady(version: bridge.version)

        _ = loadModel(named: "fa_r01")
    }

    func loadModel(named modelName: String) -> Bool {
        do {
            try bridge.loadModel(modelName)
            configureInitialConditions()
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
        backendStatus = .running(model: modelName)
        readStateFromJSBSim()
        return true
    }

    /// Advances JSBSim at a fixed 120 Hz regardless of rendering frame rate.
    func advance(realDelta: TimeInterval) {
        guard bridge.isModelLoaded else { return }

        // Prevent a background/resume or debugger pause from causing a huge catch-up burst.
        accumulator += min(max(realDelta, 0), 0.25)

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
            integrateLocalHorizontalPosition(deltaTime: fixedStep)
            simulationTime += fixedStep
            accumulator -= fixedStep
        }
    }

    private func configureInitialConditions() {
        // Start FA-R01 sitting just above the local ground plane at rest.
        bridge.setProperty("ic/terrain-elevation-ft", value: 0)
        bridge.setProperty("ic/h-agl-ft", value: 3.6)
        bridge.setProperty("ic/vg-fps", value: 0)
        bridge.setProperty("ic/phi-deg", value: 0)
        bridge.setProperty("ic/theta-deg", value: 0)
        bridge.setProperty("ic/psi-true-deg", value: 0)
    }

    private func applyControls() {
        // Full Authority owns pilot input. The aircraft XML maps these normalized
        // commands into actual rotor collective/cyclic/pedal angles.
        bridge.setProperty("fcs/aileron-cmd-norm", value: Double(controls.cyclicRoll))
        bridge.setProperty("fcs/elevator-cmd-norm", value: Double(controls.cyclicPitch))
        bridge.setProperty("fcs/collective-cmd-norm", value: Double(controls.collective))
        bridge.setProperty("fcs/rudder-cmd-norm", value: Double(controls.pedals))

        // FA-R01 uses an electric motor as a clean stand-in for the turbine/governor
        // while we tune the rotor model. Rotor power is therefore always available.
        bridge.setProperty("fcs/throttle-cmd-norm", value: 1)
        bridge.setProperty("fcs/throttle-cmd-norm[0]", value: 1)
        bridge.setProperty("fcs/throttle-cmd-norm[1]", value: 1)
    }

    private func readStateFromJSBSim() {
        let feetToMeters: Float = 0.3048
        let radiansToDegrees: Float = 180 / .pi

        let roll = Float(bridge.value(forProperty: "attitude/phi-rad"))
        let pitch = Float(bridge.value(forProperty: "attitude/theta-rad"))
        let yaw = Float(bridge.value(forProperty: "attitude/psi-rad"))

        // JSBSim uses aerospace/NED conventions; Full Authority renders Y-up.
        let yawQ = simd_quatf(angle: -yaw, axis: SIMD3<Float>(0, 1, 0))
        let pitchQ = simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
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
        state.positionMeters.y = max(0.55, state.altitudeMeters)
        state.airspeedMetersPerSecond = Float(bridge.value(forProperty: "velocities/vtrue-fps")) * feetToMeters
        state.verticalSpeedMetersPerSecond = -down

        let rawHeading = yaw * radiansToDegrees
        state.headingDegrees = rawHeading.truncatingRemainder(dividingBy: 360) >= 0
            ? rawHeading.truncatingRemainder(dividingBy: 360)
            : rawHeading.truncatingRemainder(dividingBy: 360) + 360
    }

    private func integrateLocalHorizontalPosition(deltaTime: TimeInterval) {
        let dt = Float(deltaTime)
        state.positionMeters.x += state.velocityMetersPerSecond.x * dt
        state.positionMeters.z += state.velocityMetersPerSecond.z * dt
    }
}
