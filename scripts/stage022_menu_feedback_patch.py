from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}: {old[:100]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


menu = 'App/Stage022MainMenu.swift'

replace_once(
    menu,
    '''    private let takeoffIntervals: [TimeInterval] = [52, 61, 47, 58]\n    private var takeoffIntervalIndex = 0\n    private var nextTakeoffAt: TimeInterval = 22\n''',
    '''    // A first departure happens soon enough to make the menu feel alive.\n    // The longer second gap intentionally leaves the two-minute transonic event clear.\n    private let takeoffIntervals: [TimeInterval] = [50, 75, 54, 62]\n    private var takeoffIntervalIndex = 0\n    private var nextTakeoffAt: TimeInterval = 12\n'''
)

replace_once(
    menu,
    '''    @StateObject private var runtime = Stage022MenuRuntime()\n    @State private var panel: Panel?\n''',
    '''    @StateObject private var runtime = Stage022MenuRuntime()\n    @State private var panel: Panel?\n    @State private var lookYawRadians: Float = 0\n    @State private var lookPitchRadians: Float = 0\n    @State private var lookGestureOrigin = SIMD2<Float>.zero\n    @State private var lookGestureActive = false\n'''
)

replace_once(
    menu,
    '''                    Stage022MenuScene.update(\n                        content: content,\n                        elapsed: elapsed,\n                        takeoffStart: runtime.latestTakeoffStart\n                    )\n''',
    '''                    Stage022MenuScene.update(\n                        content: content,\n                        elapsed: elapsed,\n                        takeoffStart: runtime.latestTakeoffStart,\n                        cameraLookYaw: lookYawRadians,\n                        cameraLookPitch: lookPitchRadians\n                    )\n'''
)

replace_once(
    menu,
    '''            .background(menuSky)\n            .ignoresSafeArea()\n\n            LinearGradient(\n''',
    '''            .background(menuSky)\n            .ignoresSafeArea()\n\n            if panel == nil {\n                menuLookSurface\n            }\n\n            LinearGradient(\n'''
)

replace_once(
    menu,
    '''    private var menuChrome: some View {\n''',
    '''    private var menuLookSurface: some View {\n        GeometryReader { geometry in\n            HStack(spacing: 0) {\n                Spacer(minLength: 0)\n\n                Rectangle()\n                    // Nearly transparent instead of Color.clear so the view remains\n                    // hit-testable without visibly tinting the menu scene.\n                    .fill(Color.black.opacity(0.001))\n                    .frame(width: geometry.size.width * 0.54)\n                    .contentShape(Rectangle())\n                    .gesture(\n                        DragGesture(minimumDistance: 1)\n                            .onChanged { value in\n                                if !lookGestureActive {\n                                    lookGestureActive = true\n                                    lookGestureOrigin = [lookYawRadians, lookPitchRadians]\n                                }\n\n                                let sensitivity: Float = 0.0042\n                                let yaw = lookGestureOrigin.x - Float(value.translation.width) * sensitivity\n                                let pitch = lookGestureOrigin.y + Float(value.translation.height) * sensitivity\n                                lookYawRadians = min(max(yaw, -2.35), 2.35)\n                                lookPitchRadians = min(max(pitch, -0.68), 0.58)\n                            }\n                            .onEnded { _ in\n                                lookGestureActive = false\n                            }\n                    )\n            }\n            .frame(maxWidth: .infinity, maxHeight: .infinity)\n        }\n        .ignoresSafeArea()\n        .zIndex(1)\n    }\n\n    private var menuChrome: some View {\n'''
)

replace_once(
    menu,
    '''                        Text("ATTRACT CAMERA")\n''',
    '''                        Text("DRAG RIGHT SIDE TO LOOK")\n'''
)

replace_once(
    menu,
    '''    static let cameraPosition = SIMD3<Float>(188, 6.6, 1_445)\n    static let cameraTarget = SIMD3<Float>(0, 8.0, 1_850)\n''',
    '''    // Start beside the runway looking toward the departure end so the\n    // takeoff roll is visible before the jet reaches the camera station.\n    static let cameraPosition = SIMD3<Float>(188, 6.6, 720)\n    static let cameraTarget = SIMD3<Float>(0, 7.0, 80)\n'''
)

replace_once(
    menu,
    '''    static func update(\n        content: RealityViewCameraContent,\n        elapsed: TimeInterval,\n        takeoffStart: TimeInterval?\n    ) {\n        if let takeoff = content.entities.first(where: { $0.name == takeoffJetName }) {\n''',
    '''    static func update(\n        content: RealityViewCameraContent,\n        elapsed: TimeInterval,\n        takeoffStart: TimeInterval?,\n        cameraLookYaw: Float,\n        cameraLookPitch: Float\n    ) {\n        if let camera = content.entities.first(where: { $0.name == cameraName }) {\n            updateCamera(camera, yawOffset: cameraLookYaw, pitchOffset: cameraLookPitch)\n        }\n\n        if let takeoff = content.entities.first(where: { $0.name == takeoffJetName }) {\n'''
)

replace_once(
    menu,
    '''    private static func updateTakeoffJet(_ jet: Entity, elapsed: TimeInterval, start: TimeInterval?) {\n''',
    '''    private static func updateCamera(_ camera: Entity, yawOffset: Float, pitchOffset: Float) {\n        let base = simd_normalize(cameraTarget - cameraPosition)\n        let baseYaw = atan2(base.x, base.z)\n        let basePitch = asin(min(max(base.y, -1), 1))\n        let yaw = baseYaw + yawOffset\n        let pitch = min(max(basePitch + pitchOffset, -1.15), 0.82)\n        let cp = cos(pitch)\n        let direction = SIMD3<Float>(sin(yaw) * cp, sin(pitch), cos(yaw) * cp)\n        camera.look(at: cameraPosition + direction * 1_000, from: cameraPosition, relativeTo: nil)\n    }\n\n    private static func updateTakeoffJet(_ jet: Entity, elapsed: TimeInterval, start: TimeInterval?) {\n'''
)

old_takeoff = '''        let t = Float(elapsed - start)\n        guard t >= 0, t <= 14.2 else {\n            jet.isEnabled = false\n            return\n        }\n\n        jet.isEnabled = true\n\n        // Longitudinal acceleration is deliberately obvious from the fixed\n        // runway-side camera while still using plausible fighter takeoff timing.\n        let z = -620 + 34.0 * t * t\n        let liftoff: Float = 8.15\n        let airborne = max(0, t - liftoff)\n        let climb = 1.8 + 2.8 * powf(airborne, 1.72)\n        jet.position = [0, climb, z]\n\n        let pitchDegrees = min(12.0, airborne * 3.4)\n        jet.orientation = simd_quatf(\n            angle: -pitchDegrees * .pi / 180,\n            axis: [1, 0, 0]\n        )\n\n        setGearVisible(jet, visible: t < 10.4)\n        jet.findEntity(named: PrototypeAircraftFactory.afterburnerName)?.isEnabled = t > 4.0\n'''
new_takeoff = '''        let t = Float(elapsed - start)\n        guard t >= 0, t <= 23.0 else {\n            jet.isEnabled = false\n            return\n        }\n\n        jet.isEnabled = true\n\n        // The menu departure is intentionally phase-based instead of using the\n        // old z = a*t^2 shortcut, which made the jet effectively supersonic while\n        // still on the runway and sent it behind the default camera.\n        let startZ: Float = -420\n        let spoolEnd: Float = 2.5\n        let liftoff: Float = 14.0\n        let groundRollDuration = liftoff - spoolEnd\n        let groundAcceleration: Float = 7.5\n        let groundTime = min(max(t - spoolEnd, 0), groundRollDuration)\n        let groundDistance = 0.5 * groundAcceleration * groundTime * groundTime\n        let rotationZ = startZ + 0.5 * groundAcceleration * groundRollDuration * groundRollDuration\n        let rotationSpeed = groundAcceleration * groundRollDuration\n\n        let airborne = max(0, t - liftoff)\n        let z = t <= liftoff\n            ? startZ + groundDistance\n            : rotationZ + rotationSpeed * airborne + 3.8 * airborne * airborne\n        let climb = t <= liftoff ? 1.8 : 1.8 + 3.2 * powf(airborne, 1.50)\n        jet.position = [0, climb, z]\n\n        let pitchDegrees = t < liftoff\n            ? max(0, (t - (liftoff - 1.0)) * 5.0)\n            : min(13.0, 5.0 + airborne * 2.0)\n        jet.orientation = simd_quatf(\n            angle: -pitchDegrees * .pi / 180,\n            axis: [1, 0, 0]\n        )\n\n        setGearVisible(jet, visible: t < 16.4)\n        jet.findEntity(named: PrototypeAircraftFactory.afterburnerName)?.isEnabled = t > 3.2\n'''
replace_once(menu, old_takeoff, new_takeoff)

replace_once(
    menu,
    '''        let eventStart: TimeInterval = 112.0\n''',
    '''        // With the runway-side camera moved downfield, this start time keeps\n        // closest approach centered at essentially the two-minute mark.\n        let eventStart: TimeInterval = 114.1\n'''
)

replace_once(
    menu,
    '''    private func makeTakeoffBuffer() -> AVAudioPCMBuffer {\n        makeBuffer(seconds: 9.5, seed: 0xF160_0220) { t, _, noise in\n            let normalized = min(max(t / 9.5, 0), 1)\n            let rise = min(1, normalized * 2.2)\n            let depart = max(0, 1 - max(0, normalized - 0.72) / 0.28)\n            let envelope = rise * depart\n            let rpm = 52 + 42 * normalized\n            let rumble =\n                0.72 * sin(2 * .pi * rpm * t) +\n                0.34 * sin(2 * .pi * rpm * 1.86 * t + 0.8) +\n                0.16 * sin(2 * .pi * 31 * t)\n            let exhaust = noise * (0.18 + 0.42 * normalized)\n            return envelope * (0.16 * rumble + 0.035 * exhaust)\n        }\n    }\n''',
    '''    private func makeTakeoffBuffer() -> AVAudioPCMBuffer {\n        makeBuffer(seconds: 18.5, seed: 0xF160_0220) { t, _, noise in\n            let spool = min(max(t / 2.8, 0), 1)\n            let roll = min(max((t - 2.5) / 11.5, 0), 1)\n            let departureFade = max(0, 1 - max(0, t - 15.0) / 3.5)\n            let envelope = (0.22 + 0.78 * spool) * departureFade\n            let rpm = 48 + 33 * spool + 24 * roll\n            let rumble =\n                0.72 * sin(2 * .pi * rpm * t) +\n                0.34 * sin(2 * .pi * rpm * 1.86 * t + 0.8) +\n                0.16 * sin(2 * .pi * 31 * t)\n            let exhaust = noise * (0.15 + 0.20 * spool + 0.35 * roll)\n            return envelope * (0.16 * rumble + 0.036 * exhaust)\n        }\n    }\n'''
)

# Flight pause menu -> main menu.
content = 'App/ContentView.swift'
replace_once(
    content,
    '''    @StateObject private var simulation = FlightSimulation()\n''',
    '''    let onEndFlight: () -> Void\n\n    @StateObject private var simulation = FlightSimulation()\n'''
)

replace_once(
    content,
    '''    @State private var hmdEnabled = true\n\n    var body: some View {\n''',
    '''    @State private var hmdEnabled = true\n\n    init(onEndFlight: @escaping () -> Void = {}) {\n        self.onEndFlight = onEndFlight\n    }\n\n    var body: some View {\n'''
)

replace_once(
    content,
    '''                    pauseButton("BRIEFING", systemImage: "rectangle.portrait.and.arrow.right", primary: false, action: returnToBriefing)\n''',
    '''                    pauseButton("END FLIGHT", systemImage: "xmark.circle", primary: false, action: endFlight)\n'''
)

replace_once(
    content,
    '''    private func returnToBriefing() {\n        _ = simulation.resetFlight()\n        withAnimation(.easeOut(duration: 0.20)) {\n            phase = .briefing\n        }\n    }\n''',
    '''    private func endFlight() {\n        simulation.pause()\n        _ = simulation.resetFlight()\n        onEndFlight()\n    }\n'''
)

# Root navigation connects End Flight back to the live menu.
root = 'App/Stage022RootView.swift'
replace_once(
    root,
    '''                case .flight:\n                    ContentView()\n                        .transition(.opacity)\n''',
    '''                case .flight:\n                    ContentView(onEndFlight: endFlight)\n                        .transition(.opacity)\n'''
)

replace_once(
    root,
    '''    private func launchFlight() {\n        withAnimation(.easeInOut(duration: 0.34)) {\n            phase = .flight\n        }\n    }\n''',
    '''    private func launchFlight() {\n        withAnimation(.easeInOut(duration: 0.34)) {\n            phase = .flight\n        }\n    }\n\n    private func endFlight() {\n        withAnimation(.easeInOut(duration: 0.30)) {\n            phase = .menu\n        }\n    }\n'''
)

print('Stage 022 menu feedback patch applied')
