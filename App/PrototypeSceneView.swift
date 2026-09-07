import RealityKit
import SwiftUI
import UIKit
import simd

struct PrototypeSceneView: View {
    @ObservedObject var simulation: FlightSimulation

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            RealityView { content in
                content.camera = .virtual
                content.environment = .default

                let world = CalibrationWorldFactory.make()
                content.add(world)

                let aircraft = PrototypeAircraftFactory.make()
                aircraft.position = simulation.state.positionMeters
                aircraft.orientation = simulation.state.orientation
                content.add(aircraft)

                let camera = Entity()
                camera.name = "FA.camera"
                camera.components.set(PerspectiveCameraComponent(
                    near: 0.15,
                    far: 24_000,
                    fieldOfViewInDegrees: 62
                ))

                let initialTarget = simulation.state.positionMeters
                camera.look(
                    at: initialTarget + SIMD3<Float>(0, 0.8, 22),
                    from: initialTarget + SIMD3<Float>(3.2, 4.8, -16),
                    relativeTo: nil
                )
                content.add(camera)

                let sun = Entity()
                sun.name = "FA.sun"
                sun.components.set([
                    DirectionalLightComponent(color: .white, intensity: 20_000),
                    DirectionalLightComponent.Shadow()
                ])
                sun.look(at: .zero, from: [-3_800, 6_500, 2_200], relativeTo: nil)
                content.add(sun)

                let fill = Entity()
                fill.name = "FA.fill"
                fill.components.set(DirectionalLightComponent(
                    color: UIColor(red: 0.74, green: 0.83, blue: 1.0, alpha: 1),
                    intensity: 3_500
                ))
                fill.look(at: .zero, from: [4_000, 2_500, -3_000], relativeTo: nil)
                content.add(fill)
            } update: { content in
                guard let aircraft = content.entities.first(where: { $0.name == PrototypeAircraftFactory.aircraftName }) else {
                    return
                }

                aircraft.position = simulation.state.positionMeters
                aircraft.orientation = simulation.state.orientation

                if let camera = content.entities.first(where: { $0.name == "FA.camera" }) {
                    updateFollowCamera(camera)
                }
            }
            .onChange(of: timeline.date) { oldDate, newDate in
                simulation.advance(realDelta: newDate.timeIntervalSince(oldDate))
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.20, green: 0.43, blue: 0.70),
                    Color(red: 0.42, green: 0.61, blue: 0.78),
                    Color(red: 0.70, green: 0.76, blue: 0.77),
                    Color(red: 0.78, green: 0.72, blue: 0.58)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    @MainActor
    private func updateFollowCamera(_ camera: Entity) {
        let aircraftPosition = simulation.state.positionMeters
        let fullForward = simd_act(simulation.state.orientation, SIMD3<Float>(0, 0, 1))
        let horizontalForwardVector = SIMD3<Float>(fullForward.x, 0, fullForward.z)

        let horizontalForward: SIMD3<Float>
        if simd_length_squared(horizontalForwardVector) > 0.0001 {
            horizontalForward = simd_normalize(horizontalForwardVector)
        } else {
            horizontalForward = SIMD3<Float>(0, 0, 1)
        }

        let worldUp = SIMD3<Float>(0, 1, 0)
        let right = simd_normalize(simd_cross(worldUp, horizontalForward))

        let speed = simd_length(simulation.state.velocityMetersPerSecond)
        let speedPullback = min(max((speed - 90) * 0.025, 0), 3.5)
        let speedLookAhead = min(speed * 0.07, 13.0)

        // Significantly tighter than Stage 005. The camera remains horizon-stable
        // so pitch and bank are readable, but the aircraft now owns the frame.
        let desiredPosition = aircraftPosition
            - horizontalForward * (13.5 + speedPullback)
            + right * 0.8
            + worldUp * 4.8

        let lookTarget = aircraftPosition
            + fullForward * (9.0 + speedLookAhead)
            + worldUp * 0.75

        let smoothing: Float = speed > 90 ? 0.11 : 0.14
        let smoothedPosition = camera.position + (desiredPosition - camera.position) * smoothing
        camera.look(at: lookTarget, from: smoothedPosition, relativeTo: nil)
    }
}

@MainActor
private enum CalibrationWorldFactory {
    static func make() -> Entity {
        let root = Entity()
        root.name = "FA.world"

        let grass = UIColor(red: 0.25, green: 0.34, blue: 0.20, alpha: 1)
        let grassLight = UIColor(red: 0.31, green: 0.39, blue: 0.23, alpha: 1)
        let grassDry = UIColor(red: 0.43, green: 0.42, blue: 0.25, alpha: 1)
        let asphalt = UIColor(red: 0.105, green: 0.115, blue: 0.12, alpha: 1)
        let roadColor = UIColor(red: 0.18, green: 0.19, blue: 0.18, alpha: 1)
        let concrete = UIColor(red: 0.43, green: 0.44, blue: 0.42, alpha: 1)
        let marking = UIColor(white: 0.91, alpha: 1)
        let treeTrunk = UIColor(red: 0.22, green: 0.14, blue: 0.07, alpha: 1)
        let treeGreen = UIColor(red: 0.12, green: 0.25, blue: 0.09, alpha: 1)
        let treeLight = UIColor(red: 0.17, green: 0.31, blue: 0.11, alpha: 1)

        let ground = block(size: [16_000, 0.14, 16_000], color: grass, cornerRadius: 0)
        ground.position = [0, -0.08, 1_400]
        root.addChild(ground)

        // Large, rounded landforms replace the calibration mesas. They are visual
        // terrain for now; JSBSim still uses a flat collision/elevation plane.
        let hills: [(SIMD3<Float>, SIMD3<Float>, UIColor)] = [
            ([-1_150, -115, 1_100], [780, 195, 880], grassLight),
            ([1_450, -150, 1_900], [1_050, 260, 1_180], grassDry),
            ([-2_150, -240, 3_050], [1_500, 390, 1_300], grassLight),
            ([2_500, -310, 3_700], [1_850, 500, 1_650], grassDry),
            ([-3_400, -390, 5_450], [2_250, 650, 1_800], grassLight),
            ([3_900, -450, 6_200], [2_650, 760, 2_150], grassDry),
            ([0, -560, 7_500], [3_100, 920, 1_850], UIColor(red: 0.35, green: 0.35, blue: 0.28, alpha: 1))
        ]

        for (position, radii, color) in hills {
            let hill = ellipsoid(radii: radii, color: color)
            hill.position = position
            root.addChild(hill)
        }

        // A real runway/airfield cluster provides human scale and a strong sense
        // of speed during low passes.
        let runway = block(size: [62, 0.07, 4_200], color: asphalt, cornerRadius: 1.5)
        runway.position = [0, 0.035, 850]
        root.addChild(runway)

        for z in stride(from: -1_150, through: 2_850, by: 120) {
            let dash = block(size: [1.3, 0.025, 42], color: marking, cornerRadius: 0.1)
            dash.position = [0, 0.085, Float(z)]
            root.addChild(dash)
        }

        for x: Float in [-29.2, 29.2] {
            let edge = block(size: [0.7, 0.022, 4_160], color: marking, cornerRadius: 0.05)
            edge.position = [x, 0.084, 850]
            root.addChild(edge)
        }

        let taxiway = block(size: [290, 0.055, 30], color: asphalt, cornerRadius: 2)
        taxiway.position = [160, 0.03, 520]
        root.addChild(taxiway)

        let apron = block(size: [270, 0.06, 230], color: concrete, cornerRadius: 3)
        apron.position = [330, 0.03, 520]
        root.addChild(apron)

        for index in 0..<6 {
            let row = index / 3
            let column = index % 3
            let hangar = block(size: [62, 16, 45], color: UIColor(red: 0.36, green: 0.38, blue: 0.37, alpha: 1), cornerRadius: 2)
            hangar.position = [250 + Float(column) * 78, 8, 445 + Float(row) * 105]
            root.addChild(hangar)

            let roof = block(size: [66, 2.2, 49], color: UIColor(red: 0.28, green: 0.29, blue: 0.29, alpha: 1), cornerRadius: 1)
            roof.position = [hangar.position.x, 16.1, hangar.position.z]
            root.addChild(roof)
        }

        // Roads break up the field color and make lateral motion obvious.
        addRoad(to: root, size: [2_900, 0.03, 18], position: [1_150, 0.02, -350], yaw: 0.07, color: roadColor)
        addRoad(to: root, size: [18, 0.03, 3_500], position: [-680, 0.02, 1_850], yaw: -0.18, color: roadColor)
        addRoad(to: root, size: [2_400, 0.03, 15], position: [-1_250, 0.02, 2_650], yaw: -0.28, color: roadColor)

        // Tree groups use a small number of simple primitives. They are dense
        // enough for optic flow without becoming a draw-call disaster on iPhone.
        let treePositions: [SIMD3<Float>] = [
            [-420, 0, -650], [-330, 0, -530], [-500, 0, -420], [-260, 0, -300],
            [620, 0, -550], [760, 0, -420], [910, 0, -250], [1_050, 0, -90],
            [-820, 0, 350], [-940, 0, 520], [-1_020, 0, 680], [-780, 0, 850],
            [720, 0, 1_050], [850, 0, 1_220], [980, 0, 1_400], [1_120, 0, 1_560],
            [-1_200, 0, 1_550], [-1_350, 0, 1_700], [-1_470, 0, 1_880], [-1_100, 0, 2_050],
            [1_450, 0, 2_200], [1_620, 0, 2_350], [1_760, 0, 2_530], [1_900, 0, 2_700],
            [-1_900, 0, 2_450], [-2_050, 0, 2_620], [-2_200, 0, 2_800], [-2_350, 0, 2_980]
        ]

        for (index, position) in treePositions.enumerated() {
            let height: Float = 16 + Float(index % 5) * 2.1
            addTree(
                to: root,
                position: position,
                height: height,
                trunkColor: treeTrunk,
                canopyColor: index.isMultiple(of: 3) ? treeLight : treeGreen
            )
        }

        // Low-detail cloud banks add another depth layer above the terrain. The
        // alpha is intentionally restrained so they do not hide the horizon.
        let cloudColor = UIColor(red: 0.92, green: 0.94, blue: 0.95, alpha: 0.34)
        let clouds: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([-1_000, 650, 1_900], [260, 58, 150]),
            ([900, 720, 2_700], [330, 72, 180]),
            ([-2_100, 820, 4_200], [420, 90, 220]),
            ([2_400, 900, 4_700], [500, 105, 260]),
            ([0, 1_050, 6_000], [620, 120, 300])
        ]

        for (position, radii) in clouds {
            let cloud = ellipsoid(radii: radii, color: cloudColor)
            cloud.position = position
            root.addChild(cloud)
        }

        return root
    }

    private static func addRoad(
        to root: Entity,
        size: SIMD3<Float>,
        position: SIMD3<Float>,
        yaw: Float,
        color: UIColor
    ) {
        let road = block(size: size, color: color, cornerRadius: 1)
        road.position = position
        road.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        root.addChild(road)
    }

    private static func addTree(
        to root: Entity,
        position: SIMD3<Float>,
        height: Float,
        trunkColor: UIColor,
        canopyColor: UIColor
    ) {
        let trunkHeight = height * 0.38
        let trunk = ModelEntity(
            mesh: .generateCylinder(height: trunkHeight, radius: height * 0.055),
            materials: [SimpleMaterial(color: trunkColor, isMetallic: false)]
        )
        trunk.position = [position.x, trunkHeight * 0.5, position.z]
        root.addChild(trunk)

        let canopy = ellipsoid(
            radii: [height * 0.28, height * 0.33, height * 0.28],
            color: canopyColor
        )
        canopy.position = [position.x, trunkHeight + height * 0.24, position.z]
        root.addChild(canopy)
    }

    private static func ellipsoid(radii: SIMD3<Float>, color: UIColor) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateSphere(radius: 1),
            materials: [SimpleMaterial(color: color, isMetallic: false)]
        )
        entity.scale = radii
        return entity
    }

    private static func block(
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
