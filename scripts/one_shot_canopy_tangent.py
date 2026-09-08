from pathlib import Path

path = Path('Aircraft/PrototypeAircraftFactory.swift')
text = path.read_text()

old = """        var indices: [UInt32] = []
        var faceMaterials: [UInt32] = []
"""
new = """        var indices: [UInt32] = []
        var faceMaterials: [UInt32] = []
        var parsedTriangles: [[ParsedVertex]] = []
"""
if old not in text:
    raise SystemExit('declaration anchor not found')
text = text.replace(old, new, 1)

old = """                if classifyF16Paint {
                    faceMaterials.append(f16MaterialIndex(
                        triangle[0],
                        triangle[1],
                        triangle[2]
                    ))
                }
"""
new = """                if classifyF16Paint {
                    parsedTriangles.append(triangle)
                }
"""
if old not in text:
    raise SystemExit('face classification anchor not found')
text = text.replace(old, new, 1)

old = """        guard positions.count >= 3, indices.count >= 3 else {
            throw AssetError.invalid(name)
        }

        var descriptor = MeshDescriptor(name: \"Authored F-16 \\(name)\")
"""
new = """        guard positions.count >= 3, indices.count >= 3 else {
            throw AssetError.invalid(name)
        }

        if classifyF16Paint {
            let canopyFaces = canopyFaceIndices(in: parsedTriangles)
            faceMaterials = parsedTriangles.enumerated().map { index, triangle in
                f16MaterialIndex(
                    triangle[0],
                    triangle[1],
                    triangle[2],
                    isCanopy: canopyFaces.contains(index)
                )
            }
        }

        var descriptor = MeshDescriptor(name: \"Authored F-16 \\(name)\")
"""
if old not in text:
    raise SystemExit('descriptor anchor not found')
text = text.replace(old, new, 1)

start = text.index('    private static func f16MaterialIndex(')
end = text.rindex('\n}')
replacement = r'''    private struct WeldedVertexKey: Hashable {
        let x: Int
        let y: Int
        let z: Int

        init(_ position: SIMD3<Float>) {
            let scale: Float = 10_000
            x = Int((position.x * scale).rounded())
            y = Int((position.y * scale).rounded())
            z = Int((position.z * scale).rounded())
        }
    }

    private struct WeldedEdgeKey: Hashable {
        let a: WeldedVertexKey
        let b: WeldedVertexKey

        init(_ p0: SIMD3<Float>, _ p1: SIMD3<Float>) {
            let k0 = WeldedVertexKey(p0)
            let k1 = WeldedVertexKey(p1)
            let k0First = k0.x < k1.x ||
                (k0.x == k1.x && k0.y < k1.y) ||
                (k0.x == k1.x && k0.y == k1.y && k0.z <= k1.z)

            if k0First {
                a = k0
                b = k1
            } else {
                a = k1
                b = k0
            }
        }
    }

    private static func canopyFaceIndices(in triangles: [[ParsedVertex]]) -> Set<Int> {
        guard !triangles.isEmpty else { return [] }

        var centroids = Array(repeating: SIMD3<Float>.zero, count: triangles.count)
        var geometricNormals = Array(repeating: SIMD3<Float>(0, 1, 0), count: triangles.count)
        var edgeFaces: [WeldedEdgeKey: [Int]] = [:]

        for (index, triangle) in triangles.enumerated() where triangle.count == 3 {
            let a = triangle[0].position
            let b = triangle[1].position
            let c = triangle[2].position
            centroids[index] = (a + b + c) / 3

            let cross = simd_cross(b - a, c - a)
            if simd_length_squared(cross) > 0.00000001 {
                geometricNormals[index] = simd_normalize(cross)
            }

            for edge in [
                WeldedEdgeKey(a, b),
                WeldedEdgeKey(b, c),
                WeldedEdgeKey(c, a)
            ] {
                edgeFaces[edge, default: []].append(index)
            }
        }

        // Use position only to pick the canopy crown seed and keep the flood in
        // the cockpit neighborhood. The border itself comes from the authored
        // mesh tangent discontinuity at the canopy sill/frame.
        let seedCandidates = triangles.indices.filter { index in
            let p = centroids[index]
            return abs(p.x) < 0.80 &&
                p.z > 1.65 && p.z < 4.55 &&
                p.y > 0.60
        }

        guard let seed = seedCandidates.max(by: { centroids[$0].y < centroids[$1].y }) else {
            return []
        }

        // Adjacent canopy facets can be coarse, so allow up to 36 degrees of
        // local curvature. The hard sill tangent is sharper and stops the flood.
        let smoothTangentCosine = cos(Float.pi * 36.0 / 180.0)
        var selected: Set<Int> = [seed]
        var queue: [Int] = [seed]
        var cursor = 0

        while cursor < queue.count {
            let current = queue[cursor]
            cursor += 1
            let triangle = triangles[current]
            guard triangle.count == 3 else { continue }

            let a = triangle[0].position
            let b = triangle[1].position
            let c = triangle[2].position
            let edges = [
                WeldedEdgeKey(a, b),
                WeldedEdgeKey(b, c),
                WeldedEdgeKey(c, a)
            ]

            for edge in edges {
                for neighbor in edgeFaces[edge] ?? [] where neighbor != current {
                    guard !selected.contains(neighbor) else { continue }

                    let p = centroids[neighbor]
                    guard abs(p.x) < 1.18,
                          p.z > 1.35, p.z < 4.85,
                          p.y > 0.34 else {
                        continue
                    }

                    let tangentCosine = simd_dot(
                        geometricNormals[current],
                        geometricNormals[neighbor]
                    )
                    guard tangentCosine >= smoothTangentCosine else {
                        continue
                    }

                    selected.insert(neighbor)
                    queue.append(neighbor)
                }
            }
        }

        return selected
    }

    private static func f16MaterialIndex(
        _ a: ParsedVertex,
        _ b: ParsedVertex,
        _ c: ParsedVertex,
        isCanopy: Bool
    ) -> UInt32 {
        let centroid = (a.position + b.position + c.position) / 3
        let averageNormal = simd_normalize(a.normal + b.normal + c.normal)

        if isCanopy {
            return Paint.canopy.rawValue
        }

        // Characteristic darker radome.
        if abs(centroid.x) < 1.35,
           centroid.z > 5.15,
           centroid.y > -0.85,
           centroid.y < 0.95 {
            return Paint.radome.rawValue
        }

        // Metallic F100 nozzle and tailpipe.
        if abs(centroid.x) < 0.90,
           abs(centroid.y) < 0.90,
           centroid.z < -5.45 {
            return Paint.exhaust.rawValue
        }

        // Intake lip / lower inlet area.
        if abs(centroid.x) < 1.30,
           centroid.y < -0.42,
           centroid.z > -0.15,
           centroid.z < 3.35 {
            return Paint.intake.rawValue
        }

        // Hill Gray-style darker upper surfaces and lighter lower surfaces.
        if centroid.y < -0.10 || averageNormal.y < -0.28 {
            return Paint.lower.rawValue
        }

        return Paint.upper.rawValue
    }
'''
text = text[:start] + replacement + text[end:]
path.write_text(text)
