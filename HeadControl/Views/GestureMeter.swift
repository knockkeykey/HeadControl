import SwiftUI

/// 240° gauge: live travel fills the arc, the knob is the draggable trigger angle,
/// the grey wedge near zero is the return-to-neutral zone, a dashed tick is the suggestion.
struct ArcGauge: View {
    let value: Double
    @Binding var threshold: Double
    let neutral: Double
    var peak: Double? = nil
    var suggestion: Double? = nil
    var editable = true
    var lit = false
    static let span = 60.0
    private let sweep = 240.0, start = 150.0

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let line = size * 0.09
            let radius = size / 2 - line
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let over = value >= threshold
            ZStack {
                arc(0, Self.span).stroke(Color.secondary.opacity(0.14), style: StrokeStyle(lineWidth: line, lineCap: .round))
                arc(0, neutral).stroke(Color.secondary.opacity(0.32), style: StrokeStyle(lineWidth: line, lineCap: .round))
                arc(threshold, Self.span).stroke(Color.accentColor.opacity(0.14), style: StrokeStyle(lineWidth: line, lineCap: .butt))
                arc(0, max(0, value)).stroke(over || lit ? Color.green : Color.accentColor, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .animation(.linear(duration: 0.08), value: value)
                if let peak, peak > 0 {
                    tick(peak).stroke(Color.primary.opacity(0.5), lineWidth: 1.5)
                }
                if let suggestion {
                    tick(suggestion, extra: 1.6).stroke(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                }
                Circle().fill(Color.white).shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
                    .frame(width: line * 1.6, height: line * 1.6)
                    .position(point(threshold, radius: radius, center: center))
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("gauge")).onChanged { drag in
                        guard editable else { return }
                        if let v = degrees(at: drag.location, center: center) { threshold = min(50, max(max(8, neutral + 1), v.rounded())) }
                    })
                    .accessibilityElement().accessibilityLabel("触发角度")
                    .accessibilityValue("\(Int(threshold)) 度")
                    .accessibilityAdjustableAction { dir in
                        guard editable else { return }
                        threshold = min(50, max(max(8, neutral + 1), threshold + (dir == .increment ? 1 : -1)))
                    }
                VStack(spacing: 0) {
                    Text("\(Int(max(0, value).rounded()))°").font(.system(size: size * 0.2, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(over || lit ? Color.green : Color.primary).contentTransition(.numericText())
                    Text("触发 \(Int(threshold))°").font(.system(size: max(10, size * 0.085))).foregroundStyle(.secondary)
                }.offset(y: size * 0.03)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .coordinateSpace(name: "gauge")
            .scaleEffect(lit ? 1.04 : 1).animation(.spring(duration: 0.25), value: lit)
        }
        .aspectRatio(1.15, contentMode: .fit)
    }

    private func angle(_ v: Double) -> Angle { .degrees(start + sweep * min(max(v, 0), Self.span) / Self.span) }
    private func arc(_ from: Double, _ to: Double) -> some Shape { GaugeArc(from: angle(from), to: angle(max(from, to))) }
    private func tick(_ v: Double, extra: CGFloat = 1.3) -> some Shape { GaugeTick(angle: angle(v), extra: extra) }
    private func point(_ v: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        let a = CGFloat(angle(v).radians)
        return CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius)
    }
    private func degrees(at p: CGPoint, center: CGPoint) -> Double? {
        var a = atan2(p.y - center.y, p.x - center.x) * 180 / .pi - start
        while a < 0 { a += 360 }
        if a > sweep { return a > sweep + (360 - sweep) / 2 ? 0 : Self.span }
        return a / sweep * Self.span
    }
}

private struct GaugeArc: Shape {
    let from: Angle, to: Angle
    func path(in rect: CGRect) -> Path {
        let line = min(rect.width, rect.height) * 0.09
        var p = Path()
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2 - line, startAngle: from, endAngle: to, clockwise: false)
        return p
    }
}
private struct GaugeTick: Shape {
    let angle: Angle
    let extra: CGFloat
    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height), line = size * 0.09, r = size / 2 - line
        let c = CGPoint(x: rect.midX, y: rect.midY), a = CGFloat(angle.radians)
        var p = Path()
        p.move(to: CGPoint(x: c.x + cos(a) * (r - line * extra / 2), y: c.y + sin(a) * (r - line * extra / 2)))
        p.addLine(to: CGPoint(x: c.x + cos(a) * (r + line * extra / 2), y: c.y + sin(a) * (r + line * extra / 2)))
        return p
    }
}

/// Small pictogram of the motion: head outline plus a direction arrow.
struct GestureGlyph: View {
    let gesture: Gesture
    var size: CGFloat = 20
    var body: some View {
        Image(systemName: symbol).font(.system(size: size, weight: .medium)).symbolRenderingMode(.hierarchical)
            .rotationEffect(rotation)
    }
    private var symbol: String {
        switch gesture {
        case .tiltLeft, .tiltRight: "person.crop.circle"
        case .turnLeft: "arrow.turn.up.left"
        case .turnRight: "arrow.turn.up.right"
        case .nod: "arrow.down.and.line.horizontal.and.arrow.up"
        case .shake: "arrow.left.and.right"
        }
    }
    private var rotation: Angle {
        switch gesture { case .tiltLeft: .degrees(-22); case .tiltRight: .degrees(22); default: .zero }
    }
}

extension Gesture {
    /// Target pose for the translucent ghost head during a test.
    func ghostPose(angle: Double) -> MotionSample {
        switch self {
        case .tiltLeft: MotionSample(time: 0, roll: -angle)
        case .tiltRight: MotionSample(time: 0, roll: angle)
        case .turnLeft: MotionSample(time: 0, yaw: -angle)
        case .turnRight: MotionSample(time: 0, yaw: angle)
        case .nod: MotionSample(time: 0, pitch: -angle)
        case .shake: MotionSample(time: 0, yaw: angle)
        }
    }
}
