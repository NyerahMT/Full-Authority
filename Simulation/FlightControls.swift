import Foundation

struct FlightControls: Equatable, Sendable {
    /// Lateral cyclic. -1 = full left, +1 = full right.
    var cyclicRoll: Float = 0

    /// Longitudinal cyclic. -1 = full aft, +1 = full forward.
    var cyclicPitch: Float = 0

    /// Collective. 0 = minimum, 1 = maximum.
    var collective: Float = 0

    /// Anti-torque pedals. -1 = left, +1 = right.
    var pedals: Float = 0

    mutating func clampToValidRange() {
        cyclicRoll = cyclicRoll.clamped(to: -1...1)
        cyclicPitch = cyclicPitch.clamped(to: -1...1)
        collective = collective.clamped(to: 0...1)
        pedals = pedals.clamped(to: -1...1)
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
