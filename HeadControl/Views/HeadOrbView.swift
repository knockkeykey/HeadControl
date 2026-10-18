import SwiftUI
import SceneKit

/// Ceramic orb with two AirPods; replaces the 2.0 owl. Same pose semantics, only the head pivot moves.
struct HeadOrbView: NSViewRepresentable {
    var pose: MotionSample
    /// Target pose during a calibration task, drawn as accent-coloured dashed guides.
    var ghost: MotionSample? = nil
    var link: HeadphoneLink
    var enabled = false
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> HeadOrbScene { HeadOrbScene() }
    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = context.coordinator.scene
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = false
        view.preferredFramesPerSecond = 60
        view.pointOfView = context.coordinator.camera
        return view
    }
    func updateNSView(_ view: SCNView, context: Context) {
        let status: HeadOrbScene.Status = switch link.tone {
        case .off: .off
        case .warning: .warning
        case .connected: enabled ? .tracking : .paused
        }
        // Not tracking: rest at neutral rather than freezing on the last sample.
        let live = link.tone == .connected ? pose : MotionSample(time: pose.time, yaw: 0, pitch: 0, roll: 0)
        context.coordinator.apply(pitch: live.pitch, yaw: live.yaw, roll: live.roll,
                                  ghost: ghost.map { ($0.pitch, $0.yaw, $0.roll) },
                                  status: status, dark: colorScheme == .dark)
    }
}

/// Ceramic orb wearing two AirPods, seen from behind and slightly above so it turns the same way the wearer does.
/// An equator and a forehead-to-nape meridian make turn, nod and tilt all readable.
final class HeadOrbScene {
    enum Status: Equatable { case off, warning, tracking, paused }

    let scene = SCNScene()
    let camera = SCNNode()
    private let pivot = SCNNode()
    private let ghostPivot = SCNNode()
    private let orb = SCNMaterial()
    private let lines = SCNMaterial()
    private let pod = SCNMaterial()
    private var halos: [SCNNode] = []
    private var key = SCNNode()
    private var status: Status?
    private var dark: Bool?

    init() {
        orb.lightingModel = .physicallyBased
        orb.roughness.contents = 0.62; orb.metalness.contents = 0.0
        orb.clearCoat.contents = 0.08; orb.clearCoatRoughness.contents = 0.5
        let ball = SCNSphere(radius: 1); ball.segmentCount = 128; ball.firstMaterial = orb
        pivot.addChildNode(SCNNode(geometry: ball))

        lines.lightingModel = .constant
        pivot.addChildNode(Self.guides(material: lines, dashed: false))

        pod.lightingModel = .physicallyBased
        pod.diffuse.contents = NSColor(white: 0.98, alpha: 1)
        pod.roughness.contents = 0.18; pod.clearCoat.contents = 0.8; pod.clearCoatRoughness.contents = 0.05
        for side: CGFloat in [-1, 1] { pivot.addChildNode(airPod(side: side)) }
        scene.rootNode.addChildNode(pivot)

        // Target pose: accent-coloured dashed guides only, so lining up solid with dashed means "reached".
        let accent = SCNMaterial(); accent.lightingModel = .constant
        accent.diffuse.contents = NSColor.controlAccentColor
        ghostPivot.addChildNode(Self.guides(material: accent, dashed: true, inflate: 0.035))
        ghostPivot.isHidden = true
        scene.rootNode.addChildNode(ghostPivot)

        camera.camera = SCNCamera(); camera.camera?.fieldOfView = 30
        camera.camera?.wantsHDR = false
        // Behind, about 20° above and slightly to the right.
        camera.position = SCNVector3(1.3, 2.6, 7.0); camera.look(at: SCNVector3(0, -0.05, 0))
        scene.rootNode.addChildNode(camera)

        @discardableResult func light(_ type: SCNLight.LightType, _ intensity: CGFloat, euler: SCNVector3 = SCNVector3Zero) -> SCNNode {
            let n = SCNNode(); n.light = SCNLight(); n.light?.type = type; n.light?.intensity = intensity
            n.eulerAngles = euler; scene.rootNode.addChildNode(n); return n
        }
        key = light(.directional, 1050, euler: SCNVector3(-0.75, 0.45, 0))   // key: above, camera side, right
        light(.directional, 380, euler: SCNVector3(-0.2, -1.1, 0))     // fill: low left
        light(.directional, 1400, euler: SCNVector3(-0.5, .pi + 0.6, 0)) // rim: from the far side
        light(.ambient, 300)
    }

    func apply(pitch: Double, yaw: Double, roll: Double, ghost: (Double, Double, Double)?, status: Status, dark: Bool, animated: Bool = true) {
        if self.dark != dark { self.dark = dark; paint(dark: dark) }
        SCNTransaction.begin(); SCNTransaction.animationDuration = animated ? 0.07 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .linear)
        pivot.eulerAngles = Self.euler(pitch, yaw, roll)
        SCNTransaction.commit()
        if let ghost { ghostPivot.eulerAngles = Self.euler(ghost.0, ghost.1, ghost.2) }
        ghostPivot.isHidden = ghost == nil
        if self.status != status { self.status = status; show(status) }
    }

    /// The orb faces -Z (away from the camera). Recognizer semantics: nod = pitch < 0, turnRight = yaw > 0, tiltRight = roll > 0.
    private static func euler(_ pitch: Double, _ yaw: Double, _ roll: Double) -> SCNVector3 {
        let r = Double.pi / 180
        return SCNVector3(pitch * r, -yaw * r, -roll * r)
    }

    private func paint(dark: Bool) {
        // Light mode sits on a white card: keep the orb a shade darker so its silhouette and the AirPods read.
        orb.diffuse.contents = dark ? NSColor(white: 0.40, alpha: 1) : NSColor(white: 0.66, alpha: 1)
        key.light?.intensity = dark ? 1050 : 820
        lines.diffuse.contents = dark ? NSColor(white: 0.62, alpha: 1) : NSColor(white: 0.55, alpha: 1)
        pod.diffuse.contents = NSColor(white: dark ? 0.94 : 0.995, alpha: 1)
    }

    private func show(_ status: Status) {
        let color: NSColor = switch status {
        case .off: .systemGray
        case .warning: .systemOrange
        case .tracking: .systemGreen
        case .paused: .systemGray
        }
        for halo in halos {
            halo.geometry?.firstMaterial?.diffuse.contents = color
            halo.removeAllActions()
            halo.opacity = status == .paused ? 0.35 : 1
            if status == .tracking && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                halo.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.35, duration: 0.9), .fadeOpacity(to: 1, duration: 0.9)])))
            }
        }
        pod.transparency = status == .paused ? 0.6 : 1
    }

    /// AirPods Pro: rounded bud in the ear, short stem pointing down and slightly forward.
    private func airPod(side: CGFloat) -> SCNNode {
        let root = SCNNode(); root.position = SCNVector3(1.0 * side, -0.04, 0.06)
        let bud = SCNNode(geometry: SCNSphere(radius: 0.21)); bud.geometry?.firstMaterial = pod
        bud.scale = SCNVector3(0.85, 1, 1.05)
        root.addChildNode(bud)
        let stem = SCNNode(geometry: SCNCapsule(capRadius: 0.065, height: 0.46)); stem.geometry?.firstMaterial = pod
        stem.position = SCNVector3(0.07 * side, -0.27, -0.06); stem.eulerAngles = SCNVector3(-0.25, 0, 0.12 * side)
        root.addChildNode(stem)
        // Status light: a small glowing dot on the bud's outer face.
        let dot = SCNSphere(radius: 0.055)
        let dotMaterial = SCNMaterial(); dotMaterial.lightingModel = .constant; dot.firstMaterial = dotMaterial
        let halo = SCNNode(geometry: dot)
        halo.position = SCNVector3(0.16 * side, 0.03, 0.02); halo.scale = SCNVector3(0.5, 1, 1)
        root.addChildNode(halo); halos.append(halo)
        return root
    }

    /// Equator plus a meridian running from forehead over the crown to the nape.
    private static func guides(material: SCNMaterial, dashed: Bool, inflate: CGFloat = 0) -> SCNNode {
        let root = SCNNode()
        let radius = 1.004 + inflate
        let equator = ring(radius: radius, material: material, dashed: dashed)
        let meridian = ring(radius: radius, material: material, dashed: dashed)
        meridian.eulerAngles.z = .pi / 2
        root.addChildNode(equator); root.addChildNode(meridian)
        return root
    }

    private static func ring(radius: CGFloat, material: SCNMaterial, dashed: Bool) -> SCNNode {
        guard dashed else {
            let torus = SCNTorus(ringRadius: radius, pipeRadius: 0.011)
            torus.ringSegmentCount = 160; torus.pipeSegmentCount = 12; torus.firstMaterial = material
            return SCNNode(geometry: torus)
        }
        let root = SCNNode(), count = 40
        let dash = SCNCapsule(capRadius: 0.016, height: 2 * .pi * radius / CGFloat(count) * 0.55)
        dash.firstMaterial = material
        for i in 0..<count {
            let a = CGFloat(i) / CGFloat(count) * 2 * .pi
            let n = SCNNode(geometry: dash)
            n.position = SCNVector3(radius * cos(a), 0, radius * sin(a))
            // Capsules are vertical; lay each one along the circle's tangent.
            n.eulerAngles = SCNVector3(.pi / 2, -a, 0)
            root.addChildNode(n)
        }
        return root
    }
}
