import Foundation
import SwiftUI

struct ContentView: View {
    @StateObject private var simulation = FlightSimulation()

    var body: some View {
        ZStack {
            PrototypeSceneView(simulation: simulation)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    statusPanel
                    Spacer(minLength: 8)
                    enginePanel
                    telemetryPanel
                }
                .safeAreaPadding(.horizontal, 18)
                .padding(.top, 6)

                Spacer()

                HStack(alignment: .bottom, spacing: 18) {
                    ThrottleControl(value: simulation.controls.throttle) { newValue in
                        var controls = simulation.controls
                        controls.throttle = newValue
                        simulation.controls = controls
                    }

                    Spacer(minLength: 10)

                    RudderControl(value: simulation.controls.rudder) { newValue in
                        var controls = simulation.controls
                        controls.rudder = newValue
                        simulation.controls = controls
                    }
                    .padding(.bottom, 4)

                    Spacer(minLength: 10)

                    StickControl(
                        roll: simulation.controls.roll,
                        pitch: simulation.controls.pitch
                    ) { roll, pitch in
                        var controls = simulation.controls
                        controls.roll = roll
                        controls.pitch = pitch
                        simulation.controls = controls
                    }
                }
                .safeAreaPadding(.horizontal, 42)
                .padding(.bottom, 10)
            }
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("FULL AUTHORITY")
                .font(.system(size: 17, weight: .black, design: .rounded))

            Text("STAGE 007 · F-16A · DIRECT FDM")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            Text(backendLabel)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.black.opacity(0.40), in: RoundedRectangle(cornerRadius: 13))
    }

    private var enginePanel: some View {
        HStack(spacing: 12) {
            telemetryItem("THR", String(format: "%.0f%%", simulation.controls.throttle * 100))
            telemetryItem("FDM", "F-16A")
            telemetryItem("FCS", "FBW")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.40), in: RoundedRectangle(cornerRadius: 13))
    }

    private var telemetryPanel: some View {
        let knots = simulation.state.airspeedMetersPerSecond * 1.94384
        let verticalSpeed = simulation.state.verticalSpeedMetersPerSecond

        return HStack(spacing: 12) {
            telemetryItem("ALT", String(format: "%.0f m", simulation.state.altitudeMeters))
            telemetryItem("IAS", String(format: "%.0f kt", knots))
            telemetryItem("V/S", String(format: "%+.1f", verticalSpeed))
            telemetryItem("HDG", String(format: "%03.0f°", simulation.state.headingDegrees))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.40), in: RoundedRectangle(cornerRadius: 13))
    }

    private func telemetryItem(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .monospacedDigit()
        }
    }

    private var backendLabel: String {
        switch simulation.backendStatus {
        case .bridgeReady(let version):
            return "JSBSIM \(version) · BRIDGE READY"
        case .running(let model):
            return "JSBSIM · \(model.uppercased()) · RUNNING"
        case .failed(let message):
            return "JSBSIM ERROR · \(message)"
        }
    }
}

private struct ThrottleControl: View {
    let value: Float
    let onChange: (Float) -> Void

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 5) {
                Text("THROTTLE")
                Text(String(format: "%02.0f%%", value * 100))
                    .foregroundStyle(.white)
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.secondary)

            GeometryReader { geometry in
                let height = geometry.size.height
                let knobDiameter: CGFloat = 38
                let travel = max(1, height - knobDiameter)
                let centerY = (1 - CGFloat(value)) * travel + knobDiameter * 0.5

                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(.black.opacity(0.44))
                        .frame(width: 26)

                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(0.25))
                        .frame(width: 10, height: max(4, CGFloat(value) * travel))
                        .padding(.bottom, knobDiameter * 0.5)

                    VStack {
                        Text("MAX")
                        Spacer()
                        Text("MIL")
                        Spacer()
                        Text("IDLE")
                    }
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.52))
                    .frame(maxHeight: .infinity)
                    .offset(x: 31)

                    Circle()
                        .fill(.white)
                        .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 2))
                        .frame(width: knobDiameter, height: knobDiameter)
                        .position(x: geometry.size.width * 0.5, y: centerY)
                        .shadow(radius: 3)
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
            .frame(width: 78, height: 188)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.black.opacity(0.44), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct RudderControl: View {
    let value: Float
    let onChange: (Float) -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("L RUDDER")
                Spacer()
                Text(String(format: "%+.0f%%", value * 100))
                Spacer()
                Text("R RUDDER")
            }
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(.secondary)

            GeometryReader { geometry in
                let width = geometry.size.width
                let usable = max(1, width - 46)
                let knobX = width * 0.5 + CGFloat(value) * usable * 0.5

                ZStack {
                    Capsule()
                        .fill(.black.opacity(0.48))
                        .frame(height: 30)

                    Rectangle()
                        .fill(.white.opacity(0.32))
                        .frame(width: 2, height: 34)

                    Circle()
                        .fill(.white)
                        .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 2))
                        .frame(width: 34, height: 34)
                        .position(x: knobX, y: geometry.size.height * 0.5)
                        .shadow(radius: 3)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let centered = Float((gesture.location.x - width * 0.5) / max(usable * 0.5, 1))
                            let clamped = min(max(centered, -1), 1)
                            onChange(abs(clamped) < 0.045 ? 0 : clamped)
                        }
                        .onEnded { _ in onChange(0) }
                )
            }
            .frame(width: 230, height: 42)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.black.opacity(0.44), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct StickControl: View {
    let roll: Float
    let pitch: Float
    let onChange: (Float, Float) -> Void

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text("STICK")
                Spacer()
                Text(String(format: "R%+.0f P%+.0f", roll * 100, pitch * 100))
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.secondary)

            GeometryReader { geometry in
                let side = min(geometry.size.width, geometry.size.height)
                let knobDiameter: CGFloat = 42
                let radius = max(1, (side - knobDiameter) * 0.5)

                ZStack {
                    Circle()
                        .fill(.black.opacity(0.48))
                    Circle()
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                        .padding(side * 0.23)
                    Circle()
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                        .padding(side * 0.40)
                    Rectangle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 1)
                        .padding(.vertical, 10)
                    Rectangle()
                        .fill(.white.opacity(0.18))
                        .frame(height: 1)
                        .padding(.horizontal, 10)
                    Circle()
                        .fill(.white)
                        .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 2))
                        .frame(width: knobDiameter, height: knobDiameter)
                        .shadow(radius: 4)
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
                            // Conventional stick: pull down for nose-up, move right
                            // for right roll. FlightSimulation handles FDM signs.
                            var normalizedPitch = Float(dy / radius)
                            if abs(normalizedRoll) < 0.04 { normalizedRoll = 0 }
                            if abs(normalizedPitch) < 0.04 { normalizedPitch = 0 }
                            onChange(normalizedRoll, normalizedPitch)
                        }
                        .onEnded { _ in onChange(0, 0) }
                )
            }
            .frame(width: 166, height: 166)
        }
        .padding(11)
        .background(.black.opacity(0.44), in: RoundedRectangle(cornerRadius: 22))
    }
}

#Preview {
    ContentView()
}
