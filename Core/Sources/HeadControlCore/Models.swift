import Foundation

public enum Gesture: String, CaseIterable, Codable, Identifiable, Sendable {
    case tiltLeft, tiltRight, turnLeft, turnRight, nod, shake
    public var id: String { rawValue }
    public var title: String {
        switch self { case .tiltLeft: "左歪头"; case .tiltRight: "右歪头"; case .turnLeft: "向左转头"; case .turnRight: "向右转头"; case .nod: "完整点头"; case .shake: "完整摇头" }
    }
    public var symbol: String {
        switch self { case .tiltLeft: "arrow.uturn.left"; case .tiltRight: "arrow.uturn.right"; case .turnLeft: "arrow.left"; case .turnRight: "arrow.right"; case .nod: "arrow.down.and.line.horizontal.and.arrow.up"; case .shake: "arrow.left.and.right" }
    }
    public var isSequence: Bool { self == .nod || self == .shake }
}

public enum ActionKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case disabled, shortcut, pause
    public var id: String { rawValue }
    public var title: String {
        switch self { case .disabled: "不操作"; case .shortcut: "点按快捷键"; case .pause: "暂停头势控制" }
    }
}

public struct Shortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    /// CGEventFlags raw flags, including device-specific side bits. Never archive NSEvent objects.
    public var flags: UInt64
    public var label: String
    public init(keyCode: UInt16, flags: UInt64 = 0, label: String) { self.keyCode = keyCode; self.flags = flags; self.label = label }
    public static let rightOption = Shortcut(keyCode: 61, flags: (1 << 19) | 0x40, label: "右 ⌥")
    public static let returnKey = Shortcut(keyCode: 36, label: "Return ↩")
    public var isValid: Bool { keyCode <= 127 && keyCode != 57 && !label.isEmpty && label.count <= 100 }
    public static let modifierKeyCodes: Set<UInt16> = [54,55,56,60,58,61,59,62]
}

public struct GestureBinding: Codable, Equatable, Sendable {
    public var action: ActionKind
    public var shortcut: Shortcut?
    public init(_ action: ActionKind = .disabled, shortcut: Shortcut? = nil) { self.action = action; self.shortcut = shortcut }
}

public enum Sensitivity: String, CaseIterable, Codable, Identifiable, Sendable {
    case gentle, standard, steady, custom
    public var id: String { rawValue }
    public var title: String { switch self { case .gentle: "轻柔"; case .standard: "标准"; case .steady: "稳健"; case .custom: "自定义" } }
}

public struct GestureTuning: Codable, Equatable, Sendable {
    public var preset: Sensitivity = .standard
    public var angle: Double = 18
    public var dwell: Double = 0.35
    public var completion: Double = 1.0
    public var neutral: Double = 7
    public var cooldown: Double = 0.9
    public init() {}
    public static func preset(_ sensitivity: Sensitivity, for gesture: Gesture) -> Self {
        var t = Self(); t.preset = sensitivity
        switch sensitivity {
        case .gentle: t.angle = 13; t.dwell = 0.22; t.completion = 1.2; t.neutral = 5; t.cooldown = 0.7
        case .standard, .custom: break
        case .steady: t.angle = 24; t.dwell = 0.5; t.completion = 0.9; t.neutral = 8; t.cooldown = 1.1
        }
        if gesture == .turnLeft || gesture == .turnRight || gesture == .shake { t.angle += 5 }
        return t
    }
    public var isValid: Bool {
        angle.isFinite && (8...50).contains(angle) && dwell.isFinite && (0.1...1.5).contains(dwell) && completion.isFinite && (0.35...2).contains(completion) && neutral.isFinite && (2...15).contains(neutral) && neutral < angle && cooldown.isFinite && (0.3...3).contains(cooldown)
    }
}

public struct Configuration: Codable, Equatable, Sendable {
    public var version = 2
    public var sound = true
    public var overlay = true
    public var bindings: [String: GestureBinding] = Self.defaultBindings
    public var tuning: [String: GestureTuning] = Dictionary(uniqueKeysWithValues: Gesture.allCases.map { ($0.rawValue, .preset(.standard, for: $0)) })
    public init() {}
    public static var defaultBindings: [String: GestureBinding] {
        var values = Dictionary(uniqueKeysWithValues: Gesture.allCases.map { ($0.rawValue, GestureBinding()) })
        values[Gesture.tiltLeft.rawValue] = GestureBinding(.shortcut, shortcut: .rightOption)
        values[Gesture.nod.rawValue] = GestureBinding(.shortcut, shortcut: .returnKey)
        return values
    }
    public func binding(_ gesture: Gesture) -> GestureBinding { bindings[gesture.rawValue] ?? GestureBinding() }
    public mutating func set(_ binding: GestureBinding, for gesture: Gesture) { bindings[gesture.rawValue] = binding }
    public var isValid: Bool {
        let keys = Set(Gesture.allCases.map(\.rawValue))
        return version == 2 && Set(bindings.keys) == keys && Set(tuning.keys) == keys && Gesture.allCases.allSatisfy {
            let b = binding($0)
            return tuning[$0.rawValue]?.isValid == true && (b.action != .shortcut || b.shortcut?.isValid == true)
        }
    }
    private enum CodingKeys: String, CodingKey { case version, sound, overlay, bindings, tuning }
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try c.decode(Int.self, forKey: .version)
        guard storedVersion == 1 || storedVersion == 2 else { throw ConfigError.invalid }
        sound = try c.decode(Bool.self, forKey: .sound)
        overlay = try c.decode(Bool.self, forKey: .overlay)
        tuning = try c.decode([String: GestureTuning].self, forKey: .tuning)
        // Version 1 had app/state-specific actions. Preserve tuning and feedback preferences;
        // those actions have no unambiguous global meaning, so start with the global preset.
        if storedVersion == 2 { bindings = try c.decode([String: GestureBinding].self, forKey: .bindings) }
    }
    public func encoded() throws -> Data {
        guard isValid else { throw ConfigError.invalid }
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; return try e.encode(self)
    }
    public static func decode(_ data: Data) throws -> Self {
        let c = try JSONDecoder().decode(Self.self, from: data)
        guard c.isValid else { throw ConfigError.invalid }; return c
    }
    public enum ConfigError: Error { case invalid }
}

public struct MotionSample: Equatable, Sendable {
    public var time: Double
    public var yaw: Double
    public var pitch: Double
    public var roll: Double
    public init(time: Double, yaw: Double = 0, pitch: Double = 0, roll: Double = 0) { self.time = time; self.yaw = yaw; self.pitch = pitch; self.roll = roll }
    public var finite: Bool { time.isFinite && yaw.isFinite && pitch.isFinite && roll.isFinite }
}
