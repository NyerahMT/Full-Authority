from pathlib import Path

stage_path = Path('scripts/stage-f16-calibration.sh')
text = stage_path.read_text(encoding='utf-8')
text = text.replace('MODEL_ROOT="$APP_PATH/Models"\n\nF16_VISUAL_COMMIT="e0757b1473736d5b2a64351cba4be46a20abf53e"\nF16_VISUAL_BASE="https://raw.githubusercontent.com/srdanrasic/R4/${F16_VISUAL_COMMIT}"\nF16_VISUAL_PATH="demo/R4%20iOS%20Demo/Resources/Meshes/f16.obj"\n\n', '')
text = text.replace('mkdir -p "$RESOURCE_ROOT/aircraft" "$RESOURCE_ROOT/engine" "$RESOURCE_ROOT/licenses" "$MODEL_ROOT"', 'mkdir -p "$RESOURCE_ROOT/aircraft" "$RESOURCE_ROOT/engine" "$RESOURCE_ROOT/licenses"')
legacy = '''# JSBSim intentionally does not ship render art. Stage a pinned, MIT-licensed
# F-16 OBJ rather than fabricating an aircraft from RealityKit primitives.
curl --fail --location --retry 3 --silent --show-error \\
  "$F16_VISUAL_BASE/$F16_VISUAL_PATH" \\
  -o "$MODEL_ROOT/f16.obj"
curl --fail --location --retry 3 --silent --show-error \\
  "$F16_VISUAL_BASE/LICENSE" \\
  -o "$RESOURCE_ROOT/licenses/R4-F16-MIT-LICENSE.txt"

'''
if legacy not in text:
    raise RuntimeError('legacy R4 staging block not found')
text = text.replace(legacy, '')
text = text.replace('  "$RESOURCE_ROOT/engine/direct.xml" \\\n  "$MODEL_ROOT/f16.obj" \\\n  "$APP_PATH/terrain_albedo.png"; do', '  "$RESOURCE_ROOT/engine/direct.xml" \\\n  "$APP_PATH/terrain_albedo.png"; do')
text = text.replace('grep -q \'^o f16\' "$MODEL_ROOT/f16.obj"\ngrep -q \'^f \' "$MODEL_ROOT/f16.obj"\n\n', '')
text = text.replace('echo "Staged JSBSim F-16 with upstream yaw damping, stronger pedal feed-forward, terrain texture and pinned F-16 render mesh"', 'echo "Staged JSBSim F-16 calibration data, yaw damping, pedal feed-forward and terrain texture"')
stage_path.write_text(text, encoding='utf-8')

for workflow_name in ['.github/workflows/ios-device-ipa.yml', '.github/workflows/ios-simulator.yml']:
    p = Path(workflow_name)
    w = p.read_text(encoding='utf-8')
    w = w.replace('Stage F-16 calibration data and mesh', 'Stage F-16 calibration data and verify authored visual assets')
    w = w.replace('          test -s "$APP_PATH/Models/f16.obj"\n', '''          test -s "$APP_PATH/JSBSim/visuals/f16/f16_static.obj"
          test -s "$APP_PATH/JSBSim/visuals/f16/left_flaperon.obj"
          test -s "$APP_PATH/JSBSim/visuals/f16/right_flaperon.obj"
          test -s "$APP_PATH/JSBSim/visuals/f16/left_stabilator.obj"
          test -s "$APP_PATH/JSBSim/visuals/f16/right_stabilator.obj"
          test -s "$APP_PATH/JSBSim/visuals/f16/rudder.obj"
          test -s "$APP_PATH/JSBSim/visuals/f16/afterburner_plume.obj"
          test -s "$APP_PATH/JSBSim/visuals/f16/manifest.json"
          test -s "$APP_PATH/JSBSim/visuals/f16/LICENSE-FlightSim_F16.txt"
''')
    if workflow_name.endswith('ios-device-ipa.yml'):
        w = w.replace("Payload/FullAuthority.app/(JSBSim/aircraft/f16/f16.xml|JSBSim/engine/F100-PW-229.xml|JSBSim/engine/direct.xml|Models/f16.obj|FullAuthority)", "Payload/FullAuthority.app/(JSBSim/aircraft/f16/f16.xml|JSBSim/engine/F100-PW-229.xml|JSBSim/engine/direct.xml|JSBSim/visuals/f16/f16_static.obj|JSBSim/visuals/f16/afterburner_plume.obj|FullAuthority)")
    p.write_text(w, encoding='utf-8')

print('Removed retired R4 staging and hardened final bundle checks for authored F-16 assets.')
