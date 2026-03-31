import Foundation
import CoreGraphics

class InputInjector {
    private let displayID: CGDirectDisplayID
    private let displayWidth: Int
    private let displayHeight: Int

    init(displayID: CGDirectDisplayID, width: Int, height: Int) {
        self.displayID = displayID
        self.displayWidth = width
        self.displayHeight = height
    }

    func handleInput(_ json: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else {
            fputs("Invalid input JSON: \(json)\n", stderr)
            return
        }

        switch type {
        case "tap":
            guard let point = extractPoint(obj) else { return }
            tap(at: point)
        case "rightclick":
            guard let point = extractPoint(obj) else { return }
            rightClick(at: point)
        case "drag":
            guard let point = extractPoint(obj),
                  let phase = obj["phase"] as? String else { return }
            drag(at: point, phase: phase)
        case "key":
            if let text = obj["text"] as? String {
                typeText(text)
            } else if let code = obj["code"] as? String {
                typeSpecialKey(code)
            }
        default:
            fputs("Unknown input type: \(type)\n", stderr)
        }
    }

    private func extractPoint(_ obj: [String: Any]) -> CGPoint? {
        guard let x = obj["x"] as? Double,
              let y = obj["y"] as? Double else { return nil }
        let absX = x * Double(displayWidth)
        let absY = y * Double(displayHeight)
        return CGPoint(x: absX, y: absY)
    }

    private func tap(at point: CGPoint) {
        moveMouse(to: point)
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func rightClick(at point: CGPoint) {
        moveMouse(to: point)
        let down = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right)
        let up = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func drag(at point: CGPoint, phase: String) {
        switch phase {
        case "start":
            moveMouse(to: point)
            let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
            down?.post(tap: .cghidEventTap)
        case "move":
            let drag = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left)
            drag?.post(tap: .cghidEventTap)
        case "end":
            let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
            up?.post(tap: .cghidEventTap)
        default:
            break
        }
    }

    private func moveMouse(to point: CGPoint) {
        let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        move?.post(tap: .cghidEventTap)
    }

    private func typeText(_ text: String) {
        for char in text {
            let str = String(char)
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
            if let event = event {
                let utf16 = Array(str.utf16)
                event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                event.post(tap: .cghidEventTap)
            }
            let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            up?.post(tap: .cghidEventTap)
        }
    }

    private func typeSpecialKey(_ code: String) {
        let keyCode: CGKeyCode
        switch code {
        case "enter": keyCode = 36
        case "tab": keyCode = 48
        case "escape": keyCode = 53
        case "backspace": keyCode = 51
        case "delete": keyCode = 117
        case "up": keyCode = 126
        case "down": keyCode = 125
        case "left": keyCode = 123
        case "right": keyCode = 124
        case "space": keyCode = 49
        default:
            fputs("Unknown key code: \(code)\n", stderr)
            return
        }
        let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
