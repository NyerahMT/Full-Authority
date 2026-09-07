import RealityKit
import UIKit

@MainActor
enum PrototypeAircraftFactory {
    static let aircraftName = "FA.aircraft"

    static func make() -> Entity {
        let root = Entity()
        root.name = aircraftName

        let bodyColor = UIColor(red: 0.42, green: 0.45, blue: 0.47, alpha: 1)
        let bodyLight = UIColor(red: 0.52, green: 0.55, blue: 0.57, alpha: 1)
        let bodyDark = UIColor(red: 0.19, green: 0.21, blue: 0.22, alpha: 1)
        let glass = UIColor(red: 0.05, green: 0.14, blue: 0.19, alpha: 1)

        // A deliberately simple F-15-ish calibration silhouette. This is not a
        // production aircraft asset; its job is to make pitch, roll, yaw, and
        // closure rate visually obvious while the FDM/render bridge is tuned.
        let fuselage = block(size: [1.20, 0.82, 5.30], color: bodyColor)
        fuselage.position = [0, 0, 0.15]
        root.addChild(fuselage)

        let nose = block(size: [0.78, 0.58, 2.00], color: bodyLight)
        nose.position = [0, -0.05, 3.55]
        root.addChild(nose)

        let canopy = block(size: [0.76, 0.43, 1.45], color: glass, metallic: true)
        canopy.position = [0, 0.55, 2.15]
        root.addChild(canopy)

        // Twin engine nacelles help the aircraft read immediately as a jet from
        // the chase camera, even at phone-screen scale.
        for x: Float in [-0.66, 0.66] {
            let nacelle = block(size: [0.72, 0.72, 3.25], color: bodyDark, metallic: true)
            nacelle.position = [x, -0.20, -1.55]
            root.addChild(nacelle)

            let exhaust = block(size: [0.55, 0.55, 0.28], color: .black, metallic: true)
            exhaust.position = [x, -0.20, -3.30]
            root.addChild(exhaust)
        }

        let leftWing = block(size: [4.10, 0.12, 1.55], color: bodyColor)
        leftWing.position = [-2.05, -0.03, -0.30]
        leftWing.orientation = .init(angle: 0.16, axis: [0, 1, 0])
        root.addChild(leftWing)

        let rightWing = block(size: [4.10, 0.12, 1.55], color: bodyColor)
        rightWing.position = [2.05, -0.03, -0.30]
        rightWing.orientation = .init(angle: -0.16, axis: [0, 1, 0])
        root.addChild(rightWing)

        let leftTailplane = block(size: [2.15, 0.10, 0.78], color: bodyLight)
        leftTailplane.position = [-1.30, 0.02, -3.10]
        leftTailplane.orientation = .init(angle: 0.10, axis: [0, 1, 0])
        root.addChild(leftTailplane)

        let rightTailplane = block(size: [2.15, 0.10, 0.78], color: bodyLight)
        rightTailplane.position = [1.30, 0.02, -3.10]
        rightTailplane.orientation = .init(angle: -0.10, axis: [0, 1, 0])
        root.addChild(rightTailplane)

        for x: Float in [-0.70, 0.70] {
            let tail = block(size: [0.14, 1.65, 1.08], color: bodyColor)
            tail.position = [x, 0.88, -2.90]
            tail.orientation = .init(angle: x < 0 ? -0.08 : 0.08, axis: [0, 0, 1])
            root.addChild(tail)
        }

        // A bright belly stripe gives a strong orientation cue during rolls.
        let bellyStripe = block(
            size: [0.18, 0.04, 4.70],
            color: UIColor(red: 0.88, green: 0.56, blue: 0.16, alpha: 1)
        )
        bellyStripe.position = [0, -0.44, 0.05]
        root.addChild(bellyStripe)

        return root
    }

    private static func block(size: SIMD3<Float>, color: UIColor, metallic: Bool = false) -> ModelEntity {
        ModelEntity(
            mesh: .generateBox(size: size, cornerRadius: 0.025),
            materials: [SimpleMaterial(color: color, isMetallic: metallic)]
        )
    }
}
