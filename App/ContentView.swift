import Foundation
import SwiftUI

struct ContentView: View {
    private enum GamePhase {
        case briefing
        case flying
        case paused
    }

    @StateObject private var simulation = FlightSimulation()
    @State private var phase: GamePhase = .briefing
    @State private var cameraMode: FlightCameraMode = .chase
    @State private var hmdEnabled = true

    var body: some View {
        ZStack {
            PrototypeSceneView(simulation: simulation, cameraMode: $cameraMode)
                .ignoresSafeArea()

            switch phase {
            case .briefing:
                briefingOverlay
                    .transition(.opacity)
            case .flying:
                flightInterface
                    .transition(.opacity)
            case .paused:
                flightInterface
                pauseOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .preferredColorScheme(.dark)
    }

    private var flightInterface: some View {
        ZStack {
            // HMD is a real user toggle in every camera mode. Cockpit no longer
            // forces the symbology back on after the pilot turns it off.
            if hmdEnabled {
                F16HUD(state: simulation.state, controls: simulation.controls)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    systemToggleButton(
                        title: "GEAR",
                        value: gearStatus,
                        active: simulation.controls.gearDown || simulation.state.gearPosition > 0.05
                    ) {
                        var controls = simulation.controls
                        controls.gearDown.toggle()
                        simulation.controls = controls
                    }

                    systemToggleButton(
                        title: "SPD BRK",
                        value: String(format: "%02.0f", simulation.state.speedbrakePosition * 100),
                        active: simulation.controls.speedbrakeExtended || simulation.state.speedbrakePosition > 0.05
                    ) {
                        var controls = simulation.controls
                        controls.speedbrakeExtended.toggle()
                        simulation.controls = controls
                    }

                    systemToggleButton(
                        title: "HMD",
                        value: hmdEnabled ? "ON" : "OFF",
                        active: hmdEnabled
                    ) {
                        hmdEnabled.toggle()
                    }

                    Spacer()

                    Button(action: pauseFlight) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 38, height: 38)
                            .background(.black.opacity(0.24), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.10), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .safeAreaPadding(.horizontal, 18)
                .padding(.top, 5)

                Spacer()

                HStack(alignment: .bottom, spacing: 0) {
                    CompactThrottleControl(value: simulation.controls.throttle) { value in
                        var controls = simulation.controls
                        controls.throttle = value
                        simulation.controls = controls
                    }

                    Spacer()

                    HStack(alignment: .bottom, spacing: 8) {
                        wheelBrakeButton

                        CompactRudderControl(value: simulation.controls.rudder) { value in
                            var controls = simulation.controls
                            controls.rudder = value
                            simulation.controls = controls
                        }
                    }
                    .padding(.bottom, 2)

                    Spacer()

                    CompactStickControl(
                        roll: simulation.controls.roll,
                        pitch: simulation.controls.pitch
                    ) { roll, pitch in
                        var controls = simulation.controls
                        controls.roll = roll
                        controls.pitch = pitch
                        simulation.controls = controls
                    }
                }
                .safeAreaPadding(.horizontal, 26)
                .padding(.bottom, 10)
            }
        }
    }

    private var wheelBrakeButton: some View {
        let active = simulation.controls.wheelBrake > 0.01

        return VStack(spacing: 1) {
            Text("BRAKE")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(active ? Color.black.opacity(0.64) : Color.white.opacity(0.48))
            Text(active ? "ON" : "HOLD")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(active ? Color.black : Color.white.opacity(0.90))
        }
        .frame(width: 58, height: 46)
        .background(active ? Color.white.opacity(0.92) : Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(active ? 0.04 : 0.10), lineWidth: 1))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard simulation.controls.wheelBrake < 0.99 else { return }
                    var controls = simulation.controls
                    controls.wheelBrake = 1
                    simulation.controls = controls
                }
                .onEnded { _ in
                    var controls = simulation.controls
                    controls.wheelBrake = 0
                    simulation.controls = controls
                }
        )
    }

    private var briefingOverlay: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.80), .black.opacity(0.38), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .ignoresSafeArea()

            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(.white)
                            .frame(width: 30, height: 2)
                        Text("NYERAHWORKS FLIGHT SYSTEMS")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    .padding(.bottom, 14)

                    Text("FULL")
                        .font(.system(size: 50, weight: .black, design: .rounded))
                        .tracking(-2.0)
                    Text("AUTHORITY")
                        .font(.system(size: 50, weight: .black, design: .rounded))
                        .tracking(-2.0)
                        .offset(y: -8)

                    HStack(spacing: 9) {
                        Text("STAGE 2")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .tracking(1.2)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.white, in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(.black)

                        Text("F-16A / RUNWAY SORTIE")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .tracking(1.0)
                            .foregroundStyle(.white.opacity(0.76))
                    }

                    Text("Runway start, direct JSBSim F-16 dynamics, native terrain contact and aircraft-relative cameras.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                        .frame(maxWidth: 470, alignment: .leading)
                        .padding(.top, 12)

                    HStack(spacing: 9) {
                        statusChip("FDM", "JSBSIM")
                        statusChip("FCS", "F-16 FBW")
                        statusChip("RATE", "120 HZ")
                        statusChip("GROUND", "LIVE")
                    }
                    .padding(.top, 18)

                    HStack(spacing: 15) {
                        Label("Throttle left", systemImage: "arrow.up.and.down")
                        Label("Rudder + brake center", systemImage: "arrow.left.and.right")
                        Label("Stick right", systemImage: "circle.circle")
                    }
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.48))
                    .padding(.top, 13)

                    Text("TAKEOFF  •  RELEASE BRAKE  •  ADVANCE THROTTLE  •  ROTATE ~145 KCAS  •  GEAR UP WITH POSITIVE CLIMB")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.35)
                        .foregroundStyle(.white.opacity(0.42))
                        .padding(.top, 10)

                    Button(action: launchFlight) {
                        HStack(spacing: 14) {
                            Text("BEGIN SORTIE")
                                .font(.system(size: 13, weight: .black, design: .monospaced))
                                .tracking(0.9)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 22)
                        .frame(height: 50)
                        .background(.white, in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 20)

                    Text(backendLabel)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.42))
                        .padding(.top, 10)
                }
                .safeAreaPadding(.leading, 32)

                Spacer()
            }
        }
    }

    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.40)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text("FLIGHT PAUSED")
                    .font(.system(size: 23, weight: .black, design: .rounded))
                    .tracking(0.5)

                Text("F-16A · JSBSim direct FDM · STAGE 2")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    pauseButton("RESUME", systemImage: "play.fill", primary: true, action: resumeFlight)
                    pauseButton("RESTART", systemImage: "arrow.counterclockwise", primary: false, action: restartFlight)
                    pauseButton("BRIEFING", systemImage: "rectangle.portrait.and.arrow.right", primary: false, action: returnToBriefing)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.12), lineWidth: 1))
        }
    }

    private func systemToggleButton(
        title: String,
        value: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(active ? Color.black.opacity(0.68) : Color.white.opacity(0.50))
                Text(value)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(active ? Color.black : Color.white.opacity(0.90))
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(active ? Color.white.opacity(0.92) : Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(active ? 0.04 : 0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func statusChip(_ top: String, _ bottom: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(top)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.44))
            Text(bottom)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(.white.opacity(0.90))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.09), lineWidth: 1))
    }

    private func pauseButton(
        _ title: String,
        systemImage: String,
        primary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(primary ? Color.black : Color.white)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(
                    primary ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.08)),
                    in: RoundedRectangle(cornerRadius: 12)
                )
        }
        .buttonStyle(.plain)
    }

    private var gearStatus: String {
        let position = simulation.state.gearPosition
        if position > 0.95 { return "DOWN" }
        if position < 0.05 { return "UP" }
        return "TRANS"
    }

    private var backendLabel: String {
        switch simulation.backendStatus {
        case .bridgeReady(let version):
            return "JSBSIM \(version) · BRIDGE READY"
        case .running(let model):
            return "JSBSIM · \(model.uppercased()) · READY"
        case .failed(let message):
            return "JSBSIM ERROR · \(message)"
        }
    }

    private func launchFlight() {
        simulation.resume()
        withAnimation(.easeOut(duration: 0.22)) {
            phase = .flying
        }
    }

    private func pauseFlight() {
        var controls = simulation.controls
        controls.wheelBrake = 0
        simulation.controls = controls
        simulation.pause()
        withAnimation(.easeOut(duration: 0.14)) {
            phase = .paused
        }
    }

    private func resumeFlight() {
        simulation.resume()
        withAnimation(.easeOut(duration: 0.14)) {
            phase = .flying
        }
    }

    private func restartFlight() {
        _ = simulation.resetFlight()
        simulation.resume()
        withAnimation(.easeOut(duration: 0.16)) {
            phase = .flying
        }
    }

    private func returnToBriefing() {
        _ = simulation.resetFlight()
        withAnimation(.easeOut(duration: 0.20)) {
            phase = .briefing
        }
    }
}

private struct F16HUD: View {
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

                    if gearDown {
                        let aoaBracketY = fpmY + CGFloat(13.0 - state.angleOfAttackDegrees) * pixelsPerDegree
                        F16AOABracket(color: hudColor, pixelsPerDegree: pixelsPerDegree)
                            .offset(x: fpmX - 48, y: aoaBracketY)
                    }

                    F16VelocityScale(state: state, color: hudColor)
                        .offset(x: -hudWidth * 0.68)

                    F16AltitudeScale(state: state, color: hudColor)
                        .offset(x: hudWidth * 0.67)

                    F16HeadingScale(headingDegrees: state.headingDegrees, color: hudColor)
                        .frame(width: hudWidth * 0.68, height: 48)
                        .offset(y: hudHeight * 0.39)

                    VStack {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("NAV")
                                Text(String(format: "G %.1f", state.loadFactorG))
                                Text(String(format: "M %.2f", state.mach))
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
            .offset(x: -47)

            Text("C")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .offset(x: 35, y: -17)

        }
        .frame(width: 150, height: 210)
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
            .offset(x: 49)

            Text(String(format: "R %.0f", (radarAltitude / 10).rounded() * 10))
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .monospacedDigit()
                .padding(.horizontal, 3)
                .overlay(Rectangle().stroke(color.opacity(0.72), lineWidth: 1))
                .offset(y: 92)
        }
        .frame(width: 158, height: 210)
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

private struct CompactThrottleControl: View {
    let value: Float
    let onChange: (Float) -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Text(value > 0.92 ? "AB" : "THR")
                Text(String(format: "%02.0f", value * 100))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .foregroundStyle(.white.opacity(0.58))

            GeometryReader { geometry in
                let height = geometry.size.height
                let knobHeight: CGFloat = 28
                let travel = max(1, height - knobHeight)
                let y = (1 - CGFloat(value)) * travel + knobHeight * 0.5
                let milY = (1 - CGFloat(0.82)) * travel + knobHeight * 0.5

                ZStack {
                    Capsule()
                        .fill(.black.opacity(0.24))
                        .frame(width: 16)

                    Rectangle()
                        .fill(.white.opacity(0.28))
                        .frame(width: 18, height: 1)
                        .position(x: geometry.size.width * 0.5, y: milY)

                    Text("MIL")
                        .font(.system(size: 6, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.42))
                        .position(x: geometry.size.width * 0.5 + 22, y: milY)

                    RoundedRectangle(cornerRadius: 7)
                        .fill(.white.opacity(0.93))
                        .frame(width: 30, height: knobHeight)
                        .position(x: geometry.size.width * 0.5, y: y)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let normalized = 1 - Float(gesture.location.y / max(height, 1))
                            onChange(min(max(normalized, 0), 1))
                        }
                )
            }
            .frame(width: 50, height: 126)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 6)
        .background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct CompactRudderControl: View {
    let value: Float
    let onChange: (Float) -> Void

    var body: some View {
        VStack(spacing: 3) {
            Text("RUDDER / NWS")
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundStyle(.white.opacity(0.44))

            GeometryReader { geometry in
                let width = geometry.size.width
                let travel = max(1, width - 30)
                let x = width * 0.5 + CGFloat(value) * travel * 0.5

                ZStack {
                    Capsule()
                        .fill(.black.opacity(0.24))
                        .frame(height: 18)
                    Rectangle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 1, height: 21)
                    Circle()
                        .fill(.white.opacity(0.92))
                        .frame(width: 26, height: 26)
                        .position(x: x, y: geometry.size.height * 0.5)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let normalized = Float((gesture.location.x - width * 0.5) / max(travel * 0.5, 1))
                            let clamped = min(max(normalized, -1), 1)
                            onChange(abs(clamped) < 0.04 ? 0 : clamped)
                        }
                        .onEnded { _ in onChange(0) }
                )
            }
            .frame(width: 180, height: 29)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct CompactStickControl: View {
    let roll: Float
    let pitch: Float
    let onChange: (Float, Float) -> Void

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let knob: CGFloat = 32
            let radius = max(1, (side - knob) * 0.5)

            ZStack {
                Circle()
                    .fill(.black.opacity(0.14))
                Circle()
                    .stroke(.white.opacity(0.13), lineWidth: 1)
                    .padding(side * 0.29)
                Rectangle().fill(.white.opacity(0.08)).frame(width: 1).padding(10)
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1).padding(10)
                Circle()
                    .fill(.white.opacity(0.93))
                    .frame(width: knob, height: knob)
                    .offset(x: CGFloat(roll) * radius, y: CGFloat(pitch) * radius)
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let center = CGPoint(x: geometry.size.width * 0.5, y: geometry.size.height * 0.5)
                        var dx = gesture.location.x - center.x
                        var dy = gesture.location.y - center.y
                        let magnitude = sqrt(dx * dx + dy * dy)
                        if magnitude > radius {
                            let factor = radius / magnitude
                            dx *= factor
                            dy *= factor
                        }
                        var normalizedRoll = Float(dx / radius)
                        var normalizedPitch = Float(dy / radius)
                        if abs(normalizedRoll) < 0.03 { normalizedRoll = 0 }
                        if abs(normalizedPitch) < 0.03 { normalizedPitch = 0 }
                        onChange(normalizedRoll, normalizedPitch)
                    }
                    .onEnded { _ in onChange(0, 0) }
            )
        }
        .frame(width: 112, height: 112)
        .padding(6)
        .background(.black.opacity(0.10), in: Circle())
    }
}

#Preview {
    ContentView()
}
