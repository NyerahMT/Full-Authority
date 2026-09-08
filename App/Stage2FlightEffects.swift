import Foundation
import RealityKit

@MainActor
enum Stage2FlightEffects {
    static let attachedRootName = "FA.effects.attached"
    static let trailRootName = "FA.effects.trails"

    @MainActor
    final class Runtime {}

    static func makeAttachedEffects() -> Entity {
        let root = Entity()
        root.name = attachedRootName
        root.isEnabled = false
        return root
    }

    static func makeTrailPool() -> Entity {
        let root = Entity()
        root.name = trailRootName
        root.isEnabled = false
        return root
    }

    static func updateAttachedEffects(
        aircraft: Entity,
        state: AircraftState,
        simulationTime: TimeInterval
    ) {
        // Stage 010.9 makes PrototypeAircraftFactory the sole owner of the
        // authored F-16 exhaust. The old R4 effect survived the PR #19 merge and
        // was the detached blue flame visible behind the new aircraft.
        aircraft.findEntity(named: "FA.effects.afterburner")?.isEnabled = false

        for oldName in [
            PrototypeAircraftFactory.vaporLeftName,
            PrototypeAircraftFactory.vaporRightName,
            PrototypeAircraftFactory.contrailLeftName,
            PrototypeAircraftFactory.contrailRightName,
            "FA.effects.vapor.left",
            "FA.effects.vapor.right"
        ] {
            aircraft.findEntity(named: oldName)?.isEnabled = false
        }

        _ = state
        _ = simulationTime
    }

    static func updateWorldTrails(
        root: Entity,
        state: AircraftState,
        simulationTime: TimeInterval,
        runtime: Runtime
    ) {
        root.isEnabled = false
        _ = state
        _ = simulationTime
        _ = runtime
    }
}
