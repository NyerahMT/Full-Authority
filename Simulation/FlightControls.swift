import Foundation

struct FlightControls: Equatable, Sendable {
    /// Lateral stick. -1 = full left, +1 = full right.
    var roll: Float = 0

    /// Longitudinal stick. -1 = full nose-down, +1 = full nose-up.
    var pitch: Float = 0

    /// Engine throttle. Stage 2 starts on the runway near idle.
    var throttle: Float = 0.05

    /// Rudder. -1 = full left, +1 = full right.
    var rudder: Float = 0

    /// Aircraft system commands passed directly into JSBSim.
    var gearDown = true
    var speedbrakeExtended = false

    /// Symmetric wheel-brake command. 0 = released, 1 = full braking.
    var wheelBrake: Float = 0

    mutating func clampToValidRange() {
        roll = roll.clamped(to: -1...1)
        pitch = pitch.clamped(to: -1...1)
        throttle = throttle.clamped(to: 0...1)
        rudder = rudder.clamped(to: -1...1)
        wheelBrake = wheelBrake.clamped(to: 0...1)
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
