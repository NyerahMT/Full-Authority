from __future__ import annotations

import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text()


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text)


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected exactly one match, found {count}: {old[:100]!r}")
    write(path, text.replace(old, new, 1))


def regex_once(path: str, pattern: str, replacement: str) -> None:
    text = read(path)
    result, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f"{path}: expected one regex match, found {count}: {pattern}")
    write(path, result)


# -----------------------------------------------------------------------------
# PrototypeSceneView: physically weighted chase camera, atmospheric sky,
# cinematic finishing overlay, and stronger directional-light hierarchy.
# -----------------------------------------------------------------------------
SCENE = "App/PrototypeSceneView.swift"

replace_once(
    SCENE,
    """    var lastAirspeed: Float?\n    var chasePullbackMeters: Float = 0\n    let effects = Stage2FlightEffects.Runtime()\n""",
    """    var lastAirspeed: Float?\n    var chasePullbackMeters: Float = 0\n    var cameraPosition = SIMD3<Float>.zero\n    var cameraVelocity = SIMD3<Float>.zero\n    var cameraOrientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))\n    let effects = Stage2FlightEffects.Runtime()\n""",
)

replace_once(SCENE, "environmentLightingWeight: 0.48", "environmentLightingWeight: 0.32")
replace_once(SCENE, "environmentLightingWeight: 0.56", "environmentLightingWeight: 0.43")

replace_once(
    SCENE,
    """                        DirectionalLightComponent(\n                            color: UIColor(red: 1.0, green: 0.88, blue: 0.72, alpha: 1),\n                            intensity: 10_400\n                        ),\n""",
    """                        DirectionalLightComponent(\n                            color: UIColor(red: 1.0, green: 0.935, blue: 0.825, alpha: 1),\n                            intensity: 13_200\n                        ),\n""",
)
replace_once(
    SCENE,
    "sun.look(at: .zero, from: [-9_600, 5_600, -3_200], relativeTo: nil)",
    "sun.look(at: .zero, from: [-11_400, 7_900, -4_900], relativeTo: nil)",
)
replace_once(
    SCENE,
    """                    fill.components.set(DirectionalLightComponent(\n                        color: UIColor(red: 0.42, green: 0.58, blue: 0.86, alpha: 1),\n                        intensity: 210\n                    ))\n                    fill.look(at: .zero, from: [6_800, 6_200, 7_600], relativeTo: nil)\n                    content.add(fill)\n""",
    """                    fill.components.set(DirectionalLightComponent(\n                        color: UIColor(red: 0.39, green: 0.55, blue: 0.82, alpha: 1),\n                        intensity: 145\n                    ))\n                    fill.look(at: .zero, from: [7_600, 6_800, 8_900], relativeTo: nil)\n                    content.add(fill)\n\n                    // A restrained cool rim gives the matte jet a clean silhouette\n                    // against bright cloud banks without flattening the fuselage.\n                    let rim = Entity()\n                    rim.name = \"FA.rim\"\n                    rim.components.set(DirectionalLightComponent(\n                        color: UIColor(red: 0.62, green: 0.76, blue: 1.0, alpha: 1),\n                        intensity: 275\n                    ))\n                    rim.look(at: .zero, from: [9_400, 3_900, -10_200], relativeTo: nil)\n                    content.add(rim)\n""",
)

replace_once(
    SCENE,
    """            .background(stage2Sky)\n\n            // The same free-look surface is now available in cockpit. External\n""",
    """            .background(stage2Sky)\n\n            cinematicImageOverlay\n                .allowsHitTesting(false)\n\n            // The same free-look surface is now available in cockpit. External\n""",
)

regex_once(
    SCENE,
    r"    private var stage2Sky: some View \{.*?\n    \}\n\n    private var cameraSelector: some View \{",
    """    private var cinematicImageOverlay: some View {\n        GeometryReader { geometry in\n            let radius = max(geometry.size.width, geometry.size.height)\n            ZStack {\n                // Barely-there edge falloff keeps the eye on the aircraft without\n                // turning the view into a fake camera-filter effect.\n                RadialGradient(\n                    stops: [\n                        .init(color: .clear, location: 0.00),\n                        .init(color: .clear, location: 0.67),\n                        .init(color: .black.opacity(0.085), location: 1.00)\n                    ],\n                    center: .center,\n                    startRadius: radius * 0.12,\n                    endRadius: radius * 0.78\n                )\n\n                // Very soft forward-scatter/glare around the authored sun direction.\n                // It is intentionally subtle: the aircraft and atmosphere create the\n                // drama, not screen-space gimmicks.\n                RadialGradient(\n                    stops: [\n                        .init(color: .white.opacity(0.075), location: 0.00),\n                        .init(color: Color(red: 1.0, green: 0.78, blue: 0.52).opacity(0.030), location: 0.32),\n                        .init(color: .clear, location: 1.00)\n                    ],\n                    center: UnitPoint(x: 0.16, y: 0.27),\n                    startRadius: 1,\n                    endRadius: radius * 0.42\n                )\n            }\n        }\n        .ignoresSafeArea()\n    }\n\n    private var stage2Sky: some View {\n        let altitudeBlend = Double(clamp(simulation.state.altitudeFeetMSL / 42_000, 0, 1))\n        let zenith = Color(\n            red: 0.008 + 0.012 * altitudeBlend,\n            green: 0.050 + 0.030 * altitudeBlend,\n            blue: 0.165 + 0.075 * altitudeBlend\n        )\n        let upperSky = Color(\n            red: 0.020 + 0.010 * altitudeBlend,\n            green: 0.185 + 0.015 * altitudeBlend,\n            blue: 0.430 + 0.035 * altitudeBlend\n        )\n        let lowerSky = Color(\n            red: 0.245 + 0.050 * altitudeBlend,\n            green: 0.455 + 0.020 * altitudeBlend,\n            blue: 0.635 + 0.025 * altitudeBlend\n        )\n        let horizon = Color(\n            red: 0.735 - 0.115 * altitudeBlend,\n            green: 0.665 - 0.080 * altitudeBlend,\n            blue: 0.555 - 0.010 * altitudeBlend\n        )\n\n        return ZStack {\n            // Hillaire/Bruneton-inspired structure: dark Rayleigh-rich zenith,\n            // saturated mid-sky, then a desaturated aerosol-heavy horizon.\n            LinearGradient(\n                stops: [\n                    .init(color: zenith, location: 0.00),\n                    .init(color: upperSky, location: 0.34),\n                    .init(color: lowerSky, location: 0.70),\n                    .init(color: horizon, location: 0.93),\n                    .init(color: Color(red: 0.70, green: 0.62, blue: 0.50), location: 1.00)\n                ],\n                startPoint: .top,\n                endPoint: .bottom\n            )\n\n            // Broad solar aureole: this is atmospheric forward scattering, not bloom.\n            RadialGradient(\n                stops: [\n                    .init(color: Color(red: 1.0, green: 0.965, blue: 0.88).opacity(0.60), location: 0.00),\n                    .init(color: Color(red: 1.0, green: 0.72, blue: 0.43).opacity(0.18), location: 0.20),\n                    .init(color: .clear, location: 1.00)\n                ],\n                center: UnitPoint(x: 0.16, y: 0.27),\n                startRadius: 2,\n                endRadius: 300\n            )\n\n            // Aerial-perspective wash near the horizon makes distant terrain and\n            // cloud banks read in kilometres rather than as a painted backdrop.\n            LinearGradient(\n                stops: [\n                    .init(color: .clear, location: 0.54),\n                    .init(color: Color(red: 0.60, green: 0.68, blue: 0.72).opacity(0.08), location: 0.76),\n                    .init(color: Color(red: 0.78, green: 0.70, blue: 0.59).opacity(0.13), location: 1.00)\n                ],\n                startPoint: .top,\n                endPoint: .bottom\n            )\n        }\n    }\n\n    private var cameraSelector: some View {""",
)

regex_once(
    SCENE,
    r"    @MainActor\n    private func positionCamera\(_ camera: Entity, forceSnap: Bool\) \{.*?\n    \}\n\n    private func lookRotation",
    """    @MainActor\n    private func positionCamera(_ camera: Entity, forceSnap: Bool) {\n        let state = simulation.state\n        let aircraftPosition = state.positionMeters\n        let attitude = state.orientation\n\n        let now = ProcessInfo.processInfo.systemUptime\n        let dt: Float\n        if let last = runtime.lastCameraTime {\n            dt = clamp(Float(now - last), 1.0 / 240.0, 1.0 / 20.0)\n        } else {\n            dt = 1.0 / 60.0\n        }\n        runtime.lastCameraTime = now\n\n        // Acceleration changes framing, but only by metres and a couple degrees.\n        // This is a physical camera rig response, not arcade speed-FOV pumping.\n        let airspeed = state.airspeedMetersPerSecond\n        if let previousAirspeed = runtime.lastAirspeed {\n            let acceleration = max(0, (airspeed - previousAirspeed) / max(dt, 1.0 / 240.0))\n            let accelerationPullback = min(acceleration * 0.060, 1.10)\n            let highSpeedResidual = clamp((airspeed - 260) / 280, 0, 1) * 0.42\n            let targetPullback = accelerationPullback + highSpeedResidual\n            let response: Float = targetPullback > runtime.chasePullbackMeters ? 8.5 : 3.8\n            let blend = 1 - exp(-response * dt)\n            runtime.chasePullbackMeters += (targetPullback - runtime.chasePullbackMeters) * blend\n        } else {\n            runtime.chasePullbackMeters = 0\n        }\n        runtime.lastAirspeed = airspeed\n\n        var localCameraOffset: SIMD3<Float>\n        let localLookPoint: SIMD3<Float>\n        let baseFieldOfView: Float\n        let pullbackScale: Float\n\n        switch cameraMode {\n        case .chase:\n            localCameraOffset = [0, 4.25, -17.80]\n            localLookPoint = [0, 0.72, 4.30]\n            baseFieldOfView = 56.5\n            pullbackScale = 1.0\n\n        case .close:\n            localCameraOffset = [0, 3.10, -11.95]\n            localLookPoint = [0, 0.66, 4.50]\n            baseFieldOfView = 60.0\n            pullbackScale = 0.52\n\n        case .cockpit:\n            localCameraOffset = [0, 1.08, 3.05]\n            localLookPoint = [0, 1.08, 90]\n            baseFieldOfView = 66.0\n            pullbackScale = 0\n        }\n\n        localCameraOffset.z -= runtime.chasePullbackMeters * pullbackScale\n\n        if cameraMode != .cockpit && cameraHasOrbitOffset {\n            let yawOrbit = simd_quatf(angle: orbitYawRadians, axis: [0, 1, 0])\n            let pitchOrbit = simd_quatf(angle: orbitPitchRadians, axis: [1, 0, 0])\n            localCameraOffset = simd_act(yawOrbit * pitchOrbit, localCameraOffset)\n        }\n\n        let speedFov = cameraMode == .cockpit ? 0 : clamp((airspeed - 190) / 310, 0, 1) * 1.45\n        let maneuverFov = cameraMode == .cockpit ? 0 : clamp((abs(state.loadFactorG) - 1.0) / 8.0, 0, 1) * 0.65\n        let fieldOfView = baseFieldOfView + speedFov + maneuverFov\n        camera.components.set(PerspectiveCameraComponent(\n            near: cameraMode == .cockpit ? 0.02 : 0.08,\n            far: 72_000,\n            fieldOfViewInDegrees: fieldOfView\n        ))\n\n        let desiredPosition = aircraftPosition + simd_act(attitude, localCameraOffset)\n        let desiredLookTarget: SIMD3<Float>\n        let cameraUp: SIMD3<Float>\n\n        if cameraMode == .cockpit && cameraHasOrbitOffset {\n            let yaw = simd_quatf(angle: orbitYawRadians, axis: [0, 1, 0])\n            let pitch = simd_quatf(angle: orbitPitchRadians, axis: [1, 0, 0])\n            let headRotation = yaw * pitch\n            let headForwardLocal = simd_act(headRotation, SIMD3<Float>(0, 0, 1))\n            let headUpLocal = simd_act(headRotation, SIMD3<Float>(0, 1, 0))\n\n            desiredLookTarget = desiredPosition + simd_act(attitude, headForwardLocal) * 90\n            cameraUp = simd_act(attitude, headUpLocal)\n        } else if cameraMode == .cockpit {\n            desiredLookTarget = aircraftPosition + simd_act(attitude, localLookPoint)\n            cameraUp = simd_act(attitude, SIMD3<Float>(0, 1, 0))\n        } else {\n            desiredLookTarget = aircraftPosition + simd_act(attitude, localLookPoint)\n\n            // The rig follows most of the aircraft bank, but not all of it. This\n            // tiny amount of inertial horizon stability lets hard rolls read as\n            // violent aircraft motion without faking shake or removing orientation.\n            let aircraftUp = simd_act(attitude, SIMD3<Float>(0, 1, 0))\n            let worldUp = SIMD3<Float>(0, 1, 0)\n            let bankFollow: Float = cameraMode == .close ? 0.84 : 0.72\n            cameraUp = simd_normalize(worldUp * (1 - bankFollow) + aircraftUp * bankFollow)\n        }\n\n        let desiredOrientation = lookRotation(\n            forward: desiredLookTarget - desiredPosition,\n            up: cameraUp\n        )\n\n        let modeChanged = runtime.cameraModeKey != cameraMode.rawValue\n        if forceSnap || modeChanged || !runtime.cameraInitialized || cameraMode == .cockpit {\n            runtime.cameraPosition = desiredPosition\n            runtime.cameraVelocity = .zero\n            runtime.cameraOrientation = desiredOrientation\n        } else {\n            // Critically damped translational spring. Position gets believable mass\n            // while orientation stays tight enough for serious flight-sim control.\n            let frequency: Float = cameraMode == .close ? 8.8 : 6.4\n            let displacement = runtime.cameraPosition - desiredPosition\n            let springAcceleration =\n                -2 * frequency * runtime.cameraVelocity\n                - (frequency * frequency) * displacement\n            runtime.cameraVelocity += springAcceleration * dt\n            runtime.cameraPosition += runtime.cameraVelocity * dt\n\n            let orientationResponse: Float = cameraMode == .close ? 10.5 : 8.0\n            let orientationBlend = 1 - exp(-orientationResponse * dt)\n            runtime.cameraOrientation = simd_slerp(\n                runtime.cameraOrientation,\n                desiredOrientation,\n                orientationBlend\n            )\n        }\n\n        camera.position = runtime.cameraPosition\n        camera.orientation = runtime.cameraOrientation\n        runtime.cameraInitialized = true\n        runtime.cameraModeKey = cameraMode.rawValue\n    }\n\n    private func lookRotation""",
)

# More energetic but still physically proportioned afterburner presentation.
replace_once(SCENE, "let length = (0.82 + 0.58 * intensity) * pressureExpansion * speedCompression", "let length = (0.95 + 0.82 * intensity) * pressureExpansion * speedCompression")
replace_once(SCENE, "halo.scale = [1.15 * width, 2.15 * length, 1.15 * width]", "halo.scale = [1.26 * width, 2.55 * length, 1.26 * width]")
replace_once(SCENE, "outer.scale = [0.94 * width, 1.90 * length, 1.02 * width]", "outer.scale = [0.98 * width, 2.28 * length, 1.05 * width]")
replace_once(SCENE, "inner.scale = [0.58 * width * pulse, 1.52 * length, 0.66 * width * pulse]", "inner.scale = [0.60 * width * pulse, 1.78 * length, 0.68 * width * pulse]")
replace_once(SCENE, "core.scale = [0.24 * width * pulse, 1.12 * length, 0.30 * width * pulse]", "core.scale = [0.23 * width * pulse, 1.24 * length, 0.29 * width * pulse]")


# -----------------------------------------------------------------------------
# Stage2WorldFactory: denser cloud volumes, longer terrain horizon, less obvious
# material repetition, and a more grounded natural palette.
# -----------------------------------------------------------------------------
WORLD = "App/Stage2WorldFactory.swift"

regex_once(
    WORLD,
    r"    private static func addCloudscape\(to root: Entity\) \{.*?\n    \}\n\n    private static func loadCloudTexture",
    """    private static func addCloudscape(to root: Entity) {\n        let names = [\"cloud_alpha_03\", \"cloud_alpha_05\", \"cloud_alpha_08\"]\n        let textures = names.compactMap(loadCloudTexture)\n        guard !textures.isEmpty else { return }\n\n        let cloudRoot = Entity()\n        cloudRoot.name = \"FA.world.cloudscape\"\n\n        // Stage 018 turns each old single billboard into a small crossed-card cloud\n        // volume. It keeps the CC0 art/mobile cost while adding real parallax, bright\n        // tops and darker undersides in the spirit of Schneider/Nubis cloud lighting.\n        for index in 0..<18 {\n            let angle = Float(index) * 2.3999632 + 0.31\n            let radius = Float(3_900 + (index * 1_777) % 13_800)\n            let x = cos(angle) * radius\n            let z = 2_000 + sin(angle) * radius\n            let altitude = Float(2_150 + (index * 337) % 2_050)\n            let width = Float(2_700 + (index * 701) % 4_400)\n            let depth = Float(1_700 + (index * 431) % 3_100)\n            let height = Float(760 + (index * 233) % 1_150)\n\n            let underside = cloudCard(\n                texture: textures[index % textures.count],\n                size: [width, depth],\n                tint: UIColor(red: 0.61, green: 0.66, blue: 0.71, alpha: 0.50)\n            )\n            underside.position = [x, altitude - height * 0.18, z]\n            underside.orientation = simd_quatf(\n                angle: Float(index) * 0.43,\n                axis: SIMD3<Float>(0, 1, 0)\n            )\n            cloudRoot.addChild(underside)\n\n            let top = cloudCard(\n                texture: textures[(index + 1) % textures.count],\n                size: [width * 0.86, depth * 0.80],\n                tint: UIColor(red: 0.985, green: 0.975, blue: 0.94, alpha: 0.46)\n            )\n            top.position = [x + 90, altitude + height * 0.34, z - 75]\n            top.orientation = simd_quatf(\n                angle: Float(index) * 0.43 + 0.28,\n                axis: SIMD3<Float>(0, 1, 0)\n            )\n            cloudRoot.addChild(top)\n\n            for slice in 0..<3 {\n                let face = cloudCard(\n                    texture: textures[(index + slice + 2) % textures.count],\n                    size: [width * (0.78 - Float(slice) * 0.08), height * (1.10 - Float(slice) * 0.08)],\n                    tint: UIColor(\n                        red: 0.86 + CGFloat(slice) * 0.035,\n                        green: 0.875 + CGFloat(slice) * 0.030,\n                        blue: 0.88 + CGFloat(slice) * 0.025,\n                        alpha: 0.30\n                    )\n                )\n                face.position = [\n                    x + Float(slice - 1) * 115,\n                    altitude + Float(slice) * height * 0.08,\n                    z + Float(1 - slice) * 90\n                ]\n                let upright = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))\n                let yaw = simd_quatf(\n                    angle: angle + Float(slice) * Float.pi / 3,\n                    axis: SIMD3<Float>(0, 1, 0)\n                )\n                face.orientation = yaw * upright\n                cloudRoot.addChild(face)\n            }\n        }\n\n        // Towering banks around the horizon create a huge sense of world scale and\n        // break the hard terrain/sky seam. These remain well outside the airbase.\n        for index in 0..<14 {\n            let angle = Float(index) / 14 * 2 * Float.pi + 0.17\n            let radius = Float(18_500 + (index * 1_081) % 6_400)\n            let x = cos(angle) * radius\n            let z = 2_000 + sin(angle) * radius\n            let width = Float(5_400 + (index * 827) % 4_600)\n            let height = Float(2_600 + (index * 503) % 2_800)\n            let centerY = Float(2_350 + (index * 241) % 1_800)\n\n            let bank = cloudCard(\n                texture: textures[(index + 2) % textures.count],\n                size: [width, height],\n                tint: UIColor(red: 0.84, green: 0.86, blue: 0.87, alpha: 0.43)\n            )\n            bank.position = [x, centerY, z]\n            let upright = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))\n            let facing = simd_quatf(angle: -angle + .pi / 2, axis: SIMD3<Float>(0, 1, 0))\n            bank.orientation = facing * upright\n            cloudRoot.addChild(bank)\n        }\n\n        // Very high, broad wisps stop the upper sky from feeling empty while staying\n        // faint enough to preserve the clean military-aviation art direction.\n        for index in 0..<8 {\n            let angle = Float(index) * 0.91 + 0.4\n            let radius = Float(6_000 + index * 1_450)\n            let wisp = cloudCard(\n                texture: textures[(index + 1) % textures.count],\n                size: [6_500 + Float(index % 3) * 1_300, 2_000 + Float(index % 4) * 650],\n                tint: UIColor(red: 0.97, green: 0.98, blue: 1.0, alpha: 0.12)\n            )\n            wisp.position = [cos(angle) * radius, 6_200 + Float(index % 3) * 800, 2_000 + sin(angle) * radius]\n            wisp.orientation = simd_quatf(angle: angle * 0.7, axis: SIMD3<Float>(0, 1, 0))\n            cloudRoot.addChild(wisp)\n        }\n\n        root.addChild(cloudRoot)\n    }\n\n    private static func loadCloudTexture""",
)

replace_once(WORLD, "let tileSize: Float = 6_000", "let tileSize: Float = 7_200")
replace_once(WORLD, "for tileX in -4..<4 {\n            for tileZ in -4..<4 {", "for tileX in -4..<4 {\n            for tileZ in -4..<4 {")
replace_once(WORLD, "let textureScaleMeters: Float = 24", "let textureScaleMeters: Float = 42")
replace_once(
    WORLD,
    """        let tints: [UIColor] = [\n            UIColor(red: 0.72, green: 0.78, blue: 0.58, alpha: 1),\n            UIColor(red: 0.82, green: 0.78, blue: 0.54, alpha: 1),\n            UIColor(red: 0.64, green: 0.73, blue: 0.51, alpha: 1),\n            UIColor(red: 0.82, green: 0.69, blue: 0.47, alpha: 1),\n            UIColor(red: 0.68, green: 0.68, blue: 0.47, alpha: 1),\n            UIColor(red: 0.76, green: 0.79, blue: 0.57, alpha: 1)\n        ]\n""",
    """        let tints: [UIColor] = [\n            UIColor(red: 0.54, green: 0.61, blue: 0.39, alpha: 1),\n            UIColor(red: 0.64, green: 0.61, blue: 0.38, alpha: 1),\n            UIColor(red: 0.47, green: 0.57, blue: 0.34, alpha: 1),\n            UIColor(red: 0.68, green: 0.55, blue: 0.34, alpha: 1),\n            UIColor(red: 0.52, green: 0.52, blue: 0.35, alpha: 1),\n            UIColor(red: 0.59, green: 0.64, blue: 0.40, alpha: 1)\n        ]\n""",
)


# -----------------------------------------------------------------------------
# Flight effects: longer, thinner maneuver vapor; broader/softer old contrails;
# tighter transonic condensation window.
# -----------------------------------------------------------------------------
FX = "App/Stage2FlightEffects.swift"

replace_once(FX, "baseRadius: 0.54,\n            radialGrowthPerSecond: 0.068,\n            driftScale: 0.84,\n            opacity: 0.16", "baseRadius: 0.62,\n            radialGrowthPerSecond: 0.086,\n            driftScale: 0.88,\n            opacity: 0.14")
replace_once(FX, "baseRadius: 0.36,\n            radialGrowthPerSecond: 0.052,\n            driftScale: 0.80,\n            opacity: 0.10", "baseRadius: 0.40,\n            radialGrowthPerSecond: 0.064,\n            driftScale: 0.83,\n            opacity: 0.085")
replace_once(FX, "baseRadius: 0.17,\n            radialGrowthPerSecond: 0.020,\n            driftScale: 0.24,\n            opacity: 0.22", "baseRadius: 0.145,\n            radialGrowthPerSecond: 0.017,\n            driftScale: 0.26,\n            opacity: 0.20")

replace_once(
    FX,
    """            entity.scale = [\n                (0.13 + 0.09 * i) * shimmer,\n                (0.13 + 0.07 * i) * shimmer,\n                4.6 + 4.8 * i\n            ]\n""",
    """            entity.scale = [\n                (0.105 + 0.075 * i) * shimmer,\n                (0.105 + 0.055 * i) * shimmer,\n                7.2 + 9.8 * i\n            ]\n""",
)
replace_once(
    FX,
    """            entity.scale = [\n                (0.42 + 0.32 * i) * shimmer,\n                (0.095 + 0.055 * i) * shimmer,\n                2.5 + 3.6 * i\n            ]\n""",
    """            entity.scale = [\n                (0.34 + 0.30 * i) * shimmer,\n                (0.070 + 0.045 * i) * shimmer,\n                4.0 + 6.4 * i\n            ]\n""",
)
replace_once(
    FX,
    """            entity.scale = [\n                (0.34 + 0.28 * i) * shimmer,\n                (0.13 + 0.09 * i) * shimmer,\n                2.8 + 4.0 * i\n            ]\n""",
    """            entity.scale = [\n                (0.30 + 0.27 * i) * shimmer,\n                (0.105 + 0.075 * i) * shimmer,\n                4.2 + 6.8 * i\n            ]\n""",
)
replace_once(FX, "opacity: (isTip ? 0.055 : 0.075) + (isTip ? 0.15 : 0.24) * i", "opacity: (isTip ? 0.040 : 0.060) + (isTip ? 0.13 : 0.21) * i")
replace_once(FX, "let machPeak = exp(-pow((mach - 0.995) / 0.060, 2))", "let machPeak = exp(-pow((mach - 0.995) / 0.042, 2))")
replace_once(FX, "let visible = mach > 0.90\n            && mach < 1.115", "let visible = mach > 0.925\n            && mach < 1.080")


# -----------------------------------------------------------------------------
# Aircraft: more disciplined polyurethane paint response and a blue-white/hot
# amber afterburner hierarchy instead of a flat orange cone.
# -----------------------------------------------------------------------------
AIRCRAFT = "Aircraft/PrototypeAircraftFactory.swift"

regex_once(
    AIRCRAFT,
    r"        return \[\n            material\(UIColor\(red: 0\.300.*?\n        \]\n    \}",
    """        return [\n            material(UIColor(red: 0.275, green: 0.296, blue: 0.306, alpha: 1), roughness: 0.78, metallic: 0.000, specular: 0.16, clearcoat: 0.006, clearcoatRoughness: 0.82),\n            material(UIColor(red: 0.430, green: 0.448, blue: 0.452, alpha: 1), roughness: 0.80, metallic: 0.000, specular: 0.15, clearcoat: 0.004, clearcoatRoughness: 0.84),\n            material(UIColor(red: 0.125, green: 0.132, blue: 0.136, alpha: 1), roughness: 0.86, metallic: 0.000, specular: 0.12, clearcoat: 0.000, clearcoatRoughness: 0.92),\n            material(UIColor(red: 0.018, green: 0.045, blue: 0.064, alpha: 1), roughness: 0.070, metallic: 0.04, specular: 1.00, clearcoat: 1.00, clearcoatRoughness: 0.025),\n            material(UIColor(red: 0.095, green: 0.083, blue: 0.070, alpha: 1), roughness: 0.30, metallic: 0.96, specular: 0.72, clearcoat: 0.015, clearcoatRoughness: 0.38),\n            material(UIColor(red: 0.288, green: 0.308, blue: 0.315, alpha: 1), roughness: 0.79, metallic: 0.000, specular: 0.15, clearcoat: 0.004, clearcoatRoughness: 0.84),\n            material(UIColor(red: 0.220, green: 0.240, blue: 0.248, alpha: 1), roughness: 0.77, metallic: 0.000, specular: 0.16, clearcoat: 0.005, clearcoatRoughness: 0.82),\n            material(UIColor(red: 0.242, green: 0.261, blue: 0.268, alpha: 1), roughness: 0.76, metallic: 0.000, specular: 0.17, clearcoat: 0.006, clearcoatRoughness: 0.80)\n        ]\n    }""",
)

replace_once(
    AIRCRAFT,
    """                red: 0.82,\n                green: 0.10,\n                blue: 0.025,\n                alpha: 0.15\n""",
    """                red: 0.22,\n                green: 0.32,\n                blue: 0.92,\n                alpha: 0.13\n""",
)
replace_once(
    AIRCRAFT,
    """                red: 1.0,\n                green: 0.24,\n                blue: 0.035,\n                alpha: 0.34\n""",
    """                red: 0.34,\n                green: 0.58,\n                blue: 1.0,\n                alpha: 0.32\n""",
)
replace_once(
    AIRCRAFT,
    """                red: 1.0,\n                green: 0.52,\n                blue: 0.075,\n                alpha: 0.56\n""",
    """                red: 0.62,\n                green: 0.80,\n                blue: 1.0,\n                alpha: 0.56\n""",
)
replace_once(
    AIRCRAFT,
    """                red: 1.0,\n                green: 0.88,\n                blue: 0.48,\n                alpha: 0.86\n""",
    """                red: 0.94,\n                green: 0.975,\n                blue: 1.0,\n                alpha: 0.90\n""",
)
replace_once(
    AIRCRAFT,
    """                    red: 1.0,\n                    green: 0.66,\n                    blue: 0.20,\n""",
    """                    red: 1.0,\n                    green: 0.72,\n                    blue: 0.28,\n""",
)


# -----------------------------------------------------------------------------
# Source ledger: keep the visual overhaul traceable to public research/reference
# implementations instead of pretending the rendering ideas were invented here.
# -----------------------------------------------------------------------------
DOCS = "Docs/VisualSources.md"
docs = read(DOCS)
append = """

## Stage 018 visual-generation overhaul

Stage 018 is the first cohesive art-direction pass rather than another isolated effect tweak. It keeps the iOS 18 / RealityKit baseline and applies ideas from production atmosphere/cloud literature through mobile-friendly scene construction, while leaving a future Metal renderer path open.

References:

- Sébastien Hillaire, *A Scalable and Production Ready Sky and Atmosphere Rendering Technique* (2020): https://onlinelibrary.wiley.com/doi/10.1111/cgf.14050
- Eric Bruneton & Fabrice Neyret, *Precomputed Atmospheric Scattering*: https://github.com/ebruneton/precomputed_atmospheric_scattering
- Andrew Schneider / Guerrilla Games, *The Real-time Volumetric Cloudscapes of Horizon Zero Dawn*: https://www.guerrilla-games.com/read/the-real-time-volumetric-cloudscapes-of-horizon-zero-dawn
- Apple RealityKit postprocessing documentation (future GPU finishing path): https://developer.apple.com/documentation/realitykit/postprocessing-effects

The Stage 018 cloud pass still uses the existing CC0 WickedInsignia cloud alpha art, but clusters multiple crossed layers with separate top/underside values to produce parallax and pseudo-volume instead of single cards. The chase camera uses a critically damped spring and partial horizon inertia rather than screen shake, large FOV pumping, speed lines, or other arcade-camera devices.
"""
if "## Stage 018 visual-generation overhaul" not in docs:
    write(DOCS, docs.rstrip() + append + "\n")

print("Stage 018 visual-generation overhaul patched successfully")
