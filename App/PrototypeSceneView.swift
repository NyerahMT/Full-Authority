import RealityKit
import SwiftUI
import UIKit

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
                    mesh: .generateBox(size: [40, 0.08, 40]),
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
                    far: 2_000,
                    fieldOfViewInDegrees: 55
                ))
                camera.look(at: [0, 0.65, 0], from: [5.2, 3.0, 6.8], relativeTo: nil)
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

                if let camera = content.entities.first(where: { $0.name == "FA.camera" }) {
                    let target = simulation.state.positionMeters + SIMD3<Float>(0, 0.25, 0)
                    let cameraPosition = simulation.state.positionMeters + SIMD3<Float>(5.2, 3.0, 6.8)
                    camera.look(at: target, from: cameraPosition, relativeTo: nil)
                }
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
}
