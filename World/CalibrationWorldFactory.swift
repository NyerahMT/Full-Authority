import RealityKit
import UIKit

@MainActor
enum CalibrationWorldFactory {
    static let worldName = "FA.world"

    static func make() -> Entity {
        let root = Entity()
        root.name = worldName

        let groundColor = UIColor(red: 0.23, green: 0.28, blue: 0.20, alpha: 1)
        let gridMinor = UIColor(red: 0.33, green: 0.37, blue: 0.29, alpha: 1)
        let gridMajor = UIColor(red: 0.46, green: 0.49, blue: 0.39, alpha: 1)
        let runwayColor = UIColor(red: 0.12, green: 0.13, blue: 0.14, alpha: 1)
        let markingColor = UIColor(white: 0.88, alpha: 1)
        let markerColor = UIColor(red: 0.94, green: 0.51, blue: 0.10, alpha: 1)

        // Large flat calibration surface. The grid supplies optic flow and scale
        // while the runway and raised landmarks make altitude visually legible.
        let ground = block(size: [12_000, 0.10, 12_000], color: groundColor)
        ground.position = [0, -0.05, 0]
        root.addChild(ground)

        for offset in stride(from: -6_000, through: 6_000, by: 250) {
            let coordinate = Float(offset)
            let major = offset.isMultiple(of: 1_000)
            let color = major ? gridMajor : gridMinor
            let thickness: Float = major ? 2.0 : 0.75

            let northSouth = block(size: [thickness, 0.018, 12_000], color: color)
            northSouth.position = [coordinate, 0.012, 0]
            root.addChild(northSouth)

            let eastWest = block(size: [12_000, 0.018, thickness], color: color)
            eastWest.position = [0, 0.013, coordinate]
            root.addChild(eastWest)
        }

        // A long runway gives an unmistakable straight reference and a strong
        // sense of closure rate when descending or flying low.
        let runway = block(size: [58, 0.06, 4_000], color: runwayColor)
        runway.position = [0, 0.03, 500]
        root.addChild(runway)

        for z in stride(from: -1_400, through: 2_400, by: 100) {
            let dash = block(size: [1.2, 0.025, 38], color: markingColor)
            dash.position = [0, 0.075, Float(z)]
            root.addChild(dash)
        }

        for x: Float in [-28, 28] {
            let edge = block(size: [0.8, 0.025, 4_000], color: markingColor)
            edge.position = [x, 0.075, 500]
            root.addChild(edge)
        }

        // Tall orange reference posts create near-field parallax. They are kept
        // outside the runway so they are useful without becoming obstacles yet.
        for z in stride(from: -1_250, through: 2_250, by: 250) {
            for x: Float in [-72, 72] {
                let post = block(size: [2.0, 9.0, 2.0], color: markerColor)
                post.position = [x, 4.5, Float(z)]
                root.addChild(post)
            }
        }

        // Deliberately chunky terrain landmarks. Their different heights and
        // distances are more valuable for calibration than photorealism because
        // they make pitch, altitude, and lateral motion obvious at a glance.
        let landmarks: [(position: SIMD3<Float>, size: SIMD3<Float>, color: UIColor)] = [
            ([-900, 45, 1_000], [420, 90, 500], UIColor(red: 0.34, green: 0.31, blue: 0.23, alpha: 1)),
            ([1_100, 70, 1_650], [560, 140, 420], UIColor(red: 0.37, green: 0.33, blue: 0.24, alpha: 1)),
            ([-1_750, 110, 3_200], [900, 220, 700], UIColor(red: 0.30, green: 0.30, blue: 0.26, alpha: 1)),
            ([2_100, 150, 3_800], [1_100, 300, 900], UIColor(red: 0.31, green: 0.30, blue: 0.27, alpha: 1)),
            ([0, 230, 5_000], [1_800, 460, 850], UIColor(red: 0.29, green: 0.29, blue: 0.28, alpha: 1))
        ]

        for landmark in landmarks {
            let entity = block(size: landmark.size, color: landmark.color)
            entity.position = landmark.position
            root.addChild(entity)
        }

        return root
    }

    private static func block(size: SIMD3<Float>, color: UIColor) -> ModelEntity {
        ModelEntity(
            mesh: .generateBox(size: size, cornerRadius: 0),
            materials: [SimpleMaterial(color: color, isMetallic: false)]
        )
    }
}
