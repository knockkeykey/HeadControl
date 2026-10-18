import SwiftUI
import AppKit

/// MacBook ANSI layout in key units; nil codes are drawn but cannot be recorded.
struct KeyDef: Identifiable {
    let id = UUID()
    let code: UInt16?
    let label: String
    var width: CGFloat = 1
    var sub: String? = nil
}

enum MacKeyboard {
    static let functionRow: [KeyDef] = [KeyDef(code: 53, label: "esc", width: 1.5)]
        + zip([122,120,99,118,96,97,98,100,101,109,103,111] as [UInt16], 1...12).map { KeyDef(code: $0, label: "F\($1)") }
        + [KeyDef(code: nil, label: "", width: 1.5, sub: "touchid")]
    static let rows: [[KeyDef]] = [
        [("`",50),("1",18),("2",19),("3",20),("4",21),("5",23),("6",22),("7",26),("8",28),("9",25),("0",29),("-",27),("=",24)].map { KeyDef(code: $1, label: $0) }
            + [KeyDef(code: 51, label: "⌫", width: 2, sub: "delete")],
        [KeyDef(code: 48, label: "⇥", width: 1.5, sub: "tab")]
            + [("Q",12),("W",13),("E",14),("R",15),("T",17),("Y",16),("U",32),("I",34),("O",31),("P",35),("[",33),("]",30)].map { KeyDef(code: $1, label: $0) }
            + [KeyDef(code: 42, label: "\\", width: 1.5)],
        [KeyDef(code: nil, label: "⇪", width: 1.75, sub: "caps lock")]
            + [("A",0),("S",1),("D",2),("F",3),("G",5),("H",4),("J",38),("K",40),("L",37),(";",41),("'",39)].map { KeyDef(code: $1, label: $0) }
            + [KeyDef(code: 36, label: "↩", width: 2.25, sub: "return")],
        [KeyDef(code: 56, label: "⇧", width: 2.25, sub: "shift")]
            + [("Z",6),("X",7),("C",8),("V",9),("B",11),("N",45),("M",46),(",",43),(".",47),("/",44)].map { KeyDef(code: $1, label: $0) }
            + [KeyDef(code: 60, label: "⇧", width: 2.75, sub: "shift")],
    ]
    static let bottomRow: [KeyDef] = [
        KeyDef(code: nil, label: "fn", sub: "🌐"), KeyDef(code: 59, label: "⌃", sub: "control"), KeyDef(code: 58, label: "⌥", sub: "option"),
        KeyDef(code: 55, label: "⌘", width: 1.25, sub: "command"), KeyDef(code: 49, label: "", width: 5.5, sub: "空格"),
        KeyDef(code: 54, label: "⌘", width: 1.25, sub: "command"), KeyDef(code: 61, label: "⌥", sub: "option"),
    ]
}

/// Visual keyboard: lights keys held on the real keyboard and accepts clicks.
struct VirtualKeyboard: View {
    let lit: Set<UInt16>
    let tap: (UInt16) -> Void
    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = max(3, geo.size.width / 220)
            let unit = (geo.size.width - gap * 18) / 15
            VStack(spacing: gap) {
                row(MacKeyboard.functionRow, unit: unit, gap: gap, height: unit * 0.62)
                ForEach(0..<MacKeyboard.rows.count, id: \.self) { row(MacKeyboard.rows[$0], unit: unit, gap: gap, height: unit) }
                HStack(spacing: gap) {
                    ForEach(MacKeyboard.bottomRow) { key(def: $0, unit: unit, gap: gap, height: unit) }
                    // Inverted-T arrows, as on a MacBook.
                    HStack(alignment: .bottom, spacing: gap) {
                        key(def: KeyDef(code: 123, label: "←"), unit: unit, gap: gap, height: (unit - gap) / 2)
                        VStack(spacing: gap) {
                            key(def: KeyDef(code: 126, label: "↑"), unit: unit, gap: gap, height: (unit - gap) / 2)
                            key(def: KeyDef(code: 125, label: "↓"), unit: unit, gap: gap, height: (unit - gap) / 2)
                        }
                        key(def: KeyDef(code: 124, label: "→"), unit: unit, gap: gap, height: (unit - gap) / 2)
                    }.frame(height: unit, alignment: .bottom)
                }
            }
            .padding(gap * 2)
            .background(RoundedRectangle(cornerRadius: unit * 0.35, style: .continuous).fill(Color.primary.opacity(0.06)))
        }
        .aspectRatio(15 / 6.0, contentMode: .fit)
    }
    private func row(_ keys: [KeyDef], unit: CGFloat, gap: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: gap) { ForEach(keys) { key(def: $0, unit: unit, gap: gap, height: height) } }
    }
    private func key(def: KeyDef, unit: CGFloat, gap: CGFloat, height: CGFloat) -> some View {
        let on = def.code.map(lit.contains) ?? false
        let enabled = def.code != nil
        let width = unit * def.width + gap * (def.width - 1)
        return Button { if let code = def.code { tap(code) } } label: {
            ZStack {
                RoundedRectangle(cornerRadius: unit * 0.16, style: .continuous)
                    .fill(on ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(on ? 0 : 0.22), radius: 0, y: on ? 0 : 1)
                if def.sub == "touchid" {
                    Circle().strokeBorder(Color.secondary.opacity(0.4)).padding(height * 0.2)
                } else {
                    VStack(spacing: 0) {
                        if !def.label.isEmpty { Text(def.label).font(.system(size: max(8, min(unit, height) * 0.36), weight: .medium)) }
                        if let sub = def.sub, def.width > 1 || def.label.count == 1 && def.code.map(Shortcut.modifierKeyCodes.contains) == true || def.label.isEmpty {
                            Text(sub).font(.system(size: max(7, unit * 0.17))).opacity(0.7)
                        }
                    }.foregroundStyle(on ? Color.white : Color.primary)
                }
            }
            .frame(width: width, height: height)
            .offset(y: on ? 1 : 0)
            .animation(.spring(duration: 0.12), value: on)
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(def.code.map { KeyNames.name($0) } ?? def.label)
    }
}

/// Inline recorder: press real keys or click the drawn ones.
struct ShortcutRecorderPanel: View {
    let gesture: Gesture
    let save: (Shortcut) -> Void
    let cancel: () -> Void
    @State private var held: Set<UInt16> = []
    @State private var latched: Set<UInt16> = []
    @State private var captured: Shortcut?
    private var preview: [String] {
        if let captured { return captured.caps }
        let mods = held.union(latched).filter { Shortcut.modifierKeyCodes.contains($0) }
        let order: [UInt16] = [59, 62, 58, 61, 56, 60, 55, 54]
        return order.filter(mods.contains).map { KeyNames.name($0) }
    }
    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                GestureGlyph(gesture: gesture, size: 18).foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36).background(Color.accentColor.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("为「\(gesture.title)」设置快捷键").font(.headline)
                    Text("在键盘上按下组合键，或点按下方的键。按 Esc 取消。").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if captured == nil, latched.count == 1, let only = latched.first {
                    Button("仅用 \(KeyNames.name(only))") { finish(KeyNames.shortcut(key: only, modifiers: [only])) }
                }
                Button("取消", action: cancel).keyboardShortcut(.cancelAction)
            }
            // Large, centered "field" like the macOS Keyboard Shortcuts recorder.
            ZStack {
                if preview.isEmpty {
                    Label("正在等待按键…", systemImage: "keyboard").foregroundStyle(.secondary)
                        .symbolEffect(.pulse, isActive: captured == nil)
                } else {
                    KeycapRow(caps: preview, size: 16, pressed: captured == nil)
                }
                if captured != nil {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
                        .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 14).transition(.scale)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor.opacity(captured == nil ? 0.5 : 0), lineWidth: 1.5))
            .animation(.spring(duration: 0.25), value: captured)
            VirtualKeyboard(lit: held.union(latched).union(captured.map { [$0.keyCode] } ?? [])) { code in
                if Shortcut.modifierKeyCodes.contains(code) {
                    if latched.contains(code) { latched.remove(code) } else { latched.insert(code) }
                } else { finish(KeyNames.shortcut(key: code, modifiers: latched)) }
            }
            .background(KeyCapture(held: $held, received: finish, cancelled: cancel))
        }
    }
    private func finish(_ shortcut: Shortcut) {
        captured = shortcut
        Task { @MainActor in try? await Task.sleep(for: .milliseconds(420)); save(shortcut) }
    }
}

private struct KeyCapture: NSViewRepresentable {
    @Binding var held: Set<UInt16>
    let received: (Shortcut) -> Void
    let cancelled: () -> Void
    func makeNSView(context: Context) -> CaptureView { let v = CaptureView(); update(v); return v }
    func updateNSView(_ view: CaptureView, context: Context) { update(view) }
    private func update(_ v: CaptureView) {
        v.received = received; v.cancelled = cancelled
        v.changed = { codes in DispatchQueue.main.async { held = codes } }
    }
}

private final class CaptureView: NSView {
    var received: ((Shortcut) -> Void)?
    var cancelled: (() -> Void)?
    var changed: ((Set<UInt16>) -> Void)?
    private var held: Set<UInt16> = [] { didSet { changed?(held) } }
    private var pending: UInt16?
    private var done = false
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); DispatchQueue.main.async { [weak self] in self?.window?.makeFirstResponder(self) }
    }
    // ⌘-combinations arrive as key equivalents; swallow them so menus don't act while recording.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.type == .keyDown else { return false }
        keyDown(with: event); return true
    }
    override func keyDown(with event: NSEvent) {
        guard !done, !event.isARepeat else { return }
        if event.keyCode == 53 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.function, .numericPad]).isEmpty {
            done = true; cancelled?(); return
        }
        held.insert(event.keyCode); pending = nil
        let flags = UInt64(event.modifierFlags.rawValue)
        done = true
        received?(Shortcut(keyCode: event.keyCode, flags: flags, label: KeyNames.label(keyCode: event.keyCode, flags: flags)))
    }
    override func keyUp(with event: NSEvent) { held.remove(event.keyCode) }
    override func flagsChanged(with event: NSEvent) {
        let code = event.keyCode
        guard !done, let bits = KeyNames.modifierFlags[code] else { return }
        let down = UInt64(event.modifierFlags.rawValue) & bits & 0x207F != 0
        if down {
            pending = held.isEmpty ? code : nil
            held.insert(code)
        } else {
            held.remove(code)
            if pending == code {
                pending = nil; done = true
                received?(Shortcut(keyCode: code, flags: bits, label: KeyNames.name(code)))
            }
        }
    }
}
