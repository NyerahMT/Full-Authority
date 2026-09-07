import RealityKit
import SwiftUI
import UIKit
import simd

struct PrototypeSceneView: View {
    @ObservedObject var simulation: FlightSimulation
    @State private var cameraMode: CameraMode = .chase

    private enum CameraMode: String, CaseIterable {
        case chase = "CHASE"
        case close = "CLOSE"
        case cockpit = "COCKPIT"

        var next: CameraMode {
            let all = CameraMode.allCases
            guard let index = all.firstIndex(of: self) else { return .chase }
            return all[(index + 1) % all.count]
        }
    }

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                RealityView { content in
                    content.camera = .virtual
                    content.environment = .default

                    let world = Stage2WorldFactory.make()
                    content.add(world)

                    let aircraft = PrototypeAircraftFactory.make()
                    aircraft.position = simulation.state.positionMeters
                    aircraft.orientation = simulation.state.orientation
                    content.add(aircraft)

                    let camera = Entity()
                    camera.name = "FA.camera"
                    camera.components.set(PerspectiveCameraComponent(
                        near: 0.035,
                        far: 62_000,
                        fieldOfViewInDegrees: 60
                    ))
                    positionCamera(camera)
                    content.add(camera)

                    let sun = Entity()
                    sun.name = "FA.sun"
                    sun.components.set([
                        DirectionalLightComponent(
                            color: UIColor(red: 1.0, green: 0.94, blue: 0.83, alpha: 1),
                            intensity: 25_000
                        ),
                        DirectionalLightComponent.Shadow()
                    ])
                    sun.look(at: .zero, from: [-7_000, 10_000, -4_000], relativeTo: nil)
                    content.add(sun)

                    let fill = Entity()
                    fill.name = "FA.fill"
                    fill.components.set(DirectionalLightComponent(
                        color: UIColor(red: 0.61, green: 0.74, blue: 0.94, alpha: 1),
                        intensity: 3_600
                    ))
                    fill.look(at: .zero, from: [6_000, 4_500, 5_500], relativeTo: nil)
                    content.add(fill)
                } update: { content in
                    guard let aircraft = content.entities.first(where: { $0.name == PrototypeAircraftFactory.aircraftName }) else {
                        return
                    }

                    aircraft.position = simulation.state.positionMeters
                    aircraft.orientation = simulation.state.orientation
                    aircraft.isEnabled = cameraMode != .cockpit
                    updateAircraftPresentation(aircraft)

                    if let camera = content.entities.first(where: { $0.name == "FA.camera" }) {
                        positionCamera(camera)
                    }
                }
                .onChange(of: timeline.date) { oldDate, newDate in
                    simulation.advance(realDelta: newDate.timeIntervalSince(oldDate))
                }
            }
            .background(stage2Sky)

            if !simulation.isPaused {
                cameraSelector
            }

            if cameraMode == .cockpit && !simulation.isPaused {
                CockpitFrameOverlay()
                    .allowsHitTesting(false)
            }

            flightConditionOverlay
        }
    }

    private var stage2Sky: some View {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.055, green: 0.22, blue: 0.50), location: 0.00),
                .init(color: Color(red: 0.18, green: 0.43, blue: 0.70), location: 0.44),
                .init(color: Color(red: 0.62, green: 0.72, blue: 0.77), location: 0.70),
                .init(color: Color(red: 0.79, green: 0.73, blue: 0.59), location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var cameraSelector: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    cameraMode = cameraMode.next
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: cameraMode == .cockpit ? "viewfinder" : "camera.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(cameraMode.rawValue)
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .tracking(0.6)
                    }
                    .foregroundStyle(.white.opacity(0.90))
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.11), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .safeAreaPadding(.trailing, 16)
            .padding(.top, 49)
            Spacer()
        }
    }

    @ViewBuilder
    private var flightConditionOverlay: some View {
        switch simulation.flightCondition {
        case .landed(let touchdownFPM):
            VStack {
                Spacer()
                Text(String(format: "TOUCHDOWN  %.0f FPM", touchdownFPM))
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.86))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 9))
                    .padding(.bottom, 190)
            }
            .allowsHitTesting(false)

        case .crashed(let reason):
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()

                VStack(spacing: 8) {
                    Text("AIRCRAFT LOST")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .tracking(0.4)
                    Text(reason)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.62))

                    Button {
                        _ = simulation.resetFlight()
                        simulation.resume()
                        cameraMode = .chase
                    } label: {
                        Text("RESET TO RUNWAY")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 18)
                            .frame(height: 42)
                            .background(.white, in: RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 7)
                }
            }

        default:
            EmptyView()
        }
    }

    @MainActor
    private func positionCamera(_ camera: Entity) {
        let aircraftPosition = simulation.state.positionMeters
        let attitude = simulation.state.orientation

        let localCameraOffset: SIMD3<Float>
        let localLookPoint: SIMD3<Float>
        let fieldOfView: Float

        switch cameraMode {
        case .chase:
            localCameraOffset = [0, 2.75, -13.0]
            localLookPoint = [0, -0.10, 5.2]
            fieldOfView = 59
        case .close:
            localCameraOffset = [0, 1.75, -8.15]
            localLookPoint = [0, -0.12, 5.8]
            fieldOfView = 63
        case .cockpit:
            localCameraOffset = [0, 0.10, 2.72]
            localLookPoint = [0, 0.06, 80]
            fieldOfView = 70
        }

        camera.components.set(PerspectiveCameraComponent(
            near: cameraMode == .cockpit ? 0.02 : 0.08,
            far: 62_000,
            fieldOfViewInDegrees: fieldOfView
        ))

        let desiredPosition = aircraftPosition + simd_act(attitude, localCameraOffset)
        let lookTarget = aircraftPosition + simd_act(attitude, localLookPoint)
        let aircraftUp = simd_act(attitude, SIMD3<Float>(0, 1, 0))

        // All three cameras are aircraft-relative. There is deliberately no
        // horizon-holding correction anywhere in Stage 2.
        camera.look(
            at: lookTarget,
            from: desiredPosition,
            upVector: aircraftUp,
            relativeTo: nil
        )
    }

    @MainActor
    private func updateAircraftPresentation(_ aircraft: Entity) {
        let state = simulation.state

        if let afterburner = aircraft.findEntity(named: PrototypeAircraftFactory.afterburnerName) {
            let intensity = max(0, min(1, (simulation.controls.throttle - 0.82) / 0.18))
            afterburner.isEnabled = intensity > 0.02
            afterburner.scale = [
                0.34 + intensity * 0.12,
                0.34 + intensity * 0.12,
                0.70 + intensity * 1.75
            ]
        }

        if let nozzle = aircraft.findEntity(named: PrototypeAircraftFactory.nozzleName) {
            let dryToAB = max(0, min(1, (simulation.controls.throttle - 0.78) / 0.22))
            let radialScale = 1.0 + dryToAB * 0.11
            nozzle.scale = [radialScale, radialScale, 1]
        }

        if let speedbrake = aircraft.findEntity(named: PrototypeAircraftFactory.speedbrakeName) {
            speedbrake.orientation = simd_quatf(
                angle: -state.speedbrakePosition * 0.88,
                axis: [1, 0, 0]
            )
        }

        if let left = aircraft.findEntity(named: PrototypeAircraftFactory.leftAileronName) {
            left.orientation = simd_quatf(angle: state.leftAileronPosition * 0.38, axis: [1, 0, 0])
        }
        if let right = aircraft.findEntity(named: PrototypeAircraftFactory.rightAileronName) {
            right.orientation = simd_quatf(angle: state.rightAileronPosition * 0.38, axis: [1, 0, 0])
        }
        if let left = aircraft.findEntity(named: PrototypeAircraftFactory.leftElevatorName) {
            left.orientation = simd_quatf(angle: state.elevatorPosition * 0.40, axis: [1, 0, 0])
        }
        if let right = aircraft.findEntity(named: PrototypeAircraftFactory.rightElevatorName) {
            right.orientation = simd_quatf(angle: state.elevatorPosition * 0.40, axis: [1, 0, 0])
        }
        if let rudder = aircraft.findEntity(named: PrototypeAircraftFactory.rudderName) {
            rudder.orientation = simd_quatf(angle: -state.rudderPosition * 0.42, axis: [0, 1, 0])
        }

        updateGear(aircraft, position: state.gearPosition)
        updateVapor(aircraft, state: state)
    }

    @MainActor
    private func updateGear(_ aircraft: Entity, position: Float) {
        let gear = max(0, min(1, position))
        let retract = 1 - gear

        if let nose = aircraft.findEntity(named: PrototypeAircraftFactory.noseGearName) {
            nose.isEnabled = gear > 0.015
            nose.orientation = simd_quatf(angle: retract * 1.15, axis: [1, 0, 0])
        }
        if let left = aircraft.findEntity(named: PrototypeAircraftFactory.leftGearName) {
            left.isEnabled = gear > 0.015
            left.orientation = simd_quatf(angle: -retract * 1.05, axis: [0, 0, 1])
        }
        if let right = aircraft.findEntity(named: PrototypeAircraftFactory.rightGearName) {
            right.isEnabled = gear > 0.015
            right.orientation = simd_quatf(angle: retract * 1.05, axis: [0, 0, 1])
        }
    }

    @MainActor
    private func updateVapor(_ aircraft: Entity, state: AircraftState) {
        let gContribution = max(0, (state.loadFactorG - 3.6) / 4.0)
        let alphaContribution = max(0, (abs(state.angleOfAttackDegrees) - 8) / 13)
        let intensity = min(1, max(gContribution, alphaContribution))
        let vaporOn = intensity > 0.04 && state.airspeedMetersPerSecond > 95

        for name in [PrototypeAircraftFactory.vaporLeftName, PrototypeAircraftFactory.vaporRightName] {
            if let vapor = aircraft.findEntity(named: name) {
                vapor.isEnabled = vaporOn
                vapor.scale = [
                    0.65 + intensity * 0.55,
                    0.50 + intensity * 0.65,
                    0.65 + intensity * 1.25
                ]
            }
        }

        let contrailsOn = state.altitudeFeetMSL > 22_000 && state.airspeedMetersPerSecond > 165
        for name in [PrototypeAircraftFactory.contrailLeftName, PrototypeAircraftFactory.contrailRightName] {
            aircraft.findEntity(named: name)?.isEnabled = contrailsOn
        }
    }
}

private struct CockpitFrameOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CockpitBowShape()
                    .stroke(.black.opacity(0.80), style: StrokeStyle(lineWidth: 13, lineCap: .round))
                CockpitBowShape()
                    .stroke(.white.opacity(0.055), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.black.opacity(0.78))
                        .frame(width: geometry.size.width * 0.58, height: 54)
                        .offset(y: 27)
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct CockpitBowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = CGPoint(x: rect.midX, y: rect.minY - 12)
        path.move(to: top)
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY * 0.82),
            control1: CGPoint(x: rect.midX - rect.width * 0.10, y: rect.height * 0.22),
            control2: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.height * 0.55)
        )
        path.move(to: top)
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.maxY * 0.82),
            control1: CGPoint(x: rect.midX + rect.width * 0.10, y: rect.height * 0.22),
            control2: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.height * 0.55)
        )
        return path
    }
}

@MainActor
private enum Stage2WorldFactory {
    static func make() -> Entity {
        let root = Entity()
        root.name = "FA.world.stage2"

        addTerrain(to: root)
        addAirbase(to: root)
        addRoads(to: root)
        addTown(to: root)
        addTrees(to: root)
        addClouds(to: root)

        return root
    }

    private static func addTerrain(to root: Entity) {
        let palette: [UIColor] = [
            UIColor(red: 0.205, green: 0.285, blue: 0.135, alpha: 1),
            UIColor(red: 0.245, green: 0.315, blue: 0.145, alpha: 1),
            UIColor(red: 0.285, green: 0.325, blue: 0.155, alpha: 1),
            UIColor(red: 0.225, green: 0.295, blue: 0.125, alpha: 1),
            UIColor(red: 0.315, green: 0.335, blue: 0.175, alpha: 1)
        ]

        let tileSize: Float = 6_000
        let resolution = 25

        for tileX in -4..<4 {
            for tileZ in -4..<4 {
                let centerX = (Float(tileX) + 0.5) * tileSize
                let centerZ = (Float(tileZ) + 0.5) * tileSize
                guard let mesh = makeTerrainTile(
                    centerX: centerX,
                    centerZ: centerZ,
                    size: tileSize,
                    resolution: resolution
                ) else { continue }

                let selector = abs(tileX * 13 + tileZ * 7)
                let terrain = ModelEntity(
                    mesh: mesh,
                    materials: [SimpleMaterial(color: palette[selector % palette.count], isMetallic: false)]
                )
                terrain.position = [centerX, 0, centerZ]
                root.addChild(terrain)
            }
        }
    }

    private static func makeTerrainTile(
        centerX: Float,
        centerZ: Float,
        size: Float,
        resolution: Int
    ) -> MeshResource? {
        guard resolution >= 2 else { return nil }

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        positions.reserveCapacity(resolution * resolution)
        normals.reserveCapacity(resolution * resolution)
        indices.reserveCapacity((resolution - 1) * (resolution - 1) * 6)

        let half = size * 0.5
        let step = size / Float(resolution - 1)

        for zIndex in 0..<resolution {
            for xIndex in 0..<resolution {
                let localX = -half + Float(xIndex) * step
                let localZ = -half + Float(zIndex) * step
                let globalX = centerX + localX
                let globalZ = centerZ + localZ
                let height = Stage2TerrainProfile.heightMeters(east: globalX, north: globalZ)
                positions.append([localX, height, localZ])
                normals.append(Stage2TerrainProfile.normal(east: globalX, north: globalZ))
            }
        }

        for zIndex in 0..<(resolution - 1) {
            for xIndex in 0..<(resolution - 1) {
                let i0 = UInt32(zIndex * resolution + xIndex)
                let i1 = UInt32(zIndex * resolution + xIndex + 1)
                let i2 = UInt32((zIndex + 1) * resolution + xIndex)
                let i3 = UInt32((zIndex + 1) * resolution + xIndex + 1)
                indices.append(contentsOf: [i0, i2, i1, i1, i2, i3])
            }
        }

        var descriptor = MeshDescriptor(name: "Stage2 Terrain")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    private static func addAirbase(to root: Entity) {
        let asphalt = UIColor(red: 0.075, green: 0.079, blue: 0.083, alpha: 1)
        let concrete = UIColor(red: 0.43, green: 0.44, blue: 0.42, alpha: 1)
        let marking = UIColor(white: 0.92, alpha: 1)
        let taxiYellow = UIColor(red: 0.88, green: 0.68, blue: 0.08, alpha: 1)

        let runway = block(size: [64, 0.10, 4_800], color: asphalt, cornerRadius: 1)
        runway.position = [0, 0.055, 2_000]
        root.addChild(runway)

        for z in stride(from: -260, through: 4_260, by: 120) {
            let dash = block(size: [1.3, 0.024, 38], color: marking, cornerRadius: 0.05)
            dash.position = [0, 0.12, Float(z)]
            root.addChild(dash)
        }

        for x: Float in [-30.5, 30.5] {
            let edge = block(size: [0.7, 0.022, 4_720], color: marking, cornerRadius: 0.05)
            edge.position = [x, 0.12, 2_000]
            root.addChild(edge)
        }

        for endZ: Float in [-360, 4_360] {
            for stripe in -3...3 {
                let threshold = block(size: [5.0, 0.025, 28], color: marking, cornerRadius: 0)
                threshold.position = [Float(stripe) * 7.2, 0.125, endZ]
                root.addChild(threshold)
            }
        }

        // Edge/approach lights provide powerful closure-rate and flare cues at night-like distances.
        for z in stride(from: -350, through: 4_350, by: 120) {
            addRunwayLight(to: root, position: [-33.5, 0.24, Float(z)], color: .white)
            addRunwayLight(to: root, position: [33.5, 0.24, Float(z)], color: .white)
        }

        for index in 0..<8 {
            addRunwayLight(
                to: root,
                position: [0, 0.24, -450 - Float(index) * 55],
                color: .white
            )
        }

        for index in 0..<4 {
            addRunwayLight(
                to: root,
                position: [-55 + Float(index) * 5.5, 0.30, 420],
                color: index < 2 ? .white : .red
            )
        }

        let parallelTaxiway = block(size: [30, 0.07, 3_050], color: asphalt, cornerRadius: 2)
        parallelTaxiway.position = [320, 0.045, 1_650]
        root.addChild(parallelTaxiway)

        let taxiCenter = block(size: [0.45, 0.025, 3_000], color: taxiYellow, cornerRadius: 0.05)
        taxiCenter.position = [320, 0.10, 1_650]
        root.addChild(taxiCenter)

        for connectorZ: Float in [250, 1_100, 2_100, 3_050] {
            let connector = block(size: [320, 0.07, 24], color: asphalt, cornerRadius: 2)
            connector.position = [160, 0.045, connectorZ]
            root.addChild(connector)
        }

        let apron = block(size: [430, 0.075, 360], color: concrete, cornerRadius: 3)
        apron.position = [520, 0.045, 720]
        root.addChild(apron)

        for row in 0..<2 {
            for column in 0..<4 {
                addHangar(
                    to: root,
                    position: [390 + Float(column) * 94, 0, 610 + Float(row) * 135]
                )
            }
        }

        let towerShaft = block(
            size: [18, 48, 18],
            color: UIColor(red: 0.50, green: 0.50, blue: 0.46, alpha: 1),
            cornerRadius: 1
        )
        towerShaft.position = [715, 24, 900]
        root.addChild(towerShaft)

        let towerCab = block(
            size: [31, 10, 31],
            color: UIColor(red: 0.07, green: 0.14, blue: 0.17, alpha: 1),
            cornerRadius: 2
        )
        towerCab.position = [715, 52, 900]
        root.addChild(towerCab)
    }

    private static func addRunwayLight(to root: Entity, position: SIMD3<Float>, color: UIColor) {
        let light = ModelEntity(
            mesh: .generateSphere(radius: 0.18),
            materials: [SimpleMaterial(color: color, isMetallic: false)]
        )
        light.position = position
        root.addChild(light)
    }

    private static func addHangar(to root: Entity, position: SIMD3<Float>) {
        let body = block(
            size: [70, 18, 55],
            color: UIColor(red: 0.35, green: 0.36, blue: 0.35, alpha: 1),
            cornerRadius: 2
        )
        body.position = [position.x, 9, position.z]
        root.addChild(body)

        let door = block(
            size: [50, 12, 0.8],
            color: UIColor(red: 0.14, green: 0.15, blue: 0.15, alpha: 1),
            cornerRadius: 0.5
        )
        door.position = [position.x, 6.1, position.z - 27.7]
        root.addChild(door)
    }

    private static func addRoads(to root: Entity) {
        let roadColor = UIColor(red: 0.14, green: 0.145, blue: 0.14, alpha: 1)
        let roads: [[SIMD2<Float>]] = [
            [[-5_500, -1_200], [-2_500, -400], [1_300, -650], [5_500, 500], [8_500, 2_400]],
            [[-3_500, 5_500], [-1_400, 3_800], [-900, 1_200], [-1_100, -2_500]],
            [[1_800, 4_200], [3_000, 2_800], [4_500, 1_900], [7_000, 1_500]],
            [[2_100, 7_000], [2_400, 4_800], [3_500, 3_000], [5_800, 2_500]]
        ]

        for road in roads {
            for index in 0..<(road.count - 1) {
                addRoadSegment(to: root, from: road[index], to: road[index + 1], width: 17, color: roadColor)
            }
        }
    }

    private static func addRoadSegment(
        to root: Entity,
        from start: SIMD2<Float>,
        to end: SIMD2<Float>,
        width: Float,
        color: UIColor
    ) {
        let delta = end - start
        let length = simd_length(delta)
        guard length > 1 else { return }

        let center = (start + end) * 0.5
        let y = Stage2TerrainProfile.heightMeters(east: center.x, north: center.y) + 0.10
        let road = block(size: [width, 0.08, length], color: color, cornerRadius: 1.5)
        road.position = [center.x, y, center.y]
        road.orientation = simd_quatf(angle: atan2(delta.x, delta.y), axis: [0, 1, 0])
        root.addChild(road)
    }

    private static func addTown(to root: Entity) {
        let wallColors: [UIColor] = [
            UIColor(red: 0.47, green: 0.45, blue: 0.39, alpha: 1),
            UIColor(red: 0.37, green: 0.39, blue: 0.40, alpha: 1),
            UIColor(red: 0.51, green: 0.48, blue: 0.42, alpha: 1),
            UIColor(red: 0.42, green: 0.41, blue: 0.38, alpha: 1)
        ]

        for row in 0..<6 {
            for column in 0..<8 {
                let selector = row * 8 + column
                let height = Float(16 + (selector * 13) % 52)
                let width = Float(32 + (selector * 7) % 30)
                let depth = Float(30 + (selector * 11) % 28)
                let x = 2_700 + Float(column) * 112
                let z = 3_000 + Float(row) * 118
                let terrain = Stage2TerrainProfile.heightMeters(east: x, north: z)

                let building = block(
                    size: [width, height, depth],
                    color: wallColors[selector % wallColors.count],
                    cornerRadius: 1.1
                )
                building.position = [x, terrain + height * 0.5, z]
                root.addChild(building)

                let roof = block(
                    size: [width + 2, 1.2, depth + 2],
                    color: UIColor(red: 0.17, green: 0.18, blue: 0.18, alpha: 1),
                    cornerRadius: 0.3
                )
                roof.position = [x, terrain + height + 0.6, z]
                root.addChild(roof)
            }
        }
    }

    private static func addTrees(to root: Entity) {
        let trunkColor = UIColor(red: 0.18, green: 0.11, blue: 0.06, alpha: 1)
        let greens: [UIColor] = [
            UIColor(red: 0.075, green: 0.20, blue: 0.06, alpha: 1),
            UIColor(red: 0.11, green: 0.25, blue: 0.075, alpha: 1),
            UIColor(red: 0.15, green: 0.28, blue: 0.085, alpha: 1)
        ]

        for belt in 0..<12 {
            let baseX = Float(-6_500 + belt * 1_050)
            let baseZ = Float(1_200 + (belt % 4) * 1_500)

            for treeIndex in 0..<9 {
                let x = baseX + Float(treeIndex) * 70
                let z = baseZ + sin(Float(treeIndex) * 0.82) * 115
                let height = Float(12 + ((belt * 17 + treeIndex * 7) % 12))
                addTree(
                    to: root,
                    position: [x, Stage2TerrainProfile.heightMeters(east: x, north: z), z],
                    height: height,
                    trunkColor: trunkColor,
                    canopyColor: greens[(belt + treeIndex) % greens.count]
                )
            }
        }
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
            mesh: .generateCylinder(height: trunkHeight, radius: height * 0.045),
            materials: [SimpleMaterial(color: trunkColor, isMetallic: false)]
        )
        trunk.position = [position.x, position.y + trunkHeight * 0.5, position.z]
        root.addChild(trunk)

        let canopy = ellipsoid(
            radii: [height * 0.25, height * 0.30, height * 0.25],
            color: canopyColor
        )
        canopy.position = [position.x, position.y + trunkHeight + height * 0.22, position.z]
        root.addChild(canopy)
    }

    private static func addClouds(to root: Entity) {
        let cloudColor = UIColor(red: 0.94, green: 0.96, blue: 0.98, alpha: 0.27)
        let clouds: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([-2_100, 1_250, 2_100], [460, 105, 250]),
            ([1_800, 1_430, 3_100], [540, 120, 300]),
            ([-4_800, 1_700, 6_000], [780, 155, 390]),
            ([4_600, 1_900, 7_500], [820, 165, 410]),
            ([-1_500, 2_250, 10_000], [1_050, 205, 520]),
            ([4_200, 2_450, 12_500], [1_200, 230, 590]),
            ([-8_500, 2_700, 16_000], [1_550, 260, 720]),
            ([8_000, 2_900, 19_000], [1_700, 280, 780])
        ]

        for (position, radii) in clouds {
            let cloud = ellipsoid(radii: radii, color: cloudColor)
            cloud.position = position
            root.addChild(cloud)
        }
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
