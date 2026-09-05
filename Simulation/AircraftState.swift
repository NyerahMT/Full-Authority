import Foundation
import simd

struct AircraftState: Equatable, Sendable {
    /// Local world position in meters. RealityKit mapping happens at the render boundary.
    var positionMeters: SIMD3<Float> = .zero

    /// Aircraft attitude in the game's local coordinate frame.
    var orientation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))

    var velocityMetersPerSecond: SIMD3<Float> = .zero
    var angularVelocityRadiansPerSecond: SIMD3<Float> = .zero

    var altitudeMeters: Float = 0
    var airspeedMetersPerSecond: Float = 0
    var verticalSpeedMetersPerSecond: Float = 0
    var headingDegrees: Float = 0

    var mainRotorRPM: Float = 0
    var tailRotorRPM: Float = 0
    var mainRotorPhaseRadians: Float = 0
    var tailRotorPhaseRadians: Float = 0

    static let parked = AircraftState(positionMeters: SIMD3<Float>(0, 1.9, 0))
}
