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

                let world = FreeFlightWorldFactory.make()
                content.add(world)

                let aircraft = PrototypeAircraftFactory.make()
                aircraft.position = simulation.state.positionMeters
                aircraft.orientation = simulation.state.orientation
                content.add(aircraft)

                let camera = Entity()
                camera.name = "FA.camera"
                camera.components.set(PerspectiveCameraComponent(
                    near: 0.10,
                    far: 45_000,
                    fieldOfViewInDegrees: 59
                ))
                positionFixedChaseCamera(camera)
                content.add(camera)

                let sun = Entity()
                sun.name = "FA.sun"
                sun.components.set([
                    DirectionalLightComponent(
                        color: UIColor(red: 1.0, green: 0.94, blue: 0.82, alpha: 1),
                        intensity: 24_000
                    ),
                    DirectionalLightComponent.Shadow()
                ])
                sun.look(at: .zero, from: [-4_800, 7_500, -2_400], relativeTo: nil)
                content.add(sun)

                let fill = Entity()
                fill.name = "FA.fill"
                fill.components.set(DirectionalLightComponent(
                    color: UIColor(red: 0.63, green: 0.76, blue: 0.96, alpha: 1),
                    intensity: 4_200
                ))
                fill.look(at: .zero, from: [5_000, 3_000, 3_500], relativeTo: nil)
                content.add(fill)
            } update: { content in
                guard let aircraft = content.entities.first(where: { $0.name == PrototypeAircraftFactory.aircraftName }) else {
                    return
                }

                aircraft.position = simulation.state.positionMeters
                aircraft.orientation = simulation.state.orientation

                updateAircraftEffects(aircraft)

                if let camera = content.entities.first(where: { $0.name == "FA.camera" }) {
                    positionFixedChaseCamera(camera)
                }
            }
            .onChange(of: timeline.date) { oldDate, newDate in
                simulation.advance(realDelta: newDate.timeIntervalSince(oldDate))
            }
        }
        .background(
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.10, green: 0.30, blue: 0.58), location: 0.00),
                    .init(color: Color(red: 0.27, green: 0.52, blue: 0.75), location: 0.48),
                    .init(color: Color(red: 0.69, green: 0.75, blue: 0.75), location: 0.72),
                    .init(color: Color(red: 0.83, green: 0.75, blue: 0.60), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    @MainActor
    private func positionFixedChaseCamera(_ camera: Entity) {
        let aircraftPosition = simulation.state.positionMeters
        let attitude = simulation.state.orientation

        // This is intentionally aircraft-relative, not horizon-relative. When the
        // F-16 rolls or pitches, the camera rolls and pitches with it like a rigid
        // chase mount. No speed pullback and no world-up horizon correction.
        let localCameraOffset = SIMD3<Float>(0, 2.85, -13.2)
        let localLookPoint = SIMD3<Float>(0, -0.15, 5.4)
        let desiredPosition = aircraftPosition + simd_act(attitude, localCameraOffset)
        let lookTarget = aircraftPosition + simd_act(attitude, localLookPoint)
        let aircraftUp = simd_act(attitude, SIMD3<Float>(0, 1, 0))

        camera.look(
            at: lookTarget,
            from: desiredPosition,
            upVector: aircraftUp,
            relativeTo: nil
        )
    }

    @MainActor
    private func updateAircraftEffects(_ aircraft: Entity) {
        guard let afterburner = aircraft.findEntity(named: PrototypeAircraftFactory.afterburnerName) else {
            return
        }

        let intensity = max(0, min(1, (simulation.controls.throttle - 0.78) / 0.22))
        afterburner.isEnabled = intensity > 0.02
        afterburner.scale = [
            0.28 + intensity * 0.18,
            0.28 + intensity * 0.18,
            0.75 + intensity * 1.55
        ]
    }
}

@MainActor
private enum FreeFlightWorldFactory {
    static func make() -> Entity {
        let root = Entity()
        root.name = "FA.world"

        let grass = UIColor(red: 0.235, green: 0.31, blue: 0.17, alpha: 1)
        let fieldPalette: [UIColor] = [
            UIColor(red: 0.27, green: 0.35, blue: 0.18, alpha: 1),
            UIColor(red: 0.34, green: 0.39, blue: 0.20, alpha: 1),
            UIColor(red: 0.39, green: 0.39, blue: 0.20, alpha: 1),
            UIColor(red: 0.30, green: 0.33, blue: 0.16, alpha: 1),
            UIColor(red: 0.43, green: 0.41, blue: 0.23, alpha: 1)
        ]
        let asphalt = UIColor(red: 0.085, green: 0.092, blue: 0.098, alpha: 1)
        let roadColor = UIColor(red: 0.15, green: 0.155, blue: 0.15, alpha: 1)
        let concrete = UIColor(red: 0.43, green: 0.44, blue: 0.42, alpha: 1)
        let marking = UIColor(white: 0.90, alpha: 1)
        let water = UIColor(red: 0.10, green: 0.29, blue: 0.37, alpha: 0.92)

        let ground = block(size: [36_000, 0.12, 36_000], color: grass, cornerRadius: 0)
        ground.position = [0, -0.08, 2_000]
        root.addChild(ground)

        addFields(to: root, palette: fieldPalette)
        addAirbase(to: root, asphalt: asphalt, concrete: concrete, marking: marking)
        addRoadNetwork(to: root, roadColor: roadColor)
        addRiver(to: root, water: water)
        addTown(to: root)
        addTreeBelts(to: root)
        addDistantRelief(to: root)
        addCloudLayer(to: root)

        return root
    }

    private static func addFields(to root: Entity, palette: [UIColor]) {
        for xIndex in -6...6 {
            for zIndex in -5...7 {
                let selector = abs(xIndex * 11 + zIndex * 7)
                let color = palette[selector % palette.count]
                let xJitter = Float((zIndex * 37 + xIndex * 19) % 120)
                let zJitter = Float((xIndex * 29 - zIndex * 13) % 110)
                let width = Float(720 + selector % 190)
                let depth = Float(700 + (selector * 3) % 210)

                let patch = block(size: [width, 0.025, depth], color: color, cornerRadius: 1)
                patch.position = [
                    Float(xIndex) * 920 + xJitter,
                    0.012,
                    Float(zIndex) * 900 + zJitter + 1_500
                ]
                patch.orientation = simd_quatf(
                    angle: Float((selector % 7) - 3) * 0.008,
                    axis: [0, 1, 0]
                )
                root.addChild(patch)
            }
        }
    }

    private static func addAirbase(
        to root: Entity,
        asphalt: UIColor,
        concrete: UIColor,
        marking: UIColor
    ) {
        let runway = block(size: [64, 0.08, 4_600], color: asphalt, cornerRadius: 1)
        runway.position = [0, 0.075, 850]
        root.addChild(runway)

        for z in stride(from: -1_350, through: 3_050, by: 120) {
            let dash = block(size: [1.35, 0.025, 42], color: marking, cornerRadius: 0.08)
            dash.position = [0, 0.13, Float(z)]
            root.addChild(dash)
        }

        for x: Float in [-30.2, 30.2] {
            let edge = block(size: [0.7, 0.02, 4_540], color: marking, cornerRadius: 0.05)
            edge.position = [x, 0.13, 850]
            root.addChild(edge)
        }

        for endZ: Float in [-1_390, 3_090] {
            for stripe in -3...3 {
                let threshold = block(size: [5.0, 0.022, 26], color: marking, cornerRadius: 0)
                threshold.position = [Float(stripe) * 7.1, 0.132, endZ]
                root.addChild(threshold)
            }
        }

        let taxiway = block(size: [390, 0.06, 32], color: asphalt, cornerRadius: 2)
        taxiway.position = [205, 0.055, 560]
        root.addChild(taxiway)

        let parallelTaxiway = block(size: [28, 0.055, 2_400], color: asphalt, cornerRadius: 2)
        parallelTaxiway.position = [305, 0.05, 1_100]
        root.addChild(parallelTaxiway)

        let apron = block(size: [360, 0.065, 310], color: concrete, cornerRadius: 3)
        apron.position = [470, 0.05, 560]
        root.addChild(apron)

        for row in 0..<2 {
            for column in 0..<4 {
                let x = 365 + Float(column) * 88
                let z = 470 + Float(row) * 125
                addHangar(to: root, position: [x, 0, z])
            }
        }

        let towerShaft = block(
            size: [18, 46, 18],
            color: UIColor(red: 0.53, green: 0.52, blue: 0.47, alpha: 1),
            cornerRadius: 1
        )
        towerShaft.position = [675, 23, 720]
        root.addChild(towerShaft)

        let towerCab = block(
            size: [30, 10, 30],
            color: UIColor(red: 0.09, green: 0.17, blue: 0.20, alpha: 1),
            cornerRadius: 2
        )
        towerCab.position = [675, 49, 720]
        root.addChild(towerCab)
    }

    private static func addHangar(to root: Entity, position: SIMD3<Float>) {
        let body = block(
            size: [68, 17, 52],
            color: UIColor(red: 0.37, green: 0.38, blue: 0.36, alpha: 1),
            cornerRadius: 2
        )
        body.position = [position.x, 8.5, position.z]
        root.addChild(body)

        let door = block(
            size: [48, 11, 0.8],
            color: UIColor(red: 0.17, green: 0.18, blue: 0.18, alpha: 1),
            cornerRadius: 0.5
        )
        door.position = [position.x, 5.8, position.z - 26.2]
        root.addChild(door)
    }

    private static func addRoadNetwork(to root: Entity, roadColor: UIColor) {
        addRoad(to: root, size: [5_500, 0.032, 18], position: [1_350, 0.03, -620], yaw: 0.055, color: roadColor)
        addRoad(to: root, size: [18, 0.032, 6_200], position: [-1_100, 0.03, 2_050], yaw: -0.12, color: roadColor)
        addRoad(to: root, size: [5_100, 0.032, 16], position: [-1_000, 0.03, 3_650], yaw: -0.19, color: roadColor)
        addRoad(to: root, size: [3_800, 0.032, 15], position: [2_300, 0.03, 2_050], yaw: 0.31, color: roadColor)
        addRoad(to: root, size: [16, 0.032, 4_100], position: [2_650, 0.03, 2_850], yaw: 0.08, color: roadColor)
    }

    private static func addRiver(to root: Entity, water: UIColor) {
        for index in 0..<18 {
            let z = -3_000 + Float(index) * 650
            let x = -3_500 + sin(Float(index) * 0.62) * 520
            let segment = block(size: [165, 0.02, 720], color: water, cornerRadius: 45)
            segment.position = [x, 0.018, z]
            segment.orientation = simd_quatf(
                angle: cos(Float(index) * 0.58) * 0.18,
                axis: [0, 1, 0]
            )
            root.addChild(segment)
        }
    }

    private static func addTown(to root: Entity) {
        let wallColors: [UIColor] = [
            UIColor(red: 0.48, green: 0.46, blue: 0.40, alpha: 1),
            UIColor(red: 0.38, green: 0.40, blue: 0.41, alpha: 1),
            UIColor(red: 0.53, green: 0.50, blue: 0.43, alpha: 1),
            UIColor(red: 0.43, green: 0.42, blue: 0.39, alpha: 1)
        ]

        for row in 0..<5 {
            for column in 0..<7 {
                let selector = row * 7 + column
                let height = Float(18 + (selector * 13) % 54)
                let width = Float(34 + (selector * 7) % 28)
                let depth = Float(32 + (selector * 11) % 30)
                let building = block(
                    size: [width, height, depth],
                    color: wallColors[selector % wallColors.count],
                    cornerRadius: 1.2
                )
                building.position = [
                    2_250 + Float(column) * 115,
                    height * 0.5,
                    2_450 + Float(row) * 125
                ]
                root.addChild(building)

                let roof = block(
                    size: [width + 2, 1.4, depth + 2],
                    color: UIColor(red: 0.19, green: 0.20, blue: 0.20, alpha: 1),
                    cornerRadius: 0.4
                )
                roof.position = [building.position.x, height + 0.7, building.position.z]
                root.addChild(roof)
            }
        }
    }

    private static func addTreeBelts(to root: Entity) {
        let trunk = UIColor(red: 0.19, green: 0.12, blue: 0.065, alpha: 1)
        let greens: [UIColor] = [
            UIColor(red: 0.09, green: 0.22, blue: 0.075, alpha: 1),
            UIColor(red: 0.13, green: 0.27, blue: 0.09, alpha: 1),
            UIColor(red: 0.17, green: 0.30, blue: 0.10, alpha: 1)
        ]

        for belt in 0..<9 {
            let baseX = Float(-4_000 + belt * 900)
            let baseZ = Float(700 + (belt % 3) * 1_450)
            for treeIndex in 0..<8 {
                let height = Float(13 + ((belt * 17 + treeIndex * 7) % 10))
                addTree(
                    to: root,
                    position: [
                        baseX + Float(treeIndex) * 62,
                        0,
                        baseZ + sin(Float(treeIndex) * 0.9) * 95
                    ],
                    height: height,
                    trunkColor: trunk,
                    canopyColor: greens[(belt + treeIndex) % greens.count]
                )
            }
        }
    }

    private static func addDistantRelief(to root: Entity) {
        let relief: [(SIMD3<Float>, SIMD3<Float>, UIColor)] = [
            ([-7_200, -310, 7_000], [2_900, 650, 2_300], UIColor(red: 0.29, green: 0.31, blue: 0.22, alpha: 1)),
            ([7_800, -360, 8_600], [3_200, 760, 2_800], UIColor(red: 0.34, green: 0.33, blue: 0.23, alpha: 1)),
            ([-9_500, -520, 12_000], [4_200, 1_050, 3_300], UIColor(red: 0.30, green: 0.30, blue: 0.27, alpha: 1)),
            ([9_800, -580, 13_500], [4_600, 1_180, 3_800], UIColor(red: 0.32, green: 0.31, blue: 0.27, alpha: 1)),
            ([0, -820, 16_000], [6_500, 1_550, 3_600], UIColor(red: 0.30, green: 0.30, blue: 0.29, alpha: 1))
        ]

        for (position, radii, color) in relief {
            let hill = ellipsoid(radii: radii, color: color)
            hill.position = position
            root.addChild(hill)
        }
    }

    private static func addCloudLayer(to root: Entity) {
        let cloudColor = UIColor(red: 0.92, green: 0.94, blue: 0.96, alpha: 0.32)
        let clouds: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([-2_100, 1_150, 1_500], [420, 95, 235]),
            ([1_700, 1_300, 2_400], [520, 110, 280]),
            ([-4_200, 1_550, 5_200], [680, 135, 330]),
            ([4_100, 1_700, 6_500], [720, 145, 360]),
            ([-1_200, 2_000, 9_000], [920, 175, 430]),
            ([3_400, 2_150, 10_800], [1_050, 190, 500])
        ]

        for (position, radii) in clouds {
            let cloud = ellipsoid(radii: radii, color: cloudColor)
            cloud.position = position
            root.addChild(cloud)
        }
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
            mesh: .generateCylinder(height: trunkHeight, radius: height * 0.05),
            materials: [SimpleMaterial(color: trunkColor, isMetallic: false)]
        )
        trunk.position = [position.x, trunkHeight * 0.5, position.z]
        root.addChild(trunk)

        let canopy = ellipsoid(
            radii: [height * 0.25, height * 0.31, height * 0.25],
            color: canopyColor
        )
        canopy.position = [position.x, trunkHeight + height * 0.23, position.z]
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
