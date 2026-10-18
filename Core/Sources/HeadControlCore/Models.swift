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
    /// Distinct by default so each gesture can be told apart by ear.
    public var defaultSound: String {
        switch self { case .tiltLeft: "Tink"; case .tiltRight: "Pop"; case .turnLeft: "Morse"; case .turnRight: "Bottle"; case .nod: "Glass"; case .shake: "Purr" }
    }
}

/// macOS built-in alert sounds (/System/Library/Sounds). An empty name means silent.
public enum AlertSound {
    public static let names = ["Basso","Blow","Bottle","Frog","Funk","Glass","Hero","Morse","Ping","Pop","Purr","Sosumi","Submarine","Tink"]
    public static func isValid(_ name: String) -> Bool { name.isEmpty || names.contains(name) }
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
    /// Minimum angular speed (°/s) on the gesture's axis; slow posture changes stay below it.
    public var speed: Double = 90
    public init() {}
    private enum CodingKeys: String, CodingKey { case preset, angle, dwell, completion, neutral, cooldown, speed }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preset = try c.decode(Sensitivity.self, forKey: .preset)
        angle = try c.decode(Double.self, forKey: .angle); dwell = try c.decode(Double.self, forKey: .dwell)
        completion = try c.decode(Double.self, forKey: .completion); neutral = try c.decode(Double.self, forKey: .neutral)
        cooldown = try c.decode(Double.self, forKey: .cooldown)
        // Absent before configuration version 3; Configuration fills it per gesture. Zero fails validation otherwise.
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 0
    }
    public static func preset(_ sensitivity: Sensitivity, for gesture: Gesture) -> Self {
        var t = Self(); t.preset = sensitivity
        switch sensitivity {
        case .gentle: t.angle = 13; t.dwell = 0.22; t.completion = 1.2; t.neutral = 5; t.cooldown = 0.7; t.speed = 60
        case .standard, .custom: break
        case .steady: t.angle = 24; t.dwell = 0.5; t.completion = 0.9; t.neutral = 8; t.cooldown = 1.1; t.speed = 130
        }
        if gesture == .turnLeft || gesture == .turnRight || gesture == .shake { t.angle += 5; t.speed += 20 }
        return t
    }
    public static let speedRange: ClosedRange<Double> = 20...300
    public var isValid: Bool {
        angle.isFinite && (8...50).contains(angle) && dwell.isFinite && (0.1...1.5).contains(dwell) && completion.isFinite && (0.35...2).contains(completion) && neutral.isFinite && (2...15).contains(neutral) && neutral < angle && cooldown.isFinite && (0.3...3).contains(cooldown) && speed.isFinite && Self.speedRange.contains(speed)
    }
}

public struct Configuration: Codable, Equatable, Sendable {
    public var version = 3
    public var sound = true
    public var overlay = true
    /// Suspend gestures while the headphones report walking or running.
    public var pauseWhileWalking = true
    public var bindings: [String: GestureBinding] = Self.defaultBindings
    public var tuning: [String: GestureTuning] = Dictionary(uniqueKeysWithValues: Gesture.allCases.map { ($0.rawValue, .preset(.standard, for: $0)) })
    /// Alert sound per gesture, played on every completed gesture while `sound` is on.
    public var sounds: [String: String] = Self.defaultSounds
    public init() {}
    public static var defaultSounds: [String: String] { Dictionary(uniqueKeysWithValues: Gesture.allCases.map { ($0.rawValue, $0.defaultSound) }) }
    public func sound(_ gesture: Gesture) -> String { sounds[gesture.rawValue] ?? gesture.defaultSound }
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
        return version == 3 && Set(bindings.keys) == keys && Set(tuning.keys) == keys && sounds.allSatisfy({ keys.contains($0.key) && AlertSound.isValid($0.value) }) && Gesture.allCases.allSatisfy {
            let b = binding($0)
            return tuning[$0.rawValue]?.isValid == true && (b.action != .shortcut || b.shortcut?.isValid == true)
        }
    }
    private enum CodingKeys: String, CodingKey { case version, sound, sounds, overlay, pauseWhileWalking, bindings, tuning }
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try c.decode(Int.self, forKey: .version)
        guard (1...3).contains(storedVersion) else { throw ConfigError.invalid }
        sound = try c.decode(Bool.self, forKey: .sound)
        overlay = try c.decode(Bool.self, forKey: .overlay)
        tuning = try c.decode([String: GestureTuning].self, forKey: .tuning)
        pauseWhileWalking = try c.decodeIfPresent(Bool.self, forKey: .pauseWhileWalking) ?? true
        // Older files have no per-gesture sounds; missing gestures fall back to their defaults.
        sounds.merge(try c.decodeIfPresent([String: String].self, forKey: .sounds) ?? [:]) { $1 }
        // Version 3 added a speed gate. Keep every older value and take the speed of its preset;
        // custom tuning has no speed preference yet, so it starts from the standard speed.
        if storedVersion < 3 {
            for g in Gesture.allCases {
                guard var t = tuning[g.rawValue] else { continue }
                t.speed = GestureTuning.preset(t.preset == .custom ? .standard : t.preset, for: g).speed
                tuning[g.rawValue] = t
            }
        }
        // Version 1 had app/state-specific actions. Preserve tuning and feedback preferences;
        // those actions have no unambiguous global meaning, so start with the global preset.
        if storedVersion >= 2 { bindings = try c.decode([String: GestureBinding].self, forKey: .bindings) }
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

/// Angular velocity in °/s per gesture axis, using the same sign convention as the angles.
public struct AxisRates: Equatable, Sendable {
    public var yaw: Double
    public var pitch: Double
    public var roll: Double
    public init(yaw: Double = 0, pitch: Double = 0, roll: Double = 0) { self.yaw = yaw; self.pitch = pitch; self.roll = roll }
    public var finite: Bool { yaw.isFinite && pitch.isFinite && roll.isFinite }
}

public struct MotionSample: Equatable, Sendable {
    public var time: Double
    public var yaw: Double
    public var pitch: Double
    public var roll: Double
    /// Nil when the source has no gyroscope reading; the speed gate is then skipped.
    public var rate: AxisRates?
    public init(time: Double, yaw: Double = 0, pitch: Double = 0, roll: Double = 0, rate: AxisRates? = nil) {
        self.time = time; self.yaw = yaw; self.pitch = pitch; self.roll = roll; self.rate = rate
    }
    public var finite: Bool { time.isFinite && yaw.isFinite && pitch.isFinite && roll.isFinite && rate?.finite != false }
}
