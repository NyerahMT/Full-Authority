import SwiftUI
import RealityKit
import UIKit

struct PrototypeSceneView: View {
    var body: some View {
        RealityView { content in
            content.camera = .virtual
            content.environment = .default

            let aircraft = makePrototypeAircraft()
            aircraft.position = [0, 0.75, 0]
            content.add(aircraft)

            let ground = ModelEntity(
                mesh: .generateBox(size: [24, 0.08, 24]),
                materials: [SimpleMaterial(color: UIColor(red: 0.18, green: 0.21, blue: 0.18, alpha: 1), isMetallic: false)]
            )
            ground.position = [0, -0.04, 0]
            content.add(ground)

            let camera = Entity()
            camera.components.set(PerspectiveCameraComponent(near: 0.05, far: 500, fieldOfViewInDegrees: 55))
            camera.look(at: [0, 0.65, 0], from: [5.2, 3.0, 6.8], relativeTo: nil)
            content.add(camera)

            let sun = Entity()
            sun.components.set([
                DirectionalLightComponent(color: .white, intensity: 18_000),
                DirectionalLightComponent.Shadow()
            ])
            sun.look(at: .zero, from: [-4, 8, 5], relativeTo: nil)
            content.add(sun)
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
    private func makePrototypeAircraft() -> Entity {
        let root = Entity()

        let olive = UIColor(red: 0.27, green: 0.31, blue: 0.23, alpha: 1)
        let dark = UIColor(red: 0.08, green: 0.09, blue: 0.08, alpha: 1)
        let glass = UIColor(red: 0.10, green: 0.18, blue: 0.21, alpha: 1)

        let fuselage = block(size: [1.9, 0.72, 0.78], color: olive)
        fuselage.position = [0, 0, 0]
        root.addChild(fuselage)

        let cockpit = block(size: [0.62, 0.56, 0.72], color: glass, metallic: true)
        cockpit.position = [0, 0.08, 0.84]
        root.addChild(cockpit)

        let tailBoom = block(size: [0.28, 0.28, 2.2], color: olive)
        tailBoom.position = [0, 0.08, -1.45]
        root.addChild(tailBoom)

        let verticalTail = block(size: [0.12, 0.8, 0.45], color: olive)
        verticalTail.position = [0, 0.36, -2.45]
        root.addChild(verticalTail)

        let mast = ModelEntity(
            mesh: .generateCylinder(height: 0.42, radius: 0.055),
            materials: [SimpleMaterial(color: dark, isMetallic: true)]
        )
        mast.position = [0, 0.56, -0.08]
        root.addChild(mast)

        let rotorHub = ModelEntity(
            mesh: .generateCylinder(height: 0.08, radius: 0.11),
            materials: [SimpleMaterial(color: dark, isMetallic: true)]
        )
        rotorHub.position = [0, 0.80, -0.08]
        root.addChild(rotorHub)

        let bladeA = block(size: [4.7, 0.035, 0.12], color: dark)
        bladeA.position = [0, 0.86, -0.08]
        root.addChild(bladeA)

        let bladeB = block(size: [0.12, 0.035, 4.7], color: dark)
        bladeB.position = [0, 0.86, -0.08]
        root.addChild(bladeB)

        let skidLeft = block(size: [0.07, 0.07, 2.0], color: dark, metallic: true)
        skidLeft.position = [-0.58, -0.58, -0.05]
        root.addChild(skidLeft)

        let skidRight = block(size: [0.07, 0.07, 2.0], color: dark, metallic: true)
        skidRight.position = [0.58, -0.58, -0.05]
        root.addChild(skidRight)

        for x: Float in [-0.58, 0.58] {
            for z: Float in [-0.62, 0.58] {
                let strut = block(size: [0.055, 0.48, 0.055], color: dark, metallic: true)
                strut.position = [x, -0.36, z]
                root.addChild(strut)
            }
        }

        return root
    }

    @MainActor
    private func block(size: SIMD3<Float>, color: UIColor, metallic: Bool = false) -> ModelEntity {
        ModelEntity(
            mesh: .generateBox(size: size, cornerRadius: 0.025),
            materials: [SimpleMaterial(color: color, isMetallic: metallic)]
        )
    }
}
