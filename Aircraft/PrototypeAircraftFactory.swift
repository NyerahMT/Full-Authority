import RealityKit
import UIKit

@MainActor
enum PrototypeAircraftFactory {
    static let aircraftName = "FA.aircraft"
    static let mainRotorName = "FA.mainRotor"
    static let tailRotorName = "FA.tailRotor"

    static func make() -> Entity {
        let root = Entity()
        root.name = aircraftName

        let olive = UIColor(red: 0.27, green: 0.31, blue: 0.23, alpha: 1)
        let oliveLight = UIColor(red: 0.34, green: 0.39, blue: 0.29, alpha: 1)
        let dark = UIColor(red: 0.06, green: 0.07, blue: 0.07, alpha: 1)
        let glass = UIColor(red: 0.06, green: 0.14, blue: 0.18, alpha: 1)

        let fuselage = block(size: [1.9, 0.72, 0.78], color: olive)
        root.addChild(fuselage)

        let upperDeck = block(size: [1.05, 0.28, 0.64], color: oliveLight)
        upperDeck.position = [0, 0.42, -0.12]
        root.addChild(upperDeck)

        let cockpit = block(size: [0.64, 0.56, 0.72], color: glass, metallic: true)
        cockpit.position = [0, 0.08, 0.84]
        root.addChild(cockpit)

        let tailBoom = block(size: [0.28, 0.28, 2.2], color: olive)
        tailBoom.position = [0, 0.08, -1.45]
        root.addChild(tailBoom)

        let verticalTail = block(size: [0.12, 0.82, 0.45], color: oliveLight)
        verticalTail.position = [0, 0.36, -2.45]
        root.addChild(verticalTail)

        let mast = ModelEntity(
            mesh: .generateCylinder(height: 0.42, radius: 0.055),
            materials: [SimpleMaterial(color: dark, isMetallic: true)]
        )
        mast.position = [0, 0.56, -0.08]
        root.addChild(mast)

        let mainRotor = Entity()
        mainRotor.name = mainRotorName
        mainRotor.position = [0, 0.86, -0.08]

        let rotorHub = ModelEntity(
            mesh: .generateCylinder(height: 0.08, radius: 0.11),
            materials: [SimpleMaterial(color: dark, isMetallic: true)]
        )
        mainRotor.addChild(rotorHub)

        mainRotor.addChild(block(size: [4.7, 0.035, 0.12], color: dark))
        mainRotor.addChild(block(size: [0.12, 0.035, 4.7], color: dark))
        root.addChild(mainRotor)

        let tailRotor = Entity()
        tailRotor.name = tailRotorName
        tailRotor.position = [0.18, 0.28, -2.58]

        let tailBladeA = block(size: [0.04, 0.92, 0.09], color: dark)
        tailRotor.addChild(tailBladeA)
        let tailBladeB = block(size: [0.04, 0.09, 0.92], color: dark)
        tailRotor.addChild(tailBladeB)
        root.addChild(tailRotor)

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

    private static func block(size: SIMD3<Float>, color: UIColor, metallic: Bool = false) -> ModelEntity {
        ModelEntity(
            mesh: .generateBox(size: size, cornerRadius: 0.025),
            materials: [SimpleMaterial(color: color, isMetallic: metallic)]
        )
    }
}
