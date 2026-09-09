import SwiftUI

struct Stage022RootView: View {
    private enum AppPhase {
        case menu
        case flight
    }

    @State private var phase: AppPhase = .menu
    @State private var menuSceneReady = false
    @State private var showSplash = true

    var body: some View {
        ZStack {
            Group {
                switch phase {
                case .menu:
                    Stage022MainMenuView(
                        onSceneReady: { menuSceneReady = true },
                        onFly: launchFlight
                    )
                    .transition(.opacity)
                case .flight:
                    ContentView()
                        .transition(.opacity)
                }
            }

            if showSplash {
                Stage022NyerahWorksSplash()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .task {
            let minimumSplashSeconds: TimeInterval = 1.35
            let start = Date()

            while !menuSceneReady {
                try? await Task.sleep(nanoseconds: 50_000_000)
                if Task.isCancelled { return }
            }

            let remaining = minimumSplashSeconds - Date().timeIntervalSince(start)
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }

            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.36)) {
                showSplash = false
            }
        }
    }

    private func launchFlight() {
        withAnimation(.easeInOut(duration: 0.34)) {
            phase = .flight
        }
    }
}

private struct Stage022NyerahWorksSplash: View {
    @State private var reveal = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 15) {
                ZStack {
                    RoundedRectangle(cornerRadius: 17)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                        .frame(width: 78, height: 78)

                    Text("N")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .tracking(-3)
                        .foregroundStyle(.white)
                        .offset(x: -1)
                }

                VStack(spacing: 4) {
                    Text("NYERAHWORKS")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .tracking(2.7)

                    Text("PRESENTS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(3.2)
                        .foregroundStyle(.white.opacity(0.44))
                }

                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.55))
                    .padding(.top, 14)
            }
            .opacity(reveal ? 1 : 0)
            .scaleEffect(reveal ? 1 : 0.985)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.42)) {
                reveal = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("NyerahWorks presents Full Authority")
    }
}
