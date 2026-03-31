import Foundation
import CoreGraphics

class InputInjector {
    private let layout: DisplayLayoutManager

    init(layout: DisplayLayoutManager) {
        self.layout = layout
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
            if let x = obj["x"] as? Double, let y = obj["y"] as? Double {
                let point = layout.absoluteToGlobal(relX: x, relY: y)
                tap(at: point)
            } else {
                let point = layout.currentCursorPosition()
                tap(at: point)
            }
        case "rightclick":
            if let x = obj["x"] as? Double, let y = obj["y"] as? Double {
                let point = layout.absoluteToGlobal(relX: x, relY: y)
                rightClick(at: point)
            } else {
                let point = layout.currentCursorPosition()
                rightClick(at: point)
            }
        case "move":
            if let dx = obj["dx"] as? Double, let dy = obj["dy"] as? Double {
                let point = layout.applyDelta(dx: dx, dy: dy)
                moveMouse(to: point)
            }
        case "drag":
            let phase = obj["phase"] as? String ?? "move"
            if let x = obj["x"] as? Double, let y = obj["y"] as? Double {
                let point = layout.absoluteToGlobal(relX: x, relY: y)
                drag(at: point, phase: phase)
            } else if let dx = obj["dx"] as? Double, let dy = obj["dy"] as? Double {
                let point = layout.applyDelta(dx: dx, dy: dy)
                drag(at: point, phase: phase)
            }
        case "scroll":
            let dx = Int32(obj["dx"] as? Double ?? 0)
            let dy = Int32(obj["dy"] as? Double ?? 0)
            if let x = obj["x"] as? Double, let y = obj["y"] as? Double {
                let point = layout.absoluteToGlobal(relX: x, relY: y)
                moveMouse(to: point)
            }
            scroll(dx: dx, dy: dy)
        case "pinch":
            let scale = obj["scale"] as? Double ?? 1.0
            if let x = obj["x"] as? Double, let y = obj["y"] as? Double {
                let point = layout.absoluteToGlobal(relX: x, relY: y)
                moveMouse(to: point)
            }
            pinchZoom(scale: scale)
        case "key":
            let modifiers = obj["modifiers"] as? [String] ?? []
            if let text = obj["text"] as? String {
                typeText(text, modifiers: modifiers)
            } else if let code = obj["code"] as? String {
                typeSpecialKey(code, modifiers: modifiers)
            }
        default:
            fputs("Unknown input type: \(type)\n", stderr)
        }
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

    private func scroll(dx: Int32, dy: Int32) {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)
        event?.post(tap: .cghidEventTap)
    }

    private func pinchZoom(scale: Double) {
        let dy = scale > 1.0 ? Int32(3) : Int32(-3)
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0)
        event?.flags = .maskCommand
        event?.post(tap: .cghidEventTap)
    }

    private func buildModifierFlags(_ modifiers: [String]) -> CGEventFlags {
        var flags = CGEventFlags()
        for mod in modifiers {
            switch mod {
            case "cmd": flags.insert(.maskCommand)
            case "ctrl": flags.insert(.maskControl)
            case "alt": flags.insert(.maskAlternate)
            case "shift": flags.insert(.maskShift)
            default: break
            }
        }
        return flags
    }

    private func typeText(_ text: String, modifiers: [String] = []) {
        let flags = buildModifierFlags(modifiers)
        for char in text {
            let str = String(char)
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
            if let event = event {
                let utf16 = Array(str.utf16)
                event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                if !flags.isEmpty { event.flags = flags }
                event.post(tap: .cghidEventTap)
            }
            let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            up?.post(tap: .cghidEventTap)
        }
    }

    private func typeSpecialKey(_ code: String, modifiers: [String] = []) {
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
        case "a": keyCode = 0
        case "c": keyCode = 8
        case "v": keyCode = 9
        case "x": keyCode = 7
        case "z": keyCode = 6
        case "s": keyCode = 1
        case "f": keyCode = 3
        default:
            fputs("Unknown key code: \(code)\n", stderr)
            return
        }
        let flags = buildModifierFlags(modifiers)
        let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        if !flags.isEmpty {
            down?.flags = flags
            up?.flags = flags
        }
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
