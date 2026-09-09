import Foundation
import ImageIO
import RealityKit

/// Loads the bundled CC0 Poly Haven pure-sky EXR into RealityKit. The deprecated
/// equirectangular initializer is intentional here: unlike the newer beta-only
/// creation APIs, it remains available on Full Authority's iOS 18 deployment floor.
@MainActor
enum Stage020SkyEnvironment {
    static func load() async -> EnvironmentResource? {
        guard let url = Bundle.main.url(
            forResource: "stage020_farm_field_puresky_1k",
            withExtension: "exr",
            subdirectory: "JSBSim/visuals/world"
        ),
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        return try? await EnvironmentResource(
            equirectangular: image,
            withName: "FA.stage020.farm-field-pure-sky"
        )
    }
}