import RealityKit
import UIKit
import simd

/// Lightweight aerial perspective for the iPhone renderer.
///
/// This deliberately avoids a full-screen color grade. Three translucent shells
/// sit at increasing real-world distances from the aircraft. Near terrain remains
/// untouched; terrain behind a shell progressively loses contrast like real haze.
@MainActor
enum Stage021Atmosphere {
    static let rootName = "FA.world.stage021.atmosphere"

    static func make() -> Entity {
        let root = Entity()
        root.name = rootName

        guard let texture = loadHazeTexture() else { return root }

        let shells: [(radius: Float, opacity: Float)] = [
            (11_500, 0.22),
            (23_500, 0.16),
            (46_000, 0.11)
        ]

        for (index, shell) in shells.enumerated() {
            let map = MaterialParameters.Texture(texture)
            var material = UnlitMaterial()
            material.color = .init(
                tint: UIColor(white: 1.0, alpha: CGFloat(shell.opacity)),
                texture: map
            )
            material.blending = .transparent(opacity: .init(texture: map))
            material.faceCulling = .front
            material.readsDepth = true
            material.writesDepth = false

            let sphere = ModelEntity(
                mesh: .generateSphere(radius: shell.radius),
                materials: [material]
            )
            sphere.name = "FA.world.stage021.haze.\(index)"
            root.addChild(sphere)
        }

        return root
    }

    /// Follow horizontal aircraft position while keeping the atmosphere centered
    /// on mean ground level. That lets altitude naturally change the visible
    /// horizon instead of gluing a haze band to the camera.
    static func update(_ root: Entity, aircraftPosition: SIMD3<Float>) {
        root.position = [aircraftPosition.x, 0, aircraftPosition.z]
    }

    private static func loadHazeTexture() -> TextureResource? {
        guard let url = Bundle.main.url(
            forResource: "stage021_haze",
            withExtension: "png",
            subdirectory: "JSBSim/visuals/world"
        ) else { return nil }
        return try? TextureResource.load(contentsOf: url, withName: "stage021_haze")
    }
}
