from pathlib import Path
import re

# PrototypeAircraftFactory.swift
p = Path('Aircraft/PrototypeAircraftFactory.swift')
s = p.read_text()
if 'static let cockpitRootName' not in s:
    s = s.replace(
        '    static let visualRootName = "FA.aircraft.visual-root"\n',
        '    static let visualRootName = "FA.aircraft.visual-root"\n'
        '    static let cockpitRootName = PrototypeCockpitFactory.rootName\n'
    )
if 'PrototypeCockpitFactory.make()' not in s:
    s = s.replace(
        '            try addAfterburner(to: visualRoot)\n            addLandingGear(to: aircraft)\n',
        '            try addAfterburner(to: visualRoot)\n'
        '            addLandingGear(to: aircraft)\n\n'
        '            let cockpit = PrototypeCockpitFactory.make()\n'
        '            aircraft.addChild(cockpit)\n'
    )
p.write_text(s)

# PrototypeSceneView.swift
p = Path('App/PrototypeSceneView.swift')
s = p.read_text()
old = '''                    aircraft.position = simulation.state.positionMeters
                    aircraft.orientation = simulation.state.orientation
                    aircraft.isEnabled = cameraMode != .cockpit
                    updateAircraftPresentation(aircraft)
'''
new = '''                    aircraft.position = simulation.state.positionMeters
                    aircraft.orientation = simulation.state.orientation
                    aircraft.isEnabled = true
                    updateAircraftPresentation(aircraft)

                    let cockpitMode = cameraMode == .cockpit
                    aircraft.findEntity(named: PrototypeAircraftFactory.visualRootName)?.isEnabled = !cockpitMode
                    aircraft.findEntity(named: PrototypeAircraftFactory.cockpitRootName)?.isEnabled = cockpitMode
                    aircraft.findEntity(named: Stage2FlightEffects.attachedRootName)?.isEnabled = !cockpitMode
                    if cockpitMode {
                        for name in [
                            PrototypeAircraftFactory.noseGearName,
                            PrototypeAircraftFactory.leftGearName,
                            PrototypeAircraftFactory.rightGearName
                        ] {
                            aircraft.findEntity(named: name)?.isEnabled = false
                        }
                    }
'''
if old in s:
    s = s.replace(old, new)
elif 'PrototypeAircraftFactory.cockpitRootName' not in s:
    raise SystemExit('PrototypeSceneView aircraft update block changed unexpectedly')

fake_overlay = '''            if cameraMode == .cockpit && !simulation.isPaused {
                CockpitFrameOverlay()
                    .allowsHitTesting(false)
            }

'''
s = s.replace(fake_overlay, '')
s = s.replace(
    '            fieldOfView = 68\n            pullbackScale = 0\n',
    '            fieldOfView = 66\n            pullbackScale = 0\n'
)
p.write_text(s)

# project.pbxproj
p = Path('FullAuthority.xcodeproj/project.pbxproj')
s = p.read_text()
if 'PrototypeCockpitFactory.swift in Sources' not in s:
    s = s.replace(
        '\t\tFA0000000000000000000004 /* PrototypeAircraftFactory.swift in Sources */ = {isa = PBXBuildFile; fileRef = FA0000000000000000000014 /* PrototypeAircraftFactory.swift */; };\n',
        '\t\tFA0000000000000000000004 /* PrototypeAircraftFactory.swift in Sources */ = {isa = PBXBuildFile; fileRef = FA0000000000000000000014 /* PrototypeAircraftFactory.swift */; };\n'
        '\t\tFA000000000000000000000C /* PrototypeCockpitFactory.swift in Sources */ = {isa = PBXBuildFile; fileRef = FA000000000000000000001E /* PrototypeCockpitFactory.swift */; };\n'
    )
    s = s.replace(
        '\t\tFA000000000000000000001D /* Stage2FlightEffects.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Stage2FlightEffects.swift; sourceTree = "<group>"; };\n',
        '\t\tFA000000000000000000001D /* Stage2FlightEffects.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Stage2FlightEffects.swift; sourceTree = "<group>"; };\n'
        '\t\tFA000000000000000000001E /* PrototypeCockpitFactory.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PrototypeCockpitFactory.swift; sourceTree = "<group>"; };\n'
    )
    s = s.replace(
        '\t\t\t\tFA0000000000000000000014 /* PrototypeAircraftFactory.swift */,\n',
        '\t\t\t\tFA0000000000000000000014 /* PrototypeAircraftFactory.swift */,\n'
        '\t\t\t\tFA000000000000000000001E /* PrototypeCockpitFactory.swift */,\n'
    )
    s = s.replace(
        '\t\t\t\tFA0000000000000000000004 /* PrototypeAircraftFactory.swift in Sources */,\n',
        '\t\t\t\tFA0000000000000000000004 /* PrototypeAircraftFactory.swift in Sources */,\n'
        '\t\t\t\tFA000000000000000000000C /* PrototypeCockpitFactory.swift in Sources */,\n'
    )
p.write_text(s)

# Keep SimpleMaterial initializers aligned to APIs already used in the project.
p = Path('Aircraft/PrototypeCockpitFactory.swift')
s = p.read_text()
s = re.sub(
    r',\n\s*roughness: [0-9.]+,\n\s*isMetallic:',
    ',\n            isMetallic:',
    s
)
p.write_text(s)
