from pathlib import Path

ROOT = Path('.')

factory = r'''import Foundation
import RealityKit
import UIKit
import simd

@MainActor
enum PrototypeAircraftFactory {
    static let aircraftName = "FA.aircraft"
    static let visualRootName = "FA.aircraft.visual-root"
    static let meshName = "FA.aircraft.f16.mesh"
    static let afterburnerName = "FA.aircraft.afterburner"
    static let afterburnerInnerName = "FA.aircraft.afterburner.inner"
    static let afterburnerOuterName = "FA.aircraft.afterburner.outer"
    static let nozzleName = "FA.aircraft.nozzle"
    static let nozzleGlowName = "FA.aircraft.nozzle.glow"
    static let speedbrakeName = "FA.aircraft.speedbrake"
    static let speedbrakeLeftUpperName = "FA.aircraft.speedbrake.left.upper"
    static let speedbrakeLeftLowerName = "FA.aircraft.speedbrake.left.lower"
    static let speedbrakeRightUpperName = "FA.aircraft.speedbrake.right.upper"
    static let speedbrakeRightLowerName = "FA.aircraft.speedbrake.right.lower"
    static let leftAileronName = "FA.aircraft.aileron.left"
    static let rightAileronName = "FA.aircraft.aileron.right"
    static let leftElevatorName = "FA.aircraft.elevator.left"
    static let rightElevatorName = "FA.aircraft.elevator.right"
    static let rudderName = "FA.aircraft.rudder"
    static let noseGearName = "FA.aircraft.gear.nose"
    static let leftGearName = "FA.aircraft.gear.left"
    static let rightGearName = "FA.aircraft.gear.right"
    static let vaporLeftName = "FA.aircraft.vapor.left"
    static let vaporRightName = "FA.aircraft.vapor.right"
    static let contrailLeftName = "FA.aircraft.contrail.left"
    static let contrailRightName = "FA.aircraft.contrail.right"

    // vazgriz/FlightSim_F16 source FBX is already essentially full scale.
    // Unlike the retired R4 OBJ, it has a sensible authored origin and exact
    // skinned control-surface pivots, so no visual CG fudge offset is required.
    static let visualVerticalOffset: Float = 0

    // These axes come from the source FBX's actual neutral -> deflected animation
    // transforms, not bone display vectors and not inferred geometry.
    static let leftAileronVisualAxis = simd_normalize(SIMD3<Float>(0.991671, 0.0, 0.128796))
    static let rightAileronVisualAxis = simd_normalize(SIMD3<Float>(0.991671, 0.0, -0.128796))
    static let leftStabilatorVisualAxis = SIMD3<Float>(1, 0, 0)
    static let rightStabilatorVisualAxis = SIMD3<Float>(1, 0, 0)
    static let rudderVisualAxis = simd_normalize(SIMD3<Float>(-0.002254, 0.842883, -0.538092))
    static let speedbrakeUpperVisualAxis = SIMD3<Float>(-1, 0, 0)
    static let speedbrakeLowerVisualAxis = SIMD3<Float>(1, 0, 0)

    static let authoredAileronLimitRadians: Float = 0.37524614
    static let authoredStabilatorLimitRadians: Float = 0.43633232
    static let authoredRudderLimitRadians: Float = 0.52360028
    static let authoredSpeedbrakeLimitRadians: Float = 0.78539801

    private enum AssetError: Error {
        case missing(String)
        case invalid(String)
    }

    private struct ParsedVertex {
        let position: SIMD3<Float>
        let normal: SIMD3<Float>
    }

    static func make() -> Entity {
        let aircraft = Entity()
        aircraft.name = aircraftName

        do {
            let visualRoot = Entity()
            visualRoot.name = visualRootName
            visualRoot.position = [0, visualVerticalOffset, 0]
            aircraft.addChild(visualRoot)

            let airframeMaterial = SimpleMaterial(
                color: UIColor(red: 0.47, green: 0.49, blue: 0.50, alpha: 1),
                roughness: 0.63,
                isMetallic: false
            )
            let controlMaterial = SimpleMaterial(
                color: UIColor(red: 0.455, green: 0.475, blue: 0.485, alpha: 1),
                roughness: 0.66,
                isMetallic: false
            )

            let body = ModelEntity(mesh: try loadAuthoredOBJ("f16_static"), materials: [airframeMaterial])
            body.name = meshName
            visualRoot.addChild(body)

            try addMovingPart(
                to: visualRoot,
                name: leftAileronName,
                file: "left_flaperon",
                pivot: [-2.437150, 0.0, -2.113479],
                material: controlMaterial
            )
            try addMovingPart(
                to: visualRoot,
                name: rightAileronName,
                file: "right_flaperon",
                pivot: [2.437146, 0.0, -2.113479],
                material: controlMaterial
            )
            try addMovingPart(
                to: visualRoot,
                name: leftElevatorName,
                file: "left_stabilator",
                pivot: [-1.103110, 0.0, -5.102210],
                material: controlMaterial
            )
            try addMovingPart(
                to: visualRoot,
                name: rightElevatorName,
                file: "right_stabilator",
                pivot: [1.103107, 0.0, -5.102214],
                material: controlMaterial
            )
            try addMovingPart(
                to: visualRoot,
                name: rudderName,
                file: "rudder",
                pivot: [0.0, 2.250000, -5.737493],
                material: controlMaterial
            )

            try addMovingPart(
                to: visualRoot,
                name: speedbrakeLeftUpperName,
                file: "airbrake_left_upper",
                pivot: [-0.926553, 0.0, -5.227214],
                material: controlMaterial
            )
            try addMovingPart(
                to: visualRoot,
                name: speedbrakeLeftLowerName,
                file: "airbrake_left_lower",
                pivot: [-0.926553, 0.0, -5.227214],
                material: controlMaterial
            )
            try addMovingPart(
                to: visualRoot,
                name: speedbrakeRightUpperName,
                file: "airbrake_right_upper",
                pivot: [0.926553, 0.0, -5.227214],
                material: controlMaterial
            )
            try addMovingPart(
                to: visualRoot,
                name: speedbrakeRightLowerName,
                file: "airbrake_right_lower",
                pivot: [0.926553, 0.0, -5.227214],
                material: controlMaterial
            )

            addNozzle(to: visualRoot)
            try addAfterburner(to: visualRoot)
            addLandingGear(to: aircraft)
        } catch {
            let fallback = ModelEntity(
                mesh: .generateBox(size: [4, 1, 10], cornerRadius: 0.2),
                materials: [SimpleMaterial(color: .red, isMetallic: false)]
            )
            fallback.name = "FA.aircraft.authored-f16-load-failed"
            aircraft.addChild(fallback)
        }

        return aircraft
    }

    private static func addMovingPart(
        to root: Entity,
        name: String,
        file: String,
        pivot: SIMD3<Float>,
        material: SimpleMaterial
    ) throws {
        let hinge = Entity()
        hinge.name = name
        hinge.position = pivot
        let model = ModelEntity(mesh: try loadAuthoredOBJ(file), materials: [material])
        model.name = "\(name).mesh"
        hinge.addChild(model)
        root.addChild(hinge)
    }

    private static func addNozzle(to root: Entity) {
        let nozzle = ModelEntity(
            mesh: .generateCylinder(height: 0.34, radius: 0.47),
            materials: [SimpleMaterial(
                color: UIColor(red: 0.12, green: 0.125, blue: 0.13, alpha: 1),
                roughness: 0.31,
                isMetallic: true
            )]
        )
        nozzle.name = nozzleName
        nozzle.position = [0, -0.16, -6.90]
        nozzle.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        root.addChild(nozzle)

        let glow = ModelEntity(
            mesh: .generateSphere(radius: 0.34),
            materials: [SimpleMaterial(
                color: UIColor(red: 0.34, green: 0.53, blue: 0.78, alpha: 0.20),
                isMetallic: false
            )]
        )
        glow.name = nozzleGlowName
        glow.position = [0, -0.16, -7.10]
        glow.scale = [1, 1, 0.24]
        glow.isEnabled = false
        root.addChild(glow)
    }

    private static func addAfterburner(to root: Entity) throws {
        let plumeMesh = try loadAuthoredOBJ("afterburner_plume")
        let plume = Entity()
        plume.name = afterburnerName
        plume.position = [0, -0.16, -7.03]
        plume.isEnabled = false

        let outer = ModelEntity(
            mesh: plumeMesh,
            materials: [SimpleMaterial(
                color: UIColor(red: 0.16, green: 0.40, blue: 1.0, alpha: 0.26),
                isMetallic: false
            )]
        )
        outer.name = afterburnerOuterName
        plume.addChild(outer)

        let inner = ModelEntity(
            mesh: plumeMesh,
            materials: [SimpleMaterial(
                color: UIColor(red: 0.73, green: 0.88, blue: 1.0, alpha: 0.43),
                isMetallic: false
            )]
        )
        inner.name = afterburnerInnerName
        inner.scale = [0.55, 0.55, 0.72]
        plume.addChild(inner)

        // Supersonic exhaust shock cells are represented as a short series of
        // faint hot cores inside the authored plume envelope. They are visual
        // exhaust structure only and never feed forces back into JSBSim.
        for index in 0..<4 {
            let diamond = ModelEntity(
                mesh: .generateSphere(radius: 0.24),
                materials: [SimpleMaterial(
                    color: UIColor(red: 0.78, green: 0.88, blue: 1.0, alpha: 0.22),
                    isMetallic: false
                )]
            )
            diamond.name = "FA.aircraft.afterburner.diamond.\(index)"
            diamond.position = [0, 0, -0.72 - Float(index) * 0.82]
            diamond.scale = [1.15 - Float(index) * 0.10, 0.74, 1.55]
            plume.addChild(diamond)
        }

        root.addChild(plume)
    }

    private static func addLandingGear(to root: Entity) {
        let strutColor = UIColor(red: 0.72, green: 0.73, blue: 0.71, alpha: 1)
        let tireColor = UIColor(red: 0.025, green: 0.025, blue: 0.026, alpha: 1)
        root.addChild(gearAssembly(
            name: noseGearName,
            rootPosition: [0, -0.33, 2.71],
            strutHeight: 1.12,
            wheelRadius: 0.25,
            wheelWidth: 0.20,
            strutColor: strutColor,
            tireColor: tireColor
        ))
        root.addChild(gearAssembly(
            name: leftGearName,
            rootPosition: [-1.22, -0.38, -0.87],
            strutHeight: 1.00,
            wheelRadius: 0.31,
            wheelWidth: 0.24,
            strutColor: strutColor,
            tireColor: tireColor
        ))
        root.addChild(gearAssembly(
            name: rightGearName,
            rootPosition: [1.22, -0.38, -0.87],
            strutHeight: 1.00,
            wheelRadius: 0.31,
            wheelWidth: 0.24,
            strutColor: strutColor,
            tireColor: tireColor
        ))
    }

    private static func gearAssembly(
        name: String,
        rootPosition: SIMD3<Float>,
        strutHeight: Float,
        wheelRadius: Float,
        wheelWidth: Float,
        strutColor: UIColor,
        tireColor: UIColor
    ) -> Entity {
        let assembly = Entity()
        assembly.name = name
        assembly.position = rootPosition

        let strut = ModelEntity(
            mesh: .generateCylinder(height: strutHeight, radius: 0.068),
            materials: [SimpleMaterial(color: strutColor, isMetallic: true)]
        )
        strut.position = [0, -strutHeight * 0.5, 0]
        assembly.addChild(strut)

        let wheel = ModelEntity(
            mesh: .generateCylinder(height: wheelWidth, radius: wheelRadius),
            materials: [SimpleMaterial(color: tireColor, isMetallic: false)]
        )
        wheel.position = [0, -strutHeight, 0]
        wheel.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        assembly.addChild(wheel)
        return assembly
    }

    private static func loadAuthoredOBJ(_ name: String) throws -> MeshResource {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "obj",
            subdirectory: "JSBSim/visuals/f16"
        ) else {
            throw AssetError.missing(name)
        }

        let source = try String(contentsOf: url, encoding: .utf8)
        let lines = source.split(whereSeparator: \.isNewline)
        var sourcePositions: [SIMD3<Float>] = []
        var sourceNormals: [SIMD3<Float>] = []
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for line in lines {
            if line.hasPrefix("v ") {
                let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if f.count >= 4, let x = Float(f[1]), let y = Float(f[2]), let z = Float(f[3]) {
                    sourcePositions.append([x, y, z])
                }
            } else if line.hasPrefix("vn ") {
                let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if f.count >= 4, let x = Float(f[1]), let y = Float(f[2]), let z = Float(f[3]) {
                    let n = SIMD3<Float>(x, y, z)
                    sourceNormals.append(simd_length_squared(n) > 0 ? simd_normalize(n) : SIMD3<Float>(0, 1, 0))
                }
            }
        }

        func resolved(_ raw: Int, count: Int) -> Int? {
            if raw > 0 { let i = raw - 1; return i < count ? i : nil }
            if raw < 0 { let i = count + raw; return i >= 0 && i < count ? i : nil }
            return nil
        }

        func vertex(_ token: Substring) -> ParsedVertex? {
            let c = token.split(separator: "/", omittingEmptySubsequences: false)
            guard let rawP = c.first.flatMap({ Int($0) }),
                  let pi = resolved(rawP, count: sourcePositions.count) else { return nil }
            var normal = SIMD3<Float>(0, 1, 0)
            if c.count >= 3, let rawN = Int(c[2]), let ni = resolved(rawN, count: sourceNormals.count) {
                normal = sourceNormals[ni]
            }
            return ParsedVertex(position: sourcePositions[pi], normal: normal)
        }

        for line in lines where line.hasPrefix("f ") {
            let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard f.count >= 4 else { continue }
            let face = f.dropFirst().compactMap(vertex)
            guard face.count == f.count - 1, face.count >= 3 else { continue }
            for i in 1..<(face.count - 1) {
                for v in [face[0], face[i], face[i + 1]] {
                    indices.append(UInt32(positions.count))
                    positions.append(v.position)
                    normals.append(v.normal)
                }
            }
        }

        guard positions.count >= 3, indices.count >= 3 else {
            throw AssetError.invalid(name)
        }

        var descriptor = MeshDescriptor(name: "Authored F-16 \(name)")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}
'''

(ROOT / 'Aircraft/PrototypeAircraftFactory.swift').write_text(factory, encoding='utf-8')

# Add authoritative engine telemetry to AircraftState.
state_path = ROOT / 'Simulation/AircraftState.swift'
state = state_path.read_text(encoding='utf-8')
needle = '    var engineFuelFlowPoundsPerSecond: Float = 0\n'
replacement = needle + '    var engineN1Percent: Float = 0\n    var engineN2Percent: Float = 0\n    var afterburnerActive = false\n'
if needle not in state:
    raise RuntimeError('AircraftState engine telemetry anchor not found')
state_path.write_text(state.replace(needle, replacement, 1), encoding='utf-8')

# Read turbine spool and JSBSim's own method-1 augmentation condition.
sim_path = ROOT / 'Simulation/FlightSimulation.swift'
sim = sim_path.read_text(encoding='utf-8')
needle = '        state.engineFuelFlowPoundsPerSecond = max(0, finiteFloat("propulsion/engine[0]/fuel-flow-rate-pps", fallback: 0))\n'
replacement = needle + '''        state.engineN1Percent = max(0, finiteFloat("propulsion/engine[0]/n1", fallback: 0))
        state.engineN2Percent = max(0, finiteFloat("propulsion/engine[0]/n2", fallback: 0))
        // The upstream JSBSim FGTurbine method-1 augmentation logic engages
        // above 99% throttle once N2 exceeds 97%. Mirror that engine-state
        // condition for visuals/audio only; JSBSim still owns actual thrust.
        state.afterburnerActive = controls.throttle > 0.99 && state.engineN2Percent > 97.0
'''
if needle not in sim:
    raise RuntimeError('FlightSimulation engine telemetry anchor not found')
sim_path.write_text(sim.replace(needle, replacement, 1), encoding='utf-8')

# Wire the authored rig, plume and state-driven synthesized jet audio into the existing scene.
scene_path = ROOT / 'App/PrototypeSceneView.swift'
scene = scene_path.read_text(encoding='utf-8')
scene = scene.replace('import Combine\n', 'import AVFoundation\nimport Combine\n', 1)
scene = scene.replace(
    '    let effects = Stage2FlightEffects.Runtime()\n',
    '    let effects = Stage2FlightEffects.Runtime()\n    let jetAudio = Stage0108JetAudio()\n',
    1
)
scene = scene.replace(
    '                    updateAircraftPresentation(aircraft)\n',
    '                    updateAircraftPresentation(aircraft)\n                    runtime.jetAudio.update(state: simulation.state, isPaused: simulation.isPaused)\n',
    1
)
old_presentation = '''        // Drive each visual hinge from the actual JSBSim FCS surface angle.
        if let left = aircraft.findEntity(named: PrototypeAircraftFactory.leftAileronName) {
            // Match the mature F-16 visual convention: the left JSBSim aileron
            // sign is mirrored before rotation about the mirrored hinge axis.
            left.orientation = simd_quatf(angle: -state.leftAileronRadians, axis: PrototypeAircraftFactory.leftAileronVisualAxis)
        }
        if let right = aircraft.findEntity(named: PrototypeAircraftFactory.rightAileronName) {
            right.orientation = simd_quatf(angle: state.rightAileronRadians, axis: PrototypeAircraftFactory.rightAileronVisualAxis)
        }
        if let left = aircraft.findEntity(named: PrototypeAircraftFactory.leftElevatorName) {
            // JSBSim's dht-left/dht-right outputs already carry mirrored local
            // signs. With mirror-correct hinge axes, use those angles verbatim.
            left.orientation = simd_quatf(angle: state.leftStabilatorRadians, axis: PrototypeAircraftFactory.leftStabilatorVisualAxis)
        }
        if let right = aircraft.findEntity(named: PrototypeAircraftFactory.rightElevatorName) {
            right.orientation = simd_quatf(angle: state.rightStabilatorRadians, axis: PrototypeAircraftFactory.rightStabilatorVisualAxis)
        }
        if let rudder = aircraft.findEntity(named: PrototypeAircraftFactory.rudderName) {
            rudder.orientation = simd_quatf(angle: state.rudderRadians, axis: PrototypeAircraftFactory.rudderVisualAxis)
        }

        updateGear(aircraft, position: state.gearPosition)
'''
new_presentation = '''        // The replacement F-16 is an authored rig. These sign conversions are
        // renderer-boundary conversions between JSBSim's left/right local
        // surface conventions and the source FBX animation convention.
        if let left = aircraft.findEntity(named: PrototypeAircraftFactory.leftAileronName) {
            left.orientation = simd_quatf(
                angle: -state.leftAileronRadians,
                axis: PrototypeAircraftFactory.leftAileronVisualAxis
            )
        }
        if let right = aircraft.findEntity(named: PrototypeAircraftFactory.rightAileronName) {
            right.orientation = simd_quatf(
                angle: -state.rightAileronRadians,
                axis: PrototypeAircraftFactory.rightAileronVisualAxis
            )
        }
        if let left = aircraft.findEntity(named: PrototypeAircraftFactory.leftElevatorName) {
            // JSBSim defines left differential-tail angle with the opposite local
            // sign to the right tail. The authored FBX uses the same +X hinge
            // direction on both stabilators, hence the left-side sign conversion.
            left.orientation = simd_quatf(
                angle: -state.leftStabilatorRadians,
                axis: PrototypeAircraftFactory.leftStabilatorVisualAxis
            )
        }
        if let right = aircraft.findEntity(named: PrototypeAircraftFactory.rightElevatorName) {
            right.orientation = simd_quatf(
                angle: state.rightStabilatorRadians,
                axis: PrototypeAircraftFactory.rightStabilatorVisualAxis
            )
        }
        if let rudder = aircraft.findEntity(named: PrototypeAircraftFactory.rudderName) {
            // vazgriz's authored Rudder channel uses -rudder influence.
            rudder.orientation = simd_quatf(
                angle: -state.rudderRadians,
                axis: PrototypeAircraftFactory.rudderVisualAxis
            )
        }

        let speedbrakeAngle = clamp(state.speedbrakePosition, 0, 1) * PrototypeAircraftFactory.authoredSpeedbrakeLimitRadians
        for name in [PrototypeAircraftFactory.speedbrakeLeftUpperName, PrototypeAircraftFactory.speedbrakeRightUpperName] {
            aircraft.findEntity(named: name)?.orientation = simd_quatf(
                angle: speedbrakeAngle,
                axis: PrototypeAircraftFactory.speedbrakeUpperVisualAxis
            )
        }
        for name in [PrototypeAircraftFactory.speedbrakeLeftLowerName, PrototypeAircraftFactory.speedbrakeRightLowerName] {
            aircraft.findEntity(named: name)?.orientation = simd_quatf(
                angle: speedbrakeAngle,
                axis: PrototypeAircraftFactory.speedbrakeLowerVisualAxis
            )
        }

        updateAfterburner(aircraft, state: state)
        updateGear(aircraft, position: state.gearPosition)
'''
if old_presentation not in scene:
    raise RuntimeError('PrototypeSceneView presentation block not found')
scene = scene.replace(old_presentation, new_presentation, 1)

gear_anchor = '''    @MainActor
    private func updateGear(_ aircraft: Entity, position: Float) {
'''
afterburner_method = '''    @MainActor
    private func updateAfterburner(_ aircraft: Entity, state: AircraftState) {
        let n2 = clamp((state.engineN2Percent - 97.0) / 3.5, 0, 1)
        let fuel = clamp((state.engineFuelFlowPoundsPerSecond - 0.35) / 1.25, 0, 1)
        let intensity = state.afterburnerActive ? clamp(0.50 + 0.38 * n2 + 0.12 * fuel, 0, 1) : 0

        if let plume = aircraft.findEntity(named: PrototypeAircraftFactory.afterburnerName) {
            plume.isEnabled = intensity > 0.01
            if plume.isEnabled {
                let pulse = 1.0 + 0.035 * sin(Float(simulation.simulationTime) * 43.0)
                plume.scale = [
                    0.82 + 0.18 * intensity,
                    0.82 + 0.18 * intensity,
                    (0.64 + 0.52 * intensity) * pulse
                ]
            }
        }
        if let glow = aircraft.findEntity(named: PrototypeAircraftFactory.nozzleGlowName) {
            let hot = clamp((state.engineN2Percent - 72) / 28, 0, 1)
            glow.isEnabled = hot > 0.02
            glow.scale = [0.68 + 0.32 * hot, 0.68 + 0.32 * hot, 0.16 + 0.20 * hot]
        }
    }

'''
if gear_anchor not in scene:
    raise RuntimeError('PrototypeSceneView gear anchor not found')
scene = scene.replace(gear_anchor, afterburner_method + gear_anchor, 1)

# Append synthesized, engine-state-driven jet sound without adding licensed binary audio.
audio = r'''

@MainActor
private final class Stage0108JetAudio {
    private let engine = AVAudioEngine()
    private let core = AVAudioPlayerNode()
    private let whine = AVAudioPlayerNode()
    private let exhaust = AVAudioPlayerNode()
    private let afterburner = AVAudioPlayerNode()
    private let wind = AVAudioPlayerNode()
    private let coreRate = AVAudioUnitVarispeed()
    private let whineRate = AVAudioUnitVarispeed()
    private var started = false

    init() {
        engine.attach(core)
        engine.attach(whine)
        engine.attach(exhaust)
        engine.attach(afterburner)
        engine.attach(wind)
        engine.attach(coreRate)
        engine.attach(whineRate)
    }

    func update(state: AircraftState, isPaused: Bool) {
        startIfNeeded()
        guard started else { return }

        let n1 = clamp(state.engineN1Percent / 100, 0, 1.15)
        let n2 = clamp(state.engineN2Percent / 100, 0, 1.15)
        let speed = clamp(state.airspeedMetersPerSecond / 340, 0, 1.7)
        let fuel = clamp(state.engineFuelFlowPoundsPerSecond / 1.8, 0, 1.2)
        let live: Float = isPaused ? 0 : 1

        coreRate.rate = 0.68 + 0.58 * n1
        whineRate.rate = 0.64 + 1.18 * n2
        core.volume = live * (0.06 + 0.19 * n1)
        whine.volume = live * (0.018 + 0.105 * n2 * n2)
        exhaust.volume = live * (0.025 + 0.22 * max(n1, fuel))
        afterburner.volume = live * (state.afterburnerActive ? 0.34 + 0.22 * n2 : 0)
        wind.volume = live * 0.18 * min(speed * speed, 1.0)
    }

    private func startIfNeeded() {
        guard !started else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
            engine.connect(core, to: coreRate, format: format)
            engine.connect(coreRate, to: engine.mainMixerNode, format: format)
            engine.connect(whine, to: whineRate, format: format)
            engine.connect(whineRate, to: engine.mainMixerNode, format: format)
            engine.connect(exhaust, to: engine.mainMixerNode, format: format)
            engine.connect(afterburner, to: engine.mainMixerNode, format: format)
            engine.connect(wind, to: engine.mainMixerNode, format: format)

            schedule(core, buffer: makeToneBuffer(format: format, seconds: 2.0, frequencies: [54, 82, 109], gains: [0.58, 0.28, 0.14]))
            schedule(whine, buffer: makeToneBuffer(format: format, seconds: 2.0, frequencies: [215, 430, 645], gains: [0.62, 0.27, 0.11]))
            schedule(exhaust, buffer: makeNoiseBuffer(format: format, seconds: 3.0, smoothing: 0.76, crackle: 0.015))
            schedule(afterburner, buffer: makeNoiseBuffer(format: format, seconds: 3.0, smoothing: 0.46, crackle: 0.095))
            schedule(wind, buffer: makeNoiseBuffer(format: format, seconds: 3.0, smoothing: 0.90, crackle: 0.0))

            try engine.start()
            [core, whine, exhaust, afterburner, wind].forEach { $0.play() }
            started = true
        } catch {
            started = false
        }
    }

    private func schedule(_ node: AVAudioPlayerNode, buffer: AVAudioPCMBuffer) {
        node.scheduleBuffer(buffer, at: nil, options: [.loops])
    }

    private func makeToneBuffer(
        format: AVAudioFormat,
        seconds: Double,
        frequencies: [Float],
        gains: [Float]
    ) -> AVAudioPCMBuffer {
        let count = AVAudioFrameCount(format.sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buffer.frameLength = count
        let data = buffer.floatChannelData![0]
        let rate = Float(format.sampleRate)
        for i in 0..<Int(count) {
            let t = Float(i) / rate
            var sample: Float = 0
            for (f, g) in zip(frequencies, gains) {
                sample += sin(2 * .pi * f * t) * g
            }
            data[i] = sample * 0.42
        }
        return buffer
    }

    private func makeNoiseBuffer(
        format: AVAudioFormat,
        seconds: Double,
        smoothing: Float,
        crackle: Float
    ) -> AVAudioPCMBuffer {
        let count = AVAudioFrameCount(format.sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buffer.frameLength = count
        let data = buffer.floatChannelData![0]
        var seed: UInt32 = 0xA17F_16C3
        var filtered: Float = 0
        for i in 0..<Int(count) {
            seed = 1_664_525 &* seed &+ 1_013_904_223
            let raw = Float(Int32(bitPattern: seed)) / Float(Int32.max)
            filtered = smoothing * filtered + (1 - smoothing) * raw
            let transient: Float = abs(raw) > 0.985 ? raw * crackle * 5.5 : 0
            data[i] = max(-1, min(1, filtered * 0.72 + transient))
        }
        return buffer
    }

    private func clamp(_ value: Float, _ low: Float, _ high: Float) -> Float {
        Swift.min(Swift.max(value, low), high)
    }
}
'''
scene += audio
scene_path.write_text(scene, encoding='utf-8')

print('Applied Stage 010.8 authored F-16, engine telemetry, afterburner, speedbrakes and audio runtime.')
