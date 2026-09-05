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

        let olive = UIColor(red: 0.24, green: 0.28, blue: 0.20, alpha: 1)
        let oliveLight = UIColor(red: 0.32, green: 0.36, blue: 0.25, alpha: 1)
        let dark = UIColor(red: 0.045, green: 0.05, blue: 0.05, alpha: 1)
        let glass = UIColor(red: 0.035, green: 0.11, blue: 0.15, alpha: 1)

        // Long, narrow tandem-cockpit silhouette so the calibration mule reads
        // more like a Cobra and less like a crate with a rotor on it.
        let centerBody = block(size: [0.82, 0.82, 2.45], color: olive)
        centerBody.position = [0, 0.02, 0.20]
        root.addChild(centerBody)

        let nose = block(size: [0.68, 0.55, 0.92], color: oliveLight)
        nose.position = [0, -0.08, 1.65]
        root.addChild(nose)

        let frontCanopy = block(size: [0.58, 0.48, 0.66], color: glass, metallic: true)
        frontCanopy.position = [0, 0.28, 1.12]
        root.addChild(frontCanopy)

        let rearCanopy = block(size: [0.62, 0.55, 0.72], color: glass, metallic: true)
        rearCanopy.position = [0, 0.42, 0.45]
        root.addChild(rearCanopy)

        let engineDeck = block(size: [0.86, 0.42, 1.15], color: oliveLight)
        engineDeck.position = [0, 0.38, -0.58]
        root.addChild(engineDeck)

        let tailBoom = block(size: [0.30, 0.30, 3.35], color: olive)
        tailBoom.position = [0, 0.20, -2.15]
        root.addChild(tailBoom)

        let verticalTail = block(size: [0.12, 1.05, 0.72], color: oliveLight)
        verticalTail.position = [0, 0.62, -3.85]
        root.addChild(verticalTail)

        let leftWing = block(size: [1.35, 0.12, 0.58], color: oliveLight)
        leftWing.position = [-0.82, -0.05, -0.20]
        leftWing.orientation = .init(angle: 0.08, axis: [0, 0, 1])
        root.addChild(leftWing)

        let rightWing = block(size: [1.35, 0.12, 0.58], color: oliveLight)
        rightWing.position = [0.82, -0.05, -0.20]
        rightWing.orientation = .init(angle: -0.08, axis: [0, 0, 1])
        root.addChild(rightWing)

        let mast = ModelEntity(
            mesh: .generateCylinder(height: 0.52, radius: 0.055),
            materials: [SimpleMaterial(color: dark, isMetallic: true)]
        )
        mast.position = [0, 0.86, -0.25]
        root.addChild(mast)

        let mainRotor = Entity()
        mainRotor.name = mainRotorName
        mainRotor.position = [0, 1.12, -0.25]

        let rotorHub = ModelEntity(
            mesh: .generateCylinder(height: 0.08, radius: 0.12),
            materials: [SimpleMaterial(color: dark, isMetallic: true)]
        )
        mainRotor.addChild(rotorHub)

        // AH-1 family: visually use the distinctive two-blade main rotor.
        mainRotor.addChild(block(size: [6.15, 0.04, 0.14], color: dark))
        root.addChild(mainRotor)

        let tailRotor = Entity()
        tailRotor.name = tailRotorName
        tailRotor.position = [0.22, 0.55, -4.02]
        tailRotor.addChild(block(size: [0.04, 1.16, 0.10], color: dark))
        tailRotor.addChild(block(size: [0.04, 0.10, 1.16], color: dark))
        root.addChild(tailRotor)

        let skidLeft = block(size: [0.07, 0.07, 2.45], color: dark, metallic: true)
        skidLeft.position = [-0.52, -0.65, 0.0]
        root.addChild(skidLeft)

        let skidRight = block(size: [0.07, 0.07, 2.45], color: dark, metallic: true)
        skidRight.position = [0.52, -0.65, 0.0]
        root.addChild(skidRight)

        for x: Float in [-0.52, 0.52] {
            for z: Float in [-0.78, 0.78] {
                let strut = block(size: [0.055, 0.55, 0.055], color: dark, metallic: true)
                strut.position = [x, -0.42, z]
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
