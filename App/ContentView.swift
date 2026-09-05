import SwiftUI

struct ContentView: View {
    @StateObject private var simulation = FlightSimulation()

    var body: some View {
        ZStack {
            PrototypeSceneView(simulation: simulation)
                .ignoresSafeArea()

            VStack {
                HStack(alignment: .top) {
                    statusPanel
                    Spacer()
                    telemetryPanel
                }
                .padding(.top, 8)
                .safeAreaPadding(.horizontal, 10)

                Spacer()

                HStack(alignment: .bottom) {
                    CollectiveControl(value: simulation.controls.collective) { newValue in
                        var controls = simulation.controls
                        controls.collective = newValue
                        simulation.controls = controls
                    }

                    Spacer()

                    PedalControl(value: simulation.controls.pedals) { newValue in
                        var controls = simulation.controls
                        controls.pedals = newValue
                        simulation.controls = controls
                    }

                    Spacer()

                    CyclicControl(
                        roll: simulation.controls.cyclicRoll,
                        pitch: simulation.controls.cyclicPitch
                    ) { roll, pitch in
                        var controls = simulation.controls
                        controls.cyclicRoll = roll
                        controls.cyclicPitch = pitch
                        simulation.controls = controls
                    }
                }
                .safeAreaPadding(.horizontal, 18)
                .padding(.bottom, 14)
            }
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("FULL AUTHORITY")
                .font(.system(size: 18, weight: .black, design: .rounded))

            Text("FLIGHT FOUNDATION 003 · FA-R01")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)

            Text(backendLabel)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var telemetryPanel: some View {
        let knots = simulation.state.airspeedMetersPerSecond * 1.94384
        let verticalSpeed = simulation.state.verticalSpeedMetersPerSecond

        return HStack(spacing: 13) {
            telemetryItem("ALT", String(format: "%.0f m", simulation.state.altitudeMeters))
            telemetryItem("IAS", String(format: "%.0f kt", knots))
            telemetryItem("V/S", String(format: "%+.1f", verticalSpeed))
            telemetryItem("HDG", String(format: "%03.0f°", simulation.state.headingDegrees))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
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

private struct CollectiveControl: View {
    let value: Float
    let onChange: (Float) -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text("COL")
                .font(.system(size: 9, weight: .bold, design: .monospaced))

            GeometryReader { geometry in
                let height = geometry.size.height
                let travel = max(1, height - 28)
                let knobOffset = (0.5 - CGFloat(value)) * travel

                ZStack {
                    Capsule()
                        .fill(.black.opacity(0.32))
                        .frame(width: 16)

                    Capsule()
                        .fill(.white.opacity(0.18))
                        .frame(width: 4, height: travel)

                    Circle()
                        .fill(.white.opacity(0.92))
                        .frame(width: 28, height: 28)
                        .shadow(radius: 3)
                        .offset(y: knobOffset)
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
            .frame(width: 48, height: 155)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct PedalControl: View {
    let value: Float
    let onChange: (Float) -> Void

    var body: some View {
        VStack(spacing: 5) {
            Text("PEDALS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))

            GeometryReader { geometry in
                let width = geometry.size.width
                let travel = max(1, width - 28)
                let knobOffset = CGFloat(value) * travel * 0.5

                ZStack {
                    Capsule()
                        .fill(.black.opacity(0.32))
                        .frame(height: 16)
                    Rectangle()
                        .fill(.white.opacity(0.25))
                        .frame(width: 1, height: 24)
                    Circle()
                        .fill(.white.opacity(0.92))
                        .frame(width: 28, height: 28)
                        .shadow(radius: 3)
                        .offset(x: knobOffset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let raw = Float((gesture.location.x / max(width, 1)) * 2 - 1)
                            onChange(min(max(raw, -1), 1))
                        }
                        .onEnded { _ in onChange(0) }
                )
            }
            .frame(width: 165, height: 34)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct CyclicControl: View {
    let roll: Float
    let pitch: Float
    let onChange: (Float, Float) -> Void

    var body: some View {
        VStack(spacing: 5) {
            Text("CYCLIC")
                .font(.system(size: 9, weight: .bold, design: .monospaced))

            GeometryReader { geometry in
                let side = min(geometry.size.width, geometry.size.height)
                let radius = max(1, (side - 34) * 0.5)

                ZStack {
                    Circle()
                        .fill(.black.opacity(0.30))
                    Circle()
                        .stroke(.white.opacity(0.20), lineWidth: 1)
                        .padding(side * 0.24)
                    Rectangle()
                        .fill(.white.opacity(0.13))
                        .frame(width: 1)
                    Rectangle()
                        .fill(.white.opacity(0.13))
                        .frame(height: 1)
                    Circle()
                        .fill(.white.opacity(0.92))
                        .frame(width: 34, height: 34)
                        .shadow(radius: 3)
                        .offset(
                            x: CGFloat(roll) * radius,
                            y: -CGFloat(pitch) * radius
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

                            onChange(
                                Float(dx / radius),
                                Float(-dy / radius)
                            )
                        }
                        .onEnded { _ in onChange(0, 0) }
                )
            }
            .frame(width: 132, height: 132)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

#Preview {
    ContentView()
}
