import SwiftUI
import ScrcpyCore

@MainActor final class KeyboardState: ObservableObject {
    @Published var modifiers: [String: Int] = [:]
    @Published var symbols = false
    func toggle(_ name: String) { modifiers[name] = modifiers[name,default:0] == 0 ? 1 : 0 }
    func lock(_ name: String) { modifiers[name] = modifiers[name] == 2 ? 0 : 2 }
    func reset() { modifiers = [:] }
    func consume() { for key in Array(modifiers.keys) where modifiers[key] == 1 { modifiers[key] = 0 } }
    var mask: UInt32 { var result: UInt32 = 0; for (name,flag) in [("Ctrl",UInt32(0x3000)),("Alt",0x12),("Shift",0x41),("Win",0x30000)] where modifiers[name,default:0] > 0 { result |= flag }; return result }
    var fn: Bool { modifiers["Fn",default:0] > 0 }
}

private struct KeyCap: View {
    let title: String
    var hint: String = ""
    var active = false, locked = false, height: CGFloat = 40
    var repeatable = false
    let action: (Int) -> Void
    var longPress: (() -> Void)?
    @State private var repeatTask: Task<Void,Never>?
    @State private var repeated = false
    @State private var pressed = false
    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 7).fill(active ? Color.mint.opacity(0.26) : Color.white.opacity(pressed ? 0.18 : 0.07))
            Text(title).font(.system(size: height < 33 ? 11 : 16,weight:.medium,design:.rounded)).minimumScaleFactor(0.6).lineLimit(1).frame(maxWidth:.infinity,maxHeight:.infinity)
            if !hint.isEmpty { Text(hint).font(.system(size:9)).foregroundStyle(.white.opacity(0.5)).padding(3) }
            if locked { Circle().fill(Color.mint).frame(width:4,height:4).padding(4) }
        }
        .frame(maxWidth:.infinity).frame(height:height).contentShape(Rectangle())
        .accessibilityElement(children:.ignore).accessibilityLabel(title).accessibilityIdentifier("key."+title).accessibilityAddTraits(.isButton).accessibilityAction { action(0) }
        .gesture(DragGesture(minimumDistance:0).onChanged { _ in
            guard !pressed else { return }; pressed = true; repeated = false
            if repeatable || longPress != nil {
                repeatTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds:450_000_000); guard !Task.isCancelled else { return }
                    repeated = true
                    if let longPress { longPress(); return }
                    while !Task.isCancelled { action(0); try? await Task.sleep(nanoseconds:70_000_000) }
                }
            }
        }.onEnded { value in
            repeatTask?.cancel(); repeatTask = nil; pressed = false
            if !repeated { action(value.translation.height < -16 ? -1 : value.translation.height > 16 ? 1 : 0) }
        })
        .onDisappear { repeatTask?.cancel() }
    }
}

struct VirtualKeyboard: View {
    @ObservedObject var model: AppModel
    @StateObject private var keys = KeyboardState()
    let showText: () -> Void
    var compact = false
    private var small: CGFloat { compact ? 26 : 28 }
    private var regular: CGFloat { compact ? 34 : 40 }
    private let upper: [Character: Character] = Dictionary(uniqueKeysWithValues: zip(Array("qwertyuiopasdfghjklzxcvbnm"),Array("1234567890!@#$%^&*()-_=+[]\\")))
    private func modifier(_ name: String, height: CGFloat) -> some View {
        KeyCap(title:name,active:keys.modifiers[name,default:0]>0,locked:keys.modifiers[name]==2,height:height,action:{ _ in keys.toggle(name) },longPress:{ keys.lock(name) })
    }
    private func key(_ title: String, _ code: UInt32, height: CGFloat? = nil, repeatable: Bool = false) -> some View {
        KeyCap(title:title,height:height ?? small,repeatable:repeatable,action:{ _ in model.key(code,meta:keys.mask); keys.consume() })
    }
    private func character(_ char: Character) -> some View {
        let label = keys.modifiers["Shift",default:0]>0 ? String(char).uppercased() : String(char)
        return KeyCap(title:label,hint:upper[char].map(String.init) ?? "",height:regular,action:{ direction in
            if keys.fn, let index = Array("qwertyuiop").firstIndex(of:char) { model.key(UInt32(131+index),meta:keys.mask); keys.consume(); return }
            let selected = direction < 0 ? upper[char] ?? char : direction > 0 ? Character(String(char).uppercased()) : char
            if let stroke = KeyStroke.character(selected) {
                var mask = keys.mask
                if direction < 0 { mask &= ~UInt32(0x41) }
                model.key(stroke.code,meta:mask | stroke.meta)
            } else { model.text(String(selected)) }
            keys.consume()
        })
    }
    var body: some View {
        VStack(spacing:5) {
            HStack(spacing:4) {
                key(keys.fn ? "Menu" : "Esc", keys.fn ? 82 : 111)
                modifier("Ctrl",height:small); key("Home",122); key("↑",19,repeatable:true); key("End",123); key("PgUp",92,repeatable:true)
                if keys.fn { key("F11",141) } else { KeyCap(title:L("文字","Text"),height:small,action:{ _ in keys.reset(); showText() }) }
                key("Del",112,repeatable:true)
            }
            HStack(spacing:4) {
                key(keys.fn ? "Ins" : "Tab",keys.fn ? 124 : 61)
                modifier("Alt",height:small); key("←",21,repeatable:true); key("↓",20,repeatable:true); key("→",22,repeatable:true); key("PgDn",93,repeatable:true)
                if keys.fn { key("F12",142) } else { KeyCap(title:L("粘贴","Paste"),height:small,action:{ _ in keys.reset(); model.paste() }) }
                modifier("Win",height:small)
            }
            HStack(spacing:4) { ForEach(Array((keys.symbols ? "1234567890" : "qwertyuiop").enumerated()),id:\.offset) { _,c in character(c) } }
            HStack(spacing:4) { ForEach(Array((keys.symbols ? "`-=[]\\;',/" : "asdfghjkl").enumerated()),id:\.offset) { _,c in character(c) } }.padding(.horizontal,keys.symbols ? 0 : 12)
            HStack(spacing:4) {
                modifier("Shift",height:regular)
                ForEach(Array((keys.symbols ? "\"<>|_+?" : "zxcvbnm").enumerated()),id:\.offset) { _,c in character(c) }
                key("⌫",67,height:regular,repeatable:true)
            }
            HStack(spacing:4) {
                KeyCap(title:keys.symbols ? "ABC" : "123",height:regular,action:{ _ in keys.symbols.toggle() }).frame(width:52)
                character(".").frame(width:40)
                KeyCap(title:L("空格","Space"),height:regular,action:{ _ in model.key(62,meta:keys.mask); keys.consume() })
                modifier("Fn",height:regular).frame(width:45)
                key("↵",66,height:regular,repeatable:true).frame(width:60)
            }
        }
        .padding(8).background(Color(red:0.065,green:0.10,blue:0.13)).clipShape(RoundedRectangle(cornerRadius:12))
        .onAppear { model.resetModifiers = { keys.reset() } }
        .onDisappear { keys.reset(); model.resetModifiers = nil }
    }
}
