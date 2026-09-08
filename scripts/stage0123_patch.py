from pathlib import Path

path = Path("App/ContentView.swift")
text = path.read_text()

repls = [
(
'''                                Text("NAV")
                                Text(String(format: "G %.1f", state.loadFactorG))
                                if state.mach >= 0.50 {
                                    Text(String(format: "M %.2f", state.mach))
                                }
''',
'''                                Text("NAV")
                                Text(String(format: "G %.1f", state.loadFactorG))
                                Text(String(format: "M %.2f", state.mach))
'''
),
(
'''            HStack(spacing: 4) {
                Text(String(format: "%03.0f", speed < 60 ? 0 : speed))
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .monospacedDigit()
                    .padding(.horizontal, 3)
                    .background(.black.opacity(0.16))

                Rectangle().frame(width: 18, height: 1.2)
            }
            .offset(x: 5)
''',
'''            HStack(spacing: 4) {
                Text(String(format: "%03.0f", speed < 60 ? 0 : speed))
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .monospacedDigit()
                    .padding(.horizontal, 3)
                    .background(.black.opacity(0.16))

                Rectangle().frame(width: 18, height: 1.2)
            }
            // Current KCAS readout sits beside the tape pointer, not over the
            // scrolling ladder.
            .offset(x: -47)
'''
),
(
'''            Text(String(format: "M %.2f", state.mach))
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .monospacedDigit()
                .offset(y: 92)
        }
        .frame(width: 86, height: 210)
''',
'''        }
        .frame(width: 150, height: 210)
'''
),
(
'''            HStack(spacing: 4) {
                Rectangle().frame(width: 18, height: 1.2)
                Text(String(format: "%05.0f", (altitude / 10).rounded() * 10))
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .monospacedDigit()
                    .padding(.horizontal, 3)
                    .background(.black.opacity(0.16))
            }
            .offset(x: -3)
''',
'''            HStack(spacing: 4) {
                Rectangle().frame(width: 18, height: 1.2)
                Text(String(format: "%05.0f", (altitude / 10).rounded() * 10))
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .monospacedDigit()
                    .padding(.horizontal, 3)
                    .background(.black.opacity(0.16))
            }
            // Mirror the airspeed side: keep the current altitude readout clear
            // of the scrolling ladder.
            .offset(x: 49)
'''
),
(
'''        .frame(width: 92, height: 210)
''',
'''        .frame(width: 158, height: 210)
'''
)
]
for old, new in repls:
    if old not in text:
        raise SystemExit("HUD anchor not found")
    text = text.replace(old, new, 1)
path.write_text(text)

path = Path("Aircraft/PrototypeAircraftFactory.swift")
text = path.read_text()

old = '''                    let tangentCosine = simd_dot(
                        geometricNormals[current],
                        geometricNormals[neighbor]
                    )
                    guard tangentCosine >= smoothTangentCosine else {
                        continue
                    }
'''
new = '''                    let tangentCosine = simd_dot(
                        geometricNormals[current],
                        geometricNormals[neighbor]
                    )

                    // The front of the coarse canopy turns through a steeper
                    // facet than the side glass. Let that local crown continue
                    // while the hard sill still blocks the flood elsewhere.
                    let forwardBubble = p.z > 3.05 && p.y > 0.58 && abs(p.x) < 0.88
                    let localTangentCosine = forwardBubble
                        ? cos(Float.pi * 52.0 / 180.0)
                        : smoothTangentCosine
                    guard tangentCosine >= localTangentCosine else {
                        continue
                    }
'''
if old not in text:
    raise SystemExit("canopy tangent anchor not found")
text = text.replace(old, new, 1)

start = text.index("    private static func addLandingGear(to root: Entity) {")
end = text.index("    private static func loadAuthoredOBJ(", start)
replacement = r'''    private static func addLandingGear(to root: Entity) {
        let strutColor = UIColor(red: 0.74, green: 0.75, blue: 0.73, alpha: 1)
        let chromeColor = UIColor(red: 0.88, green: 0.90, blue: 0.91, alpha: 1)
        let tireColor = UIColor(red: 0.022, green: 0.022, blue: 0.024, alpha: 1)
        let rimColor = UIColor(red: 0.48, green: 0.50, blue: 0.50, alpha: 1)
        let doorColor = UIColor(red: 0.43, green: 0.45, blue: 0.45, alpha: 1)

        root.addChild(gearAssembly(
            name: noseGearName,
            rootPosition: [0, -0.30, 2.78],
            strutHeight: 1.14,
            wheelRadius: 0.245,
            wheelWidth: 0.18,
            side: 0,
            isNose: true,
            strutColor: strutColor,
            chromeColor: chromeColor,
            tireColor: tireColor,
            rimColor: rimColor,
            doorColor: doorColor
        ))
        root.addChild(gearAssembly(
            name: leftGearName,
            rootPosition: [-1.08, -0.34, -0.80],
            strutHeight: 1.04,
            wheelRadius: 0.315,
            wheelWidth: 0.235,
            side: -1,
            isNose: false,
            strutColor: strutColor,
            chromeColor: chromeColor,
            tireColor: tireColor,
            rimColor: rimColor,
            doorColor: doorColor
        ))
        root.addChild(gearAssembly(
            name: rightGearName,
            rootPosition: [1.08, -0.34, -0.80],
            strutHeight: 1.04,
            wheelRadius: 0.315,
            wheelWidth: 0.235,
            side: 1,
            isNose: false,
            strutColor: strutColor,
            chromeColor: chromeColor,
            tireColor: tireColor,
            rimColor: rimColor,
            doorColor: doorColor
        ))
    }

    private static func gearAssembly(
        name: String,
        rootPosition: SIMD3<Float>,
        strutHeight: Float,
        wheelRadius: Float,
        wheelWidth: Float,
        side: Float,
        isNose: Bool,
        strutColor: UIColor,
        chromeColor: UIColor,
        tireColor: UIColor,
        rimColor: UIColor,
        doorColor: UIColor
    ) -> Entity {
        let assembly = Entity()
        assembly.name = name
        assembly.position = rootPosition

        let upperLength = strutHeight * (isNose ? 0.42 : 0.46)
        let lowerLength = strutHeight * (isNose ? 0.54 : 0.50)
        let wheelY = -strutHeight

        let upperStrut = ModelEntity(
            mesh: .generateCylinder(height: upperLength, radius: isNose ? 0.064 : 0.078),
            materials: [SimpleMaterial(color: strutColor, isMetallic: true)]
        )
        upperStrut.position = [0, -upperLength * 0.5, 0]
        assembly.addChild(upperStrut)

        let lowerStrut = ModelEntity(
            mesh: .generateCylinder(height: lowerLength, radius: isNose ? 0.038 : 0.046),
            materials: [SimpleMaterial(color: chromeColor, isMetallic: true)]
        )
        lowerStrut.position = [0, -upperLength - lowerLength * 0.5 + 0.035, 0]
        assembly.addChild(lowerStrut)

        let braceStart = SIMD3<Float>(
            isNose ? 0.0 : -side * 0.08,
            -strutHeight * 0.24,
            isNose ? -0.18 : 0.10
        )
        let braceEnd = SIMD3<Float>(
            isNose ? 0.0 : side * 0.18,
            wheelY + wheelRadius * 0.36,
            isNose ? 0.22 : -0.20
        )
        assembly.addChild(gearLink(
            from: braceStart,
            to: braceEnd,
            radius: isNose ? 0.027 : 0.034,
            color: strutColor
        ))

        let axle = ModelEntity(
            mesh: .generateCylinder(height: wheelWidth * 1.42, radius: isNose ? 0.030 : 0.038),
            materials: [SimpleMaterial(color: strutColor, isMetallic: true)]
        )
        axle.position = [0, wheelY, 0]
        axle.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        assembly.addChild(axle)

        let wheel = ModelEntity(
            mesh: .generateCylinder(height: wheelWidth, radius: wheelRadius),
            materials: [SimpleMaterial(color: tireColor, isMetallic: false)]
        )
        wheel.position = [0, wheelY, 0]
        wheel.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        assembly.addChild(wheel)

        let rim = ModelEntity(
            mesh: .generateCylinder(height: wheelWidth * 1.035, radius: wheelRadius * 0.46),
            materials: [SimpleMaterial(color: rimColor, isMetallic: true)]
        )
        rim.position = [0, wheelY, 0]
        rim.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        assembly.addChild(rim)

        let hub = ModelEntity(
            mesh: .generateCylinder(height: wheelWidth * 1.08, radius: wheelRadius * 0.17),
            materials: [SimpleMaterial(color: chromeColor, isMetallic: true)]
        )
        hub.position = [0, wheelY, 0]
        hub.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        assembly.addChild(hub)

        if isNose {
            for x in [-wheelWidth * 0.62, wheelWidth * 0.62] {
                assembly.addChild(gearLink(
                    from: [x, -strutHeight * 0.58, 0.02],
                    to: [x, wheelY + wheelRadius * 0.12, 0.0],
                    radius: 0.024,
                    color: strutColor
                ))
            }

            let door = ModelEntity(
                mesh: .generateBox(size: [0.34, 0.034, 0.88], cornerRadius: 0.015),
                materials: [SimpleMaterial(color: doorColor, isMetallic: false)]
            )
            door.position = [0.28, -0.11, -0.08]
            door.orientation = simd_quatf(angle: 0.10, axis: [0, 0, 1])
            assembly.addChild(door)
        } else {
            assembly.addChild(gearLink(
                from: [-side * 0.18, -strutHeight * 0.18, -0.12],
                to: [side * 0.12, -strutHeight * 0.72, 0.06],
                radius: 0.030,
                color: strutColor
            ))

            let door = ModelEntity(
                mesh: .generateBox(size: [0.52, 0.036, 0.78], cornerRadius: 0.018),
                materials: [SimpleMaterial(color: doorColor, isMetallic: false)]
            )
            door.position = [-side * 0.34, -0.13, 0.02]
            door.orientation = simd_quatf(angle: side * 0.13, axis: [0, 0, 1])
            assembly.addChild(door)
        }

        return assembly
    }

    private static func gearLink(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        radius: Float,
        color: UIColor
    ) -> Entity {
        let delta = end - start
        let length = max(simd_length(delta), 0.001)
        let link = ModelEntity(
            mesh: .generateCylinder(height: length, radius: radius),
            materials: [SimpleMaterial(color: color, isMetallic: true)]
        )
        link.position = (start + end) * 0.5
        link.orientation = simd_quatf(
            from: SIMD3<Float>(0, 1, 0),
            to: simd_normalize(delta)
        )
        return link
    }

'''
text = text[:start] + replacement + text[end:]
path.write_text(text)
