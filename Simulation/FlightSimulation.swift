import Combine
import Foundation
import simd

enum Stage2TerrainProfile {
    static func heightMeters(east: Float, north: Float) -> Float {
        let e = Double(east)
        let n = Double(north)

        var base =
            55.0 * sin(n / 2800.0) * cos(e / 3600.0) +
            38.0 * sin((e + n) / 1900.0) +
            28.0 * cos((e - 0.45 * n) / 2400.0)

        let ridge1East = (e + 6500.0) / 2500.0
        let ridge1North = (n - 9000.0) / 3500.0
        base += 145.0 * exp(-0.5 * (ridge1East * ridge1East + ridge1North * ridge1North))

        let ridge2East = (e - 7200.0) / 2800.0
        let ridge2North = (n - 6500.0) / 3000.0
        base += 105.0 * exp(-0.5 * (ridge2East * ridge2East + ridge2North * ridge2North))

        let dx = max(abs(e) - 1000.0, 0.0)
        let dz = max(abs(n - 2000.0) - 3600.0, 0.0)
        let distanceOutsideAirfield = hypot(dx, dz)
        let terrainBlend = smoothStep(distanceOutsideAirfield / 1800.0)

        return Float(base * terrainBlend)
    }

    static func normal(east: Float, north: Float) -> SIMD3<Float> {
        let sample: Float = 20
        let dhde = (
            heightMeters(east: east + sample, north: north) -
            heightMeters(east: east - sample, north: north)
        ) / (2 * sample)
        let dhdn = (
            heightMeters(east: east, north: north + sample) -
            heightMeters(east: east, north: north - sample)
        ) / (2 * sample)
        return simd_normalize(SIMD3<Float>(-dhde, 1, -dhdn))
    }

    private static func smoothStep(_ value: Double) -> Double {
        let t = min(max(value, 0), 1)
        return t * t * (3 - 2 * t)
    }
}

@MainActor
final class FlightSimulation: ObservableObject {
    enum BackendStatus: Equatable {
        case bridgeReady(version: String)
        case running(model: String)
        case failed(message: String)
    }

    enum FlightCondition: Equatable {
        case ready
        case airborne
        case landed(touchdownFPM: Float)
        case crashed(reason: String)
    }

    @Published var controls = FlightControls()
    @Published private(set) var state = AircraftState.parked
    @Published private(set) var backendStatus: BackendStatus
    @Published private(set) var simulationTime: TimeInterval = 0
    @Published private(set) var isPaused = true
    @Published private(set) var flightCondition: FlightCondition = .ready

    let fixedStep: TimeInterval = 1.0 / 120.0

    private let bridge: FAJSBSimBridge
    private var accumulator: TimeInterval = 0
    private var activeModel: String?
    private var originLatitudeRadians: Double?
    private var originLongitudeRadians: Double?
    private var previousWeightOnWheels = false
    private var hasBeenAirborne = false

    // The F-16 ground sortie begins with neutral pilot commands. We still keep
    // the trim-command fields because other fixed-wing models can use an air trim.
    private var trimAileronCommand: Double = 0
    private var trimElevatorCommand: Double = 0
    private var trimRudderCommand: Double = 0

    init() {
        let resourceRoot = Bundle.main.resourceURL?
            .appendingPathComponent("JSBSim", isDirectory: true)
            .path ?? Bundle.main.bundlePath

        bridge = FAJSBSimBridge(rootPath: resourceRoot)
        bridge.setDeltaTime(fixedStep)
        backendStatus = .bridgeReady(version: bridge.version)

        _ = loadModel(named: "f16")
        isPaused = true
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        guard bridge.isModelLoaded else { return }
        guard case .crashed = flightCondition else {
            isPaused = false
            return
        }
    }

    @discardableResult
    func resetFlight() -> Bool {
        isPaused = true
        controls = FlightControls()
        flightCondition = .ready
        hasBeenAirborne = false
        return loadModel(named: activeModel ?? "f16")
    }

    func loadModel(named modelName: String) -> Bool {
        do {
            try bridge.loadModel(modelName)
            activeModel = modelName
            resetTrimCommands()
            configureInitialConditions(for: modelName)
            configureModelSystems(for: modelName)
            applyRawNeutralControls()
            try bridge.runInitialConditions()
            configureModelSystems(for: modelName)

            if modelName == "f16" {
                // Stage 2 is a runway sortie. Let JSBSim settle the real F-16
                // landing gear and struts against the terrain callback.
                _ = try? bridge.trimGround()
                resetTrimCommands()
            } else {
                do {
                    try bridge.trimFull()
                    captureTrimCommands()
                } catch {
                    resetTrimCommands()
                }
            }

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
        previousWeightOnWheels = state.weightOnWheels
        hasBeenAirborne = false
        flightCondition = .ready
        return true
    }

    /// Advances JSBSim at a fixed 120 Hz regardless of rendering frame rate.
    func advance(realDelta: TimeInterval) {
        guard bridge.isModelLoaded, !isPaused else { return }

        accumulator += min(max(realDelta, 0), 0.20)

        while accumulator >= fixedStep {
            controls.clampToValidRange()
            applyControls()

            let wasOnWheels = state.weightOnWheels
            let verticalSpeedBeforeStep = state.verticalSpeedMetersPerSecond

            do {
                try bridge.step()
            } catch {
                backendStatus = .failed(message: error.localizedDescription)
                accumulator = 0
                isPaused = true
                return
            }

            readStateFromJSBSim()
            evaluateFlightCondition(
                wasOnWheels: wasOnWheels,
                verticalSpeedBeforeStep: verticalSpeedBeforeStep
            )
            previousWeightOnWheels = state.weightOnWheels
            simulationTime += fixedStep
            accumulator -= fixedStep

            if isPaused { break }
        }
    }

    private func configureInitialConditions(for modelName: String) {
        bridge.setProperty("ic/lat-geod-deg", value: 0)
        bridge.setProperty("ic/long-gc-deg", value: 0)
        bridge.setProperty("ic/phi-deg", value: 0)
        bridge.setProperty("ic/theta-deg", value: 0)
        bridge.setProperty("ic/psi-true-deg", value: 0)
        bridge.setProperty("ic/beta-deg", value: 0)
        bridge.setProperty("ic/gamma-deg", value: 0)

        if modelName == "f16" {
            // CG height is close to the F-16 gear geometry defined by the model.
            // Ground trim performs the final strut/contact settling.
            bridge.setProperty("ic/h-agl-ft", value: 5.8)
            bridge.setProperty("ic/vc-kts", value: 0)
            bridge.setProperty("ic/alpha-deg", value: 0)
        } else {
            bridge.setProperty("ic/h-agl-ft", value: 1_000)
            bridge.setProperty("ic/vc-kts", value: 250)
            bridge.setProperty("ic/alpha-deg", value: 2)
        }
    }

    private func configureModelSystems(for modelName: String) {
        guard modelName == "f16" else { return }

        // The XML continues to own propulsion, FCS, aerodynamics, tire friction,
        // strut forces and gear contact. These are only pilot/system commands.
        bridge.setProperty("propulsion/set-running", value: -1)
        bridge.setProperty("gear/gear-cmd-norm", value: controls.gearDown ? 1 : 0)
        bridge.setProperty("gear/gear-pos-norm", value: controls.gearDown ? 1 : 0)
        bridge.setProperty("fcs/speedbrake-cmd-norm", value: controls.speedbrakeExtended ? 1 : 0)
        bridge.setProperty("fcs/left-brake-cmd-norm", value: Double(controls.wheelBrake))
        bridge.setProperty("fcs/right-brake-cmd-norm", value: Double(controls.wheelBrake))
        bridge.setProperty("fcs/center-brake-cmd-norm", value: Double(controls.wheelBrake))
        bridge.setProperty("fcs/steer-cmd-norm", value: 0)
        bridge.setProperty("fcs/fbw-override", value: 0)
        bridge.setProperty("fcs/pitch-trim-cmd-norm", value: 0)
        bridge.setProperty("fcs/roll-trim-cmd-norm", value: 0)
        bridge.setProperty("fcs/yaw-trim-cmd-norm", value: 0)
    }

    private func applyRawNeutralControls() {
        bridge.setProperty("fcs/aileron-cmd-norm", value: 0)
        bridge.setProperty("fcs/elevator-cmd-norm", value: 0)
        bridge.setProperty("fcs/rudder-cmd-norm", value: 0)
        bridge.setProperty("fcs/throttle-cmd-norm", value: Double(controls.throttle))
        bridge.setProperty("fcs/throttle-cmd-norm[0]", value: Double(controls.throttle))
        bridge.setProperty("fcs/left-brake-cmd-norm", value: Double(controls.wheelBrake))
        bridge.setProperty("fcs/right-brake-cmd-norm", value: Double(controls.wheelBrake))
        bridge.setProperty("fcs/center-brake-cmd-norm", value: Double(controls.wheelBrake))
        bridge.setProperty("fcs/steer-cmd-norm", value: 0)
    }

    private func captureTrimCommands() {
        trimAileronCommand = clamp(bridge.value(forProperty: "fcs/aileron-cmd-norm"), min: -1, max: 1)
        trimElevatorCommand = clamp(bridge.value(forProperty: "fcs/elevator-cmd-norm"), min: -1, max: 0.44)
        trimRudderCommand = clamp(bridge.value(forProperty: "fcs/rudder-cmd-norm"), min: -1, max: 1)

        let trimmedThrottle = bridge.value(forProperty: "fcs/throttle-cmd-norm[0]")
        if trimmedThrottle.isFinite, trimmedThrottle >= 0, trimmedThrottle <= 1 {
            var initialControls = controls
            initialControls.throttle = Float(trimmedThrottle)
            controls = initialControls
        }
    }

    private func resetTrimCommands() {
        trimAileronCommand = 0
        trimElevatorCommand = 0
        trimRudderCommand = 0
    }

    private func applyControls() {
        let aileron = clamp(trimAileronCommand - Double(controls.roll), min: -1, max: 1)
        let elevator = clamp(trimElevatorCommand - Double(controls.pitch), min: -1, max: 0.44)

        // Full Authority's touch control is screen-centric: dragging right means
        // right pedal / nose-right. The current F-16 resource patch converts this
        // sign again at the model boundary; NWS uses this sign directly.
        let pilotYawCommand = -Double(controls.rudder)
        let rudder = clamp(trimRudderCommand + pilotYawCommand, min: -1, max: 1)

        let throttle = clamp(Double(controls.throttle), min: 0, max: 1)
        let brake = clamp(Double(controls.wheelBrake), min: 0, max: 1)

        bridge.setProperty("fcs/aileron-cmd-norm", value: aileron)
        bridge.setProperty("fcs/elevator-cmd-norm", value: elevator)
        bridge.setProperty("fcs/rudder-cmd-norm", value: rudder)
        bridge.setProperty("fcs/throttle-cmd-norm", value: throttle)
        bridge.setProperty("fcs/throttle-cmd-norm[0]", value: throttle)
        bridge.setProperty("gear/gear-cmd-norm", value: controls.gearDown ? 1 : 0)
        bridge.setProperty("fcs/speedbrake-cmd-norm", value: controls.speedbrakeExtended ? 1 : 0)
        bridge.setProperty("fcs/left-brake-cmd-norm", value: brake)
        bridge.setProperty("fcs/right-brake-cmd-norm", value: brake)
        bridge.setProperty("fcs/center-brake-cmd-norm", value: brake)

        let steering = state.weightOnWheels && state.gearPosition > 0.8
            ? clamp(pilotYawCommand, min: -1, max: 1)
            : 0
        bridge.setProperty("fcs/steer-cmd-norm", value: steering)
    }

    private func readStateFromJSBSim() {
        let feetToMeters: Float = 0.3048
        let radiansToDegrees: Float = 180 / .pi

        let roll = Float(bridge.value(forProperty: "attitude/phi-rad"))
        let pitch = Float(bridge.value(forProperty: "attitude/theta-rad"))
        let yaw = Float(bridge.value(forProperty: "attitude/psi-rad"))

        // JSBSim uses its aerospace body/NED convention; RealityKit uses Y-up.
        // Keep one explicit conversion and expose display-space bank below so
        // HUD attitude symbology rotates with the rendered world, not against it.
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
        state.terrainElevationMeters = finiteFloat("position/terrain-elevation-asl-ft", fallback: 0) * feetToMeters
        state.altitudeFeetMSL = finiteFloat("position/h-sl-ft", fallback: state.altitudeMeters * 3.28084)
        updateLocalPositionFromGeodetic()
        state.positionMeters.y = state.altitudeFeetMSL * feetToMeters

        state.airspeedMetersPerSecond = max(0, Float(bridge.value(forProperty: "velocities/vtrue-fps")) * feetToMeters)
        state.calibratedAirspeedKnots = max(
            0,
            finiteFloat("velocities/vc-kts", fallback: state.airspeedMetersPerSecond * 1.94384)
        )
        state.groundSpeedKnots = max(0, finiteFloat("velocities/vg-fps", fallback: 0) * 0.592484)
        state.verticalSpeedMetersPerSecond = -down
        state.flightPathAngleDegrees = finiteFloat("flight-path/gamma-deg", fallback: 0)

        let rawHeading = yaw * radiansToDegrees
        let wrappedHeading = rawHeading.truncatingRemainder(dividingBy: 360)
        state.headingDegrees = wrappedHeading >= 0 ? wrappedHeading : wrappedHeading + 360

        state.rollDegrees = -roll * radiansToDegrees
        state.pitchDegrees = pitch * radiansToDegrees
        state.mach = finiteFloat("velocities/mach", fallback: 0)
        state.angleOfAttackDegrees = finiteFloat("aero/alpha-deg", fallback: 0)
        state.sideslipDegrees = finiteFloat("aero/beta-deg", fallback: 0)
        state.loadFactorG = finiteFloat("accelerations/n-pilot-z-norm", fallback: 1)
        state.dynamicPressurePSF = max(0, finiteFloat("aero/qbar-psf", fallback: 0))

        // Feed presentation the atmosphere JSBSim is actually using.
        let temperatureRankine = finiteFloat("atmosphere/T-R", fallback: 518.67)
        state.ambientTemperatureC = temperatureRankine / 1.8 - 273.15
        state.ambientPressurePSF = max(0, finiteFloat("atmosphere/P-psf", fallback: 2_116.22))
        state.airDensitySlugsPerCubicFoot = max(0, finiteFloat("atmosphere/rho-slugs_ft3", fallback: 0.0023769))
        state.engineFuelFlowPoundsPerSecond = max(0, finiteFloat("propulsion/engine[0]/fuel-flow-rate-pps", fallback: 0))
        let windNorth = finiteFloat("atmosphere/total-wind-north-fps", fallback: 0) * feetToMeters
        let windEast = finiteFloat("atmosphere/total-wind-east-fps", fallback: 0) * feetToMeters
        let windDown = finiteFloat("atmosphere/total-wind-down-fps", fallback: 0) * feetToMeters
        state.windMetersPerSecond = SIMD3<Float>(windEast, -windDown, windNorth)

        state.gearPosition = clampFloat(finiteFloat("gear/gear-pos-norm", fallback: 0), min: 0, max: 1)
        state.speedbrakePosition = clampFloat(finiteFloat("fcs/speedbrake-pos-norm", fallback: 0), min: 0, max: 1)
        state.weightOnWheels = finiteFloat("gear/wow", fallback: 0) > 0.5

        state.leftAileronPosition = clampFloat(finiteFloat("fcs/left-aileron-pos-norm", fallback: 0), min: -1, max: 1)
        state.rightAileronPosition = clampFloat(finiteFloat("fcs/right-aileron-pos-norm", fallback: 0), min: -1, max: 1)
        state.elevatorPosition = clampFloat(finiteFloat("fcs/elevator-pos-norm", fallback: 0), min: -1, max: 1)
        state.rudderPosition = clampFloat(finiteFloat("fcs/rudder-pos-norm", fallback: 0), min: -1, max: 1)

        // Use the model's actual surface angles for animation. In particular the
        // F-16 mixes roll command into the differential horizontal tails, so a
        // single generic elevator value cannot correctly animate both stabilators.
        state.leftAileronRadians = finiteFloat("fcs/left-aileron-pos-rad", fallback: 0)
        state.rightAileronRadians = finiteFloat("fcs/right-aileron-pos-rad", fallback: 0)
        state.leftStabilatorRadians = finiteFloat("fcs/dht-left-pos-rad", fallback: 0)
        state.rightStabilatorRadians = finiteFloat("fcs/dht-right-pos-rad", fallback: 0)
        state.rudderRadians = finiteFloat("fcs/rudder-pos-rad", fallback: 0)

        state.mainRotorRPM = 0
        state.tailRotorRPM = 0
        state.mainRotorPhaseRadians = 0
        state.tailRotorPhaseRadians = 0
    }

    private func evaluateFlightCondition(wasOnWheels: Bool, verticalSpeedBeforeStep: Float) {
        if !state.weightOnWheels && state.altitudeMeters > 8 {
            hasBeenAirborne = true
            flightCondition = .airborne
        }

        if hasBeenAirborne && !wasOnWheels && state.weightOnWheels {
            let touchdownFPM = max(0, -verticalSpeedBeforeStep * 196.8504)
            let badAttitude = abs(state.rollDegrees) > 24 || abs(state.pitchDegrees) > 22
            let gearUnsafe = state.gearPosition < 0.72

            if gearUnsafe {
                crash("GEAR-UP GROUND CONTACT")
            } else if touchdownFPM > 1_800 || badAttitude {
                crash(String(format: "HARD IMPACT · %.0f FPM", touchdownFPM))
            } else {
                flightCondition = .landed(touchdownFPM: touchdownFPM)
            }
        }

        if hasBeenAirborne,
           state.altitudeMeters < 1.2,
           state.gearPosition < 0.25,
           state.groundSpeedKnots > 70 {
            crash("AIRFRAME GROUND CONTACT")
        }
    }

    private func crash(_ reason: String) {
        flightCondition = .crashed(reason: reason)
        var stoppedControls = controls
        stoppedControls.throttle = 0
        stoppedControls.wheelBrake = 1
        controls = stoppedControls
        isPaused = true
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

    private func finiteFloat(_ property: String, fallback: Float) -> Float {
        let value = Float(bridge.value(forProperty: property))
        return value.isFinite ? value : fallback
    }

    private func clampFloat(_ value: Float, min minimum: Float, max maximum: Float) -> Float {
        Swift.min(Swift.max(value, minimum), maximum)
    }

    private func clamp(_ value: Double, min minimum: Double, max maximum: Double) -> Double {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}
