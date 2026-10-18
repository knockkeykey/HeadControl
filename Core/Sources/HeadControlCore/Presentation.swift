import Foundation

/// Headphone link as the UI should explain it; the motion service is the only writer.
public enum HeadphoneLink: Equatable, Sendable {
    case idle
    case unavailable
    case permissionDenied
    case waiting
    case tracking
    case interrupted(String)

    public enum Tone: Sendable { case off, warning, connected }
    public var tone: Tone {
        switch self {
        case .idle, .waiting: .off
        case .unavailable, .permissionDenied, .interrupted: .warning
        case .tracking: .connected
        }
    }
    public var title: String {
        switch self {
        case .idle: "未连接耳机"
        case .unavailable: "未发现支持的耳机"
        case .permissionDenied: "缺少运动与健身权限"
        case .waiting: "等待耳机数据…"
        case .tracking: "耳机已连接"
        case .interrupted: "耳机连接中断"
        }
    }
    public var detail: String {
        switch self {
        case .idle: "戴上 AirPods Pro 并连接到这台 Mac"
        case .unavailable: "需要 AirPods Pro、AirPods Max 等支持头部追踪的耳机"
        case .permissionDenied: "到“权限”页允许运动与健身"
        case .waiting: "戴上耳机后会自动开始"
        case .tracking: "正在接收头部动作"
        case .interrupted(let reason): reason
        }
    }
}

/// Gesture-level helpers for visual feedback; pure so the meter and test flow agree with the recognizer.
public extension Gesture {
    /// Movement toward this gesture in degrees; positive means the intended direction.
    func travel(_ s: MotionSample) -> Double {
        switch self {
        case .tiltLeft: -s.roll
        case .tiltRight: s.roll
        case .turnLeft: -s.yaw
        case .turnRight: s.yaw
        case .nod: -s.pitch
        case .shake: abs(s.yaw)
        }
    }
    var prompt: String {
        switch self {
        case .tiltLeft: "把头向左肩歪，停一下"
        case .tiltRight: "把头向右肩歪，停一下"
        case .turnLeft: "向左转头，停一下"
        case .turnRight: "向右转头，停一下"
        case .nod: "低头再抬起，点一下头"
        case .shake: "左右摇一下头，再回正"
        }
    }
    var shortTitle: String {
        switch self { case .tiltLeft: "左歪"; case .tiltRight: "右歪"; case .turnLeft: "左转"; case .turnRight: "右转"; case .nod: "点头"; case .shake: "摇头" }
    }
}

public enum ThresholdAdvisor {
    /// Suggest ~70% of the user's measured peak so the gesture fires reliably without full effort.
    public static func suggest(peak: Double, tuning: GestureTuning) -> Double? {
        guard peak.isFinite, peak > 0 else { return nil }
        let lower = max(8, tuning.neutral + 1)
        return min(50, max(lower, (peak * 0.7).rounded()))
    }
}

/// Key naming shared by the recorder, the virtual keyboard and keycap rendering.
public enum KeyNames {
    public static let names: [UInt16: String] = [
        0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",
        18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"-",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",
        34:"I",35:"P",36:"↩",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",48:"⇥",49:"空格",
        50:"`",51:"⌫",53:"Esc",96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",103:"F11",109:"F10",111:"F12",
        114:"Help",115:"Home",116:"PgUp",117:"⌦",118:"F4",119:"End",120:"F2",121:"PgDn",122:"F1",123:"←",124:"→",125:"↓",126:"↑",
        105:"F13",107:"F14",113:"F15",106:"F16",64:"F17",79:"F18",80:"F19",90:"F20",
    ]
    public static let modifierNames: [UInt16: String] = [54:"右 ⌘",55:"左 ⌘",56:"左 ⇧",60:"右 ⇧",58:"左 ⌥",61:"右 ⌥",59:"左 ⌃",62:"右 ⌃"]
    /// Device-specific side bit plus generic mask, matching CGEventFlags.
    public static let modifierFlags: [UInt16: UInt64] = [54:(1<<20)|0x10,55:(1<<20)|0x08,56:(1<<17)|0x02,60:(1<<17)|0x04,58:(1<<19)|0x20,61:(1<<19)|0x40,59:(1<<18)|0x01,62:(1<<18)|0x2000]

    public static func name(_ code: UInt16) -> String { modifierNames[code] ?? names[code] ?? "键 \(code)" }

    /// Visible keycaps in ⌃⌥⇧⌘ order followed by the main key.
    public static func caps(keyCode: UInt16, flags: UInt64) -> [String] {
        if let single = modifierNames[keyCode] { return [single] }
        var caps: [String] = []
        for (mask, symbol) in [(UInt64(1<<18),"⌃"),(1<<19,"⌥"),(1<<17,"⇧"),(1<<20,"⌘")] where flags & mask != 0 { caps.append(symbol) }
        caps.append(name(keyCode))
        return caps
    }
    public static func label(keyCode: UInt16, flags: UInt64) -> String {
        let caps = caps(keyCode: keyCode, flags: flags)
        return caps.count == 1 ? caps[0] : caps.joined()
    }
    /// Shortcut from a main key plus held modifier key codes (virtual keyboard clicks).
    public static func shortcut(key: UInt16, modifiers: Set<UInt16>) -> Shortcut {
        if modifierNames[key] != nil && modifiers.subtracting([key]).isEmpty {
            return Shortcut(keyCode: key, flags: modifierFlags[key] ?? 0, label: name(key))
        }
        let flags = modifiers.subtracting([key]).reduce(UInt64(0)) { $0 | (modifierFlags[$1] ?? 0) }
        return Shortcut(keyCode: key, flags: flags, label: label(keyCode: key, flags: flags))
    }
}

public extension Shortcut {
    var caps: [String] { KeyNames.caps(keyCode: keyCode, flags: flags) }
}
