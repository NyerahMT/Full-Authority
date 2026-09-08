from pathlib import Path

content_path = Path('App/ContentView.swift')
text = content_path.read_text()

old_state = '''    @StateObject private var simulation = FlightSimulation()\n    @State private var phase: GamePhase = .briefing\n'''
new_state = '''    @StateObject private var simulation = FlightSimulation()\n    @State private var phase: GamePhase = .briefing\n    @State private var cameraMode: FlightCameraMode = .chase\n    @State private var hmdEnabled = true\n'''
if text.count(old_state) != 1:
    raise SystemExit('ContentView state anchor mismatch')
text = text.replace(old_state, new_state, 1)

old_scene = '            PrototypeSceneView(simulation: simulation)\n'
new_scene = '            PrototypeSceneView(simulation: simulation, cameraMode: $cameraMode)\n'
if text.count(old_scene) != 1:
    raise SystemExit('PrototypeSceneView call anchor mismatch')
text = text.replace(old_scene, new_scene, 1)

old_hud = '''            F16HUD(state: simulation.state, controls: simulation.controls)\n                .allowsHitTesting(false)\n'''
new_hud = '''            if cameraMode == .cockpit || hmdEnabled {\n                F16HUD(state: simulation.state, controls: simulation.controls)\n                    .allowsHitTesting(false)\n            }\n'''
if text.count(old_hud) != 1:
    raise SystemExit('HUD overlay anchor mismatch')
text = text.replace(old_hud, new_hud, 1)

pause_anchor = '''                    Spacer()\n\n                    Button(action: pauseFlight) {\n'''
hmd_button = '''                    systemToggleButton(\n                        title: "HMD",\n                        value: hmdEnabled ? "ON" : "OFF",\n                        active: hmdEnabled\n                    ) {\n                        hmdEnabled.toggle()\n                    }\n\n                    Spacer()\n\n                    Button(action: pauseFlight) {\n'''
if text.count(pause_anchor) != 1:
    raise SystemExit('HMD button anchor mismatch')
text = text.replace(pause_anchor, hmd_button, 1)

start = text.index('private struct F16HUD: View {')
end = text.index('private struct CompactThrottleControl: View {')

hud = r'''private struct F16HUD: View {
    let state: AircraftState
    let controls: FlightControls

    private let hudColor = Color(red: 0.44, green: 1.0, blue: 0.52)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let hudWidth = min(width * 0.58, 520)
            let hudHeight = min(height * 0.70, 360)
            let pixelsPerDegree = max(4.8, hudHeight / 54.0)

            let rawFpmX = CGFloat(-state.sideslipDegrees) * pixelsPerDegree
            let rawFpmY = CGFloat(state.angleOfAttackDegrees) * pixelsPerDegree
            let horizontalLimit = hudWidth * 0.43
            let verticalLimit = hudHeight * 0.38
            let fpmX = clamp(rawFpmX, min: -horizontalLimit, max: horizontalLimit)
            let fpmY = clamp(rawFpmY, min: -verticalLimit, max: verticalLimit)
            let fpmLimited = abs(rawFpmX) > horizontalLimit || abs(rawFpmY) > verticalLimit
            let gearDown = state.gearPosition > 0.50

            ZStack {
                GForceVignette(loadFactorG: state.loadFactorG)
                    .ignoresSafeArea()

                ZStack {
                    F16PitchLadder(
                        pitchDegrees: state.pitchDegrees,
                        rollDegrees: state.rollDegrees,
                        driftX: fpmX,
                        pixelsPerDegree: pixelsPerDegree,
                        gearDown: gearDown,
                        color: hudColor
                    )

                    F16BoresightCross(color: hudColor)

                    F16FlightPathMarker(color: hudColor, limited: fpmLimited)
                        .offset(x: fpmX, y: fpmY)

                    F16BankAngleIndicator(rollDegrees: state.rollDegrees, color: hudColor)
                        .offset(x: fpmX, y: fpmY)

                    if gearDown {
                        let aoaBracketY = fpmY + CGFloat(13.0 - state.angleOfAttackDegrees) * pixelsPerDegree
                        F16AOABracket(color: hudColor, pixelsPerDegree: pixelsPerDegree)
                            .offset(x: fpmX - 48, y: aoaBracketY)
                    }

                    F16VelocityScale(state: state, color: hudColor)
                        .offset(x: -hudWidth * 0.48)

                    F16AltitudeScale(state: state, color: hudColor)
                        .offset(x: hudWidth * 0.47)

                    F16VerticalVelocityScale(state: state, color: hudColor)
                        .offset(x: hudWidth * 0.59)

                    F16HeadingScale(headingDegrees: state.headingDegrees, color: hudColor)
                        .frame(width: hudWidth * 0.68, height: 48)
                        .offset(y: hudHeight * 0.39)

                    VStack {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("NAV")
                                Text(String(format: "G %.1f", state.loadFactorG))
                                if state.mach >= 0.50 {
                                    Text(String(format: "M %.2f", state.mach))
                                }
                            }
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .monospacedDigit()

                            Spacer()

                            if gearDown {
                                Text("GEAR")
                                    .font(.system(size: 9, weight: .black, design: .monospaced))
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 2)

                    warningBanner
                }
                .frame(width: hudWidth, height: hudHeight)
                .position(x: width * 0.5, y: height * 0.45)
            }
            .foregroundStyle(hudColor)
        }
    }

    @ViewBuilder
    private var warningBanner: some View {
        let radarAltitudeFeet = state.altitudeMeters * 3.28084
        let sinkFPM = state.verticalSpeedMetersPerSecond * 196.8504

        VStack {
            if radarAltitudeFeet < 450 && sinkFPM < -4_000 {
                Text("PULL UP")
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .tracking(1.3)
                    .padding(.horizontal, 8)
                    .background(.black.opacity(0.18))
            }
            Spacer()
        }
        .padding(.top, 36)
    }

    private func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}

private struct F16VelocityScale: View {
    let state: AircraftState
    let color: Color

    var body: some View {
        let speed = max(0, state.calibratedAirspeedKnots)
        let base = floor(speed / 10) * 10
        let pixelsPerKnot: CGFloat = 0.58

        ZStack {
            ForEach(-10...10, id: \.self) { index in
                let value = base + Float(index * 10)
                if value >= 0 && value <= 950 {
                    let major = Int(value.rounded()) % 50 == 0
                    HStack(spacing: 3) {
                        if major {
                            Text(String(format: "%02d", Int(value / 10)))
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .monospacedDigit()
                                .frame(width: 22, alignment: .trailing)
                        } else {
                            Spacer().frame(width: 22)
                        }
                        Rectangle()
                            .frame(width: major ? 14 : 7, height: 1)
                    }
                    .offset(y: CGFloat(speed - value) * pixelsPerKnot)
                    .opacity(major ? 0.92 : 0.66)
                }
            }

            HStack(spacing: 4) {
                Text(String(format: "%03.0f", speed < 60 ? 0 : speed))
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .monospacedDigit()
                    .padding(.horizontal, 3)
                    .background(.black.opacity(0.16))

                Rectangle().frame(width: 18, height: 1.2)
            }
            .offset(x: 5)

            Text("C")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .offset(x: 35, y: -17)

            Text(String(format: "M %.2f", state.mach))
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .monospacedDigit()
                .offset(y: 92)
        }
        .frame(width: 86, height: 210)
        .foregroundStyle(color)
        .clipped()
    }
}

private struct F16AltitudeScale: View {
    let state: AircraftState
    let color: Color

    var body: some View {
        let altitude = max(0, state.altitudeFeetMSL)
        let radarAltitude = max(0, state.altitudeMeters * 3.28084)
        let base = floor(altitude / 100) * 100
        let pixelsPerFoot: CGFloat = 0.056

        ZStack {
            ForEach(-10...10, id: \.self) { index in
                let value = base + Float(index * 100)
                if value >= 0 {
                    let major = Int(value.rounded()) % 500 == 0
                    HStack(spacing: 3) {
                        Rectangle()
                            .frame(width: major ? 14 : 7, height: 1)
                        if major {
                            Text(String(format: "%.1f", value / 1_000))
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .monospacedDigit()
                                .frame(width: 30, alignment: .leading)
                        }
                    }
                    .offset(y: CGFloat(altitude - value) * pixelsPerFoot)
                    .opacity(major ? 0.92 : 0.66)
                }
            }

            HStack(spacing: 4) {
                Rectangle().frame(width: 18, height: 1.2)
                Text(String(format: "%05.0f", (altitude / 10).rounded() * 10))
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .monospacedDigit()
                    .padding(.horizontal, 3)
                    .background(.black.opacity(0.16))
            }
            .offset(x: -3)

            Text(String(format: "R %.0f", (radarAltitude / 10).rounded() * 10))
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .monospacedDigit()
                .padding(.horizontal, 3)
                .overlay(Rectangle().stroke(color.opacity(0.72), lineWidth: 1))
                .offset(y: 92)
        }
        .frame(width: 92, height: 210)
        .foregroundStyle(color)
        .clipped()
    }
}

private struct F16VerticalVelocityScale: View {
    let state: AircraftState
    let color: Color

    var body: some View {
        let fpm = state.verticalSpeedMetersPerSecond * 196.8504
        let clampedFPM = min(max(fpm, -6_000), 6_000)
        let pointerY = CGFloat(-clampedFPM / 500) * 8.0

        ZStack {
            Rectangle()
                .frame(width: 1, height: 112)
                .opacity(0.54)

            ForEach(-6...6, id: \.self) { index in
                HStack(spacing: 2) {
                    Rectangle().frame(width: index == 0 ? 10 : 6, height: 1)
                    if abs(index) == 2 || abs(index) == 4 || abs(index) == 6 {
                        Text("\(abs(index) / 2)")
                            .font(.system(size: 6, weight: .black, design: .monospaced))
                    }
                }
                .offset(y: CGFloat(-index) * 8.0)
                .opacity(index == 0 ? 0.90 : 0.58)
            }

            Image(systemName: "triangle.fill")
                .font(.system(size: 6, weight: .black))
                .rotationEffect(.degrees(-90))
                .offset(x: -8, y: pointerY)
        }
        .frame(width: 34, height: 130)
        .foregroundStyle(color)
    }
}

private struct F16HeadingScale: View {
    let headingDegrees: Float
    let color: Color

    var body: some View {
        let heading = wrappedHeading(headingDegrees)
        let base = floor(heading / 5) * 5
        let pixelsPerDegree: CGFloat = 5.1

        ZStack {
            ForEach(-8...8, id: \.self) { index in
                let value = wrappedHeading(base + Float(index * 5))
                let major = Int(value.rounded()) % 10 == 0
                VStack(spacing: 2) {
                    Rectangle()
                        .frame(width: 1, height: major ? 9 : 5)
                    if major {
                        Text(String(format: "%02d", Int(value / 10) % 36))
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .monospacedDigit()
                    }
                }
                .offset(x: CGFloat(signedHeadingDelta(value, heading)) * pixelsPerDegree)
                .opacity(major ? 0.92 : 0.62)
            }

            VStack(spacing: 1) {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 5, weight: .black))
                    .rotationEffect(.degrees(180))
                Text(String(format: "%03.0f", heading))
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .monospacedDigit()
                    .padding(.horizontal, 3)
                    .background(.black.opacity(0.14))
            }
            .offset(y: -13)
        }
        .foregroundStyle(color)
        .clipped()
    }

    private func wrappedHeading(_ value: Float) -> Float {
        let wrapped = value.truncatingRemainder(dividingBy: 360)
        return wrapped >= 0 ? wrapped : wrapped + 360
    }

    private func signedHeadingDelta(_ target: Float, _ reference: Float) -> Float {
        var delta = target - reference
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }
}

private struct F16PitchLadder: View {
    let pitchDegrees: Float
    let rollDegrees: Float
    let driftX: CGFloat
    let pixelsPerDegree: CGFloat
    let gearDown: Bool
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(Array(stride(from: -90, through: 90, by: 5)), id: \.self) { mark in
                    F16PitchBar(mark: mark, color: color)
                        .offset(y: CGFloat(pitchDegrees - Float(mark)) * pixelsPerDegree)
                }

                if gearDown {
                    F16LandingPitchReference(color: color)
                        .offset(y: CGFloat(pitchDegrees + 2.5) * pixelsPerDegree)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .offset(x: driftX)
            .rotationEffect(.degrees(Double(-rollDegrees)))
            .clipped()
        }
    }
}

private struct F16PitchBar: View {
    let mark: Int
    let color: Color

    var body: some View {
        let horizon = mark == 0
        let negative = mark < 0
        let longBar: CGFloat = horizon ? 138 : 76

        HStack(spacing: 7) {
            if !horizon {
                Text("\(abs(mark))")
                    .font(.system(size: 7, weight: .black, design: .monospaced))
                    .monospacedDigit()
                    .frame(width: 20, alignment: .trailing)
            }

            pitchWing(width: longBar, negative: negative, pointsTowardHorizonDown: mark > 0)

            if !horizon {
                Text("\(abs(mark))")
                    .font(.system(size: 7, weight: .black, design: .monospaced))
                    .monospacedDigit()
                    .frame(width: 20, alignment: .leading)
            }
        }
        .foregroundStyle(color)
        .opacity(horizon ? 0.95 : 0.76)
    }

    @ViewBuilder
    private func pitchWing(width: CGFloat, negative: Bool, pointsTowardHorizonDown: Bool) -> some View {
        if mark == 0 {
            HStack(spacing: 22) {
                Rectangle().frame(width: width * 0.5, height: 1.2)
                Rectangle().frame(width: width * 0.5, height: 1.2)
            }
        } else {
            HStack(spacing: 18) {
                wingHalf(width: width, negative: negative, inward: false, down: pointsTowardHorizonDown)
                wingHalf(width: width, negative: negative, inward: true, down: pointsTowardHorizonDown)
            }
        }
    }

    @ViewBuilder
    private func wingHalf(width: CGFloat, negative: Bool, inward: Bool, down: Bool) -> some View {
        HStack(spacing: 3) {
            if inward { Spacer(minLength: 0) }
            if negative {
                HStack(spacing: 3) {
                    Rectangle().frame(width: width * 0.18, height: 1)
                    Rectangle().frame(width: width * 0.18, height: 1)
                    Rectangle().frame(width: width * 0.18, height: 1)
                }
            } else {
                Rectangle().frame(width: width * 0.56, height: 1)
            }
            Rectangle()
                .frame(width: 1, height: 6)
                .offset(y: down ? 2.5 : -2.5)
            if !inward { Spacer(minLength: 0) }
        }
        .frame(width: width)
    }
}

private struct F16LandingPitchReference: View {
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            Text("2.5")
                .font(.system(size: 7, weight: .black, design: .monospaced))
            HStack(spacing: 4) {
                Rectangle().frame(width: 24, height: 1)
                Rectangle().frame(width: 24, height: 1)
            }
            Text("2.5")
                .font(.system(size: 7, weight: .black, design: .monospaced))
        }
        .foregroundStyle(color.opacity(0.82))
    }
}

private struct F16FlightPathMarker: View {
    let color: Color
    let limited: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(color, lineWidth: 1.25)
                .frame(width: 18, height: 18)
            Rectangle().frame(width: 17, height: 1.2).offset(x: -17)
            Rectangle().frame(width: 17, height: 1.2).offset(x: 17)
            Rectangle().frame(width: 1.2, height: 10).offset(y: -14)

            if limited {
                ZStack {
                    Rectangle().frame(width: 32, height: 1.2).rotationEffect(.degrees(45))
                    Rectangle().frame(width: 32, height: 1.2).rotationEffect(.degrees(-45))
                }
            }
        }
        .frame(width: 62, height: 52)
        .foregroundStyle(color)
    }
}

private struct F16BoresightCross: View {
    let color: Color

    var body: some View {
        ZStack {
            Rectangle().frame(width: 11, height: 1).offset(x: -9)
            Rectangle().frame(width: 11, height: 1).offset(x: 9)
            Rectangle().frame(width: 1, height: 7).offset(y: -6)
            Rectangle().frame(width: 1, height: 7).offset(y: 6)
        }
        .frame(width: 34, height: 28)
        .foregroundStyle(color.opacity(0.92))
    }
}

private struct F16BankAngleIndicator: View {
    let rollDegrees: Float
    let color: Color

    var body: some View {
        ZStack {
            ForEach([-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60], id: \.self) { angle in
                Rectangle()
                    .frame(width: 1, height: abs(angle) == 30 || angle == 0 ? 8 : 5)
                    .offset(y: -35)
                    .rotationEffect(.degrees(Double(angle)))
                    .opacity(angle == 0 ? 0.86 : 0.58)
            }

            Image(systemName: "triangle.fill")
                .font(.system(size: 6, weight: .black))
                .offset(y: -45)
                .rotationEffect(.degrees(Double(-rollDegrees)))
        }
        .frame(width: 100, height: 100)
        .foregroundStyle(color)
    }
}

private struct F16AOABracket: View {
    let color: Color
    let pixelsPerDegree: CGFloat

    var body: some View {
        let halfHeight = pixelsPerDegree * 2.0

        ZStack(alignment: .leading) {
            Rectangle()
                .frame(width: 1, height: halfHeight * 2)
            Rectangle()
                .frame(width: 11, height: 1)
                .offset(y: -halfHeight)
            Rectangle()
                .frame(width: 7, height: 1)
            Rectangle()
                .frame(width: 11, height: 1)
                .offset(y: halfHeight)
        }
        .frame(width: 14, height: halfHeight * 2 + 4, alignment: .leading)
        .foregroundStyle(color)
    }
}

private struct GForceVignette: View {
    let loadFactorG: Float

    var body: some View {
        let positiveIntensity = min(max((loadFactorG - 4.5) / 4.5, 0), 1)
        let negativeIntensity = min(max((-loadFactorG - 1.4) / 1.6, 0), 1)
        let intensity = max(positiveIntensity, negativeIntensity)

        RadialGradient(
            colors: [
                .clear,
                .black.opacity(Double(intensity) * 0.08),
                .black.opacity(Double(intensity) * 0.48)
            ],
            center: .center,
            startRadius: 90,
            endRadius: 590
        )
        .opacity(intensity > 0.01 ? 1 : 0)
        .allowsHitTesting(false)
    }
}
'''

text = text[:start] + hud + '\n\n' + text[end:]
content_path.write_text(text)

scene_path = Path('App/PrototypeSceneView.swift')
scene = scene_path.read_text()

old_decl = '''struct PrototypeSceneView: View {\n    @ObservedObject var simulation: FlightSimulation\n    @State private var cameraMode: CameraMode = .chase\n'''
new_decl = '''enum FlightCameraMode: String, CaseIterable {\n    case chase = "CHASE"\n    case close = "CLOSE"\n    case cockpit = "COCKPIT"\n\n    var next: FlightCameraMode {\n        let all = FlightCameraMode.allCases\n        guard let index = all.firstIndex(of: self) else { return .chase }\n        return all[(index + 1) % all.count]\n    }\n}\n\nstruct PrototypeSceneView: View {\n    @ObservedObject var simulation: FlightSimulation\n    @Binding var cameraMode: FlightCameraMode\n'''
if scene.count(old_decl) != 1:
    raise SystemExit('camera mode declaration anchor mismatch')
scene = scene.replace(old_decl, new_decl, 1)

old_enum = '''\n    private enum CameraMode: String, CaseIterable {\n        case chase = "CHASE"\n        case close = "CLOSE"\n        case cockpit = "COCKPIT"\n\n        var next: CameraMode {\n            let all = CameraMode.allCases\n            guard let index = all.firstIndex(of: self) else { return .chase }\n            return all[(index + 1) % all.count]\n        }\n    }\n'''
if scene.count(old_enum) != 1:
    raise SystemExit('camera mode enum anchor mismatch')
scene = scene.replace(old_enum, '\n', 1)
scene_path.write_text(scene)
