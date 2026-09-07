import RealityKit
import UIKit
import simd

@MainActor
enum PrototypeAircraftFactory {
    static let aircraftName = "FA.aircraft"

    static func make() -> Entity {
        let root = Entity()
        root.name = aircraftName

        let upperGray = UIColor(red: 0.40, green: 0.43, blue: 0.45, alpha: 1)
        let lowerGray = UIColor(red: 0.50, green: 0.52, blue: 0.53, alpha: 1)
        let darkGray = UIColor(red: 0.16, green: 0.18, blue: 0.19, alpha: 1)
        let edgeGray = UIColor(red: 0.30, green: 0.32, blue: 0.33, alpha: 1)
        let glass = UIColor(red: 0.06, green: 0.15, blue: 0.19, alpha: 0.96)
        let intakeDark = UIColor(red: 0.055, green: 0.06, blue: 0.065, alpha: 1)

        // Stage 006 targets a stylized-realistic silhouette: real proportions and
        // recognizable major forms, without spending mobile GPU budget on tiny
        // panel/rivet geometry. The physics aircraft remains JSBSim's F-15.
        let mainBody = ellipsoid(radii: [1.28, 0.76, 6.20], color: upperGray, metallic: true)
        mainBody.position = [0, 0.06, 0.55]
        root.addChild(mainBody)

        let lowerBody = ellipsoid(radii: [1.06, 0.53, 4.70], color: lowerGray, metallic: true)
        lowerBody.position = [0, -0.40, -0.20]
        root.addChild(lowerBody)

        let nose = ellipsoid(radii: [0.82, 0.56, 3.55], color: upperGray, metallic: true)
        nose.position = [0, -0.02, 6.20]
        root.addChild(nose)

        let radome = ellipsoid(radii: [0.55, 0.43, 1.52], color: darkGray, metallic: false)
        radome.position = [0, -0.03, 8.25]
        root.addChild(radome)

        let canopy = ellipsoid(radii: [0.68, 0.42, 1.72], color: glass, metallic: true)
        canopy.position = [0, 0.70, 3.70]
        root.addChild(canopy)

        let canopyFrame = roundedBlock(size: [0.10, 0.48, 2.50], color: edgeGray, cornerRadius: 0.04)
        canopyFrame.position = [0, 0.71, 3.45]
        root.addChild(canopyFrame)

        // Twin inlet trunks and nacelles give the rear three-quarter view the
        // unmistakable Eagle shape that the Stage 005 boxes could not provide.
        for x: Float in [-1.02, 1.02] {
            let inlet = roundedBlock(size: [1.18, 0.82, 2.85], color: intakeDark, cornerRadius: 0.18)
            inlet.position = [x, -0.08, 1.65]
            root.addChild(inlet)

            let inletLip = roundedBlock(size: [1.32, 0.96, 0.18], color: lowerGray, cornerRadius: 0.10)
            inletLip.position = [x, -0.08, 3.05]
            root.addChild(inletLip)

            let nacelle = cylinder(length: 5.85, radius: 0.61, color: darkGray, metallic: true)
            nacelle.position = [x, -0.35, -2.45]
            root.addChild(nacelle)

            let exhaustOuter = cylinder(length: 0.72, radius: 0.67, color: edgeGray, metallic: true)
            exhaustOuter.position = [x, -0.35, -5.67]
            root.addChild(exhaustOuter)

            let exhaustInner = cylinder(length: 0.78, radius: 0.43, color: .black, metallic: true)
            exhaustInner.position = [x, -0.35, -5.78]
            root.addChild(exhaustInner)
        }

        // Swept wings are built from tapered visual segments. They read far more
        // naturally than one rectangular slab while remaining very inexpensive.
        addWing(to: root, side: -1, upperGray: upperGray, edgeGray: edgeGray)
        addWing(to: root, side: 1, upperGray: upperGray, edgeGray: edgeGray)

        addTailplane(to: root, side: -1, color: upperGray)
        addTailplane(to: root, side: 1, color: upperGray)

        for x: Float in [-1.02, 1.02] {
            let fin = roundedBlock(size: [0.18, 2.95, 2.45], color: upperGray, cornerRadius: 0.07)
            fin.position = [x, 1.32, -4.15]
            fin.orientation = simd_quatf(angle: x < 0 ? -0.10 : 0.10, axis: [0, 0, 1])
            root.addChild(fin)

            let finCap = roundedBlock(size: [0.22, 0.30, 1.42], color: edgeGray, cornerRadius: 0.08)
            finCap.position = [x, 2.70, -4.55]
            finCap.orientation = fin.orientation
            root.addChild(finCap)
        }

        // Subtle high-contrast underside stripe remains as a gameplay cue; unlike
        // the previous orange bar, this is narrow enough not to dominate the art.
        let orientationStripe = roundedBlock(
            size: [0.14, 0.035, 6.3],
            color: UIColor(red: 0.84, green: 0.46, blue: 0.11, alpha: 1),
            cornerRadius: 0.02
        )
        orientationStripe.position = [0, -0.96, -0.60]
        root.addChild(orientationStripe)

        return root
    }

    private static func addWing(
        to root: Entity,
        side: Float,
        upperGray: UIColor,
        edgeGray: UIColor
    ) {
        let direction: Float = side < 0 ? -1 : 1
        let yaw: Float = side < 0 ? 0.19 : -0.19

        let inner = roundedBlock(size: [3.05, 0.14, 3.05], color: upperGray, cornerRadius: 0.06)
        inner.position = [direction * 2.15, -0.02, -0.10]
        inner.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        root.addChild(inner)

        let middle = roundedBlock(size: [2.15, 0.12, 2.28], color: upperGray, cornerRadius: 0.05)
        middle.position = [direction * 4.50, -0.03, -0.86]
        middle.orientation = simd_quatf(angle: yaw * 1.08, axis: [0, 1, 0])
        root.addChild(middle)

        let tip = roundedBlock(size: [1.25, 0.10, 1.52], color: edgeGray, cornerRadius: 0.05)
        tip.position = [direction * 6.15, -0.04, -1.47]
        tip.orientation = simd_quatf(angle: yaw * 1.16, axis: [0, 1, 0])
        root.addChild(tip)
    }

    private static func addTailplane(to root: Entity, side: Float, color: UIColor) {
        let direction: Float = side < 0 ? -1 : 1
        let yaw: Float = side < 0 ? 0.20 : -0.20

        let tailplane = roundedBlock(size: [2.70, 0.10, 1.58], color: color, cornerRadius: 0.05)
        tailplane.position = [direction * 2.05, 0.02, -4.45]
        tailplane.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        root.addChild(tailplane)
    }

    private static func ellipsoid(
        radii: SIMD3<Float>,
        color: UIColor,
        metallic: Bool
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateSphere(radius: 1),
            materials: [SimpleMaterial(color: color, isMetallic: metallic)]
        )
        entity.scale = radii
        return entity
    }

    private static func cylinder(
        length: Float,
        radius: Float,
        color: UIColor,
        metallic: Bool
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateCylinder(height: length, radius: radius),
            materials: [SimpleMaterial(color: color, isMetallic: metallic)]
        )
        entity.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        return entity
    }

    private static func roundedBlock(
        size: SIMD3<Float>,
        color: UIColor,
        cornerRadius: Float
    ) -> ModelEntity {
        ModelEntity(
            mesh: .generateBox(size: size, cornerRadius: cornerRadius),
            materials: [SimpleMaterial(color: color, isMetallic: false)]
        )
    }
}
