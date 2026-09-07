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

    var body: some View {
        ZStack {
            PrototypeSceneView(simulation: simulation)
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
            F16HUD(state: simulation.state, controls: simulation.controls)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    systemToggleButton(
                        title: simulation.state.gearPosition > 0.05 ? "GEAR" : "GEAR",
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

                    wheelBrakeButton

                    if simulation.state.weightOnWheels {
                        Text("WOW")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.84))
                            .padding(.horizontal, 10)
                            .frame(height: 36)
                            .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 9))
                    }

                    Spacer()

                    Button(action: pauseFlight) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.30), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .safeAreaPadding(.horizontal, 16)
                .padding(.top, 5)

                Spacer()

                HStack(alignment: .bottom) {
                    CompactThrottleControl(value: simulation.controls.throttle) { value in
                        var controls = simulation.controls
                        controls.throttle = value
                        simulation.controls = controls
                    }

                    Spacer()

                    CompactRudderControl(value: simulation.controls.rudder) { value in
                        var controls = simulation.controls
                        controls.rudder = value
                        simulation.controls = controls
                    }
                    .padding(.bottom, 4)

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
                .safeAreaPadding(.horizontal, 24)
                .padding(.bottom, 7)
            }
        }
    }

    private var wheelBrakeButton: some View {
        let active = simulation.controls.wheelBrake > 0.01

        return VStack(spacing: 1) {
            Text("WHEEL BRK")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(active ? Color.black.opacity(0.70) : Color.white.opacity(0.52))
            Text(active ? "ON" : "HOLD")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(active ? Color.black : Color.white.opacity(0.90))
        }
        .padding(.horizontal, 11)
        .frame(height: 36)
        .background(active ? Color.white.opacity(0.92) : Color.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(active ? 0.04 : 0.11), lineWidth: 1))
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
                        Text("PHASE II")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .tracking(1.2)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.white, in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(.black)

                        Text("F-16A / FREE FLIGHT")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .tracking(1.0)
                            .foregroundStyle(.white.opacity(0.76))
                    }

                    Text("Direct JSBSim F-16 dynamics with a fighter-oriented flight display and native ground reactions.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                        .frame(maxWidth: 450, alignment: .leading)
                        .padding(.top, 12)

                    HStack(spacing: 9) {
                        statusChip("FDM", "JSBSIM")
                        statusChip("FCS", "F-16 FBW")
                        statusChip("RATE", "120 HZ")
                        statusChip("HUD", "NAV")
                        statusChip("GROUND", "NATIVE")
                    }
                    .padding(.top, 18)

                    HStack(spacing: 16) {
                        Label("Hold WHEEL BRK to brake", systemImage: "hand.tap")
                        Label("Rudder steers on WOW", systemImage: "arrow.left.and.right")
                    }
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.48))
                    .padding(.top, 13)

                    Button(action: launchFlight) {
                        HStack(spacing: 14) {
                            Text("ENTER FREE FLIGHT")
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
                    .padding(.top, 22)

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

                Text("F-16A · JSBSim direct FDM · PHASE II")
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
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(active ? Color.white.opacity(0.92) : Color.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(active ? 0.04 : 0.11), lineWidth: 1))
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

    private let hudColor = Color(red: 0.45, green: 1.0, blue: 0.56)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let fpmX = clamp(CGFloat(-state.sideslipDegrees) * 5.0, min: -width * 0.30, max: width * 0.30)
            let fpmY = clamp(CGFloat(state.angleOfAttackDegrees) * 5.0, min: -height * 0.27, max: height * 0.27)

            ZStack {
                GForceVignette(loadFactorG: state.loadFactorG)
                    .ignoresSafeArea()

                PitchLadder(
                    pitchDegrees: state.pitchDegrees,
                    rollDegrees: state.rollDegrees,
                    color: hudColor
                )
                .frame(width: min(width * 0.52, 470), height: min(height * 0.64, 330))

                BoresightCue(color: hudColor)
                    .offset(y: -18)

                FlightPathMarker(color: hudColor, limited: abs(fpmX) >= width * 0.295 || abs(fpmY) >= height * 0.265)
                    .offset(x: fpmX, y: fpmY)

                if state.gearPosition > 0.55 {
                    LandingReferenceCue(color: hudColor)
                        .offset(y: 24)
                }

                VStack(spacing: 0) {
                    HeadingTape(headingDegrees: state.headingDegrees, color: hudColor)
                        .frame(width: min(width * 0.46, 420), height: 52)
                    Spacer()
                }
                .safeAreaPadding(.top, 5)

                HStack {
                    AirspeedTape(state: state, color: hudColor)
                    Spacer()
                    AltitudeTape(state: state, color: hudColor)
                }
                .safeAreaPadding(.horizontal, 76)

                VStack {
                    Spacer()
                    bottomData
                        .padding(.bottom, 58)
                }

                warningBanner
            }
            .foregroundStyle(hudColor)
        }
    }

    private var bottomData: some View {
        HStack(spacing: 15) {
            hudDatum("M", String(format: "%.2f", state.mach))
            hudDatum("G", String(format: "%+.1f", state.loadFactorG))
            hudDatum("AOA", String(format: "%+.1f", state.angleOfAttackDegrees))
            hudDatum("FPA", String(format: "%+.1f", state.flightPathAngleDegrees))

            Rectangle()
                .frame(width: 1, height: 22)
                .opacity(0.26)

            hudDatum("GEAR", gearReadout)
            hudDatum("SB", String(format: "%02.0f", state.speedbrakePosition * 100))
            if controls.wheelBrake > 0.01 {
                hudDatum("BRK", String(format: "%02.0f", controls.wheelBrake * 100))
            }
            if state.weightOnWheels {
                hudDatum("WOW", "ON")
            }
        }
        .fontDesign(.monospaced)
    }

    private var gearReadout: String {
        if state.gearPosition > 0.95 { return "DN" }
        if state.gearPosition < 0.05 { return "UP" }
        return "T"
    }

    @ViewBuilder
    private var warningBanner: some View {
        let altitudeFeetAGL = state.altitudeMeters * 3.28084
        let descendingFast = state.verticalSpeedMetersPerSecond < -28

        VStack {
            if altitudeFeetAGL < 450 && descendingFast {
                warningText("PULL UP")
            } else if abs(state.angleOfAttackDegrees) > 24 {
                warningText("AOA LIMIT")
            } else if state.loadFactorG > 8.4 {
                warningText("G LIMIT")
            } else if state.gearPosition > 0.5 && state.calibratedAirspeedKnots > 300 {
                warningText("GEAR OVERSPEED")
            }
            Spacer()
        }
        .padding(.top, 60)
    }

    private func warningText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .black, design: .monospaced))
            .tracking(1.7)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 6))
    }

    private func hudDatum(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .opacity(0.54)
            Text(value)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .monospacedDigit()
        }
    }

    private func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}

private struct HeadingTape: View {
    let headingDegrees: Float
    let color: Color

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                ForEach(Array(-3...3), id: \.self) { index in
                    let heading = wrappedHeading(headingDegrees + Float(index * 10))
                    VStack(spacing: 2) {
                        Rectangle()
                            .frame(width: 1, height: index == 0 ? 10 : 6)
                            .opacity(index == 0 ? 0.95 : 0.62)
                        Text(tapeLabel(heading))
                            .font(.system(size: index == 0 ? 11 : 9, weight: .black, design: .monospaced))
                            .monospacedDigit()
                            .opacity(index == 0 ? 0.96 : 0.67)
                    }
                    .frame(width: 52)
                }
            }

            VStack(spacing: 1) {
                Text(String(format: "%03.0f", wrappedHeading(headingDegrees)))
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .background(.black.opacity(0.18))
                Image(systemName: "triangle.fill")
                    .font(.system(size: 5, weight: .bold))
            }
            .offset(y: 27)
        }
        .foregroundStyle(color)
        .clipped()
    }

    private func wrappedHeading(_ heading: Float) -> Float {
        let value = heading.truncatingRemainder(dividingBy: 360)
        return value >= 0 ? value : value + 360
    }

    private func tapeLabel(_ heading: Float) -> String {
        let tens = Int((heading / 10).rounded()) % 36
        return String(format: "%02d", tens)
    }
}

private struct AirspeedTape: View {
    let state: AircraftState
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("CAS")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .opacity(0.58)

            HStack(spacing: 4) {
                Text(String(format: "%03.0f", state.calibratedAirspeedKnots))
                    .font(.system(size: 19, weight: .black, design: .monospaced))
                    .monospacedDigit()
                HStack(spacing: 0) {
                    Rectangle().frame(width: 14, height: 1)
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 5))
                        .rotationEffect(.degrees(90))
                }
            }

            Text(String(format: "M %.2f", state.mach))
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .opacity(0.72)

            if state.weightOnWheels {
                Text(String(format: "GS %03.0f", state.groundSpeedKnots))
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .opacity(0.56)
            }
        }
        .foregroundStyle(color)
    }
}

private struct AltitudeTape: View {
    let state: AircraftState
    let color: Color

    var body: some View {
        let aglFeet = state.altitudeMeters * 3.28084
        let verticalFeetPerMinute = state.verticalSpeedMetersPerSecond * 196.8504

        VStack(alignment: .trailing, spacing: 1) {
            Text("BARO")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .opacity(0.58)

            HStack(spacing: 4) {
                HStack(spacing: 0) {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 5))
                        .rotationEffect(.degrees(-90))
                    Rectangle().frame(width: 14, height: 1)
                }
                Text(String(format: "%05.0f", state.altitudeFeetMSL))
                    .font(.system(size: 19, weight: .black, design: .monospaced))
                    .monospacedDigit()
            }

            Text(String(format: "AGL %04.0f", aglFeet))
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .opacity(aglFeet < 1_500 ? 0.86 : 0.56)

            Text(String(format: "%+.0f FPM", verticalFeetPerMinute))
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .opacity(0.55)
        }
        .foregroundStyle(color)
    }
}

private struct PitchLadder: View {
    let pitchDegrees: Float
    let rollDegrees: Float
    let color: Color

    private let pixelsPerDegree: CGFloat = 6.1

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(Array(stride(from: -30, through: 30, by: 5)), id: \.self) { mark in
                    ladderLine(mark)
                        .offset(y: CGFloat(pitchDegrees - Float(mark)) * pixelsPerDegree)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .rotationEffect(.degrees(Double(-rollDegrees)))
            .clipped()
        }
        .foregroundStyle(color)
    }

    @ViewBuilder
    private func ladderLine(_ mark: Int) -> some View {
        let horizon = mark == 0
        let negative = mark < 0
        let width: CGFloat = horizon ? 138 : 84

        HStack(spacing: 7) {
            if !horizon {
                Text("\(abs(mark))")
                    .font(.system(size: 7, weight: .black, design: .monospaced))
                    .monospacedDigit()
            }

            if negative {
                HStack(spacing: 4) {
                    Rectangle().frame(width: width * 0.23, height: 1)
                    Rectangle().frame(width: width * 0.23, height: 1)
                    Rectangle().frame(width: width * 0.23, height: 1)
                }
            } else {
                Rectangle().frame(width: width, height: horizon ? 1.4 : 1)
            }

            if !horizon {
                Text("\(abs(mark))")
                    .font(.system(size: 7, weight: .black, design: .monospaced))
                    .monospacedDigit()
            }
        }
        .opacity(horizon ? 0.95 : 0.70)
    }
}

private struct FlightPathMarker: View {
    let color: Color
    let limited: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(color, lineWidth: 1.4)
                .frame(width: 18, height: 18)

            HStack(spacing: 18) {
                Rectangle().frame(width: 18, height: 1.4)
                Rectangle().frame(width: 18, height: 1.4)
            }

            Rectangle()
                .frame(width: 1.4, height: 11)
                .offset(y: -13)

            if limited {
                Text("X")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
            }
        }
        .foregroundStyle(color)
        .frame(width: 62, height: 50)
    }
}

private struct BoresightCue: View {
    let color: Color

    var body: some View {
        ZStack {
            HStack(spacing: 6) {
                Rectangle().frame(width: 10, height: 1)
                Rectangle().frame(width: 10, height: 1)
            }
            Rectangle().frame(width: 1, height: 7)
        }
        .foregroundStyle(color.opacity(0.82))
        .frame(width: 34, height: 18)
    }
}

private struct LandingReferenceCue: View {
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Text("-2.5")
                .font(.system(size: 7, weight: .black, design: .monospaced))
            Rectangle().frame(width: 70, height: 1)
            Text("-2.5")
                .font(.system(size: 7, weight: .black, design: .monospaced))
        }
        .foregroundStyle(color.opacity(0.76))
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
                let knobHeight: CGFloat = 30
                let travel = max(1, height - knobHeight)
                let y = (1 - CGFloat(value)) * travel + knobHeight * 0.5
                let milY = (1 - CGFloat(0.82)) * travel + knobHeight * 0.5

                ZStack {
                    Capsule()
                        .fill(.black.opacity(0.28))
                        .frame(width: 18)

                    Rectangle()
                        .fill(.white.opacity(0.30))
                        .frame(width: 20, height: 1)
                        .position(x: geometry.size.width * 0.5, y: milY)

                    Text("MIL")
                        .font(.system(size: 6, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.44))
                        .position(x: geometry.size.width * 0.5 + 24, y: milY)

                    RoundedRectangle(cornerRadius: 7)
                        .fill(.white.opacity(0.93))
                        .frame(width: 32, height: knobHeight)
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
            .frame(width: 54, height: 136)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 7)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
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
                let travel = max(1, width - 32)
                let x = width * 0.5 + CGFloat(value) * travel * 0.5

                ZStack {
                    Capsule()
                        .fill(.black.opacity(0.28))
                        .frame(height: 20)
                    Rectangle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 1, height: 23)
                    Circle()
                        .fill(.white.opacity(0.90))
                        .frame(width: 28, height: 28)
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
            .frame(width: 158, height: 31)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.black.opacity(0.17), in: RoundedRectangle(cornerRadius: 13))
    }
}

private struct CompactStickControl: View {
    let roll: Float
    let pitch: Float
    let onChange: (Float, Float) -> Void

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let knob: CGFloat = 34
            let radius = max(1, (side - knob) * 0.5)

            ZStack {
                Circle()
                    .fill(.black.opacity(0.20))
                Circle()
                    .stroke(.white.opacity(0.14), lineWidth: 1)
                    .padding(side * 0.29)
                Rectangle().fill(.white.opacity(0.09)).frame(width: 1).padding(10)
                Rectangle().fill(.white.opacity(0.09)).frame(height: 1).padding(10)
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
        .frame(width: 124, height: 124)
        .padding(7)
        .background(.black.opacity(0.16), in: Circle())
    }
}

#Preview {
    ContentView()
}
