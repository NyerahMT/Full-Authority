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
