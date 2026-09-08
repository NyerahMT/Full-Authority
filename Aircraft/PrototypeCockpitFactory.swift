import Foundation
import RealityKit
import UIKit
import simd

@MainActor
enum PrototypeCockpitFactory {
    static let rootName = "FA.aircraft.cockpit"

    static func make() -> Entity {
        let root = Entity()
        root.name = rootName
        root.isEnabled = false

        let charcoal = SimpleMaterial(
            color: UIColor(red: 0.055, green: 0.060, blue: 0.062, alpha: 1),
            roughness: 0.82,
            isMetallic: false
        )
        let darkPanel = SimpleMaterial(
            color: UIColor(red: 0.075, green: 0.080, blue: 0.082, alpha: 1),
            roughness: 0.74,
            isMetallic: false
        )
        let console = SimpleMaterial(
            color: UIColor(red: 0.095, green: 0.100, blue: 0.100, alpha: 1),
            roughness: 0.68,
            isMetallic: false
        )
        let frame = SimpleMaterial(
            color: UIColor(red: 0.025, green: 0.028, blue: 0.030, alpha: 1),
            roughness: 0.44,
            isMetallic: true
        )
        let seatCushion = SimpleMaterial(
            color: UIColor(red: 0.145, green: 0.155, blue: 0.135, alpha: 1),
            roughness: 0.92,
            isMetallic: false
        )
        let belt = SimpleMaterial(
            color: UIColor(red: 0.55, green: 0.52, blue: 0.42, alpha: 1),
            roughness: 0.88,
            isMetallic: false
        )
        let screen = UnlitMaterial(color: UIColor(
            red: 0.018,
            green: 0.070,
            blue: 0.050,
            alpha: 1
        ))
        let screenGlow = UnlitMaterial(color: UIColor(
            red: 0.12,
            green: 0.52,
            blue: 0.31,
            alpha: 1
        ))
        let warning = UnlitMaterial(color: UIColor(
            red: 0.82,
            green: 0.23,
            blue: 0.055,
            alpha: 1
        ))

        // Cockpit tub and glareshield. The existing camera eyepoint is
        // [0, 0.88, 3.64], so every piece is built directly in the same authored
        // F-16 local frame rather than screen space.
        root.addChild(box(
            size: [1.18, 0.12, 2.25],
            position: [0, -0.02, 3.34],
            material: charcoal
        ))
        root.addChild(box(
            size: [0.12, 0.72, 2.12],
            position: [-0.72, 0.29, 3.43],
            material: charcoal
        ))
        root.addChild(box(
            size: [0.12, 0.72, 2.12],
            position: [0.72, 0.29, 3.43],
            material: charcoal
        ))

        let leftConsole = box(
            size: [0.46, 0.14, 1.55],
            position: [-0.52, 0.28, 3.43],
            material: console
        )
        leftConsole.orientation = simd_quatf(angle: -0.045, axis: [0, 0, 1])
        root.addChild(leftConsole)

        let rightConsole = box(
            size: [0.46, 0.14, 1.55],
            position: [0.52, 0.28, 3.43],
            material: console
        )
        rightConsole.orientation = simd_quatf(angle: 0.045, axis: [0, 0, 1])
        root.addChild(rightConsole)

        let mainPanel = box(
            size: [1.34, 0.66, 0.12],
            position: [0, 0.48, 4.17],
            material: darkPanel
        )
        mainPanel.orientation = simd_quatf(angle: -0.16, axis: [1, 0, 0])
        root.addChild(mainPanel)

        let glareshield = box(
            size: [1.36, 0.13, 0.52],
            position: [0, 0.79, 4.00],
            material: charcoal
        )
        glareshield.orientation = simd_quatf(angle: -0.08, axis: [1, 0, 0])
        root.addChild(glareshield)

        // Two low-poly MFDs and a center ICP/UFC stack. They are actual scene
        // geometry so free-look has real parallax immediately. Live symbology can
        // be rendered into them later without changing the cockpit mesh.
        addMFD(to: root, x: -0.31, y: 0.51, z: 4.095, screen: screen, bezel: frame)
        addMFD(to: root, x: 0.31, y: 0.51, z: 4.095, screen: screen, bezel: frame)

        let centerStack = box(
            size: [0.30, 0.22, 0.035],
            position: [0, 0.75, 4.085],
            material: frame
        )
        centerStack.orientation = simd_quatf(angle: -0.16, axis: [1, 0, 0])
        root.addChild(centerStack)

        let centerDisplay = box(
            size: [0.20, 0.055, 0.010],
            position: [0, 0.785, 4.064],
            material: screenGlow
        )
        centerDisplay.orientation = simd_quatf(angle: -0.16, axis: [1, 0, 0])
        root.addChild(centerDisplay)

        for row in 0..<2 {
            for column in 0..<5 {
                let button = box(
                    size: [0.034, 0.025, 0.012],
                    position: [
                        -0.080 + Float(column) * 0.040,
                        0.720 - Float(row) * 0.032,
                        4.064
                    ],
                    material: row == 0 && column == 4 ? warning : console
                )
                button.orientation = simd_quatf(angle: -0.16, axis: [1, 0, 0])
                root.addChild(button)
            }
        }

        // Physical HUD combiner and support posts. HUD/HMD symbology remains the
        // existing SwiftUI layer for now, but the glass and frame are truly 3D.
        var hudGlassMaterial = PhysicallyBasedMaterial()
        hudGlassMaterial.baseColor = .init(tint: UIColor(
            red: 0.20,
            green: 0.55,
            blue: 0.34,
            alpha: 1
        ))
        hudGlassMaterial.roughness = .init(floatLiteral: 0.08)
        hudGlassMaterial.metallic = .init(floatLiteral: 0.0)
        hudGlassMaterial.blending = .transparent(
            opacity: PhysicallyBasedMaterial.Opacity(floatLiteral: 0.10)
        )
        hudGlassMaterial.faceCulling = .none
        hudGlassMaterial.writesDepth = false

        let hudGlass = ModelEntity(
            mesh: .generatePlane(width: 0.50, depth: 0.30),
            materials: [hudGlassMaterial]
        )
        hudGlass.position = [0, 1.02, 4.30]
        hudGlass.orientation = simd_quatf(angle: .pi / 2 - 0.13, axis: [1, 0, 0])
        root.addChild(hudGlass)

        root.addChild(bar(
            from: [-0.29, 0.80, 4.14],
            to: [-0.27, 1.18, 4.30],
            radius: 0.020,
            material: frame
        ))
        root.addChild(bar(
            from: [0.29, 0.80, 4.14],
            to: [0.27, 1.18, 4.30],
            radius: 0.020,
            material: frame
        ))
        root.addChild(bar(
            from: [-0.27, 1.18, 4.30],
            to: [0.27, 1.18, 4.30],
            radius: 0.018,
            material: frame
        ))

        // ACES-style seat silhouette and rails, placed behind the eyepoint so it
        // appears naturally when checking six instead of being painted on-screen.
        let seatPan = box(
            size: [0.58, 0.13, 0.66],
            position: [0, 0.18, 3.05],
            material: seatCushion
        )
        seatPan.orientation = simd_quatf(angle: -0.12, axis: [1, 0, 0])
        root.addChild(seatPan)

        let seatBack = box(
            size: [0.58, 0.86, 0.15],
            position: [0, 0.57, 2.82],
            material: seatCushion
        )
        seatBack.orientation = simd_quatf(angle: -0.22, axis: [1, 0, 0])
        root.addChild(seatBack)

        root.addChild(box(
            size: [0.42, 0.30, 0.18],
            position: [0, 1.00, 2.72],
            material: charcoal
        ))
        root.addChild(bar(
            from: [-0.33, 0.17, 2.76],
            to: [-0.33, 1.16, 2.64],
            radius: 0.026,
            material: frame
        ))
        root.addChild(bar(
            from: [0.33, 0.17, 2.76],
            to: [0.33, 1.16, 2.64],
            radius: 0.026,
            material: frame
        ))

        let leftHarness = box(
            size: [0.055, 0.72, 0.025],
            position: [-0.16, 0.63, 2.72],
            material: belt
        )
        leftHarness.orientation = simd_quatf(angle: -0.28, axis: [0, 0, 1])
        root.addChild(leftHarness)
        let rightHarness = box(
            size: [0.055, 0.72, 0.025],
            position: [0.16, 0.63, 2.72],
            material: belt
        )
        rightHarness.orientation = simd_quatf(angle: 0.28, axis: [0, 0, 1])
        root.addChild(rightHarness)

        // Right-hand sidestick.
        root.addChild(ModelEntity(
            mesh: .generateCylinder(height: 0.28, radius: 0.035),
            materials: [frame]
        ).configured(position: [0.48, 0.47, 3.48]))
        let stickGrip = box(
            size: [0.105, 0.18, 0.10],
            position: [0.48, 0.65, 3.49],
            material: charcoal
        )
        stickGrip.orientation = simd_quatf(angle: -0.18, axis: [1, 0, 0])
        root.addChild(stickGrip)

        // Left throttle quadrant.
        root.addChild(box(
            size: [0.24, 0.10, 0.42],
            position: [-0.55, 0.42, 3.42],
            material: frame
        ))
        let throttleHandle = box(
            size: [0.15, 0.22, 0.16],
            position: [-0.55, 0.57, 3.43],
            material: charcoal
        )
        throttleHandle.orientation = simd_quatf(angle: -0.22, axis: [1, 0, 0])
        root.addChild(throttleHandle)

        // Console switch banks. The slight asymmetry keeps the cockpit from
        // reading as a sterile mirrored box while staying cheap on iPhone.
        addSwitchBank(to: root, x: -0.51, zStart: 3.02, rows: 7, material: frame)
        addSwitchBank(to: root, x: 0.51, zStart: 3.12, rows: 6, material: frame)

        // Canopy sill and rear bow. No fake center V-bars; the bubble remains
        // visually open ahead of the pilot.
        root.addChild(bar(
            from: [-0.78, 0.58, 2.75],
            to: [-0.78, 0.62, 4.18],
            radius: 0.030,
            material: frame
        ))
        root.addChild(bar(
            from: [0.78, 0.58, 2.75],
            to: [0.78, 0.62, 4.18],
            radius: 0.030,
            material: frame
        ))
        root.addChild(bar(
            from: [-0.72, 0.78, 2.72],
            to: [0, 1.38, 2.58],
            radius: 0.026,
            material: frame
        ))
        root.addChild(bar(
            from: [0.72, 0.78, 2.72],
            to: [0, 1.38, 2.58],
            radius: 0.026,
            material: frame
        ))

        return root
    }

    private static func addMFD(
        to root: Entity,
        x: Float,
        y: Float,
        z: Float,
        screen: UnlitMaterial,
        bezel: SimpleMaterial
    ) {
        let body = box(
            size: [0.42, 0.34, 0.040],
            position: [x, y, z],
            material: bezel
        )
        body.orientation = simd_quatf(angle: -0.16, axis: [1, 0, 0])
        root.addChild(body)

        let display = box(
            size: [0.31, 0.23, 0.012],
            position: [x, y + 0.003, z - 0.028],
            material: screen
        )
        display.orientation = simd_quatf(angle: -0.16, axis: [1, 0, 0])
        root.addChild(display)

        let buttonMaterial = SimpleMaterial(
            color: UIColor(red: 0.16, green: 0.17, blue: 0.17, alpha: 1),
            roughness: 0.74,
            isMetallic: false
        )
        for i in 0..<5 {
            let dx = -0.125 + Float(i) * 0.0625
            let top = box(
                size: [0.030, 0.020, 0.010],
                position: [x + dx, y + 0.145, z - 0.027],
                material: buttonMaterial
            )
            top.orientation = simd_quatf(angle: -0.16, axis: [1, 0, 0])
            root.addChild(top)

            let bottom = box(
                size: [0.030, 0.020, 0.010],
                position: [x + dx, y - 0.145, z + 0.012],
                material: buttonMaterial
            )
            bottom.orientation = simd_quatf(angle: -0.16, axis: [1, 0, 0])
            root.addChild(bottom)
        }
    }

    private static func addSwitchBank(
        to root: Entity,
        x: Float,
        zStart: Float,
        rows: Int,
        material: SimpleMaterial
    ) {
        for row in 0..<rows {
            for column in 0..<3 {
                let toggle = ModelEntity(
                    mesh: .generateCylinder(height: 0.055, radius: 0.010),
                    materials: [material]
                )
                toggle.position = [
                    x + Float(column - 1) * 0.085,
                    0.395,
                    zStart + Float(row) * 0.13
                ]
                toggle.orientation = simd_quatf(angle: 0.16, axis: [1, 0, 0])
                root.addChild(toggle)
            }
        }
    }

    private static func box<M: Material>(
        size: SIMD3<Float>,
        position: SIMD3<Float>,
        material: M
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateBox(size: size, cornerRadius: 0.015),
            materials: [material]
        )
        entity.position = position
        return entity
    }

    private static func bar<M: Material>(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        radius: Float,
        material: M
    ) -> ModelEntity {
        let delta = end - start
        let length = max(simd_length(delta), 0.001)
        let entity = ModelEntity(
            mesh: .generateCylinder(height: length, radius: radius),
            materials: [material]
        )
        entity.position = (start + end) * 0.5
        entity.orientation = simd_quatf(
            from: SIMD3<Float>(0, 1, 0),
            to: simd_normalize(delta)
        )
        return entity
    }
}

private extension ModelEntity {
    func configured(position: SIMD3<Float>) -> ModelEntity {
        self.position = position
        return self
    }
}
