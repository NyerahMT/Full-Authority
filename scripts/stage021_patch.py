from pathlib import Path


def load(path: str) -> str:
    return Path(path).read_text(encoding="utf-8")


def save(path: str, text: str) -> None:
    Path(path).write_text(text, encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one anchor, found {count}")
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# Xcode project — compile Stage021Atmosphere.swift.
# ---------------------------------------------------------------------------
project_path = "FullAuthority.xcodeproj/project.pbxproj"
p = load(project_path)

build_line = '\t\tFA0210000000000000000001 /* Stage021Atmosphere.swift in Sources */ = {isa = PBXBuildFile; fileRef = FA0210000000000000000011 /* Stage021Atmosphere.swift */; };\n'
if "FA0210000000000000000001" not in p:
    p = replace_once(p, "/* End PBXBuildFile section */", build_line + "/* End PBXBuildFile section */", "PBXBuildFile")

ref_line = '\t\tFA0210000000000000000011 /* Stage021Atmosphere.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Stage021Atmosphere.swift; sourceTree = "<group>"; };\n'
if "FA0210000000000000000011 /* Stage021Atmosphere.swift */ = {isa = PBXFileReference" not in p:
    p = replace_once(p, "/* End PBXFileReference section */", ref_line + "/* End PBXFileReference section */", "PBXFileReference")

app_anchor = '\t\t\t\tFA0200000000000000000012 /* Stage020SkyEnvironment.swift */,\n'
if "FA0210000000000000000011 /* Stage021Atmosphere.swift */," not in p:
    p = replace_once(p, app_anchor, app_anchor + '\t\t\t\tFA0210000000000000000011 /* Stage021Atmosphere.swift */,\n', "App group")

sources_anchor = '\t\t\t\tFA0200000000000000000002 /* Stage020SkyEnvironment.swift in Sources */,\n'
if "FA0210000000000000000001 /* Stage021Atmosphere.swift in Sources */," not in p:
    p = replace_once(p, sources_anchor, sources_anchor + '\t\t\t\tFA0210000000000000000001 /* Stage021Atmosphere.swift in Sources */,\n', "Sources phase")

save(project_path, p)


# ---------------------------------------------------------------------------
# Scene — atmosphere hookup, restrained AB presentation, audio rebalance.
# Camera section intentionally untouched.
# ---------------------------------------------------------------------------
scene_path = "App/PrototypeSceneView.swift"
s = load(scene_path)

world_anchor = """                    content.add(world)\n\n                    let aircraft = PrototypeAircraftFactory.make()"""
world_new = """                    content.add(world)\n\n                    let atmosphere = Stage021Atmosphere.make()\n                    content.add(atmosphere)\n\n                    let aircraft = PrototypeAircraftFactory.make()"""
s = replace_once(s, world_anchor, world_new, "Stage021 atmosphere create")

update_anchor = """                    aircraft.position = simulation.state.positionMeters\n                    aircraft.orientation = simulation.state.orientation\n                    aircraft.isEnabled = true\n                    updateAircraftPresentation(aircraft)"""
update_new = """                    aircraft.position = simulation.state.positionMeters\n                    aircraft.orientation = simulation.state.orientation\n                    aircraft.isEnabled = true\n                    updateAircraftPresentation(aircraft)\n\n                    if let atmosphere = content.entities.first(where: { $0.name == Stage021Atmosphere.rootName }) {\n                        Stage021Atmosphere.update(atmosphere, aircraftPosition: simulation.state.positionMeters)\n                    }"""
s = replace_once(s, update_anchor, update_new, "Stage021 atmosphere update")

# Afterburner scale hierarchy: less solid volume, more concentrated luminous core.
s = s.replace("halo.scale = [1.15 * width, 2.15 * length, 1.15 * width]", "halo.scale = [1.04 * width, 1.82 * length, 1.04 * width]", 1)
s = s.replace("outer.scale = [0.94 * width, 1.90 * length, 1.02 * width]", "outer.scale = [0.84 * width, 1.64 * length, 0.90 * width]", 1)
s = s.replace("inner.scale = [0.58 * width * pulse, 1.52 * length, 0.66 * width * pulse]", "inner.scale = [0.50 * width * pulse, 1.34 * length, 0.56 * width * pulse]", 1)
s = s.replace("core.scale = [0.24 * width * pulse, 1.12 * length, 0.30 * width * pulse]", "core.scale = [0.19 * width * pulse, 0.96 * length, 0.23 * width * pulse]", 1)

# Audio: reduce synthetic compressor dominance, emphasize low/mid exhaust body,
# and let AoA/beta produce tactile wind/buffet rather than broadband hiss.
old_audio = """        let live: Float = isPaused ? 0 : 1\n        let dryPower = max(n1, fuel)\n\n        rumbleRate.rate = 0.78 + 0.33 * n1\n        turbineRate.rate = 0.70 + 1.00 * n2\n\n        // The persistent high-pitched whir is the synthetic compressor/turbine\n        // layer, not an APU. In the cockpit it was actually louder than outside.\n        // Helmet/canopy attenuation now knocks that layer down hard while leaving\n        // enough low-frequency engine body to know the jet is alive.\n        let cockpitRumble: Float = isCockpit ? 0.52 : 1.0\n        let cockpitTurbine: Float = isCockpit ? 0.30 : 0.82\n        let cockpitExhaust: Float = isCockpit ? 0.18 : 1.0\n        let cockpitWind: Float = isCockpit ? 0.22 : 1.0\n\n        rumble.volume = live * cockpitRumble * (0.050 + 0.18 * n1)\n        turbine.volume = live * cockpitTurbine * (0.014 + 0.095 * n2 * n2)\n        exhaust.volume = live * cockpitExhaust * (0.025 + 0.20 * dryPower)\n        afterburner.volume = live * cockpitExhaust * (state.afterburnerActive ? 0.16 + 0.14 * n2 : 0)\n        wind.volume = live * cockpitWind * (0.004 + 0.030 * min(powf(mach, 1.55), 1.40))"""
new_audio = """        let live: Float = isPaused ? 0 : 1\n        let dryPower = max(n1, fuel)\n        let aoaBuffet = clamp((abs(state.angleOfAttackDegrees) - 7.5) / 11.0, 0, 1)\n        let betaBuffet = clamp((abs(state.sideslipDegrees) - 2.0) / 8.0, 0, 1)\n        let buffet = max(aoaBuffet, betaBuffet)\n\n        rumbleRate.rate = 0.72 + 0.30 * n1\n        turbineRate.rate = 0.62 + 0.74 * n2\n\n        // Stage 021 is referenced against public-domain F-16 burner/test-cell\n        // recordings: outside is exhaust-body dominant; cockpit is strongly\n        // attenuated and never becomes a constant compressor whistle.\n        let cockpitRumble: Float = isCockpit ? 0.46 : 1.0\n        let cockpitTurbine: Float = isCockpit ? 0.10 : 0.50\n        let cockpitExhaust: Float = isCockpit ? 0.10 : 1.0\n        let cockpitWind: Float = isCockpit ? 0.17 : 1.0\n\n        rumble.volume = live * cockpitRumble * (0.055 + 0.205 * n1)\n        turbine.volume = live * cockpitTurbine * (0.008 + 0.062 * n2 * n2)\n        exhaust.volume = live * cockpitExhaust * (0.032 + 0.245 * dryPower)\n        afterburner.volume = live * cockpitExhaust * (state.afterburnerActive ? 0.13 + 0.15 * n2 : 0)\n        let baseWind = 0.003 + 0.024 * min(powf(mach, 1.55), 1.40)\n        wind.volume = live * cockpitWind * baseWind * (1.0 + 1.65 * buffet)"""
s = replace_once(s, old_audio, new_audio, "Stage021 audio update")

# Less shrill turbine source.
s = s.replace("0.52 * sin(2 * .pi * 315 * t + phase)", "0.45 * sin(2 * .pi * 255 * t + phase)", 1)
s = s.replace("0.27 * sin(2 * .pi * 630 * t + 0.3)", "0.23 * sin(2 * .pi * 510 * t + 0.3)", 1)
s = s.replace("0.13 * sin(2 * .pi * 945 * t + 0.9)", "0.10 * sin(2 * .pi * 765 * t + 0.9)", 1)
s = s.replace("0.06 * sin(2 * .pi * 1_575 * t + 1.4)", "0.035 * sin(2 * .pi * 1_275 * t + 1.4)", 1)
s = s.replace("return (blade * shimmer + random * 0.006) * 0.34", "return (blade * shimmer + random * 0.004) * 0.27", 1)

# Push roar energy down in frequency; remove the remaining white-noise edge.
s = s.replace("0.020 * edge +", "0.007 * edge +", 1)
s = s.replace("0.010 * edge", "0.004 * edge", 1)
s = s.replace("1.55 * lowBand +", "1.72 * lowBand +", 1)
s = s.replace("0.58 * bodyBand +", "0.66 * bodyBand +", 1)
s = s.replace("1.28 * lowBand +", "1.42 * lowBand +", 1)
s = s.replace("0.44 * bodyBand +", "0.52 * bodyBand +", 1)

# EQ keeps the upper spectrum under control on iPhone speakers/headphones.
s = s.replace("exhaustBands[0].gain = 4.5", "exhaustBands[0].gain = 6.5", 1)
s = s.replace("exhaustBands[2].gain = -11.0", "exhaustBands[2].gain = -14.5", 1)
s = s.replace("burnerBands[0].gain = 6.0", "burnerBands[0].gain = 7.5", 1)
s = s.replace("burnerBands[2].gain = -12.5", "burnerBands[2].gain = -15.5", 1)

save(scene_path, s)


# ---------------------------------------------------------------------------
# F-16 visual burner materials — transparent daylight envelope, hot core.
# ---------------------------------------------------------------------------
aircraft_path = "Aircraft/PrototypeAircraftFactory.swift"
a = load(aircraft_path)
a = replace_once(a,
"""                red: 0.82,\n                green: 0.10,\n                blue: 0.025,\n                alpha: 0.15""",
"""                red: 0.34,\n                green: 0.47,\n                blue: 1.00,\n                alpha: 0.075""",
"AB halo color")
a = replace_once(a,
"""                red: 1.0,\n                green: 0.24,\n                blue: 0.035,\n                alpha: 0.34""",
"""                red: 1.0,\n                green: 0.34,\n                blue: 0.055,\n                alpha: 0.20""",
"AB outer color")
a = replace_once(a,
"""                red: 1.0,\n                green: 0.52,\n                blue: 0.075,\n                alpha: 0.56""",
"""                red: 1.0,\n                green: 0.68,\n                blue: 0.18,\n                alpha: 0.40""",
"AB inner color")
a = replace_once(a,
"""                red: 1.0,\n                green: 0.88,\n                blue: 0.48,\n                alpha: 0.86""",
"""                red: 1.0,\n                green: 0.96,\n                blue: 0.78,\n                alpha: 0.72""",
"AB core color")
# Initial scales must match update hierarchy to avoid a one-frame pop.
a = a.replace("halo.scale = [1.15, 2.15, 1.15]", "halo.scale = [1.04, 1.82, 1.04]", 1)
a = a.replace("outer.scale = [0.94, 1.90, 1.02]", "outer.scale = [0.84, 1.64, 0.90]", 1)
a = a.replace("inner.scale = [0.58, 1.52, 0.66]", "inner.scale = [0.50, 1.34, 0.56]", 1)
a = a.replace("core.scale = [0.24, 1.12, 0.30]", "core.scale = [0.19, 0.96, 0.23]", 1)
save(aircraft_path, a)


# ---------------------------------------------------------------------------
# Flight effects — less tube-like contrails, finer attached vapor, tighter
# transonic condition window. Formation physics remain state-driven.
# ---------------------------------------------------------------------------
effects_path = "App/Stage2FlightEffects.swift"
e = load(effects_path)

# Contrail cross sections: retain long persistence but remove giant white rope.
e = e.replace("baseRadius: 0.54,\n            radialGrowthPerSecond: 0.068,\n            driftScale: 0.84,\n            opacity: 0.16", "baseRadius: 0.38,\n            radialGrowthPerSecond: 0.055,\n            driftScale: 0.86,\n            opacity: 0.105", 1)
e = e.replace("baseRadius: 0.36,\n            radialGrowthPerSecond: 0.052,\n            driftScale: 0.80,\n            opacity: 0.10", "baseRadius: 0.25,\n            radialGrowthPerSecond: 0.043,\n            driftScale: 0.82,\n            opacity: 0.070", 1)
e = e.replace("baseRadius: 0.17,\n            radialGrowthPerSecond: 0.020,\n            driftScale: 0.24,\n            opacity: 0.22", "baseRadius: 0.12,\n            radialGrowthPerSecond: 0.015,\n            driftScale: 0.30,\n            opacity: 0.165", 1)

# Deterministic wake meander and radius breakup as the trail ages.
center_anchor = """            let center = sample.position\n                + sample.driftVelocity * age * driftScale\n\n            // Wake spreading is fast for the first minute, then saturates so a"""
center_new = """            var center = sample.position\n                + sample.driftVelocity * age * driftScale\n            let meander = min(4.5, 0.020 * powf(age, 1.16))\n            let seed = Float(sample.simulationTime.truncatingRemainder(dividingBy: 97.0))\n            center.x += sin(age * 0.19 + seed * 0.31) * meander\n            center.y += sin(age * 0.13 + seed * 0.17) * meander * 0.24\n            center.z += cos(age * 0.16 + seed * 0.23) * meander * 0.72\n\n            // Wake spreading is fast for the first minute, then saturates so a"""
e = replace_once(e, center_anchor, center_new, "contrail meander")

radius_anchor = """            let strengthRadius = 0.78 + 0.42 * sample.strength\n\n            centers.append(center)\n            radii.append(\n                baseRadius\n                    * growth\n                    * strengthRadius\n                    * birthRamp\n                    * deathRamp\n            )"""
radius_new = """            let strengthRadius = 0.78 + 0.42 * sample.strength\n            let textureBreakup = 0.90 + 0.10 * sin(age * 0.23 + seed * 0.41)\n\n            centers.append(center)\n            radii.append(\n                baseRadius\n                    * growth\n                    * strengthRadius\n                    * birthRamp\n                    * deathRamp\n                    * textureBreakup\n            )"""
e = replace_once(e, radius_anchor, radius_new, "contrail radius breakup")

# Finer spindle and slightly lower opacity.
e = e.replace("let sides = 8", "let sides = 12", 1)
e = replace_once(e,
"""            ( 0.00, 0.05, 0.05),\n            (-0.12, 0.72, 0.60),\n            (-0.38, 1.00, 0.82),\n            (-0.68, 0.72, 0.60),\n            (-1.00, 0.08, 0.07)""",
"""            ( 0.00, 0.025, 0.025),\n            (-0.10, 0.58, 0.48),\n            (-0.32, 1.00, 0.78),\n            (-0.66, 0.60, 0.48),\n            (-1.00, 0.025, 0.020)""",
"vapor streamer profile")
e = e.replace("opacity: (isTip ? 0.055 : 0.075) + (isTip ? 0.15 : 0.24) * i", "opacity: (isTip ? 0.040 : 0.055) + (isTip ? 0.115 : 0.185) * i", 1)

# Transonic cloud should be a brief atmospheric event, not a permanent suit.
e = e.replace("let machPeak = exp(-pow((mach - 0.995) / 0.060, 2))", "let machPeak = exp(-pow((mach - 0.995) / 0.040, 2))", 1)
e = e.replace("let visible = mach > 0.90\n            && mach < 1.115", "let visible = mach > 0.935\n            && mach < 1.070", 1)
e = e.replace("opacity: 0.045 + 0.125 * intensity", "opacity: 0.032 + 0.095 * intensity", 1)

save(effects_path, e)


# ---------------------------------------------------------------------------
# Touch rudder — show commanded vs actual FLCS surface while input is held.
# ---------------------------------------------------------------------------
ui_path = "App/ContentView.swift"
u = load(ui_path)

call_old = """                        CompactRudderControl(value: simulation.controls.rudder) { value in\n                            var controls = simulation.controls\n                            controls.rudder = value\n                            simulation.controls = controls\n                        }"""
call_new = """                        CompactRudderControl(\n                            value: simulation.controls.rudder,\n                            actual: simulation.state.rudderPosition\n                        ) { value in\n                            var controls = simulation.controls\n                            controls.rudder = value\n                            simulation.controls = controls\n                        }"""
u = replace_once(u, call_old, call_new, "rudder control call")

u = replace_once(u,
"""private struct CompactRudderControl: View {\n    let value: Float\n    let onChange: (Float) -> Void""",
"""private struct CompactRudderControl: View {\n    let value: Float\n    let actual: Float\n    let onChange: (Float) -> Void""",
"rudder signature")

label_old = """            Text(\"RUDDER  /  NWS\")\n                .font(.system(size: 7, weight: .black, design: .monospaced))\n                .foregroundStyle(.white.opacity(0.44))"""
label_new = """            HStack(spacing: 7) {\n                Text(\"RUDDER  /  NWS\")\n                if abs(value) > 0.025 {\n                    Text(String(format: \"PED %+03.0f  RUD %+03.0f\", value * 100, actual * 100))\n                        .foregroundStyle(.white.opacity(0.78))\n                }\n            }\n            .font(.system(size: 7, weight: .black, design: .monospaced))\n            .foregroundStyle(.white.opacity(0.44))"""
u = replace_once(u, label_old, label_new, "rudder diagnostic")

save(ui_path, u)


# ---------------------------------------------------------------------------
# F-16 yaw control — pedal-active lateral-acceleration feedback gate.
# ---------------------------------------------------------------------------
stage_path = "scripts/stage-f16-calibration.sh"
sh = load(stage_path)

load_block = '''old_rate = \'\'\'      80.0  0.0\n      100.0    15.0\n      150.0    100.0\'\'\'\nnew_rate = \'\'\'      80.0  0.0\n      100.0    15.0\n      150.0    112.0\'\'\'\n'''
insert_block = load_block + '''old_load = \'\'\'   <!-- Calculate the normalized yaw-load -->\n   <pure_gain name="fcs/yaw-load-norm">\n    <input>accelerations/n-pilot-y-norm</input>\n    <gain>0.25</gain>\n   </pure_gain>\'\'\'\nnew_load = \'\'\'   <!-- Stage 021: lateral acceleration coordinates feet-off-pedals flight,\n        but does not resist a deliberate pilot sideslip command. -->\n   <pure_gain name="fcs/yaw-load-raw">\n    <input>accelerations/n-pilot-y-norm</input>\n    <gain>0.25</gain>\n   </pure_gain>\n   <switch name="fcs/yaw-load-norm">\n    <default value="fcs/yaw-load-raw"/>\n    <test logic="OR" value="0">\n     fcs/rudder-cmd-norm gt 0.035\n     fcs/rudder-cmd-norm lt -0.035\n    </test>\n   </switch>\'\'\'\nif text.count(old_load) != 1:\n    raise SystemExit(f"expected one upstream yaw-load block, found {text.count(old_load)}")\ntext = text.replace(old_load, new_load, 1)\n'''
sh = replace_once(sh, load_block, insert_block, "yaw load gate patch source")

verify_anchor = """grep -q '150.0    112.0' \"$RESOURCE_ROOT/aircraft/f16/f16.xml\"\ntest \"$(grep -c '<input>fcs/rudder-cmd-norm</input>' \"$RESOURCE_ROOT/aircraft/f16/f16.xml\")\" -eq 1"""
verify_new = """grep -q '150.0    112.0' \"$RESOURCE_ROOT/aircraft/f16/f16.xml\"\ngrep -q 'Stage 021: lateral acceleration coordinates feet-off-pedals flight' \"$RESOURCE_ROOT/aircraft/f16/f16.xml\"\ngrep -q 'fcs/rudder-cmd-norm gt 0.035' \"$RESOURCE_ROOT/aircraft/f16/f16.xml\"\ntest \"$(grep -c '<input>fcs/rudder-cmd-norm</input>' \"$RESOURCE_ROOT/aircraft/f16/f16.xml\")\" -eq 1"""
sh = replace_once(sh, verify_anchor, verify_new, "yaw load gate verification")

sh = sh.replace("Stage 020 yaw SAS correction", "Stage 021 pedal-aware yaw SAS correction")
save(stage_path, sh)

print("Stage 021 source patch applied")
