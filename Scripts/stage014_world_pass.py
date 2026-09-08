from pathlib import Path


def replace(path: str, old: str, new: str, count: int = 1):
    p = Path(path)
    s = p.read_text()
    if old not in s:
        raise SystemExit(f"pattern not found in {path}: {old[:120]!r}")
    p.write_text(s.replace(old, new, count))

# ---------------- Aerodynamic FX: keep physics, fix the giant white geometry ----------------
p = Path('App/Stage2FlightEffects.swift')
s = p.read_text()
s = s.replace('let gIntensity = clamp((abs(state.loadFactorG) - 2.4) / 4.8, 0, 1)',
              'let gIntensity = clamp((abs(state.loadFactorG) - 2.8) / 5.2, 0, 1)', 1)
s = s.replace('let alphaIntensity = clamp((abs(state.angleOfAttackDegrees) - 6.8) / 13.5, 0, 1)',
              'let alphaIntensity = clamp((abs(state.angleOfAttackDegrees) - 7.5) / 14.0, 0, 1)', 1)
s = s.replace('left.position = [-3.62, -0.08 + 0.008 * sin(Float(simulationTime) * 24.0), -1.72]',
              'left.position = [-3.42, -0.04 + 0.006 * sin(Float(simulationTime) * 24.0), -1.35]', 1)
s = s.replace('left.scale = [0.68 + vaporIntensity * 0.52, 0.62 + vaporIntensity * 0.34, 0.72 + vaporIntensity * 1.18]',
              'left.scale = [0.34 + vaporIntensity * 0.26, 0.24 + vaporIntensity * 0.20, 0.32 + vaporIntensity * 0.54]', 1)
s = s.replace('setEffectAlpha(left, alpha: 0.020 + vaporIntensity * 0.155)',
              'setEffectAlpha(left, alpha: 0.004 + vaporIntensity * 0.038)', 1)
s = s.replace('right.position = [3.62, -0.08 + 0.008 * sin(Float(simulationTime) * 25.0 + 0.8), -1.72]',
              'right.position = [3.42, -0.04 + 0.006 * sin(Float(simulationTime) * 25.0 + 0.8), -1.35]', 1)
s = s.replace('right.scale = [0.68 + vaporIntensity * 0.52, 0.62 + vaporIntensity * 0.34, 0.72 + vaporIntensity * 1.18]',
              'right.scale = [0.34 + vaporIntensity * 0.26, 0.24 + vaporIntensity * 0.20, 0.32 + vaporIntensity * 0.54]', 1)
s = s.replace('setEffectAlpha(right, alpha: 0.020 + vaporIntensity * 0.155)',
              'setEffectAlpha(right, alpha: 0.004 + vaporIntensity * 0.038)', 1)
s = s.replace('let moisture = clamp((iceRH - 0.64) / 0.40, 0, 1)',
              'let moisture = clamp((iceRH - 0.68) / 0.36, 0, 1)', 1)
s = s.replace('let transonicPeak = exp(-pow((mach - 1.005) / 0.038, 2))',
              'let transonicPeak = exp(-pow((mach - 1.000) / 0.034, 2))', 1)
s = s.replace('let visible = mach > 0.955 && mach < 1.085 && intensity > 0.025',
              'let visible = mach > 0.958 && mach < 1.070 && intensity > 0.040', 1)
s = s.replace('let flutter = 1 + 0.018 * sin(Float(simulationTime) * (18 + Float(layer) * 2.4) + phase)',
              'let flutter = 1 + 0.012 * sin(Float(simulationTime) * (18 + Float(layer) * 2.4) + phase)', 1)
s = s.replace('let layerScale = 0.92 + Float(layer) * 0.08',
              'let layerScale = 0.72 + Float(layer) * 0.065', 1)
s = s.replace('0.94 + intensity * 0.22', '0.72 + intensity * 0.12', 1)
s = s.replace('cloud.position.y = -0.02 + 0.04 * sin(Float(simulationTime) * 11 + phase)',
              'cloud.position.y = -0.04 + 0.018 * sin(Float(simulationTime) * 11 + phase)', 1)
s = s.replace('setEffectAlpha(cloud, alpha: (0.050 - Float(layer) * 0.010) * intensity)',
              'setEffectAlpha(cloud, alpha: (0.012 - Float(layer) * 0.0025) * intensity)', 1)
s = s.replace('let segments = 22', 'let segments = 18', 1)
s = s.replace('let z = -0.10 - 7.4 * t', 'let z = -0.08 - 4.4 * t', 1)
s = s.replace('let width = 0.08 + 0.56 * envelope', 'let width = 0.055 + 0.34 * envelope', 1)
s = s.replace('let ripple = sin(t * 17.0 + phase + Float(sheet)) * 0.045 * t',
              'let ripple = sin(t * 17.0 + phase + Float(sheet)) * 0.026 * t', 1)
s = s.replace('let z = 2.7 - 6.2 * t', 'let z = 1.75 - 3.9 * t', 1)
s = s.replace('let baseRadius = 0.72 + 3.25 * center', 'let baseRadius = 0.48 + 1.95 * center', 1)
s = s.replace('sin(angle) * radius * 0.72', 'sin(angle) * radius * 0.54', 1)
s = s.replace('UnlitMaterial(color: UIColor(white: 0.985, alpha: CGFloat(clamp(alpha, 0, 1))))',
              'UnlitMaterial(color: UIColor(red: 0.86, green: 0.92, blue: 0.98, alpha: CGFloat(clamp(alpha, 0, 1))))', 1)
p.write_text(s)

# ---------------- Terrain/world: more geometry, more relief, more landmarks ----------------
p = Path('App/Stage2WorldFactory.swift')
s = p.read_text()
s = s.replace('let resolution = 49', 'let resolution = 81', 1)
s = s.replace('''        let tints: [UIColor] = [
            UIColor(red: 0.86, green: 0.91, blue: 0.80, alpha: 1),
            UIColor(red: 0.93, green: 0.91, blue: 0.79, alpha: 1),
            UIColor(red: 0.80, green: 0.88, blue: 0.76, alpha: 1),
            UIColor(red: 0.90, green: 0.86, blue: 0.73, alpha: 1)
        ]''', '''        let tints: [UIColor] = [
            UIColor(red: 0.48, green: 0.56, blue: 0.34, alpha: 1),
            UIColor(red: 0.57, green: 0.57, blue: 0.35, alpha: 1),
            UIColor(red: 0.39, green: 0.50, blue: 0.30, alpha: 1),
            UIColor(red: 0.59, green: 0.52, blue: 0.31, alpha: 1),
            UIColor(red: 0.43, green: 0.47, blue: 0.28, alpha: 1),
            UIColor(red: 0.53, green: 0.60, blue: 0.39, alpha: 1)
        ]''', 1)
s = s.replace('tint: UIColor(red: 0.25, green: 0.34, blue: 0.17, alpha: 1)',
              'tint: UIColor(red: 0.24, green: 0.32, blue: 0.16, alpha: 1)', 1)
s = s.replace('material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.97)',
              'material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.90)', 1)
s = s.replace('''        let rocks: [UIColor] = [
            UIColor(red: 0.29, green: 0.29, blue: 0.26, alpha: 1),
            UIColor(red: 0.34, green: 0.32, blue: 0.27, alpha: 1),
            UIColor(red: 0.27, green: 0.30, blue: 0.27, alpha: 1)
        ]''', '''        let rocks: [UIColor] = [
            UIColor(red: 0.24, green: 0.235, blue: 0.21, alpha: 1),
            UIColor(red: 0.31, green: 0.285, blue: 0.235, alpha: 1),
            UIColor(red: 0.225, green: 0.25, blue: 0.225, alpha: 1),
            UIColor(red: 0.36, green: 0.325, blue: 0.255, alpha: 1)
        ]''', 1)
# More road corridors so the landscape gives scale from altitude.
s = s.replace('''            [[2_100, 7_000], [2_400, 4_800], [3_500, 3_000], [5_800, 2_500]]
        ]''', '''            [[2_100, 7_000], [2_400, 4_800], [3_500, 3_000], [5_800, 2_500]],
            [[-8_000, 6_000], [-5_800, 4_900], [-4_200, 2_300], [-2_900, 300]],
            [[-7_200, 8_200], [-4_500, 7_500], [-1_800, 7_900], [1_200, 7_200]],
            [[4_600, -3_800], [3_200, -1_800], [2_100, 400], [1_900, 2_600]],
            [[6_500, 6_400], [5_400, 5_000], [4_900, 3_600], [5_800, 2_500]]
        ]''', 1)
# Bigger town.
s = s.replace('for row in 0..<6 {\n            for column in 0..<8 {',
              'for row in 0..<8 {\n            for column in 0..<10 {', 1)
s = s.replace('let selector = row * 8 + column', 'let selector = row * 10 + column', 1)
s = s.replace('let x = 2_700 + Float(column) * 112', 'let x = 2_650 + Float(column) * 108', 1)
s = s.replace('let z = 3_000 + Float(row) * 118', 'let z = 2_900 + Float(row) * 112', 1)
# Much denser vegetation belts while staying bounded for mobile.
s = s.replace('for belt in 0..<15 {', 'for belt in 0..<28 {', 1)
s = s.replace('let baseX = Float(-7_400 + belt * 980)', 'let baseX = Float(-9_200 + belt * 690)', 1)
s = s.replace('let baseZ = Float(1_100 + (belt % 5) * 1_280)', 'let baseZ = Float(-1_600 + (belt % 7) * 1_280)', 1)
s = s.replace('for treeIndex in 0..<11 {', 'for treeIndex in 0..<16 {', 1)
s = s.replace('let x = baseX + Float(treeIndex) * 78 + sin(Float(belt + treeIndex) * 1.91) * 32',
              'let x = baseX + Float(treeIndex) * 64 + sin(Float(belt + treeIndex) * 1.91) * 42', 1)
s = s.replace('let z = baseZ + sin(Float(treeIndex) * 0.82 + Float(belt)) * 155',
              'let z = baseZ + sin(Float(treeIndex) * 0.82 + Float(belt)) * 230', 1)
# Add runway rubber/patch detail before taxiway construction.
needle = '''        for index in 0..<8 {
            addRunwayLight(to: root, position: [0, 0.24, -450 - Float(index) * 55], color: .white)
        }

        let parallelTaxiway'''
replacement = '''        for index in 0..<8 {
            addRunwayLight(to: root, position: [0, 0.24, -450 - Float(index) * 55], color: .white)
        }

        // Subtle rubber, seams and repaired slabs keep the runway from reading
        // like one giant perfect gray rectangle at low altitude.
        let rubber = UIColor(red: 0.026, green: 0.028, blue: 0.030, alpha: 1)
        for z: Float in [-250, -120, 3_980, 4_110] {
            for x: Float in [-5.4, -2.0, 2.0, 5.4] {
                let skid = block(size: [1.4, 0.012, 84], color: rubber, roughness: 0.99, cornerRadius: 0.05)
                skid.position = [x, 0.126, z]
                root.addChild(skid)
            }
        }
        let seam = UIColor(red: 0.075, green: 0.078, blue: 0.080, alpha: 1)
        for z in stride(from: -300, through: 4_300, by: 240) {
            let joint = block(size: [62, 0.010, 0.18], color: seam, roughness: 0.99, cornerRadius: 0)
            joint.position = [0, 0.126, Float(z)]
            root.addChild(joint)
        }

        let parallelTaxiway'''
if needle not in s:
    raise SystemExit('runway detail insertion point not found')
s = s.replace(needle, replacement, 1)
p.write_text(s)

# ---------------- Physical terrain profile: much more readable relief ----------------
p = Path('Simulation/FlightSimulation.swift')
s = p.read_text()
old = '''        var base =
            55.0 * sin(n / 2800.0) * cos(e / 3600.0) +
            38.0 * sin((e + n) / 1900.0) +
            28.0 * cos((e - 0.45 * n) / 2400.0)

        let ridge1East = (e + 6500.0) / 2500.0
        let ridge1North = (n - 9000.0) / 3500.0
        base += 145.0 * exp(-0.5 * (ridge1East * ridge1East + ridge1North * ridge1North))

        let ridge2East = (e - 7200.0) / 2800.0
        let ridge2North = (n - 6500.0) / 3000.0
        base += 105.0 * exp(-0.5 * (ridge2East * ridge2East + ridge2North * ridge2North))
'''
new = '''        // Layered terrain at several spatial scales. The airfield flattening
        // below still guarantees the runway/contact surface stays usable, while
        // the wider world now has ridges, valleys and smaller rolling relief that
        // actually communicates altitude and speed.
        var base =
            78.0 * sin(n / 2750.0) * cos(e / 3500.0) +
            52.0 * sin((e + n) / 1820.0) +
            36.0 * cos((e - 0.45 * n) / 2250.0) +
            19.0 * sin((1.25 * e + 0.72 * n) / 820.0) +
            12.0 * cos((0.65 * e - 1.10 * n) / 510.0) +
            6.5 * sin((1.80 * e + 1.35 * n) / 285.0)

        let ridge1East = (e + 6500.0) / 2350.0
        let ridge1North = (n - 9000.0) / 3300.0
        base += 245.0 * exp(-0.5 * (ridge1East * ridge1East + ridge1North * ridge1North))

        let ridge2East = (e - 7200.0) / 2500.0
        let ridge2North = (n - 6500.0) / 2750.0
        base += 185.0 * exp(-0.5 * (ridge2East * ridge2East + ridge2North * ridge2North))

        let ridge3East = (e + 10500.0) / 3200.0
        let ridge3North = (n + 2500.0) / 2600.0
        base += 210.0 * exp(-0.5 * (ridge3East * ridge3East + ridge3North * ridge3North))

        // Cut a broad valley through the eastern side so the world has negative
        // as well as positive forms instead of looking like rolling noise only.
        let valleyEast = (e - 4200.0) / 2300.0
        let valleyNorth = (n - 9800.0) / 5000.0
        base -= 92.0 * exp(-0.5 * (valleyEast * valleyEast + valleyNorth * valleyNorth))
'''
if old not in s:
    raise SystemExit('terrain profile block not found')
s = s.replace(old, new, 1)
s = s.replace('let terrainBlend = smoothStep(distanceOutsideAirfield / 1800.0)',
              'let terrainBlend = smoothStep(distanceOutsideAirfield / 1250.0)', 1)
s = s.replace('let sample: Float = 20', 'let sample: Float = 8', 1)
p.write_text(s)

# ---------------- Scene lighting: keep definition without clipping the airplane white ----------------
p = Path('App/PrototypeSceneView.swift')
s = p.read_text()
s = s.replace('intensity: 12_600', 'intensity: 7_800', 1)
s = s.replace('intensity: 520', 'intensity: 340', 1)
p.write_text(s)
