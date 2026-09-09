from pathlib import Path

path = Path("App/Stage2WorldFactory.swift")
text = path.read_text()

call_anchor = """        addTerrain(to: root)\n        addAirbase(to: root)\n"""
call_replacement = """        addTerrain(to: root)\n        addGroundScaleCues(to: root)\n        addAirbase(to: root)\n"""

if "addGroundScaleCues(to: root)" not in text:
    if call_anchor not in text:
        raise SystemExit("Could not find Stage2WorldFactory.make() terrain anchor")
    text = text.replace(call_anchor, call_replacement, 1)

marker = "\n    // MARK: - Airbase\n"
insert = r'''

    // MARK: - Ground scale cues

    /// Adds fixed-size, terrain-conforming features that give the pilot a visual
    /// ruler at low altitude. The underlying heightfield remains authoritative;
    /// these are thin surface treatments only and never change collision geometry.
    private static func addGroundScaleCues(to root: Entity) {
        let fieldColors: [UIColor] = [
            UIColor(red: 0.205, green: 0.285, blue: 0.125, alpha: 1),
            UIColor(red: 0.255, green: 0.315, blue: 0.145, alpha: 1),
            UIColor(red: 0.315, green: 0.305, blue: 0.145, alpha: 1),
            UIColor(red: 0.285, green: 0.245, blue: 0.120, alpha: 1),
            UIColor(red: 0.180, green: 0.260, blue: 0.115, alpha: 1),
            UIColor(red: 0.335, green: 0.335, blue: 0.175, alpha: 1)
        ]

        // A deterministic patchwork around the primary operating area. Individual
        // fields are hundreds of metres across: large enough to read from altitude,
        // but small enough to create obvious ground rush below ~500 ft AGL.
        for row in -5...5 {
            for column in -5...5 {
                let selector = (row + 7) * 31 + (column + 7) * 17
                if selector.isMultiple(of: 4) { continue }

                let x = Float(column) * 2_150 + sin(Float(selector) * 0.63) * 390
                let z = Float(row) * 1_850 + cos(Float(selector) * 0.41) * 340

                // Leave the runway/apron complex clean and readable.
                if abs(x) < 1_550 && z > -2_400 && z < 5_900 { continue }

                // Fields belong on readable rolling ground, not cliff faces.
                let centerNormal = Stage2TerrainProfile.normal(east: x, north: z)
                if centerNormal.y < 0.94 { continue }

                let width = Float(520 + (selector * 37) % 620)
                let depth = Float(360 + (selector * 53) % 520)
                let rotationDegrees = Float((selector * 29) % 31) - 15
                let rotation = rotationDegrees * .pi / 180

                if let patch = makeTerrainPatch(
                    center: [x, z],
                    size: [width, depth],
                    rotation: rotation,
                    color: fieldColors[selector % fieldColors.count]
                ) {
                    root.addChild(patch)
                }
            }
        }

        // Narrow farm/service tracks create a second, smaller scale reference than
        // the existing 15.5 m paved roads. They conform to the same terrain profile.
        let trackColor = UIColor(red: 0.245, green: 0.215, blue: 0.145, alpha: 1)
        let tracks: [[SIMD2<Float>]] = [
            [[-10_800, -6_900], [-8_100, -5_500], [-5_300, -5_900], [-2_700, -7_200]],
            [[-9_600, 1_600], [-6_900, 900], [-4_600, 1_500], [-2_300, 3_100]],
            [[-10_200, 7_600], [-7_300, 6_700], [-4_200, 6_900], [-1_900, 8_300]],
            [[1_800, -7_800], [3_500, -5_900], [5_900, -5_200], [8_800, -5_900]],
            [[2_000, -2_700], [4_100, -1_800], [6_300, -2_200], [9_500, -900]],
            [[6_000, 8_700], [4_500, 7_100], [3_500, 5_200], [2_700, 3_900]],
            [[-7_800, -2_200], [-6_000, -500], [-4_400, 900], [-2_800, 1_700]],
            [[8_900, 6_200], [7_400, 4_500], [6_600, 2_500], [7_100, 700]]
        ]

        for track in tracks {
            for index in 0..<(track.count - 1) {
                if let ribbon = makeConformingRibbon(
                    from: track[index],
                    to: track[index + 1],
                    width: 4.2,
                    color: trackColor
                ) {
                    root.addChild(ribbon)
                }
            }
        }
    }

    private static func makeTerrainPatch(
        center: SIMD2<Float>,
        size: SIMD2<Float>,
        rotation: Float,
        color: UIColor
    ) -> ModelEntity? {
        let subdivisions = 5
        let pointsPerSide = subdivisions + 1
        let c = cos(rotation)
        let s = sin(rotation)

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(pointsPerSide * pointsPerSide)
        normals.reserveCapacity(pointsPerSide * pointsPerSide)
        indices.reserveCapacity(subdivisions * subdivisions * 6)

        for zIndex in 0...subdivisions {
            let v = Float(zIndex) / Float(subdivisions)
            for xIndex in 0...subdivisions {
                let u = Float(xIndex) / Float(subdivisions)
                let localX = (u - 0.5) * size.x
                let localZ = (v - 0.5) * size.y
                let worldX = center.x + localX * c - localZ * s
                let worldZ = center.y + localX * s + localZ * c
                let height = Stage2TerrainProfile.heightMeters(east: worldX, north: worldZ) + 0.055

                positions.append([worldX, height, worldZ])
                normals.append(Stage2TerrainProfile.normal(east: worldX, north: worldZ))
            }
        }

        for zIndex in 0..<subdivisions {
            for xIndex in 0..<subdivisions {
                let i0 = UInt32(zIndex * pointsPerSide + xIndex)
                let i1 = i0 + 1
                let i2 = UInt32((zIndex + 1) * pointsPerSide + xIndex)
                let i3 = i2 + 1
                indices.append(contentsOf: [i0, i2, i1, i1, i2, i3])
            }
        }

        var descriptor = MeshDescriptor(name: "Ground scale field")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }

        return ModelEntity(
            mesh: mesh,
            materials: [SimpleMaterial(color: color, roughness: 0.99, isMetallic: false)]
        )
    }
'''

if "private static func addGroundScaleCues" not in text:
    if marker not in text:
        raise SystemExit("Could not find Airbase MARK anchor")
    text = text.replace(marker, insert + marker, 1)

path.write_text(text)

# Fail loudly if either half of the pass did not land.
patched = path.read_text()
required = [
    "addGroundScaleCues(to: root)",
    "private static func addGroundScaleCues",
    "private static func makeTerrainPatch",
    "Ground scale field",
]
for token in required:
    if token not in patched:
        raise SystemExit(f"Stage 015 verification failed: missing {token}")

print("Stage 015 terrain depth pass applied")
