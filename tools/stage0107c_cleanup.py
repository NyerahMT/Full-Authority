from pathlib import Path
import re

factory = Path('Aircraft/PrototypeAircraftFactory.swift')
t = factory.read_text()

# Remove dead procedural control-surface helpers. Only source-mesh moving faces
# and functional landing gear remain.
pattern = re.compile(
    r'\n    private static func horizontalHingedSurface\(.*?\n    private static func gearAssembly\(',
    re.S,
)
t, n = pattern.subn('\n    private static func gearAssembly(', t, count=1)
if n != 1:
    raise SystemExit(f'procedural surface helper cleanup: {n}')

# Remove dead decorative light / ellipsoid / cylinder helpers.
pattern = re.compile(
    r'\n    private static func addNavigationLight\(.*?\n    // FlightGear\'s mature F-16 model is used only as hinge-direction',
    re.S,
)
t, n = pattern.subn("\n    // FlightGear's mature F-16 model is used only as hinge-direction", t, count=1)
if n != 1:
    raise SystemExit(f'decorative primitive helper cleanup: {n}')

# Remove old dynamic-Y helper now that left/right pivots are exact mirrors.
pattern = re.compile(
    r'\n    private static func meanSurfaceY\(.*?\n    \}\n\n    private static func makeMeshResource',
    re.S,
)
t, n = pattern.subn('\n    private static func makeMeshResource', t, count=1)
if n != 1:
    raise SystemExit(f'meanSurfaceY cleanup: {n}')

factory.write_text(t)

scene = Path('App/PrototypeSceneView.swift')
s = scene.read_text()

# Remove presentation branches for exterior entities that no longer exist.
pattern = re.compile(
    r'\n        if let afterburner = aircraft\.findEntity\(named: PrototypeAircraftFactory\.afterburnerName\) \{.*?\n        \}\n\n        if let nozzle = aircraft\.findEntity\(named: PrototypeAircraftFactory\.nozzleName\) \{.*?\n        \}\n\n        if let speedbrake = aircraft\.findEntity\(named: PrototypeAircraftFactory\.speedbrakeName\) \{.*?\n        \}\n',
    re.S,
)
s, n = pattern.subn('\n', s, count=1)
if n != 1:
    raise SystemExit(f'stale primitive presentation cleanup: {n}')

old = '''        if let left = aircraft.findEntity(named: PrototypeAircraftFactory.leftAileronName) {
            left.orientation = simd_quatf(angle: state.leftAileronRadians, axis: PrototypeAircraftFactory.leftAileronVisualAxis)
        }'''
new = '''        if let left = aircraft.findEntity(named: PrototypeAircraftFactory.leftAileronName) {
            // Match the mature F-16 visual convention: the left JSBSim aileron
            // sign is mirrored before rotation about the mirrored hinge axis.
            left.orientation = simd_quatf(angle: -state.leftAileronRadians, axis: PrototypeAircraftFactory.leftAileronVisualAxis)
        }'''
if s.count(old) != 1:
    raise SystemExit('left aileron presentation block mismatch')
s = s.replace(old, new, 1)
scene.write_text(s)
