import SwiftUI
import ScrcpyCore

struct RemoteCanvas: UIViewRepresentable {
    @ObservedObject var model: AppModel
    func makeUIView(context: Context) -> CanvasView { let view = CanvasView(model: model); model.cancelInput = { [weak view] in view?.cancelAll() }; return view }
    func updateUIView(_ view: CanvasView, context: Context) { view.width = model.videoWidth; view.height = model.videoHeight; view.accessibilityValue = "\(view.width)x\(view.height)"; view.setNeedsLayout() }
    static func dismantleUIView(_ view: CanvasView, coordinator: ()) { view.cancelAll() }
}

final class CanvasView: UIView, UIKeyInput {
    private weak var model: AppModel?
    private let display: VideoRenderer
    var width: Int, height: Int
    private struct Finger { var id: UInt64; var start: CGPoint; var point: CGPoint; var edge: Int?; var sent = false; var handled = false }
    private var fingers: [ObjectIdentifier: Finger] = [:], nextID: UInt64 = 0
    private let emptyKeyboard = UIView(frame: .zero)
    override var inputView: UIView? { emptyKeyboard }
    override var canBecomeFirstResponder: Bool { true }
    var hasText: Bool { true }
    init(model: AppModel) { self.model = model; display = model.renderer; width = model.videoWidth; height = model.videoHeight; super.init(frame: .zero); backgroundColor = .black; isMultipleTouchEnabled = true; layer.addSublayer(display.layer); accessibilityIdentifier = "remoteSurface"; isAccessibilityElement = true; accessibilityLabel = L("远控屏幕", "Remote screen") }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); CATransaction.begin(); CATransaction.setDisableActions(true); display.layer.frame = bounds; CATransaction.commit() }
    private var picture: CGRect {
        let scale = min(bounds.width / CGFloat(max(width,1)), bounds.height / CGFloat(max(height,1)))
        return CGRect(x: (bounds.width - CGFloat(width) * scale) / 2, y: (bounds.height - CGFloat(height) * scale) / 2, width: CGFloat(width) * scale, height: CGFloat(height) * scale)
    }
    private func emit(_ action: UInt8, _ finger: Finger, point: CGPoint? = nil) {
        let p = point ?? finger.point, frame = picture; guard frame.width > 0 && frame.height > 0 else { return }
        let x = min(width - 1, max(0, Int((p.x - frame.minX) * CGFloat(width) / frame.width)))
        let y = min(height - 1, max(0, Int((p.y - frame.minY) * CGFloat(height) / frame.height)))
        model?.touch(action, pointer: finger.id, x: x, y: y, pressure: action == 1 ? 0 : 1)
    }
    private func edge(_ point: CGPoint) -> Int? {
        let frame = picture
        let distances = [abs(point.x-frame.minX),abs(point.x-frame.maxX),abs(point.y-frame.maxY),abs(point.y-frame.minY)]
        let candidates = [point.x <= frame.minX+28, point.x >= frame.maxX-28, point.y >= frame.maxY-28, point.y <= frame.minY+28]
        return (0..<4).filter { candidates[$0] }.min { distances[$0] < distances[$1] }
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        becomeFirstResponder()
        for touch in touches {
            let point = touch.location(in: self); var finger = Finger(id: nextID, start: point, point: point, edge: edge(point)); nextID &+= 1
            if !fingers.isEmpty {
                for (id, var other) in fingers where !other.handled { if !other.sent && picture.contains(other.start) { emit(0,other,point:other.start); other.sent = true }; other.edge = nil; fingers[id] = other }
                finger.edge = nil
            }
            if finger.edge == nil && picture.contains(point) { emit(0,finger); finger.sent = true }
            fingers[ObjectIdentifier(touch)] = finger
        }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch); guard var finger = fingers[id], !finger.handled else { continue }; finger.point = touch.location(in: self)
            if let edge = finger.edge {
                let dx = finger.point.x - finger.start.x, dy = finger.point.y - finger.start.y, frame = picture
                let inward = [dx, -dx, -dy, dy][edge], cross = edge < 2 ? abs(dy) : abs(dx)
                let crossed = [finger.point.x >= frame.minX+10, finger.point.x <= frame.maxX-10, finger.point.y <= frame.maxY-10, finger.point.y >= frame.minY+10][edge]
                if inward >= 22 && inward > cross * 1.15 && crossed {
                    if finger.sent { emit(1,finger) }; finger.handled = true; model?.navigate(edge)
                } else if hypot(dx,dy) > 14 && (inward < 0 || cross > max(inward,1) * 1.5) {
                    finger.edge = nil
                    if picture.contains(finger.start) { emit(0,finger,point:finger.start); finger.sent = true }
                }
            }
            if finger.sent && !finger.handled { emit(2,finger) }; fingers[id] = finger
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard var finger = fingers.removeValue(forKey: ObjectIdentifier(touch)), !finger.handled else { continue }; finger.point = touch.location(in: self)
            if !finger.sent && picture.contains(finger.start) { emit(0,finger,point:finger.start); finger.sent = true }
            if finger.sent { emit(1,finger) }
        }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { cancelAll() }
    func cancelAll() { let active = fingers.values; fingers.removeAll(); for finger in active where finger.sent && !finger.handled { emit(1,finger) } }
    func insertText(_ text: String) { for char in text { if let stroke = KeyStroke.character(char) { model?.key(stroke.code,meta:stroke.meta) } else { model?.text(String(char)) } } }
    func deleteBackward() { model?.key(67) }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }; let hid = Int(key.keyCode.rawValue)
            var code: UInt32?
            if (4...29).contains(hid) { code = UInt32(29+hid-4) }
            else if (30...38).contains(hid) { code = UInt32(8+hid-30) }
            else if (58...69).contains(hid) { code = UInt32(131+hid-58) }
            else { code = [39:7,40:66,41:111,42:67,43:61,44:62,45:69,46:70,47:71,48:72,49:73,51:74,52:75,53:68,54:55,55:56,56:76,74:122,75:92,76:112,77:123,78:93,79:22,80:21,81:20,82:19][hid].map(UInt32.init) }
            if let code {
                var meta: UInt32 = 0
                if key.modifierFlags.contains(.control) { meta |= 0x3000 }; if key.modifierFlags.contains(.alternate) { meta |= 0x12 }; if key.modifierFlags.contains(.shift) { meta |= 0x41 }; if key.modifierFlags.contains(.command) { meta |= 0x30000 }
                model?.key(code,meta:meta); handled = true
            }
        }
        if !handled { super.pressesBegan(presses,with:event) }
    }
}
