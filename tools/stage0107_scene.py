from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected 1 match for {old[:100]!r}, got {count}")
    p.write_text(text.replace(old, new, 1))


def replace_between(path, start, end, new):
    p = Path(path)
    text = p.read_text()
    i = text.find(start)
    if i < 0:
        raise SystemExit(f"{path}: missing start marker {start!r}")
    j = text.find(end, i)
    if j < 0:
        raise SystemExit(f"{path}: missing end marker {end!r}")
    p.write_text(text[:i] + new.rstrip() + "\n\n" + text[j:])

scene = "App/PrototypeSceneView.swift"
replace_once(
    scene,
    "    @StateObject private var runtime = Stage2SceneRuntime()\n",
    "    @StateObject private var runtime = Stage2SceneRuntime()\n"
    "    @State private var orbitYawRadians: Float = 0\n"
    "    @State private var orbitPitchRadians: Float = 0\n"
    "    @State private var orbitGestureOrigin = SIMD2<Float>.zero\n"
    "    @State private var orbitGestureActive = false\n"
)

replace_once(
    scene,
    "            .background(stage2Sky)\n\n            if !simulation.isPaused {\n                cameraSelector\n            }",
    "            .background(stage2Sky)\n\n"
    "            if !simulation.isPaused && cameraMode != .cockpit {\n                orbitGestureSurface\n            }\n\n"
    "            if !simulation.isPaused {\n                cameraSelector\n            }"
)

replace_between(
    scene,
    "    private var cameraSelector: some View {",
    "    @ViewBuilder\n    private var flightConditionOverlay",
    r'''    private var cameraSelector: some View {
        VStack {
            HStack(spacing: 8) {
                Spacer()

                if cameraHasOrbitOffset && cameraMode != .cockpit {
                    Button {
                        orbitYawRadians = 0
                        orbitPitchRadians = 0
                        orbitGestureActive = false
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "scope")
                                .font(.system(size: 9, weight: .bold))
                            Text("RECENTER")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .tracking(0.45)
                        }
                        .foregroundStyle(.white.opacity(0.90))
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    cameraMode = cameraMode.next
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: cameraMode == .cockpit ? "viewfinder" : "camera.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text(cameraMode.rawValue)
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .tracking(0.45)
                    }
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.09), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .safeAreaPadding(.trailing, 18)
            .padding(.top, 50)
            Spacer()
        }
    }

    private var cameraHasOrbitOffset: Bool {
        abs(orbitYawRadians) > 0.008 || abs(orbitPitchRadians) > 0.008
    }

    private var orbitGestureSurface: some View {
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .frame(width: geometry.size.width * 0.56, height: geometry.size.height * 0.50)
                .position(x: geometry.size.width * 0.50, y: geometry.size.height * 0.48)
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            if !orbitGestureActive {
                                orbitGestureOrigin = SIMD2<Float>(orbitYawRadians, orbitPitchRadians)
                                orbitGestureActive = true
                            }
                            let sensitivity: Float = 0.0045
                            orbitYawRadians = wrappedAngle(
                                orbitGestureOrigin.x - Float(value.translation.width) * sensitivity
                            )
                            orbitPitchRadians = clamp(
                                orbitGestureOrigin.y + Float(value.translation.height) * sensitivity,
                                -0.72,
                                0.62
                            )
                        }
                        .onEnded { _ in orbitGestureActive = false }
                )
        }
        .allowsHitTesting(true)
    }

    private func wrappedAngle(_ value: Float) -> Float {
        var angle = value.truncatingRemainder(dividingBy: 2 * Float.pi)
        if angle > Float.pi { angle -= 2 * Float.pi }
        if angle < -Float.pi { angle += 2 * Float.pi }
        return angle
    }'''
)

replace_once(
    scene,
    "                        runtime.cameraInitialized = false\n                        runtime.cameraModeKey = \"\"\n",
    "                        runtime.cameraInitialized = false\n"
    "                        runtime.cameraModeKey = \"\"\n"
    "                        orbitYawRadians = 0\n"
    "                        orbitPitchRadians = 0\n"
)

replace_once(
    scene,
    "        localCameraOffset.z -= runtime.chasePullbackMeters * pullbackScale\n\n        camera.components.set(PerspectiveCameraComponent(",
    "        localCameraOffset.z -= runtime.chasePullbackMeters * pullbackScale\n\n"
    "        if cameraMode != .cockpit && cameraHasOrbitOffset {\n"
    "            let yawOrbit = simd_quatf(angle: orbitYawRadians, axis: [0, 1, 0])\n"
    "            let pitchOrbit = simd_quatf(angle: orbitPitchRadians, axis: [1, 0, 0])\n"
    "            localCameraOffset = simd_act(yawOrbit * pitchOrbit, localCameraOffset)\n"
    "        }\n\n"
    "        camera.components.set(PerspectiveCameraComponent("
)

replace_once(scene, "            left.orientation = simd_quatf(angle: state.leftAileronRadians, axis: [1, 0, 0])", "            left.orientation = simd_quatf(angle: state.leftAileronRadians, axis: PrototypeAircraftFactory.leftAileronVisualAxis)")
replace_once(scene, "            right.orientation = simd_quatf(angle: state.rightAileronRadians, axis: [1, 0, 0])", "            right.orientation = simd_quatf(angle: state.rightAileronRadians, axis: PrototypeAircraftFactory.rightAileronVisualAxis)")
replace_once(scene, "            left.orientation = simd_quatf(angle: -state.leftStabilatorRadians, axis: [1, 0, 0])", "            left.orientation = simd_quatf(angle: -state.leftStabilatorRadians, axis: PrototypeAircraftFactory.leftStabilatorVisualAxis)")
replace_once(scene, "            right.orientation = simd_quatf(angle: state.rightStabilatorRadians, axis: [1, 0, 0])", "            right.orientation = simd_quatf(angle: state.rightStabilatorRadians, axis: PrototypeAircraftFactory.rightStabilatorVisualAxis)")
replace_once(scene, "            rudder.orientation = simd_quatf(angle: -state.rudderRadians, axis: [0, 1, 0])", "            rudder.orientation = simd_quatf(angle: -state.rudderRadians, axis: PrototypeAircraftFactory.rudderVisualAxis)")
