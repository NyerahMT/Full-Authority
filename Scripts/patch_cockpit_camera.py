from pathlib import Path

p = Path('App/PrototypeSceneView.swift')
s = p.read_text()
old = '''        case .cockpit:
            // Fixed eyepoint in the F-16 seat. Free-look below rotates the head,
            // not the eyepoint, so the runway does not slide around the cockpit.
            localCameraOffset = [0, 0.88, 3.64]
            localLookPoint = [0, 0.88, 90]
            fieldOfView = 66
            pullbackScale = 0
'''
new = '''        case .cockpit:
            // Pilot eyepoint sits near the top of the seat/headrest, not up against
            // the instrument panel. Free-look rotates the head around this fixed
            // seated position so the cockpit has believable depth and parallax.
            localCameraOffset = [0, 1.08, 3.05]
            localLookPoint = [0, 1.08, 90]
            fieldOfView = 66
            pullbackScale = 0
'''
if old not in s:
    raise SystemExit('Cockpit camera block changed unexpectedly')
p.write_text(s.replace(old, new))
