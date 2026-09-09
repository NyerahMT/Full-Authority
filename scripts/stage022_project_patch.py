from pathlib import Path

project = Path('FullAuthority.xcodeproj/project.pbxproj')
text = project.read_text(encoding='utf-8')

replacements = [
    (
        '\t\tFA0210000000000000000001 /* Stage021Atmosphere.swift in Sources */ = {isa = PBXBuildFile; fileRef = FA0210000000000000000011 /* Stage021Atmosphere.swift */; };\n',
        '\t\tFA0210000000000000000001 /* Stage021Atmosphere.swift in Sources */ = {isa = PBXBuildFile; fileRef = FA0210000000000000000011 /* Stage021Atmosphere.swift */; };\n'
        '\t\tFA0220000000000000000001 /* Stage022RootView.swift in Sources */ = {isa = PBXBuildFile; fileRef = FA0220000000000000000011 /* Stage022RootView.swift */; };\n'
        '\t\tFA0220000000000000000002 /* Stage022MainMenu.swift in Sources */ = {isa = PBXBuildFile; fileRef = FA0220000000000000000012 /* Stage022MainMenu.swift */; };\n'
    ),
    (
        '\t\tFA0210000000000000000011 /* Stage021Atmosphere.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Stage021Atmosphere.swift; sourceTree = "<group>"; };\n',
        '\t\tFA0210000000000000000011 /* Stage021Atmosphere.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Stage021Atmosphere.swift; sourceTree = "<group>"; };\n'
        '\t\tFA0220000000000000000011 /* Stage022RootView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Stage022RootView.swift; sourceTree = "<group>"; };\n'
        '\t\tFA0220000000000000000012 /* Stage022MainMenu.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Stage022MainMenu.swift; sourceTree = "<group>"; };\n'
    ),
    (
        '\t\t\t\tFA0210000000000000000011 /* Stage021Atmosphere.swift */,\n',
        '\t\t\t\tFA0210000000000000000011 /* Stage021Atmosphere.swift */,\n'
        '\t\t\t\tFA0220000000000000000011 /* Stage022RootView.swift */,\n'
        '\t\t\t\tFA0220000000000000000012 /* Stage022MainMenu.swift */,\n'
    ),
    (
        '\t\t\t\tFA0210000000000000000001 /* Stage021Atmosphere.swift in Sources */,\n',
        '\t\t\t\tFA0210000000000000000001 /* Stage021Atmosphere.swift in Sources */,\n'
        '\t\t\t\tFA0220000000000000000001 /* Stage022RootView.swift in Sources */,\n'
        '\t\t\t\tFA0220000000000000000002 /* Stage022MainMenu.swift in Sources */,\n'
    ),
]

for old, new in replacements:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'expected exactly one project anchor, found {count}: {old[:80]!r}')
    text = text.replace(old, new, 1)

project.write_text(text, encoding='utf-8')
