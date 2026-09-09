from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    n = text.count(old)
    if n != 1:
        raise SystemExit(f'{label}: expected one anchor, found {n}')
    return text.replace(old, new, 1)

# Replace the continuous exported surface with a regular 50 m height grid whose
# triangle interpolation exactly matches the RealityKit mesh topology.
mm = Path('Simulation/Bridge/FAJSBSimBridge.mm')
text = mm.read_text(encoding='utf-8')
pattern = re.compile(r'extern "C" double FATerrainHeightMeters\(double eastMeters, double northMeters\) \{.*?\n\}\n\n@interface FAJSBSimBridge', re.S)
match = pattern.search(text)
if not match:
    raise SystemExit('canonical terrain function not found')
new = r'''double FATerrainAnalyticHeightMeters(double eastMeters, double northMeters) {
    double base =
        78.0 * std::sin(northMeters / 2750.0) * std::cos(eastMeters / 3500.0) +
        52.0 * std::sin((eastMeters + northMeters) / 1820.0) +
        36.0 * std::cos((eastMeters - 0.45 * northMeters) / 2250.0) +
        19.0 * std::sin((1.25 * eastMeters + 0.72 * northMeters) / 820.0) +
        12.0 * std::cos((0.65 * eastMeters - 1.10 * northMeters) / 510.0) +
        6.5 * std::sin((1.80 * eastMeters + 1.35 * northMeters) / 285.0);

    const double ridge1East = (eastMeters + 6500.0) / 2350.0;
    const double ridge1North = (northMeters - 9000.0) / 3300.0;
    base += 245.0 * std::exp(-0.5 * (ridge1East * ridge1East + ridge1North * ridge1North));

    const double ridge2East = (eastMeters - 7200.0) / 2500.0;
    const double ridge2North = (northMeters - 6500.0) / 2750.0;
    base += 185.0 * std::exp(-0.5 * (ridge2East * ridge2East + ridge2North * ridge2North));

    const double ridge3East = (eastMeters + 10500.0) / 3200.0;
    const double ridge3North = (northMeters + 2500.0) / 2600.0;
    base += 210.0 * std::exp(-0.5 * (ridge3East * ridge3East + ridge3North * ridge3North));

    const double valleyEast = (eastMeters - 4200.0) / 2300.0;
    const double valleyNorth = (northMeters - 9800.0) / 5000.0;
    base -= 92.0 * std::exp(-0.5 * (valleyEast * valleyEast + valleyNorth * valleyNorth));

    const double dx = std::max(std::abs(eastMeters) - 1000.0, 0.0);
    const double dz = std::max(std::abs(northMeters - 2000.0) - 3600.0, 0.0);
    const double distanceOutsideAirfield = std::hypot(dx, dz);
    return base * SmoothStep(distanceOutsideAirfield / 1250.0);
}

extern "C" double FATerrainHeightMeters(double eastMeters, double northMeters) {
    // Same regular elevation grid and diagonal split used by Stage2WorldFactory.
    // This makes visual triangle height and JSBSim contact height identical.
    constexpr double grid = 50.0;
    const double x0 = std::floor(eastMeters / grid) * grid;
    const double z0 = std::floor(northMeters / grid) * grid;
    const double tx = (eastMeters - x0) / grid;
    const double tz = (northMeters - z0) / grid;

    const double h00 = FATerrainAnalyticHeightMeters(x0, northMeters - tz * grid);
    const double h10 = FATerrainAnalyticHeightMeters(x0 + grid, northMeters - tz * grid);
    const double h01 = FATerrainAnalyticHeightMeters(x0, northMeters - tz * grid + grid);
    const double h11 = FATerrainAnalyticHeightMeters(x0 + grid, northMeters - tz * grid + grid);

    if (tx + tz <= 1.0) {
        return h00 + tx * (h10 - h00) + tz * (h01 - h00);
    }
    return h11 + (1.0 - tz) * (h10 - h11) + (1.0 - tx) * (h01 - h11);
}

@interface FAJSBSimBridge'''
text = text[:match.start()] + new + text[match.end():]
mm.write_text(text, encoding='utf-8')

world = Path('App/Stage2WorldFactory.swift')
text = world.read_text(encoding='utf-8')
text = replace_once(text, '        let resolution = 81\n', '        let resolution = 121\n', '50 m terrain grid')
# Tile-to-tile color changes were visible at altitude. Let Stage 023 parcels carry
# macro variation instead of six-kilometre square tint changes.
old_palette = '''        let tints: [UIColor] = [
            UIColor(red: 0.46, green: 0.54, blue: 0.34, alpha: 1),
            UIColor(red: 0.50, green: 0.56, blue: 0.37, alpha: 1),
            UIColor(red: 0.42, green: 0.50, blue: 0.31, alpha: 1),
            UIColor(red: 0.48, green: 0.52, blue: 0.34, alpha: 1),
            UIColor(red: 0.43, green: 0.49, blue: 0.30, alpha: 1),
            UIColor(red: 0.49, green: 0.55, blue: 0.35, alpha: 1)
        ]'''
new_palette = '''        let tints: [UIColor] = Array(
            repeating: UIColor(red: 0.465, green: 0.525, blue: 0.325, alpha: 1),
            count: 6
        )'''
text = replace_once(text, old_palette, new_palette, 'uniform base terrain tint')
# Remove dead rock classification work now that the high-altitude triangle overlay is gone.
text = text.replace('        var rockIndices: [UInt32] = []\n', '')
text = text.replace('        rockIndices.reserveCapacity(indices.capacity / 5)\n', '')
rock_class = re.compile(r'''\n\s*let centerIndex = zIndex \* resolution \+ xIndex\n\s*let n = normals\[centerIndex\]\n\s*let h = positions\[centerIndex\]\.y\n\s*let worldX = centerX \+ positions\[centerIndex\]\.x\n\s*let worldZ = centerZ \+ positions\[centerIndex\]\.z\n\s*let breakup = sin\(worldX / 610\.0 \+ worldZ / 930\.0\) \* cos\(worldZ / 470\.0\)\n\s*if n\.y < 0\.955 \|\| h > 115 \+ breakup \* 32 \{\n\s*rockIndices\.append\(contentsOf: cell\)\n\s*\}\n''')
text, n = rock_class.subn('\n', text, count=1)
if n != 1:
    raise SystemExit(f'rock classification block: expected 1, found {n}')
world.write_text(text, encoding='utf-8')

# Lower and strengthen the special menu pass based on the phone test.
menu = Path('App/Stage022MainMenu.swift')
text = menu.read_text(encoding='utf-8')
text = replace_once(text, '        let y: Float = 34 + 1.2 * sin(t * 0.72)\n',
                    '        let y: Float = 21 + 0.7 * sin(t * 0.72)\n', 'lower supersonic pass')
text = replace_once(text, '        flyby.volume = 0.82\n', '        flyby.volume = 1.0\n', 'flyby player volume')
old_flyby = '                channels[ch][frame] = gain * approach * (0.15 * engineBody + 0.13 * turbulent)\n'
new_flyby = '''                let sample = 2.25 * gain * approach * (0.15 * engineBody + 0.13 * turbulent)
                channels[ch][frame] = min(max(sample, -0.92), 0.92)
'''
text = replace_once(text, old_flyby, new_flyby, 'flyby buffer gain')
text = replace_once(text, '            let pressureMix: Float = 0.93 * shock + 0.42 * thump\n',
                    '            let pressureMix: Float = 1.65 * shock + 0.72 * thump\n', 'sonic boom gain')
menu.write_text(text, encoding='utf-8')

print('Stage 023 terrain finalization applied')
