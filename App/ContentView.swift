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
            FlightHUD(state: simulation.state, throttle: simulation.controls.throttle)
                .allowsHitTesting(false)

            VStack {
                HStack(spacing: 8) {
                    flightSystemButton(
                        simulation.controls.gearDown ? "GEAR DN" : "GEAR UP",
                        active: simulation.controls.gearDown
                    ) {
                        var controls = simulation.controls
                        controls.gearDown.toggle()
                        simulation.controls = controls
                    }

                    flightSystemButton(
                        simulation.controls.speedbrakeExtended ? "BRK OUT" : "SPD BRK",
                        active: simulation.controls.speedbrakeExtended
                    ) {
                        var controls = simulation.controls
                        controls.speedbrakeExtended.toggle()
                        simulation.controls = controls
                    }

                    Spacer()

                    Button(action: pauseFlight) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.40), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.14), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .safeAreaPadding(.horizontal, 18)
                .padding(.top, 6)

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
                    .padding(.bottom, 5)

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
                .padding(.bottom, 8)
            }
        }
    }

    private var briefingOverlay: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.76), .black.opacity(0.28), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .ignoresSafeArea()

            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(.white)
                            .frame(width: 28, height: 2)
                        Text("NYERAHWORKS FLIGHT SYSTEMS")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    .padding(.bottom, 16)

                    Text("FULL")
                        .font(.system(size: 52, weight: .black, design: .rounded))
                        .tracking(-2.2)
                    Text("AUTHORITY")
                        .font(.system(size: 52, weight: .black, design: .rounded))
                        .tracking(-2.2)
                        .offset(y: -8)

                    Text("F-16A  /  FREE FLIGHT")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.74))
                        .padding(.top, 1)

                    Text("A native JSBSim flight model inside an iPhone-first combat aviation sandbox.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                        .frame(maxWidth: 410, alignment: .leading)
                        .padding(.top, 12)

                    HStack(spacing: 10) {
                        statusChip("JSBSIM", "LIVE FDM")
                        statusChip("F-16A", "FBW")
                        statusChip("PHYSICS", "120 HZ")
                        statusChip("CAM", "AIRFRAME")
                    }
                    .padding(.top, 20)

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
                        .frame(height: 52)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 24)

                    Text(backendLabel)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.42))
                        .padding(.top, 12)
                }
                .safeAreaPadding(.leading, 34)

                Spacer()
            }
        }
    }

    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.38)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text("FLIGHT PAUSED")
                    .font(.system(size: 23, weight: .black, design: .rounded))
                    .tracking(0.5)

                Text("F-16A  ·  JSBSim direct FDM")
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

    private func flightSystemButton(
        _ title: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(active ? Color.black : Color.white.opacity(0.78))
                .padding(.horizontal, 11)
                .frame(height: 38)
                .background(
                    active ? AnyShapeStyle(Color.white.opacity(0.92)) : AnyShapeStyle(Color.black.opacity(0.32)),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(active ? 0.05 : 0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func statusChip(_ top: String, _ bottom: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(top)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.46))
            Text(bottom)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.10), lineWidth: 1))
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
        _ = simulation.resetFlight()
        simulation.resume()
        withAnimation(.easeOut(duration: 0.24)) {
            phase = .flying
        }
    }

    private func pauseFlight() {
        simulation.pause()
        withAnimation(.easeOut(duration: 0.16)) {
            phase = .paused
        }
    }

    private func resumeFlight() {
        simulation.resume()
        withAnimation(.easeOut(duration: 0.16)) {
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
        withAnimation(.easeOut(duration: 0.22)) {
            phase = .briefing
        }
    }
}

private struct FlightHUD: View {
    let state: AircraftState
    let throttle: Float

    private let hudColor = Color(red: 0.57, green: 1.0, blue: 0.66)

    var body: some View {
        ZStack {
            GForceVignette(loadFactorG: state.loadFactorG)
                .ignoresSafeArea()

            VStack(spacing: 6) {
                headingRibbon
                Spacer()
            }
            .safeAreaPadding(.top, 8)

            HStack {
                speedTape
                Spacer()
                altitudeTape
            }
            .safeAreaPadding(.horizontal, 104)

            AttitudeCue(
                rollDegrees: state.rollDegrees,
                pitchDegrees: state.pitchDegrees,
                color: hudColor
            )

            VStack {
                Spacer()
                HStack(spacing: 17) {
                    hudReadout("MACH", String(format: "%.2f", state.mach))
                    hudReadout("G", String(format: "%+.1f", state.loadFactorG))
                    hudReadout("AOA", String(format: "%+.1f°", state.angleOfAttackDegrees))
                    hudReadout("THR", String(format: "%.0f", throttle * 100))
                }
                .padding(.bottom, 72)
            }

            warningBanner
        }
        .foregroundStyle(hudColor)
    }

    private var headingRibbon: some View {
        VStack(spacing: 2) {
            Text(String(format: "%03.0f", state.headingDegrees))
                .font(.system(size: 15, weight: .black, design: .monospaced))
                .monospacedDigit()

            HStack(spacing: 5) {
                Rectangle().frame(width: 24, height: 1)
                Image(systemName: "triangle.fill")
                    .font(.system(size: 6))
                    .rotationEffect(.degrees(180))
                Rectangle().frame(width: 24, height: 1)
            }
            .opacity(0.72)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
    }

    private var speedTape: some View {
        let knots = state.airspeedMetersPerSecond * 1.94384
        return VStack(alignment: .leading, spacing: 1) {
            Text("SPD")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .opacity(0.62)
            HStack(spacing: 5) {
                Text(String(format: "%03.0f", knots))
                    .font(.system(size: 21, weight: .black, design: .monospaced))
                    .monospacedDigit()
                Rectangle().frame(width: 17, height: 1)
            }
            Text("KTAS")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .opacity(0.55)
        }
        .padding(9)
        .background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 10))
    }

    private var altitudeTape: some View {
        let feet = state.altitudeMeters * 3.28084
        let verticalFeetPerMinute = state.verticalSpeedMetersPerSecond * 196.8504
        return VStack(alignment: .trailing, spacing: 1) {
            Text("ALT")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .opacity(0.62)
            HStack(spacing: 5) {
                Rectangle().frame(width: 17, height: 1)
                Text(String(format: "%04.0f", feet))
                    .font(.system(size: 21, weight: .black, design: .monospaced))
                    .monospacedDigit()
            }
            Text(String(format: "%+.0f FPM", verticalFeetPerMinute))
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .opacity(0.55)
        }
        .padding(9)
        .background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 10))
    }

    private func hudReadout(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .opacity(0.55)
            Text(value)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.black.opacity(0.20), in: Capsule())
    }

    @ViewBuilder
    private var warningBanner: some View {
        let lowAltitude = state.altitudeMeters < 150 && state.verticalSpeedMetersPerSecond < -8
        let highAlpha = abs(state.angleOfAttackDegrees) > 25
        let highG = abs(state.loadFactorG) > 8.6

        VStack {
            Spacer()
            if lowAltitude || highAlpha || highG {
                Text(lowAltitude ? "PULL UP" : (highAlpha ? "AOA LIMIT" : "G LIMIT"))
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Color(red: 1.0, green: 0.43, blue: 0.25))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.42), in: Capsule())
                    .padding(.bottom, 112)
            }
        }
    }
}

private struct GForceVignette: View {
    let loadFactorG: Float

    var body: some View {
        let magnitude = abs(loadFactorG)
        let intensity = max(0, min(1, (magnitude - 5.4) / 3.6))
        RadialGradient(
            colors: [
                .clear,
                .black.opacity(Double(intensity) * 0.08),
                .black.opacity(Double(intensity) * 0.42)
            ],
            center: .center,
            startRadius: 90,
            endRadius: 520
        )
        .opacity(intensity > 0 ? 1 : 0)
    }
}

private struct AttitudeCue: View {
    let rollDegrees: Float
    let pitchDegrees: Float
    let color: Color

    private let marks = [-20, -10, 0, 10, 20]

    var body: some View {
        ZStack {
            ForEach(marks, id: \.self) { mark in
                HStack(spacing: 6) {
                    if mark != 0 {
                        Text("\(abs(mark))")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                    }
                    Rectangle()
                        .frame(width: mark == 0 ? 84 : 42, height: mark == 0 ? 1.5 : 1)
                    if mark != 0 {
                        Text("\(abs(mark))")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                    }
                }
                .offset(y: CGFloat(pitchDegrees - Float(mark)) * 2.55)
            }

            HStack(spacing: 5) {
                Rectangle().frame(width: 18, height: 2)
                Circle().stroke(lineWidth: 1.5).frame(width: 24, height: 24)
                Rectangle().frame(width: 18, height: 2)
            }
        }
        .foregroundStyle(color)
        .frame(width: 190, height: 150)
        .clipped()
        .rotationEffect(.degrees(Double(-rollDegrees)))
        .opacity(0.82)
    }
}

private struct CompactThrottleControl: View {
    let value: Float
    let onChange: (Float) -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text(String(format: "%02.0f", value * 100))
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(.white.opacity(0.72))

            GeometryReader { geometry in
                let height = geometry.size.height
                let knob: CGFloat = 38
                let travel = max(1, height - knob)
                let centerY = (1 - CGFloat(value)) * travel + knob * 0.5

                ZStack {
                    Capsule()
                        .fill(.black.opacity(0.32))
                        .frame(width: 18)
                    Capsule()
                        .fill(.white.opacity(0.18))
                        .frame(width: 4, height: travel)
                    Circle()
                        .fill(.white.opacity(0.94))
                        .frame(width: knob, height: knob)
                        .overlay(Circle().stroke(.black.opacity(0.30), lineWidth: 1))
                        .position(x: geometry.size.width * 0.5, y: centerY)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let normalized = 1 - Float(gesture.location.y / max(height, 1))
                            onChange(min(max(normalized, 0), 1))
                        }
                )
            }
            .frame(width: 52, height: 142)

            Text("THR")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.46))
        }
        .padding(8)
        .background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct CompactRudderControl: View {
    let value: Float
    let onChange: (Float) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let usable = max(1, width - 42)
            let knobX = width * 0.5 + CGFloat(value) * usable * 0.5

            ZStack {
                Capsule()
                    .fill(.black.opacity(0.28))
                    .frame(height: 22)
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(width: usable, height: 2)
                Rectangle()
                    .fill(.white.opacity(0.35))
                    .frame(width: 1, height: 24)
                Circle()
                    .fill(.white.opacity(0.92))
                    .frame(width: 32, height: 32)
                    .position(x: knobX, y: geometry.size.height * 0.5)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let centered = Float((gesture.location.x - width * 0.5) / max(usable * 0.5, 1))
                        let clamped = min(max(centered, -1), 1)
                        onChange(abs(clamped) < 0.04 ? 0 : clamped)
                    }
                    .onEnded { _ in onChange(0) }
            )
        }
        .frame(width: 188, height: 40)
    }
}

private struct CompactStickControl: View {
    let roll: Float
    let pitch: Float
    let onChange: (Float, Float) -> Void

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let knob: CGFloat = 38
            let radius = max(1, (side - knob) * 0.5)

            ZStack {
                Circle()
                    .fill(.black.opacity(0.24))
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 1)
                Circle()
                    .stroke(.white.opacity(0.10), lineWidth: 1)
                    .padding(side * 0.27)
                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 1)
                    .padding(.vertical, 8)
                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(height: 1)
                    .padding(.horizontal, 8)
                Circle()
                    .fill(.white.opacity(0.94))
                    .frame(width: knob, height: knob)
                    .overlay(Circle().stroke(.black.opacity(0.30), lineWidth: 1))
                    .offset(
                        x: CGFloat(roll) * radius,
                        y: CGFloat(pitch) * radius
                    )
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
                            let scale = radius / magnitude
                            dx *= scale
                            dy *= scale
                        }

                        var normalizedRoll = Float(dx / radius)
                        var normalizedPitch = Float(dy / radius)
                        if abs(normalizedRoll) < 0.035 { normalizedRoll = 0 }
                        if abs(normalizedPitch) < 0.035 { normalizedPitch = 0 }
                        onChange(normalizedRoll, normalizedPitch)
                    }
                    .onEnded { _ in onChange(0, 0) }
            )
        }
        .frame(width: 148, height: 148)
    }
}

#Preview {
    ContentView()
}
