import SwiftUI
import RealityKit
import UIKit
import simd

// MARK: - Stage 020 procedural inhabited world

/// Terrain-aware urban generation inspired by tensor-field road systems, implemented
/// natively so RealityKit and JSBSim keep sharing Stage2TerrainProfile as the one
/// authoritative ground surface.
///
/// Stage 020 is intentionally additive. Stage2WorldFactory continues to own the
/// authored airbase, clouds, terrain, Stage 019 land-use, CC0 vegetation, and the
/// industrial/service district. This layer grows a larger deterministic city east
/// of that district and adds smaller satellite settlements to make the world read as
/// inhabited from aviation altitudes.
@MainActor
enum Stage020ProceduralWorld {
    private struct CityConfig {
        let seed: Int
        let preferredCenter: SIMD2<Float>
        let columns: Int
        let rows: Int
        let spacingX: Float
        let spacingZ: Float
        let maxWarp: Float
    }

    private struct SurfaceTextures {
        let base: TextureResource?
        let roughness: TextureResource?
        let normal: TextureResource?
    }

    private struct Grid {
        let points: [[SIMD2<Float>]]
        let axisX: SIMD2<Float>
        let axisZ: SIMD2<Float>
        let center: SIMD2<Float>

        var rows: Int { points.count }
        var columns: Int { points.first?.count ?? 0 }
    }

    private struct SharedMeshes {
        let box: MeshResource
        let lowBox: MeshResource
        let sphere: MeshResource
    }

    static func make(base: Entity) -> Entity {
        guard base.findEntity(named: "FA.world.stage020.procedural-region") == nil else {
            return base
        }

        let config = CityConfig(
            seed: 20_260_920,
            preferredCenter: [6_150, 3_250],
            columns: 13,
            rows: 10,
            spacingX: 330,
            spacingZ: 305,
            maxWarp: 86
        )

        let region = Entity()
        region.name = "FA.world.stage020.procedural-region"

        let grid = makeGrid(config: config)
        let meshes = SharedMeshes(
            box: .generateBox(size: [1, 1, 1], cornerRadius: 0.025),
            lowBox: .generateBox(size: [1, 1, 1], cornerRadius: 0.012),
            sphere: .generateSphere(radius: 0.5)
        )

        let asphalt = texturedMaterial(
            stem: "runway_asphalt",
            tint: UIColor(red: 0.42, green: 0.43, blue: 0.43, alpha: 1),
            roughnessScale: 0.97,
            specular: 0.19
        )
        let concrete = texturedMaterial(
            stem: "apron_concrete",
            tint: UIColor(red: 0.59, green: 0.58, blue: 0.54, alpha: 1),
            roughnessScale: 0.96,
            specular: 0.17
        )
        let park = texturedMaterial(
            stem: "terrain_grass",
            tint: UIColor(red: 0.34, green: 0.45, blue: 0.24, alpha: 1),
            roughnessScale: 0.98,
            specular: 0.12
        )

        addStreetNetwork(
            grid: grid,
            root: region,
            asphalt: asphalt,
            concrete: concrete
        )
        addHighwayConnector(
            cityGrid: grid,
            root: region,
            asphalt: asphalt,
            concrete: concrete
        )
        addCityBlocks(
            grid: grid,
            config: config,
            meshes: meshes,
            root: region,
            concrete: concrete,
            park: park
        )
        addPeripheralDevelopment(
            config: config,
            meshes: meshes,
            root: region,
            asphalt: asphalt,
            concrete: concrete,
            park: park
        )

        base.addChild(region)
        return base
    }

    // MARK: - Grid / road planning

    private static func makeGrid(config: CityConfig) -> Grid {
        let center = chooseCityCenter(near: config.preferredCenter)
        let normal = Stage2TerrainProfile.normal(east: center.x, north: center.y)
        let gradient = terrainGradient(from: normal)

        var axisX: SIMD2<Float>
        if simd_length_squared(gradient) > 0.0001 {
            axisX = simd_normalize(SIMD2<Float>(gradient.y, -gradient.x))
            if simd_dot(axisX, SIMD2<Float>(1, 0)) < 0 { axisX = -axisX }
        } else {
            let angle: Float = 0.15
            axisX = [cos(angle), sin(angle)]
        }
        let axisZ = SIMD2<Float>(-axisX.y, axisX.x)

        let halfColumns = Float(config.columns - 1) * 0.5
        let halfRows = Float(config.rows - 1) * 0.5
        var points: [[SIMD2<Float>]] = []
        points.reserveCapacity(config.rows)

        for row in 0..<config.rows {
            var rowPoints: [SIMD2<Float>] = []
            rowPoints.reserveCapacity(config.columns)

            for column in 0..<config.columns {
                let gx = (Float(column) - halfColumns) * config.spacingX
                let gz = (Float(row) - halfRows) * config.spacingZ

                let phase = Float(config.seed % 997) * 0.001
                let broadX = sin(Float(row) * 0.73 + Float(column) * 0.29 + phase)
                let broadZ = cos(Float(column) * 0.61 - Float(row) * 0.23 + phase * 2.1)
                let fine = hash(config.seed + row * 131 + column * 37)

                var point = center + axisX * gx + axisZ * gz
                let localNormal = Stage2TerrainProfile.normal(east: point.x, north: point.y)
                let localGradient = terrainGradient(from: localNormal)
                let localContour: SIMD2<Float>
                if simd_length_squared(localGradient) > 0.0001 {
                    localContour = simd_normalize(SIMD2<Float>(localGradient.y, -localGradient.x))
                } else {
                    localContour = axisX
                }

                let warpX = broadX * config.maxWarp * 0.56
                    + (fine - 0.5) * config.maxWarp * 0.34
                let warpZ = broadZ * config.maxWarp * 0.46
                    + (hash(config.seed + row * 79 + column * 181) - 0.5) * config.maxWarp * 0.28

                point += axisX * warpX + axisZ * warpZ

                // A small contour-following correction keeps the network from looking
                // like a rigid grid projected onto the hills while retaining sane blocks.
                let slope = min(simd_length(localGradient), 0.30)
                point += localContour * (slope * 135)
                    * sin(Float(row + column) * 0.71 + phase)

                rowPoints.append(point)
            }
            points.append(rowPoints)
        }

        return Grid(points: points, axisX: axisX, axisZ: axisZ, center: center)
    }

    private static func chooseCityCenter(near preferred: SIMD2<Float>) -> SIMD2<Float> {
        var best = preferred
        var bestScore = Float.greatestFiniteMagnitude
        let offsets: [Float] = [-900, -450, 0, 450, 900]

        for dx in offsets {
            for dz in offsets {
                let candidate = preferred + SIMD2<Float>(dx, dz)
                guard candidate.x > 4_300 else { continue }

                var slopePenalty: Float = 0
                var heights: [Float] = []
                for ox: Float in [-700, 0, 700] {
                    for oz: Float in [-550, 0, 550] {
                        let sample = candidate + SIMD2<Float>(ox, oz)
                        let normal = Stage2TerrainProfile.normal(east: sample.x, north: sample.y)
                        slopePenalty += max(0, 0.985 - normal.y) * 2_200
                        heights.append(Stage2TerrainProfile.heightMeters(east: sample.x, north: sample.y))
                    }
                }

                let average = heights.reduce(0, +) / Float(max(heights.count, 1))
                let variance = heights.reduce(0) { partial, height in
                    let delta = height - average
                    return partial + delta * delta
                } / Float(max(heights.count, 1))

                let distancePenalty = simd_length(candidate - preferred) * 0.018
                let score = slopePenalty + sqrt(max(variance, 0)) * 1.7 + distancePenalty
                if score < bestScore {
                    bestScore = score
                    best = candidate
                }
            }
        }

        return best
    }

    private static func addStreetNetwork(
        grid: Grid,
        root: Entity,
        asphalt: PhysicallyBasedMaterial,
        concrete: PhysicallyBasedMaterial
    ) {
        let roadRoot = Entity()
        roadRoot.name = "FA.world.stage020.road-network"

        for row in 0..<grid.rows {
            let points = grid.points[row]
            let arterial = row == grid.rows / 2 || row.isMultiple(of: 4)
            addRoad(
                points: points,
                width: arterial ? 17.5 : 9.4,
                root: roadRoot,
                asphalt: asphalt,
                concrete: concrete,
                marked: arterial,
                name: "east-west-\(row)"
            )
        }

        for column in 0..<grid.columns {
            let points = (0..<grid.rows).map { grid.points[$0][column] }
            let arterial = column == grid.columns / 2 || column.isMultiple(of: 4)
            addRoad(
                points: points,
                width: arterial ? 18.5 : 9.2,
                root: roadRoot,
                asphalt: asphalt,
                concrete: concrete,
                marked: arterial,
                name: "north-south-\(column)"
            )
        }

        root.addChild(roadRoot)
    }

    private static func addRoad(
        points: [SIMD2<Float>],
        width: Float,
        root: Entity,
        asphalt: PhysicallyBasedMaterial,
        concrete: PhysicallyBasedMaterial,
        marked: Bool,
        name: String
    ) {
        guard points.count >= 2 else { return }

        if let sidewalk = makeConformingPolylineRibbon(
            points: points,
            width: width + 7.0,
            verticalOffset: 0.065,
            metersPerTile: 8.0,
            material: concrete
        ) {
            sidewalk.name = "FA.world.stage020.sidewalk.\(name)"
            root.addChild(sidewalk)
        }

        if let road = makeConformingPolylineRibbon(
            points: points,
            width: width,
            verticalOffset: 0.105,
            metersPerTile: 7.0,
            material: asphalt
        ) {
            road.name = "FA.world.stage020.road.\(name)"
            root.addChild(road)
        }

        if marked {
            var marking = PhysicallyBasedMaterial()
            marking.baseColor = .init(
                tint: UIColor(red: 0.86, green: 0.68, blue: 0.14, alpha: 1)
            )
            marking.roughness = .init(floatLiteral: 0.92)
            marking.metallic = .init(floatLiteral: 0)
            marking.specular = .init(floatLiteral: 0.12)

            if let centerline = makeConformingPolylineRibbon(
                points: points,
                width: 0.44,
                verticalOffset: 0.135,
                metersPerTile: 4.0,
                material: marking
            ) {
                centerline.name = "FA.world.stage020.centerline.\(name)"
                root.addChild(centerline)
            }
        }
    }

    private static func addHighwayConnector(
        cityGrid: Grid,
        root: Entity,
        asphalt: PhysicallyBasedMaterial,
        concrete: PhysicallyBasedMaterial
    ) {
        guard cityGrid.rows > 0, cityGrid.columns > 0 else { return }
        let westEdge = cityGrid.points[cityGrid.rows / 2][0]

        let connector: [SIMD2<Float>] = [
            [1_080, 1_050],
            [1_850, 1_520],
            [2_780, 1_980],
            [3_650, 2_180],
            [4_350, 2_420],
            simd_mix(SIMD2<Float>(4_350, 2_420), westEdge, SIMD2<Float>(repeating: 0.55)),
            westEdge
        ]
        addRoad(
            points: connector,
            width: 20.5,
            root: root,
            asphalt: asphalt,
            concrete: concrete,
            marked: true,
            name: "airbase-city-connector"
        )

        let southWest = cityGrid.points[cityGrid.rows - 1][0]
        let northEast = cityGrid.points[0][cityGrid.columns - 1]
        let bypass: [SIMD2<Float>] = [
            southWest + [-520, -420],
            cityGrid.center + [-1_050, -1_520],
            cityGrid.center + [350, -1_770],
            cityGrid.center + [1_650, -1_120],
            northEast + [620, 280]
        ]
        addRoad(
            points: bypass,
            width: 17.0,
            root: root,
            asphalt: asphalt,
            concrete: concrete,
            marked: true,
            name: "southern-bypass"
        )
    }

    // MARK: - Lots / zoning / skyline

    private static func addCityBlocks(
        grid: Grid,
        config: CityConfig,
        meshes: SharedMeshes,
        root: Entity,
        concrete: PhysicallyBasedMaterial,
        park: PhysicallyBasedMaterial
    ) {
        let buildings = Entity()
        buildings.name = "FA.world.stage020.city-buildings"

        let buildingPalette = makeBuildingPalette()
        let roofPalette = makeRoofPalette()
        let cellCenter = SIMD2<Float>(
            Float(grid.columns - 2) * 0.5,
            Float(grid.rows - 2) * 0.5
        )

        for row in 0..<(grid.rows - 1) {
            for column in 0..<(grid.columns - 1) {
                let p00 = grid.points[row][column]
                let p10 = grid.points[row][column + 1]
                let p01 = grid.points[row + 1][column]
                let p11 = grid.points[row + 1][column + 1]
                let center = (p00 + p10 + p01 + p11) * 0.25

                let normal = Stage2TerrainProfile.normal(east: center.x, north: center.y)
                guard normal.y > 0.955 else { continue }

                let rowCenter = (p00 + p10) * 0.5
                let nextRowCenter = (p01 + p11) * 0.5
                let columnCenter = (p00 + p01) * 0.5
                let nextColumnCenter = (p10 + p11) * 0.5

                var cellX = nextColumnCenter - columnCenter
                var cellZ = nextRowCenter - rowCenter
                guard simd_length_squared(cellX) > 1, simd_length_squared(cellZ) > 1 else { continue }
                cellX = simd_normalize(cellX)
                cellZ = simd_normalize(cellZ)

                let cellWidth = min(simd_length(p10 - p00), simd_length(p11 - p01))
                let cellDepth = min(simd_length(p01 - p00), simd_length(p11 - p10))
                guard cellWidth > 130, cellDepth > 120 else { continue }

                let normalizedCell = SIMD2<Float>(Float(column), Float(row))
                let distance = simd_length(
                    SIMD2<Float>(
                        (normalizedCell.x - cellCenter.x) / max(cellCenter.x, 1),
                        (normalizedCell.y - cellCenter.y) / max(cellCenter.y, 1)
                    )
                )
                let density = clamp(1 - distance * 0.74, 0.05, 1)
                let selector = config.seed + row * 503 + column * 197
                let parkChance = hash(selector + 11)

                if parkChance < 0.085
                    || (row == grid.rows / 2 - 1 && column == grid.columns / 2 + 1) {
                    addPark(
                        center: center,
                        axisX: cellX,
                        axisZ: cellZ,
                        width: cellWidth - 30,
                        depth: cellDepth - 30,
                        selector: selector,
                        meshes: meshes,
                        root: buildings,
                        park: park
                    )
                    continue
                }

                if density < 0.30 && hash(selector + 19) < 0.17 {
                    continue
                }

                let count: Int
                if density > 0.67 {
                    count = hash(selector + 23) > 0.30 ? 3 : 2
                } else if density > 0.34 {
                    count = 2
                } else {
                    count = 1
                }

                let usableWidth = max(cellWidth - 54, 70)
                let usableDepth = max(cellDepth - 50, 65)

                for buildingIndex in 0..<count {
                    let local: SIMD2<Float>
                    switch count {
                    case 1:
                        local = [
                            (hash(selector + 31) - 0.5) * usableWidth * 0.20,
                            (hash(selector + 37) - 0.5) * usableDepth * 0.18
                        ]
                    case 2:
                        local = [
                            (buildingIndex == 0 ? -0.25 : 0.25) * usableWidth,
                            (hash(selector + 41 + buildingIndex) - 0.5) * usableDepth * 0.18
                        ]
                    default:
                        let slots: [SIMD2<Float>] = [
                            [-0.27, -0.18],
                            [0.27, -0.14],
                            [0.03, 0.27]
                        ]
                        local = [
                            slots[buildingIndex].x * usableWidth,
                            slots[buildingIndex].y * usableDepth
                        ]
                    }

                    let position = center + cellX * local.x + cellZ * local.y
                    let footprintWidth = usableWidth * (count == 1 ? 0.54 : 0.34)
                        * (0.86 + hash(selector + 53 + buildingIndex) * 0.24)
                    let footprintDepth = usableDepth * (count >= 3 ? 0.34 : 0.48)
                        * (0.84 + hash(selector + 61 + buildingIndex) * 0.24)

                    let downtown = powf(density, 2.25)
                    let variation = hash(selector + 71 + buildingIndex * 17)
                    var height = 10 + variation * 22
                        + downtown * (92 + hash(selector + 79) * 72)

                    if density > 0.72 && hash(selector + 83 + buildingIndex) > 0.88 {
                        height += 58 + hash(selector + 89) * 48
                    }

                    addBuilding(
                        at: position,
                        axisX: cellX,
                        width: clamp(footprintWidth, 24, 102),
                        depth: clamp(footprintDepth, 24, 92),
                        height: clamp(height, 10, 235),
                        selector: selector + buildingIndex * 101,
                        density: density,
                        meshes: meshes,
                        buildingPalette: buildingPalette,
                        roofPalette: roofPalette,
                        root: buildings
                    )
                }

                if density > 0.54 && hash(selector + 131) < 0.10 {
                    addSurfacePad(
                        center: center + cellX * usableWidth * 0.31,
                        axisX: cellX,
                        width: usableWidth * 0.22,
                        depth: usableDepth * 0.34,
                        verticalOffset: 0.115,
                        material: concrete,
                        root: buildings,
                        name: "plaza-\(row)-\(column)"
                    )
                }
            }
        }

        root.addChild(buildings)
    }

    private static func addBuilding(
        at position: SIMD2<Float>,
        axisX: SIMD2<Float>,
        width: Float,
        depth: Float,
        height: Float,
        selector: Int,
        density: Float,
        meshes: SharedMeshes,
        buildingPalette: [PhysicallyBasedMaterial],
        roofPalette: [PhysicallyBasedMaterial],
        root: Entity
    ) {
        let terrainNormal = Stage2TerrainProfile.normal(east: position.x, north: position.y)
        guard terrainNormal.y > 0.952 else { return }

        let ground = Stage2TerrainProfile.heightMeters(east: position.x, north: position.y)
        let yaw = atan2(axisX.y, axisX.x)
        let orientation = simd_quatf(angle: -yaw, axis: [0, 1, 0])
        let wall = buildingPalette[abs(selector) % buildingPalette.count]
        let roofMaterial = roofPalette[abs(selector / 3 + 1) % roofPalette.count]

        if height > 88 {
            let lowerHeight = height * (0.62 + hash(selector + 5) * 0.10)
            let lower = ModelEntity(mesh: meshes.box, materials: [wall])
            lower.name = "FA.world.stage020.tower.base"
            lower.scale = [width, lowerHeight, depth]
            lower.position = [position.x, ground + lowerHeight * 0.5, position.y]
            lower.orientation = orientation
            root.addChild(lower)

            let upperHeight = height - lowerHeight
            let inset = 0.68 + hash(selector + 7) * 0.16
            let upper = ModelEntity(mesh: meshes.box, materials: [wall])
            upper.name = "FA.world.stage020.tower.upper"
            upper.scale = [width * inset, upperHeight, depth * inset]
            upper.position = [position.x, ground + lowerHeight + upperHeight * 0.5, position.y]
            upper.orientation = orientation
            root.addChild(upper)
        } else {
            let body = ModelEntity(mesh: meshes.box, materials: [wall])
            body.name = "FA.world.stage020.building"
            body.scale = [width, height, depth]
            body.position = [position.x, ground + height * 0.5, position.y]
            body.orientation = orientation
            root.addChild(body)
        }

        let roof = ModelEntity(mesh: meshes.lowBox, materials: [roofMaterial])
        roof.name = "FA.world.stage020.roof"
        roof.scale = [width * 0.96, 1.1, depth * 0.96]
        roof.position = [position.x, ground + height + 0.55, position.y]
        roof.orientation = orientation
        root.addChild(roof)

        if height > 42 && hash(selector + 17) > 0.32 {
            let equipment = ModelEntity(mesh: meshes.lowBox, materials: [roofMaterial])
            let equipmentWidth = clamp(width * 0.18, 4, 16)
            let equipmentDepth = clamp(depth * 0.16, 4, 14)
            let equipmentHeight = 2.4 + hash(selector + 21) * 4.8
            equipment.name = "FA.world.stage020.rooftop-equipment"
            equipment.scale = [equipmentWidth, equipmentHeight, equipmentDepth]
            equipment.position = [
                position.x,
                ground + height + 1.1 + equipmentHeight * 0.5,
                position.y
            ]
            equipment.orientation = orientation
            root.addChild(equipment)
        }

        if density > 0.70 && height > 135 && hash(selector + 29) > 0.62 {
            let mastMaterial = roofPalette[(abs(selector) + 2) % roofPalette.count]
            let mastHeight: Float = 14 + hash(selector + 31) * 17
            let mast = ModelEntity(mesh: meshes.lowBox, materials: [mastMaterial])
            mast.scale = [0.75, mastHeight, 0.75]
            mast.position = [position.x, ground + height + mastHeight * 0.5 + 1.1, position.y]
            mast.orientation = orientation
            root.addChild(mast)
        }
    }

    private static func addPark(
        center: SIMD2<Float>,
        axisX: SIMD2<Float>,
        axisZ: SIMD2<Float>,
        width: Float,
        depth: Float,
        selector: Int,
        meshes: SharedMeshes,
        root: Entity,
        park: PhysicallyBasedMaterial
    ) {
        addSurfacePad(
            center: center,
            axisX: axisX,
            width: width,
            depth: depth,
            verticalOffset: 0.10,
            material: park,
            root: root,
            name: "park-\(selector)"
        )

        let trunkMaterial = SimpleMaterial(
            color: UIColor(red: 0.17, green: 0.11, blue: 0.065, alpha: 1),
            roughness: 0.98,
            isMetallic: false
        )
        let foliageColors: [UIColor] = [
            UIColor(red: 0.085, green: 0.19, blue: 0.070, alpha: 1),
            UIColor(red: 0.105, green: 0.22, blue: 0.080, alpha: 1),
            UIColor(red: 0.070, green: 0.16, blue: 0.060, alpha: 1)
        ]
        let yaw = atan2(axisX.y, axisX.x)

        for index in 0..<7 {
            let hx = hash(selector + index * 17 + 1)
            let hz = hash(selector + index * 17 + 2)
            let point = center
                + axisX * ((hx - 0.5) * width * 0.72)
                + axisZ * ((hz - 0.5) * depth * 0.72)
            let ground = Stage2TerrainProfile.heightMeters(east: point.x, north: point.y)
            let height = 8 + hash(selector + index * 17 + 3) * 8

            let trunk = ModelEntity(mesh: meshes.lowBox, materials: [trunkMaterial])
            trunk.scale = [0.52, height * 0.42, 0.52]
            trunk.position = [point.x, ground + height * 0.21, point.y]
            trunk.orientation = simd_quatf(angle: -yaw, axis: [0, 1, 0])
            root.addChild(trunk)

            let foliage = ModelEntity(
                mesh: meshes.sphere,
                materials: [SimpleMaterial(
                    color: foliageColors[index % foliageColors.count],
                    roughness: 0.97,
                    isMetallic: false
                )]
            )
            foliage.scale = [height * 0.52, height * 0.58, height * 0.52]
            foliage.position = [point.x, ground + height * 0.76, point.y]
            root.addChild(foliage)
        }
    }

    private static func addPeripheralDevelopment(
        config: CityConfig,
        meshes: SharedMeshes,
        root: Entity,
        asphalt: PhysicallyBasedMaterial,
        concrete: PhysicallyBasedMaterial,
        park: PhysicallyBasedMaterial
    ) {
        let satellites: [(SIMD2<Float>, Float, Int)] = [
            ([-5_900, 5_800], 0.18, 41),
            ([7_600, -4_400], -0.36, 73)
        ]

        let palette = makeBuildingPalette()
        let roofs = makeRoofPalette()
        let group = Entity()
        group.name = "FA.world.stage020.satellite-settlements"

        for (center, angle, salt) in satellites {
            let axisX = SIMD2<Float>(cos(angle), sin(angle))
            let axisZ = SIMD2<Float>(-axisX.y, axisX.x)
            let roadA: [SIMD2<Float>] = [
                center - axisX * 720,
                center,
                center + axisX * 720
            ]
            let roadB: [SIMD2<Float>] = [
                center - axisZ * 540,
                center,
                center + axisZ * 540
            ]

            addRoad(
                points: roadA,
                width: 9.0,
                root: group,
                asphalt: asphalt,
                concrete: concrete,
                marked: false,
                name: "satellite-\(salt)-a"
            )
            addRoad(
                points: roadB,
                width: 8.4,
                root: group,
                asphalt: asphalt,
                concrete: concrete,
                marked: false,
                name: "satellite-\(salt)-b"
            )

            for index in 0..<14 {
                let row = index / 7
                let column = index % 7
                let xOffset = (Float(column) - 3) * 145
                let zOffset = (Float(row) - 0.5) * 190
                let jitterX = (hash(config.seed + salt + index * 11) - 0.5) * 44
                let jitterZ = (hash(config.seed + salt + index * 13) - 0.5) * 54
                let point = center
                    + axisX * (xOffset + jitterX)
                    + axisZ * (zOffset + jitterZ)

                if Stage2TerrainProfile.normal(east: point.x, north: point.y).y < 0.95 {
                    continue
                }

                addBuilding(
                    at: point,
                    axisX: axisX,
                    width: 34 + hash(salt + index * 17) * 34,
                    depth: 28 + hash(salt + index * 19) * 28,
                    height: 9 + hash(salt + index * 23) * 24,
                    selector: config.seed + salt * 101 + index,
                    density: 0.16,
                    meshes: meshes,
                    buildingPalette: palette,
                    roofPalette: roofs,
                    root: group
                )
            }

            if hash(config.seed + salt) > 0.25 {
                addPark(
                    center: center + axisZ * 310,
                    axisX: axisX,
                    axisZ: axisZ,
                    width: 170,
                    depth: 120,
                    selector: config.seed + salt,
                    meshes: meshes,
                    root: group,
                    park: park
                )
            }
        }

        root.addChild(group)
    }

    // MARK: - Geometry / materials

    private static func makeConformingPolylineRibbon(
        points: [SIMD2<Float>],
        width: Float,
        verticalOffset: Float,
        metersPerTile: Float,
        material: PhysicallyBasedMaterial
    ) -> ModelEntity? {
        guard points.count >= 2 else { return nil }

        var centers: [SIMD2<Float>] = []
        for segment in 0..<(points.count - 1) {
            let start = points[segment]
            let end = points[segment + 1]
            let length = simd_length(end - start)
            let steps = max(1, Int(ceil(length / 72)))

            // Every segment excludes only its own endpoint. The next segment starts
            // on that exact shared vertex, so road ribbons remain continuous.
            for step in 0..<steps {
                let t = Float(step) / Float(steps)
                centers.append(simd_mix(start, end, SIMD2<Float>(repeating: t)))
            }
        }
        if let last = points.last { centers.append(last) }
        guard centers.count >= 2 else { return nil }

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var tangents: [SIMD3<Float>] = []
        var texcoords: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        positions.reserveCapacity(centers.count * 2)
        normals.reserveCapacity(centers.count * 2)
        tangents.reserveCapacity(centers.count * 2)
        texcoords.reserveCapacity(centers.count * 2)
        indices.reserveCapacity((centers.count - 1) * 6)

        var accumulated: Float = 0

        for index in centers.indices {
            let previous = centers[max(index - 1, 0)]
            let next = centers[min(index + 1, centers.count - 1)]
            var forward = next - previous
            if simd_length_squared(forward) < 0.001 {
                forward = [1, 0]
            } else {
                forward = simd_normalize(forward)
            }
            let side = SIMD2<Float>(forward.y, -forward.x)
            let left = centers[index] + side * width * 0.5
            let right = centers[index] - side * width * 0.5

            if index > 0 {
                accumulated += simd_length(centers[index] - centers[index - 1])
            }

            for (edge, uvV) in [(left, Float(0)), (right, Float(1))] {
                let normal = Stage2TerrainProfile.normal(east: edge.x, north: edge.y)
                let height = Stage2TerrainProfile.heightMeters(east: edge.x, north: edge.y)
                    + verticalOffset
                let flatTangent = SIMD3<Float>(forward.x, 0, forward.y)
                let projected = flatTangent - normal * simd_dot(flatTangent, normal)
                let tangent = simd_length_squared(projected) > 0.000001
                    ? simd_normalize(projected)
                    : SIMD3<Float>(1, 0, 0)

                positions.append([edge.x, height, edge.y])
                normals.append(normal)
                tangents.append(tangent)
                texcoords.append([accumulated / max(metersPerTile, 0.5), uvV])
            }
        }

        for index in 0..<(centers.count - 1) {
            let i0 = UInt32(index * 2)
            let i1 = i0 + 1
            let i2 = i0 + 2
            let i3 = i0 + 3
            indices.append(contentsOf: [i0, i2, i1, i1, i2, i3])
        }

        var descriptor = MeshDescriptor(name: "Stage 020 conforming road ribbon")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.tangents = MeshBuffers.Tangents(tangents)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(texcoords)
        descriptor.primitives = .triangles(indices)

        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }
        return ModelEntity(mesh: mesh, materials: [material])
    }

    private static func addSurfacePad(
        center: SIMD2<Float>,
        axisX: SIMD2<Float>,
        width: Float,
        depth: Float,
        verticalOffset: Float,
        material: PhysicallyBasedMaterial,
        root: Entity,
        name: String
    ) {
        let axisZ = SIMD2<Float>(-axisX.y, axisX.x)
        let halfW = width * 0.5
        let halfD = depth * 0.5
        let corners = [
            center - axisX * halfW - axisZ * halfD,
            center + axisX * halfW - axisZ * halfD,
            center - axisX * halfW + axisZ * halfD,
            center + axisX * halfW + axisZ * halfD
        ]

        let positions = corners.map { point -> SIMD3<Float> in
            [
                point.x,
                Stage2TerrainProfile.heightMeters(east: point.x, north: point.y) + verticalOffset,
                point.y
            ]
        }
        let normals = corners.map {
            Stage2TerrainProfile.normal(east: $0.x, north: $0.y)
        }
        let tangent3 = SIMD3<Float>(axisX.x, 0, axisX.y)
        let tangents = normals.map { normal -> SIMD3<Float> in
            let projected = tangent3 - normal * simd_dot(tangent3, normal)
            return simd_length_squared(projected) > 0.000001
                ? simd_normalize(projected)
                : SIMD3<Float>(1, 0, 0)
        }
        let texcoords: [SIMD2<Float>] = [
            [0, 0],
            [width / 8, 0],
            [0, depth / 8],
            [width / 8, depth / 8]
        ]
        let indices: [UInt32] = [0, 2, 1, 1, 2, 3]

        var descriptor = MeshDescriptor(name: "Stage 020 surface pad")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.tangents = MeshBuffers.Tangents(tangents)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(texcoords)
        descriptor.primitives = .triangles(indices)

        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return }
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "FA.world.stage020.\(name)"
        root.addChild(entity)
    }

    private static func texturedMaterial(
        stem: String,
        tint: UIColor,
        roughnessScale: Float,
        specular: Float
    ) -> PhysicallyBasedMaterial {
        let textures = SurfaceTextures(
            base: loadTexture("\(stem)_diff"),
            roughness: loadTexture("\(stem)_rough"),
            normal: loadTexture("\(stem)_nor")
        )

        var material = PhysicallyBasedMaterial()
        if let base = textures.base {
            material.baseColor = .init(tint: tint, texture: repeated(base))
        } else {
            material.baseColor = .init(tint: tint)
        }

        if let roughness = textures.roughness {
            material.roughness = .init(
                scale: roughnessScale,
                texture: repeated(roughness)
            )
        } else {
            material.roughness = .init(floatLiteral: roughnessScale)
        }

        if let normal = textures.normal {
            material.normal = .init(texture: repeated(normal))
        }

        material.metallic = .init(floatLiteral: 0)
        material.specular = .init(floatLiteral: specular)
        return material
    }

    private static func loadTexture(_ name: String) -> TextureResource? {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "jpg",
            subdirectory: "JSBSim/visuals/world"
        ) else { return nil }

        return try? TextureResource.load(contentsOf: url, withName: "stage020-\(name)")
    }

    private static func repeated(_ resource: TextureResource) -> MaterialParameters.Texture {
        var texture = MaterialParameters.Texture(resource)
        texture.sampler.modify { sampler in
            sampler.sAddressMode = .repeat
            sampler.tAddressMode = .repeat
            sampler.mipFilter = .linear
            sampler.minFilter = .linear
            sampler.magFilter = .linear
            sampler.maxAnisotropy = 8
        }
        return texture
    }

    private static func makeBuildingPalette() -> [PhysicallyBasedMaterial] {
        let colors: [UIColor] = [
            UIColor(red: 0.44, green: 0.45, blue: 0.43, alpha: 1),
            UIColor(red: 0.51, green: 0.47, blue: 0.40, alpha: 1),
            UIColor(red: 0.37, green: 0.40, blue: 0.42, alpha: 1),
            UIColor(red: 0.55, green: 0.53, blue: 0.47, alpha: 1),
            UIColor(red: 0.39, green: 0.36, blue: 0.33, alpha: 1),
            UIColor(red: 0.42, green: 0.46, blue: 0.47, alpha: 1),
            UIColor(red: 0.48, green: 0.42, blue: 0.36, alpha: 1)
        ]

        return colors.enumerated().map { index, color in
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: color)
            material.roughness = .init(floatLiteral: 0.82 + Float(index % 3) * 0.045)
            material.metallic = .init(floatLiteral: 0)
            material.specular = .init(floatLiteral: 0.17)
            return material
        }
    }

    private static func makeRoofPalette() -> [PhysicallyBasedMaterial] {
        let colors: [UIColor] = [
            UIColor(red: 0.115, green: 0.125, blue: 0.125, alpha: 1),
            UIColor(red: 0.16, green: 0.155, blue: 0.145, alpha: 1),
            UIColor(red: 0.20, green: 0.205, blue: 0.20, alpha: 1)
        ]

        return colors.map { color in
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: color)
            material.roughness = .init(floatLiteral: 0.90)
            material.metallic = .init(floatLiteral: 0.01)
            material.specular = .init(floatLiteral: 0.15)
            return material
        }
    }

    private static func terrainGradient(from normal: SIMD3<Float>) -> SIMD2<Float> {
        let y = max(abs(normal.y), 0.001)
        return [-normal.x / y, -normal.z / y]
    }

    private static func hash(_ value: Int) -> Float {
        let x = sin(Float(value) * 12.9898 + 78.233) * 43_758.5453
        return x - floor(x)
    }

    private static func clamp(_ value: Float, _ low: Float, _ high: Float) -> Float {
        Swift.min(Swift.max(value, low), high)
    }
}
