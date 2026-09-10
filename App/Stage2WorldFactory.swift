import RealityKit
import UIKit
import simd

/// Base scene content that is independent of a specific theater. Terrain,
/// airfields, roads and settlements now belong to the active theater renderer.
@MainActor
enum Stage2WorldFactory {
    static func make(includeLegacyRegionalRoads: Bool = true) -> Entity {
        let root = Entity()
        root.name = "FA.world.stage2"
        addCloudscape(to: root)
        return root
    }

    // MARK: - Atmosphere / cloudscape

    /// Mobile-friendly layered cloud cards retained from the proven Stage 017
    /// presentation. They are theater-independent and remain cheap at jet speed.
    private static func addCloudscape(to root: Entity) {
        let names = ["cloud_alpha_03", "cloud_alpha_05", "cloud_alpha_08"]
        let textures = names.compactMap(loadCloudTexture)
        guard !textures.isEmpty else { return }

        let cloudRoot = Entity()
        cloudRoot.name = "FA.world.cloudscape"

        for index in 0..<14 {
            let angle = Float(index) * 2.3999632 + 0.37
            let radius = Float(4_800 + (index * 1_917) % 10_800)
            let x = cos(angle) * radius
            let z = 2_000 + sin(angle) * radius
            let altitude = Float(2_200 + (index * 347) % 1_650)
            let width = Float(2_900 + (index * 733) % 3_700)
            let depth = Float(1_700 + (index * 419) % 2_700)
            let texture = textures[index % textures.count]

            let underside = cloudCard(
                texture: texture,
                size: [width, depth],
                tint: UIColor(red: 0.73, green: 0.76, blue: 0.79, alpha: 0.64)
            )
            underside.position = [x, altitude, z]
            underside.orientation = simd_quatf(
                angle: Float(index) * 0.71,
                axis: SIMD3<Float>(0, 1, 0)
            )
            cloudRoot.addChild(underside)

            let highlight = cloudCard(
                texture: textures[(index + 1) % textures.count],
                size: [width * 0.78, depth * 0.82],
                tint: UIColor(red: 0.94, green: 0.94, blue: 0.91, alpha: 0.34)
            )
            highlight.position = [x + 140, altitude + 135, z - 95]
            highlight.orientation = simd_quatf(
                angle: Float(index) * 0.71 + 0.42,
                axis: SIMD3<Float>(0, 1, 0)
            )
            cloudRoot.addChild(highlight)
        }

        for index in 0..<10 {
            let angle = Float(index) / 10 * 2 * Float.pi + 0.21
            let radius = Float(15_000 + (index * 1_037) % 4_800)
            let x = cos(angle) * radius
            let z = 2_000 + sin(angle) * radius
            let width = Float(5_000 + (index * 911) % 3_800)
            let height = Float(2_400 + (index * 557) % 2_100)
            let centerY = Float(2_300 + (index * 229) % 1_500)
            let texture = textures[(index + 2) % textures.count]

            let bank = cloudCard(
                texture: texture,
                size: [width, height],
                tint: UIColor(red: 0.86, green: 0.87, blue: 0.86, alpha: 0.50)
            )
            bank.position = [x, centerY, z]
            let pitch = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
            let yaw = simd_quatf(angle: -angle + .pi / 2, axis: SIMD3<Float>(0, 1, 0))
            bank.orientation = yaw * pitch
            cloudRoot.addChild(bank)
        }

        root.addChild(cloudRoot)
    }

    private static func loadCloudTexture(_ name: String) -> TextureResource? {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "JSBSim/visuals/world"
        ) else { return nil }
        return try? TextureResource.load(contentsOf: url, withName: name)
    }

    private static func cloudCard(
        texture: TextureResource,
        size: SIMD2<Float>,
        tint: UIColor
    ) -> ModelEntity {
        let map = MaterialParameters.Texture(texture)
        var material = UnlitMaterial()
        material.color = .init(tint: tint, texture: map)
        material.blending = .transparent(opacity: .init(texture: map))
        material.faceCulling = .none
        material.readsDepth = true
        material.writesDepth = false

        return ModelEntity(
            mesh: .generatePlane(width: size.x, depth: size.y),
            materials: [material]
        )
    }
}
