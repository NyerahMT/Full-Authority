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

                let aircraft = PrototypeAircraftFactory.make()
                aircraft.position = simulation.state.positionMeters
                content.add(aircraft)

                let ground = ModelEntity(
                    mesh: .generateBox(size: [420, 0.08, 420]),
                    materials: [SimpleMaterial(
                        color: UIColor(red: 0.18, green: 0.21, blue: 0.18, alpha: 1),
                        isMetallic: false
                    )]
                )
                ground.name = "FA.ground"
                ground.position = [0, -0.04, 0]
                content.add(ground)

                let camera = Entity()
                camera.name = "FA.camera"
                camera.components.set(PerspectiveCameraComponent(
                    near: 0.05,
                    far: 5_000,
                    fieldOfViewInDegrees: 60
                ))
                camera.look(at: [0, 1.2, 1.5], from: [0.8, 3.0, -8.5], relativeTo: nil)
                content.add(camera)

                let sun = Entity()
                sun.name = "FA.sun"
                sun.components.set([
                    DirectionalLightComponent(color: .white, intensity: 18_000),
                    DirectionalLightComponent.Shadow()
                ])
                sun.look(at: .zero, from: [-4, 8, 5], relativeTo: nil)
                content.add(sun)
            } update: { content in
                guard let aircraft = content.entities.first(where: { $0.name == PrototypeAircraftFactory.aircraftName }) else {
                    return
                }

                aircraft.position = simulation.state.positionMeters
                aircraft.orientation = simulation.state.orientation

                if let mainRotor = aircraft.findEntity(named: PrototypeAircraftFactory.mainRotorName) {
                    mainRotor.orientation = simd_quatf(
                        angle: simulation.state.mainRotorPhaseRadians,
                        axis: SIMD3<Float>(0, 1, 0)
                    )
                }

                if let tailRotor = aircraft.findEntity(named: PrototypeAircraftFactory.tailRotorName) {
                    tailRotor.orientation = simd_quatf(
                        angle: simulation.state.tailRotorPhaseRadians,
                        axis: SIMD3<Float>(1, 0, 0)
                    )
                }

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
                    Color(red: 0.38, green: 0.54, blue: 0.68),
                    Color(red: 0.72, green: 0.72, blue: 0.64)
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
        let speedPullback = min(speed * 0.035, 2.5)

        let desiredPosition = aircraftPosition
            - horizontalForward * (8.2 + speedPullback)
            + right * 1.05
            + worldUp * 3.1

        let lookTarget = aircraftPosition
            + horizontalForward * (2.8 + min(speed * 0.025, 2.0))
            + worldUp * 0.55

        let smoothing: Float = speed > 18 ? 0.09 : 0.14
        let smoothedPosition = camera.position + (desiredPosition - camera.position) * smoothing
        camera.look(at: lookTarget, from: smoothedPosition, relativeTo: nil)
    }
}
