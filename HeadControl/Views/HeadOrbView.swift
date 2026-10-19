import SwiftUI
import SceneKit

/// Ceramic orb with two AirPods; replaces the 2.0 owl. Same pose semantics, only the head pivot moves.
struct HeadOrbView: NSViewRepresentable {
    var pose: MotionSample
    /// Target pose during a calibration task, drawn as accent-coloured dashed guides.
    var ghost: MotionSample? = nil
    var link: HeadphoneLink
    var enabled = false
    var showsBodyBackdrop = false
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> HeadOrbScene { HeadOrbScene() }
    func makeNSView(context: Context) -> SCNView {
        let view = HeadOrbSceneView(frame: .zero)
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
                                  status: status, dark: colorScheme == .dark,
                                  showsBodyBackdrop: showsBodyBackdrop)
    }
}

/// Keep outgoing rings inside narrow preview cards while preserving the normal head size.
private final class HeadOrbSceneView: SCNView {
    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0, let camera = pointOfView?.camera else { return }
        camera.projectionDirection = .vertical
        let aspect = bounds.width / bounds.height
        camera.fieldOfView = max(30, 2 * atan(2.4 / (7.58 * aspect)) * 180 / .pi)
    }
}

/// Ceramic orb wearing two AirPods, seen straight from behind so neutral looks fully centred.
/// An equator and a forehead-to-nape meridian make turn, nod and tilt all readable.
final class HeadOrbScene {
    enum Status: Equatable { case off, warning, tracking, paused }

    let scene = SCNScene()
    let camera = SCNNode()
    private let pivot = SCNNode()
    private let ghostPivot = SCNNode()
    private let bodyBackdrop = SCNNode()
    private let bodyMaterial = SCNMaterial()
    private let gridBackdrop = SCNNode()
    private let gridMaterial = SCNMaterial()
    private let orb = SCNMaterial()
    private let lines = SCNMaterial()
    private let pod = SCNMaterial()
    private var connectionLights: [SCNNode] = []
    private var reduceMotion: Bool?
    private var key = SCNNode()
    private var status: Status?
    private var dark: Bool?

    init() {
        orb.lightingModel = .physicallyBased
        // Matte, no clear coat: a glossy finish catches the rim light as a hot spot on the upper-left edge.
        orb.roughness.contents = 0.78; orb.metalness.contents = 0.0
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

        // A flat, stationary back silhouette: it must never inherit the head's pose.
        // Compensate for its depth so its projected shoulders span 1.6 head diameters.
        let backdropDepth: CGFloat = 1.2
        let projectionScale = (7.58 + backdropDepth) / 7.58
        let bodyPlane = SCNPlane(width: 3.8 * projectionScale, height: 1.6 * projectionScale)
        bodyMaterial.lightingModel = .constant
        bodyMaterial.writesToDepthBuffer = false
        bodyPlane.firstMaterial = bodyMaterial
        bodyBackdrop.geometry = bodyPlane
        bodyBackdrop.position = SCNVector3(0, -1.2 * projectionScale, -backdropDepth)
        bodyBackdrop.isHidden = true
        scene.rootNode.addChildNode(bodyBackdrop)

        // A rear wall and receding floor, drawn behind both the head and the stationary body.
        let gridDepth: CGFloat = 3
        let gridScale = (7.58 + gridDepth) / 7.58
        let gridPlane = SCNPlane(width: 12.8 * gridScale, height: 4.4 * gridScale)
        gridMaterial.lightingModel = .constant
        gridMaterial.writesToDepthBuffer = false
        gridMaterial.diffuse.mipFilter = .linear
        gridPlane.firstMaterial = gridMaterial
        gridBackdrop.geometry = gridPlane
        gridBackdrop.position = SCNVector3(0, 0, -gridDepth)
        gridBackdrop.renderingOrder = -2
        gridBackdrop.isHidden = true
        scene.rootNode.addChildNode(gridBackdrop)

        camera.camera = SCNCamera(); camera.camera?.fieldOfView = 30
        camera.camera?.wantsHDR = false
        // Keep the camera level and centred: a zero pose must not look partly turned or tilted.
        camera.position = SCNVector3(0, 0, 7.58); camera.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(camera)

        @discardableResult func light(_ type: SCNLight.LightType, _ intensity: CGFloat, euler: SCNVector3 = SCNVector3Zero) -> SCNNode {
            let n = SCNNode(); n.light = SCNLight(); n.light?.type = type; n.light?.intensity = intensity
            n.eulerAngles = euler; scene.rootNode.addChildNode(n); return n
        }
        key = light(.directional, 1050, euler: SCNVector3(-0.75, 0.45, 0))   // key: above, camera side, right
        light(.directional, 380, euler: SCNVector3(-0.2, -1.1, 0))     // fill: low left
        light(.directional, 320, euler: SCNVector3(-0.5, .pi + 0.6, 0)) // rim: from the far side, kept soft
        light(.ambient, 380)
    }

    func apply(pitch: Double, yaw: Double, roll: Double, ghost: (Double, Double, Double)?, status: Status, dark: Bool, showsBodyBackdrop: Bool = false, animated: Bool = true) {
        if self.dark != dark { self.dark = dark; paint(dark: dark) }
        bodyBackdrop.isHidden = !showsBodyBackdrop
        gridBackdrop.isHidden = !showsBodyBackdrop
        SCNTransaction.begin(); SCNTransaction.animationDuration = animated ? 0.07 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .linear)
        pivot.eulerAngles = Self.euler(pitch, yaw, roll)
        SCNTransaction.commit()
        if let ghost { ghostPivot.eulerAngles = Self.euler(ghost.0, ghost.1, ghost.2) }
        ghostPivot.isHidden = ghost == nil
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if self.status != status || self.reduceMotion != reduceMotion {
            self.status = status; self.reduceMotion = reduceMotion
            show(status, reduceMotion: reduceMotion)
        }
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
        bodyMaterial.diffuse.contents = Self.bodyTexture(dark: dark)
        gridMaterial.diffuse.contents = Self.gridTexture(dark: dark)
    }

    /// Coordinates use the head's projected radius (1), with the neck tucked behind its lower edge.
    /// The texture supplies both the outline and a soft alpha fade, independent of scene lighting.
    private static func bodyTexture(dark: Bool) -> NSImage {
        NSImage(size: NSSize(width: 1140, height: 480), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: (x + 1.9) * 300, y: (y + 2) * 300)
            }
            let silhouette = Self.bodyOutline(point: point)

            context.saveGState()
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            NSColor(white: dark ? 0.82 : 0.38, alpha: dark ? 0.055 : 0.23).setFill()
            silhouette.fill()
            NSColor(white: dark ? 0.75 : 0.40, alpha: dark ? 0.30 : 0.68).setStroke()
            silhouette.lineWidth = dark ? 3.6 : 5.4
            silhouette.lineJoinStyle = .round
            silhouette.stroke()
            context.setBlendMode(.destinationIn)
            NSGradient(colorsAndLocations: (.clear, 0), (.white, 0.38), (.white, 1))?
                .draw(from: NSPoint(x: rect.midX, y: rect.minY), to: NSPoint(x: rect.midX, y: rect.maxY), options: [])
            context.endTransparencyLayer()
            context.restoreGState()
            return true
        }
    }

    private static func bodyOutline(point: (CGFloat, CGFloat) -> NSPoint) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: point(-0.32, -0.65))
        path.curve(to: point(-0.40, -1.10), controlPoint1: point(-0.31, -0.88), controlPoint2: point(-0.29, -1.02))
        path.curve(to: point(-1.38, -1.40), controlPoint1: point(-0.60, -1.25), controlPoint2: point(-1.10, -1.25))
        path.curve(to: point(-1.60, -1.72), controlPoint1: point(-1.55, -1.49), controlPoint2: point(-1.60, -1.59))
        path.line(to: point(-1.60, -2.2))
        path.line(to: point(1.60, -2.2))
        path.line(to: point(1.60, -1.72))
        path.curve(to: point(1.38, -1.40), controlPoint1: point(1.60, -1.59), controlPoint2: point(1.55, -1.49))
        path.curve(to: point(0.40, -1.10), controlPoint1: point(1.10, -1.25), controlPoint2: point(0.60, -1.25))
        path.curve(to: point(0.32, -0.65), controlPoint1: point(0.29, -1.02), controlPoint2: point(0.31, -0.88))
        path.close()
        return path
    }

    private static func gridTexture(dark: Bool) -> NSImage {
        NSImage(size: NSSize(width: 2304, height: 792), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: (x + 6.4) * 180, y: (y + 2.2) * 180)
            }
            let grid = NSBezierPath()
            let horizon: CGFloat = 0.65, seam: CGFloat = -0.65, bottom: CGFloat = -2.2
            for column in -18...18 {
                let x = CGFloat(column) * 0.48
                // Wall columns continue onto the floor toward a shared vanishing point.
                grid.move(to: point(x, 2.2))
                grid.line(to: point(x, seam))
                grid.line(to: point(x * (bottom - horizon) / (seam - horizon), bottom))
            }
            for row in 0...7 {
                let y = seam + CGFloat(row) * 0.40
                grid.move(to: point(-6.4, y)); grid.line(to: point(6.4, y))
            }
            for row in 1...5 {
                let y = horizon + (seam - horizon) * pow(1.20, CGFloat(row))
                grid.move(to: point(-6.4, y)); grid.line(to: point(6.4, y))
            }
            context.saveGState()
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            NSColor(white: dark ? 0.72 : 0.40, alpha: dark ? 0.16 : 0.40).setStroke()
            grid.lineWidth = dark ? 1.8 : 2.7
            grid.stroke()
            // Keep the grid outside the body, even where its fill fades to the card background.
            context.setBlendMode(.destinationOut)
            NSColor.white.setFill()
            Self.bodyOutline(point: point).fill()
            context.setBlendMode(.destinationIn)
            NSGradient(colorsAndLocations: (.white, 0), (.white, 0.42), (.clear, 1))?
                .draw(fromCenter: point(0, -0.10), radius: 0, toCenter: point(0, -0.10),
                      radius: 6.2 * 180, options: [.drawsAfterEndingLocation])
            context.endTransparencyLayer()
            context.restoreGState()
            return true
        }
    }

    private func show(_ status: Status, reduceMotion: Bool) {
        // Connection remains green when shortcut delivery is paused.
        let connected = status == .tracking || status == .paused
        let color: NSColor = connected ? .systemGreen : .systemOrange
        for light in connectionLights {
            light.removeAllActions()
            light.isHidden = status == .off
            light.enumerateChildNodes { node, _ in
                node.geometry?.firstMaterial?.diffuse.contents = color
            }
            // The inner ring is always visible, even between outgoing waves.
            light.childNodes[0].opacity = 0.9
            let waves = Array(light.childNodes.dropFirst())
            Self.placeConnectionWaves(waves, phase: 0, moving: !reduceMotion)
            for wave in waves { wave.isHidden = !connected }
            if connected && !reduceMotion {
                light.runAction(.repeatForever(.customAction(duration: 1.8) { node, elapsed in
                    Self.placeConnectionWaves(Array(node.childNodes.dropFirst()),
                                              phase: elapsed / 1.8, moving: true)
                }))
            }
        }
    }

    private static func placeConnectionWaves(_ waves: [SCNNode], phase: CGFloat, moving: Bool) {
        for (index, wave) in waves.enumerated() {
            let progress = (phase + CGFloat(index) / CGFloat(waves.count)).truncatingRemainder(dividingBy: 1)
            let growth = 0.85 + 1.05 * progress
            wave.position.x = 0.06 + 0.76 * progress
            wave.scale = SCNVector3(0.45 * growth, growth, 1)
            // Staggered waves keep both sides readable throughout the cycle.
            wave.opacity = moving ? 0.85 * (1 - progress) : 0.8 - 0.5 * progress
        }
    }

    /// A crisp green ring with a wider translucent rim, legible on the white grid without HDR bloom.
    private static func connectionRing() -> SCNNode {
        let root = SCNNode()
        for (width, opacity): (CGFloat, CGFloat) in [(0.032, 0.12), (0.012, 1)] {
            let ring = SCNTorus(ringRadius: 0.25, pipeRadius: width)
            ring.ringSegmentCount = 80; ring.pipeSegmentCount = 8
            let material = SCNMaterial(); material.lightingModel = .constant
            material.writesToDepthBuffer = false
            ring.firstMaterial = material
            let node = SCNNode(geometry: ring)
            node.eulerAngles.x = .pi / 2
            node.opacity = opacity
            root.addChildNode(node)
        }
        return root
    }

    /// AirPods Pro deliberately visible along the head's side silhouette.
    private func airPod(side: CGFloat) -> SCNNode {
        // Sit the bud on the outer edge instead of burying it in the orb. A little
        // overlap keeps it attached, while the larger oval reads clearly at this scale.
        let root = SCNNode(); root.position = SCNVector3(1.0 * side, -0.02, 0.16)
        let bud = SCNNode(geometry: SCNSphere(radius: 0.24)); bud.geometry?.firstMaterial = pod
        bud.scale = SCNVector3(0.88, 1.02, 1.0)
        root.addChildNode(bud)
        let stem = SCNNode(geometry: SCNCapsule(capRadius: 0.065, height: 0.44)); stem.geometry?.firstMaterial = pod
        // Let the stem follow the outer contour, with a gentle inward lean toward its tip.
        stem.position = SCNVector3(0.025 * side, -0.30, 0.015)
        stem.eulerAngles = SCNVector3(-0.18, 0, -0.10 * side)
        root.addChildNode(stem)
        // Mirror the emitter so rings travel away from each ear and follow the head's pose.
        let light = SCNNode()
        light.position = SCNVector3(0.22 * side, 0.03, 0.30)
        light.scale.x = side
        let steady = Self.connectionRing()
        steady.position.x = 0.015; steady.scale = SCNVector3(0.45, 0.85, 1)
        light.addChildNode(steady)
        for _ in 0..<3 { light.addChildNode(Self.connectionRing()) }
        light.isHidden = true
        root.addChildNode(light); connectionLights.append(light)
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
