from pathlib import Path
p = Path('App/Stage022MainMenu.swift')
text = p.read_text(encoding='utf-8')
changes = [
    ('if !lowPassAudioPlayed && elapsed >= 117.35 {', 'if !lowPassAudioPlayed && elapsed >= 117.55 {'),
    ('let eventStart: TimeInterval = 116.8', 'let eventStart: TimeInterval = 117.03'),
    ('// 340 m/s puts the scripted pass in the transonic neighborhood. The path\n        // crosses the camera\'s runway station almost exactly at two minutes.\n        let z = -1_275 + 340 * t', '// 365 m/s is a deliberately low-supersonic pass at this altitude: fast\n        // enough to support a real shock/boom event without turning this into an\n        // arcade high-Mach flyby. It crosses the camera at essentially 2:00.\n        let z = -1_275 + 365 * t'),
]
for old, new in changes:
    if text.count(old) != 1:
        raise SystemExit(f'expected one anchor: {old!r}')
    text = text.replace(old, new, 1)
p.write_text(text, encoding='utf-8')
