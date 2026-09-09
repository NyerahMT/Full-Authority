from pathlib import Path
p = Path('App/Stage022MainMenu.swift')
text = p.read_text(encoding='utf-8')
old = '''            let stereo = channel == 0 ? 0.98 : 1.0\n            return min(max(stereo * (0.93 * shock + 0.42 * thump), -0.98), 0.98)\n'''
new = '''            let stereo: Float = channel == 0 ? 0.98 : 1.0\n            let pressureMix: Float = 0.93 * shock + 0.42 * thump\n            let output: Float = stereo * pressureMix\n            return Swift.min(Swift.max(output, -0.98), 0.98)\n'''
if text.count(old) != 1:
    raise SystemExit('expected one sonic boom expression')
p.write_text(text.replace(old, new, 1), encoding='utf-8')
