import Foundation

/// Pure event planning allows side identity, pairing and modifier conflicts to be tested without posting events.
public struct KeyClickPlan: Equatable, Sendable {
    public struct Stroke: Equatable, Sendable {
        public let code: UInt16
        public let down: Bool
        public let flags: UInt64
        public let flagsChanged: Bool
    }
    public let strokes: [Stroke]
    public static func releaseFlags(owned: UInt64, current: UInt64, baseline: UInt64) -> UInt64 {
        var flags = (current & ~owned) | (baseline & (1<<16))
        let pairs: [(UInt64,UInt64)] = [(0x18,1<<20),(0x60,1<<19),(0x06,1<<17),(0x2001,1<<18)]
        for (device, generic) in pairs {
            if flags & device != 0 { flags |= generic }
        }
        return flags
    }
    public enum Failure: Error { case physicalModifierHeld, invalidKey }
    public static func make(_ key: Shortcut, physical: UInt64) throws -> Self {
        let conflict: UInt64 = (1<<17) | (1<<18) | (1<<19) | (1<<20) | (1<<23)
        guard physical & conflict == 0 else { throw Failure.physicalModifierHeld }
        guard key.keyCode <= 127, key.keyCode != 57 else { throw Failure.invalidKey }
        let cap: UInt64 = physical & (1<<16)
        let modifier = Shortcut.modifierKeyCodes.contains(key.keyCode)
        var flags = key.flags & (conflict | 0x207F | (1<<21))
        let sided: [UInt16:UInt64] = [54:(1<<20)|0x10,55:(1<<20)|0x08,56:(1<<17)|0x02,60:(1<<17)|0x04,58:(1<<19)|0x20,61:(1<<19)|0x40,59:(1<<18)|0x01,62:(1<<18)|0x2000]
        if let precise = sided[key.keyCode] { flags = precise }
        return Self(strokes:[Stroke(code:key.keyCode,down:true,flags:flags|cap,flagsChanged:modifier),Stroke(code:key.keyCode,down:false,flags:cap,flagsChanged:modifier)])
    }
}
