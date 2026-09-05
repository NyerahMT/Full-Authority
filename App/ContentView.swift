import SwiftUI

struct ContentView: View {
    @StateObject private var simulation = FlightSimulation()

    var body: some View {
        ZStack(alignment: .topLeading) {
            PrototypeSceneView(simulation: simulation)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 5) {
                Text("FULL AUTHORITY")
                    .font(.system(size: 18, weight: .black, design: .rounded))

                Text("FLIGHT FOUNDATION 002")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(backendLabel)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding()
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

#Preview {
    ContentView()
}
