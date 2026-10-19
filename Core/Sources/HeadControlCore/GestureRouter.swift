import Foundation

/// Routes sensor gestures to one global binding. Preview never authorizes key execution.
public struct GestureRouter: Sendable {
    public enum Mode: Sendable { case paused, testing, active }
    public struct Route: Sendable {
        public let gesture: Gesture
        public let binding: GestureBinding
        public let executes: Bool
        public let revision: Int
    }
    public private(set) var mode: Mode = .paused
    public private(set) var revision = 0
    private var recognizer = GestureRecognizer()
    public init() {}
    public mutating func setMode(_ value: Mode) {
        mode = value; revision += 1; recognizer.reset()
    }
    /// Drops half-finished gestures and in-flight routes, but keeps the current mode: editing a setting does not pause control.
    public mutating func configurationChanged() { setMode(mode) }
    public var status: [Gesture: GestureStatus] { recognizer.status }
    public func preview(_ gesture: Gesture, configuration: Configuration) -> Route? {
        guard mode == .testing, configuration.isEnabled(gesture) else { return nil }
        return Route(gesture:gesture,binding:configuration.binding(gesture),executes:false,revision:revision)
    }
    public mutating func update(_ sample: MotionSample, configuration: Configuration, testingGesture: Gesture? = nil, feedbackWhenPaused: Bool = false) -> Route? {
        // A visible gesture page may request recognition feedback while paused, never key execution.
        var gestures = Set(configuration.enabledGestures)
        if mode == .testing, let testingGesture { gestures.formIntersection([testingGesture]) }
        let recognized = recognizer.update(sample,tuning:configuration.tuning,enabledGestures:gestures)
        guard let gesture = recognized, mode != .paused || feedbackWhenPaused else { return nil }
        let binding = configuration.binding(gesture)
        return Route(gesture:gesture,binding:binding,executes:mode == .active && binding.action != .disabled,revision:revision)
    }
    public func accepts(_ route: Route) -> Bool {
        mode == .active && route.executes && route.revision == revision
    }
}
