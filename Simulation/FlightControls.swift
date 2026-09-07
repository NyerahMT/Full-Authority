import Foundation

struct FlightControls: Equatable, Sendable {
    /// Lateral stick. -1 = full left, +1 = full right.
    var roll: Float = 0

    /// Longitudinal stick. -1 = full nose-down, +1 = full nose-up.
    var pitch: Float = 0

    /// Engine throttle. 0 = idle, 1 = maximum command.
    var throttle: Float = 0.72

    /// Rudder. -1 = full left, +1 = full right.
    var rudder: Float = 0

    mutating func clampToValidRange() {
        roll = roll.clamped(to: -1...1)
        pitch = pitch.clamped(to: -1...1)
        throttle = throttle.clamped(to: 0...1)
        rudder = rudder.clamped(to: -1...1)
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
