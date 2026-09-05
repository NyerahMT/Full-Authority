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

    /// JSBSim's recommended real-time stepping rate for this project.
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
    }

    func loadModel(named modelName: String) -> Bool {
        do {
            try bridge.loadModel(modelName)

            // Start from a deliberately neutral command state. Aircraft-specific
            // initialization belongs in the aircraft package, not in the renderer.
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

    /// Advances the simulation using a fixed 120 Hz step regardless of display FPS.
    func advance(realDelta: TimeInterval) {
        guard bridge.isModelLoaded else { return }

        // A breakpoint/background resume should not turn into hundreds of catch-up steps.
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

            integrateLocalRenderPosition(deltaTime: fixedStep)
            readStateFromJSBSim()
            simulationTime += fixedStep
            accumulator -= fixedStep
        }
    }

    private func applyControls() {
        // These are the standard JSBSim pilot-command properties and are also
        // the interface used by JSBSim's rotorcraft control system.
        bridge.setProperty("fcs/aileron-cmd-norm", value: Double(controls.cyclicRoll))
        bridge.setProperty("fcs/elevator-cmd-norm", value: Double(controls.cyclicPitch))
        bridge.setProperty("fcs/collective-cmd-norm", value: Double(controls.collective))
        bridge.setProperty("fcs/rudder-cmd-norm", value: Double(controls.pedals))
    }

    private func readStateFromJSBSim() {
        let feetToMeters: Float = 0.3048

        let roll = Float(bridge.value(forProperty: "attitude/phi-rad"))
        let pitch = Float(bridge.value(forProperty: "attitude/theta-rad"))
        let yaw = Float(bridge.value(forProperty: "attitude/psi-rad"))

        // JSBSim uses aerospace/NED conventions; Full Authority's render world
        // is Y-up. Keep the conversion here so sign swaps never leak into UI code.
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

        state.altitudeMeters = Float(bridge.value(forProperty: "position/h-agl-ft")) * feetToMeters
        state.airspeedMetersPerSecond = Float(bridge.value(forProperty: "velocities/vtrue-fps")) * feetToMeters
        state.verticalSpeedMetersPerSecond = -down
    }

    private func integrateLocalRenderPosition(deltaTime: TimeInterval) {
        state.positionMeters += state.velocityMetersPerSecond * Float(deltaTime)
    }
}
