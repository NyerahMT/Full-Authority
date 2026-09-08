from pathlib import Path

path = Path('Aircraft/PrototypeAircraftFactory.swift')
text = path.read_text()

replacements = {
'''        halo.position = meshLipCompensation
        halo.scale = [1.15, 2.15, 1.15]''': '''        halo.scale = [1.15, 2.15, 1.15]
        halo.position = [0, 0, 0.5 * halo.scale.y]''',
'''        outer.position = meshLipCompensation
        outer.scale = [0.94, 1.90, 1.02]''': '''        outer.scale = [0.94, 1.90, 1.02]
        outer.position = [0, 0, 0.5 * outer.scale.y]''',
'''        inner.position = meshLipCompensation
        inner.scale = [0.58, 1.52, 0.66]''': '''        inner.scale = [0.58, 1.52, 0.66]
        inner.position = [0, 0, 0.5 * inner.scale.y]''',
'''        core.position = meshLipCompensation
        core.scale = [0.24, 1.12, 0.30]''': '''        core.scale = [0.24, 1.12, 0.30]
        core.position = [0, 0, 0.5 * core.scale.y]''',
}

for old, new in replacements.items():
    if text.count(old) != 1:
        raise SystemExit(f'factory alignment anchor mismatch: {old[:40]}')
    text = text.replace(old, new, 1)

# The fixed literal compensation is no longer needed; each layer's compensation
# follows its current axial scale so the plume lip stays welded to the nozzle.
old = '        let meshLipCompensation = SIMD3<Float>(0, 0, 0.50)\n\n'
if text.count(old) != 1:
    raise SystemExit('meshLipCompensation declaration mismatch')
text = text.replace(old, '', 1)
path.write_text(text)

scene = Path('App/PrototypeSceneView.swift')
s = scene.read_text()
updates = {
'''                halo.scale = [1.15 * width, 2.15 * length, 1.15 * width]
''': '''                halo.scale = [1.15 * width, 2.15 * length, 1.15 * width]
                halo.position.z = 0.5 * halo.scale.y
''',
'''                outer.scale = [0.94 * width, 1.90 * length, 1.02 * width]
''': '''                outer.scale = [0.94 * width, 1.90 * length, 1.02 * width]
                outer.position.z = 0.5 * outer.scale.y
''',
'''                inner.scale = [0.58 * width * pulse, 1.52 * length, 0.66 * width * pulse]
''': '''                inner.scale = [0.58 * width * pulse, 1.52 * length, 0.66 * width * pulse]
                inner.position.z = 0.5 * inner.scale.y
''',
'''                core.scale = [0.24 * width * pulse, 1.12 * length, 0.30 * width * pulse]
''': '''                core.scale = [0.24 * width * pulse, 1.12 * length, 0.30 * width * pulse]
                core.position.z = 0.5 * core.scale.y
''',
}
for old, new in updates.items():
    if s.count(old) != 1:
        raise SystemExit(f'presentation alignment anchor mismatch: {old[:45]}')
    s = s.replace(old, new, 1)
scene.write_text(s)
