import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            PrototypeSceneView()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 6) {
                Text("FULL AUTHORITY")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                Text("RENDER TEST 001")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
