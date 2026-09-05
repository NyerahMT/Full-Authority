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
                    mesh: .generateBox(size: [160, 0.08, 160]),
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
                    far: 4_000,
                    fieldOfViewInDegrees: 58
                ))
                camera.look(at: [0, 0.8, 1.5], from: [2.2, 2.6, -6.5], relativeTo: nil)
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

                let seconds = Float(timeline.date.timeIntervalSinceReferenceDate)

                if let mainRotor = aircraft.findEntity(named: PrototypeAircraftFactory.mainRotorName) {
                    mainRotor.orientation = simd_quatf(
                        angle: seconds * 32,
                        axis: SIMD3<Float>(0, 1, 0)
                    )
                }

                if let tailRotor = aircraft.findEntity(named: PrototypeAircraftFactory.tailRotorName) {
                    tailRotor.orientation = simd_quatf(
                        angle: seconds * 115,
                        axis: SIMD3<Float>(1, 0, 0)
                    )
                }

                updateFollowCamera(in: content)
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
    private func updateFollowCamera(in content: RealityViewCameraContent) {
        guard let camera = content.entities.first(where: { $0.name == "FA.camera" }) else {
            return
        }

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

        // A game-style chase camera: mostly behind the aircraft, slightly to the
        // right and above. It follows heading, but deliberately does not inherit
        // every roll/pitch twitch from the flight model.
        let desiredPosition = aircraftPosition
            - horizontalForward * 6.6
            + right * 1.6
            + worldUp * 2.7

        let lookTarget = aircraftPosition
            + horizontalForward * 2.2
            + worldUp * 0.45

        // Ease the camera instead of rigidly bolting it to the aircraft.
        let smoothing: Float = 0.13
        let smoothedPosition = camera.position + (desiredPosition - camera.position) * smoothing
        camera.look(at: lookTarget, from: smoothedPosition, relativeTo: nil)
    }
}
