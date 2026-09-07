import RealityKit
import SwiftUI
import UIKit
import simd

struct PrototypeSceneView: View {
    @ObservedObject var simulation: FlightSimulation

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            RealityView { content in
                content.camera = .virtual
                content.environment = .default

                let world = CalibrationWorldFactory.make()
                content.add(world)

                let aircraft = PrototypeAircraftFactory.make()
                aircraft.position = simulation.state.positionMeters
                aircraft.orientation = simulation.state.orientation
                content.add(aircraft)

                let camera = Entity()
                camera.name = "FA.camera"
                camera.components.set(PerspectiveCameraComponent(
                    near: 0.10,
                    far: 20_000,
                    fieldOfViewInDegrees: 67
                ))

                let initialTarget = simulation.state.positionMeters
                camera.look(
                    at: initialTarget + SIMD3<Float>(0, 0, 20),
                    from: initialTarget + SIMD3<Float>(6, 7, -26),
                    relativeTo: nil
                )
                content.add(camera)

                let sun = Entity()
                sun.name = "FA.sun"
                sun.components.set([
                    DirectionalLightComponent(color: .white, intensity: 16_000),
                    DirectionalLightComponent.Shadow()
                ])
                sun.look(at: .zero, from: [-3_000, 6_000, 2_000], relativeTo: nil)
                content.add(sun)
            } update: { content in
                guard let aircraft = content.entities.first(where: { $0.name == PrototypeAircraftFactory.aircraftName }) else {
                    return
                }

                aircraft.position = simulation.state.positionMeters
                aircraft.orientation = simulation.state.orientation

                if let camera = content.entities.first(where: { $0.name == "FA.camera" }) {
                    updateFollowCamera(camera)
                }
            }
            .onChange(of: timeline.date) { oldDate, newDate in
                simulation.advance(realDelta: newDate.timeIntervalSince(oldDate))
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.29, green: 0.49, blue: 0.70),
                    Color(red: 0.64, green: 0.73, blue: 0.78),
                    Color(red: 0.76, green: 0.72, blue: 0.60)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    @MainActor
    private func updateFollowCamera(_ camera: Entity) {
        let aircraftPosition = simulation.state.positionMeters
        let fullForward = simd_act(simulation.state.orientation, SIMD3<Float>(0, 0, 1))
        let horizontalForwardVector = SIMD3<Float>(fullForward.x, 0, fullForward.z)

        let horizontalForward: SIMD3<Float>
        if simd_length_squared(horizontalForwardVector) > 0.0001 {
            horizontalForward = simd_normalize(horizontalForwardVector)
        } else {
            horizontalForward = SIMD3<Float>(0, 0, 1)
        }

        let worldUp = SIMD3<Float>(0, 1, 0)
        let right = simd_normalize(simd_cross(worldUp, horizontalForward))

        let speed = simd_length(simulation.state.velocityMetersPerSecond)
        let speedPullback = min(speed * 0.055, 12.0)
        let speedLookAhead = min(speed * 0.12, 28.0)

        // Keep the camera mostly horizon-stable. This makes the aircraft's bank
        // and pitch readable instead of rotating the entire world with the jet.
        let desiredPosition = aircraftPosition
            - horizontalForward * (23.0 + speedPullback)
            + right * 1.2
            + worldUp * 7.0

        let lookTarget = aircraftPosition
            + fullForward * (15.0 + speedLookAhead)
            + worldUp * 0.6

        let smoothing: Float = speed > 90 ? 0.075 : 0.10
        let smoothedPosition = camera.position + (desiredPosition - camera.position) * smoothing
        camera.look(at: lookTarget, from: smoothedPosition, relativeTo: nil)
    }
}

@MainActor
private enum CalibrationWorldFactory {
    static func make() -> Entity {
        let root = Entity()
        root.name = "FA.world"

        let groundColor = UIColor(red: 0.23, green: 0.28, blue: 0.20, alpha: 1)
        let gridMinor = UIColor(red: 0.33, green: 0.37, blue: 0.29, alpha: 1)
        let gridMajor = UIColor(red: 0.46, green: 0.49, blue: 0.39, alpha: 1)
        let runwayColor = UIColor(red: 0.12, green: 0.13, blue: 0.14, alpha: 1)
        let markingColor = UIColor(white: 0.88, alpha: 1)
        let markerColor = UIColor(red: 0.94, green: 0.51, blue: 0.10, alpha: 1)

        // The grid is intentionally obvious: it provides scale, optic flow, and
        // closure-rate cues that the old single-color ground plane could not.
        let ground = block(size: [12_000, 0.10, 12_000], color: groundColor)
        ground.position = [0, -0.05, 0]
        root.addChild(ground)

        for offset in stride(from: -6_000, through: 6_000, by: 250) {
            let coordinate = Float(offset)
            let major = offset.isMultiple(of: 1_000)
            let color = major ? gridMajor : gridMinor
            let thickness: Float = major ? 2.0 : 0.75

            let northSouth = block(size: [thickness, 0.018, 12_000], color: color)
            northSouth.position = [coordinate, 0.012, 0]
            root.addChild(northSouth)

            let eastWest = block(size: [12_000, 0.018, thickness], color: color)
            eastWest.position = [0, 0.013, coordinate]
            root.addChild(eastWest)
        }

        let runway = block(size: [58, 0.06, 4_000], color: runwayColor)
        runway.position = [0, 0.03, 500]
        root.addChild(runway)

        for z in stride(from: -1_400, through: 2_400, by: 100) {
            let dash = block(size: [1.2, 0.025, 38], color: markingColor)
            dash.position = [0, 0.075, Float(z)]
            root.addChild(dash)
        }

        for x: Float in [-28, 28] {
            let edge = block(size: [0.8, 0.025, 4_000], color: markingColor)
            edge.position = [x, 0.075, 500]
            root.addChild(edge)
        }

        // Repeated vertical objects give much stronger near-field parallax than a
        // texture alone, especially on a phone display.
        for z in stride(from: -1_250, through: 2_250, by: 250) {
            for x: Float in [-72, 72] {
                let post = block(size: [2.0, 9.0, 2.0], color: markerColor)
                post.position = [x, 4.5, Float(z)]
                root.addChild(post)
            }
        }

        let landmarks: [(SIMD3<Float>, SIMD3<Float>, UIColor)] = [
            ([-900, 45, 1_000], [420, 90, 500], UIColor(red: 0.34, green: 0.31, blue: 0.23, alpha: 1)),
            ([1_100, 70, 1_650], [560, 140, 420], UIColor(red: 0.37, green: 0.33, blue: 0.24, alpha: 1)),
            ([-1_750, 110, 3_200], [900, 220, 700], UIColor(red: 0.30, green: 0.30, blue: 0.26, alpha: 1)),
            ([2_100, 150, 3_800], [1_100, 300, 900], UIColor(red: 0.31, green: 0.30, blue: 0.27, alpha: 1)),
            ([0, 230, 5_000], [1_800, 460, 850], UIColor(red: 0.29, green: 0.29, blue: 0.28, alpha: 1))
        ]

        for (position, size, color) in landmarks {
            let entity = block(size: size, color: color)
            entity.position = position
            root.addChild(entity)
        }

        return root
    }

    private static func block(size: SIMD3<Float>, color: UIColor) -> ModelEntity {
        ModelEntity(
            mesh: .generateBox(size: size, cornerRadius: 0),
            materials: [SimpleMaterial(color: color, isMetallic: false)]
        )
    }
}
