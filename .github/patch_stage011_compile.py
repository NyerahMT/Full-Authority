from pathlib import Path

factory = Path('Aircraft/PrototypeAircraftFactory.swift')
f = factory.read_text()
old = 'alpha: max(0.11, 0.30 - Float(index) * 0.038)'
new = 'alpha: CGFloat(max(0.11, 0.30 - Float(index) * 0.038))'
if f.count(old) != 1:
    raise SystemExit('shock alpha anchor mismatch')
f = f.replace(old, new, 1)
factory.write_text(f)

scene = Path('App/PrototypeSceneView.swift')
s = scene.read_text()
replacements = {
    'let pressureExpansion = clamp(sqrt(2_116.22 / max(state.ambientPressurePSF, 450)), 0.90, 1.62)': 'let pressureExpansion = clamp(sqrtf(2_116.22 / max(state.ambientPressurePSF, 450)), 0.90, 1.62)',
    'halo.position.z = 0.5 * halo.scale.y': 'halo.position = [0, 0, 0.5 * halo.scale.y]',
    'outer.position.z = 0.5 * outer.scale.y': 'outer.position = [0, 0, 0.5 * outer.scale.y]',
    'inner.position.z = 0.5 * inner.scale.y': 'inner.position = [0, 0, 0.5 * inner.scale.y]',
    'core.position.z = 0.5 * core.scale.y': 'core.position = [0, 0, 0.5 * core.scale.y]',
    'exp(-7.0 * t)': 'expf(-7.0 * t)',
    'exp(-2.0 * t)': 'expf(-2.0 * t)',
}
for old, new in replacements.items():
    if s.count(old) != 1:
        raise SystemExit(f'compile cleanup anchor mismatch: {old}')
    s = s.replace(old, new, 1)
scene.write_text(s)
