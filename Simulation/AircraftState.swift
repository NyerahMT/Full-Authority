import Foundation
import simd

struct AircraftState: Equatable, Sendable {
    /// Local world position in meters. RealityKit mapping happens at the render boundary.
    var positionMeters: SIMD3<Float> = .zero

    /// Aircraft attitude in the game's local coordinate frame.
    var orientation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))

    var velocityMetersPerSecond: SIMD3<Float> = .zero
    var angularVelocityRadiansPerSecond: SIMD3<Float> = .zero

    /// Height above the real Stage 2 JSBSim terrain surface.
    var altitudeMeters: Float = 0
    var terrainElevationMeters: Float = 0
    var altitudeFeetMSL: Float = 0
    var airspeedMetersPerSecond: Float = 0
    var calibratedAirspeedKnots: Float = 0
    var groundSpeedKnots: Float = 0
    var verticalSpeedMetersPerSecond: Float = 0
    var headingDegrees: Float = 0
    var flightPathAngleDegrees: Float = 0

    /// Additional raw JSBSim telemetry used by the in-game HUD and presentation.
    var rollDegrees: Float = 0
    var pitchDegrees: Float = 0
    var mach: Float = 0
    var angleOfAttackDegrees: Float = 0
    var sideslipDegrees: Float = 0
    var loadFactorG: Float = 1
    var dynamicPressurePSF: Float = 0

    /// Atmospheric/propulsion telemetry used by weather-dependent visual effects.
    /// JSBSim remains authoritative for aircraft forces; these values only drive rendering.
    var ambientTemperatureC: Float = 15
    var ambientPressurePSF: Float = 2_116.22
    var airDensitySlugsPerCubicFoot: Float = 0.0023769
    var engineFuelFlowPoundsPerSecond: Float = 0
    var engineN1Percent: Float = 0
    var engineN2Percent: Float = 0
    var afterburnerActive = false
    var aircraftMassKg: Float = 9_500
    var windMetersPerSecond: SIMD3<Float> = .zero

    /// Actual system state read back from JSBSim rather than inferred from UI commands.
    var gearPosition: Float = 0
    var speedbrakePosition: Float = 0
    var weightOnWheels = false

    /// Legacy normalized surface values retained for presentation compatibility.
    var leftAileronPosition: Float = 0
    var rightAileronPosition: Float = 0
    var elevatorPosition: Float = 0
    var rudderPosition: Float = 0

    /// Actual F-16 surface angles from the JSBSim FCS. These are the values the
    /// renderer should use for hinge animation instead of guessed multipliers.
    var leftAileronRadians: Float = 0
    var rightAileronRadians: Float = 0
    var leftStabilatorRadians: Float = 0
    var rightStabilatorRadians: Float = 0
    var rudderRadians: Float = 0

    // Retained for the helicopter path when Full Authority returns to rotary wing.
    var mainRotorRPM: Float = 0
    var tailRotorRPM: Float = 0
    var mainRotorPhaseRadians: Float = 0
    var tailRotorPhaseRadians: Float = 0

    static let parked = AircraftState(positionMeters: SIMD3<Float>(0, 1.8, 0))
}
