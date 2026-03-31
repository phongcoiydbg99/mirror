# Input Interaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor input handling to support locked (absolute) and unlocked (trackpad) modes, add scroll/pinch/modifier key support, and fix coordinate mapping for multi-monitor.

**Architecture:** Swift `InputInjector` gets a `DisplayLayoutManager` for coordinate mapping and new handlers for scroll, pinch, move, and modifier keys. Flutter client splits touch overlay into `AbsoluteTouchOverlay` and `TrackpadOverlay`, adds modifier key bar. Node.js `input.js` validates new message types.

**Tech Stack:** Swift (CGEvent, CoreGraphics display APIs), Dart/Flutter (gesture detection), Node.js (message validation)

---

## File Structure

### Server (Swift)
```
swift/Sources/MirrorCapture/
├── DisplayLayoutManager.swift  # NEW: query display bounds, listen for reconfig
├── InputInjector.swift         # MODIFY: add scroll, pinch, move, modifiers, coordinate mapping
└── main.swift                  # MODIFY: create DisplayLayoutManager, pass to InputInjector
```

### Node.js
```
src/input.js                    # MODIFY: validate new message types
test/input.test.js              # MODIFY: add tests for new types
```

### Flutter
```
app/lib/
├── services/input_service.dart     # MODIFY: add new InputMessage factories
├── widgets/
│   ├── touch_overlay.dart          # MODIFY: rename to AbsoluteTouchOverlay, add scroll/pinch
│   ├── trackpad_overlay.dart       # NEW: trackpad mode with delta movement
│   └── modifier_keys_bar.dart      # NEW: Cmd/Ctrl/Alt/Shift toggle buttons
├── screens/display_screen.dart     # MODIFY: toggle locked/unlocked, add modifier bar
└── screens/settings_screen.dart    # MODIFY: add trackpad sensitivity slider
app/test/input_service_test.dart    # MODIFY: add tests for new messages
```

---

### Task 1: Swift — DisplayLayoutManager

**Files:**
- Create: `swift/Sources/MirrorCapture/DisplayLayoutManager.swift`

- [ ] **Step 1: Create DisplayLayoutManager.swift**

Create `swift/Sources/MirrorCapture/DisplayLayoutManager.swift`:

```swift
import Foundation
import CoreGraphics

class DisplayLayoutManager {
    private(set) var virtualDisplayBounds: CGRect = .zero
    private(set) var totalDesktopBounds: CGRect = .zero
    private let virtualDisplayID: CGDirectDisplayID

    init(virtualDisplayID: CGDirectDisplayID) {
        self.virtualDisplayID = virtualDisplayID
        refreshLayout()
        registerForChanges()
    }

    func refreshLayout() {
        // Get virtual display bounds
        virtualDisplayBounds = CGDisplayBounds(virtualDisplayID)
        fputs("Display layout: virtual display \(virtualDisplayID) at \(virtualDisplayBounds)\n", stderr)

        // Calculate total desktop bounds (union of all displays)
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(16, &displayIDs, &displayCount)

        var total = CGRect.zero
        for i in 0..<Int(displayCount) {
            let bounds = CGDisplayBounds(displayIDs[i])
            total = total == .zero ? bounds : total.union(bounds)
            fputs("  Display \(displayIDs[i]): \(bounds)\n", stderr)
        }
        totalDesktopBounds = total
        fputs("  Total desktop: \(totalDesktopBounds)\n", stderr)
    }

    /// Convert relative (0-1) coordinate to global coordinate on virtual display
    func absoluteToGlobal(relX: Double, relY: Double) -> CGPoint {
        let x = virtualDisplayBounds.origin.x + relX * virtualDisplayBounds.width
        let y = virtualDisplayBounds.origin.y + relY * virtualDisplayBounds.height
        return clampToVirtualDisplay(CGPoint(x: x, y: y))
    }

    /// Apply delta to current cursor position, clamp to total desktop
    func applyDelta(dx: Double, dy: Double) -> CGPoint {
        let current = NSEvent.mouseLocation
        // NSEvent uses bottom-left origin, CGEvent uses top-left
        let screenHeight = totalDesktopBounds.height
        let currentY = screenHeight - current.y
        let newX = current.x + dx
        let newY = currentY + dy
        return clampToDesktop(CGPoint(x: newX, y: newY))
    }

    /// Get current cursor position in CGEvent coordinate space
    func currentCursorPosition() -> CGPoint {
        let current = NSEvent.mouseLocation
        let screenHeight = totalDesktopBounds.height
        return CGPoint(x: current.x, y: screenHeight - current.y)
    }

    /// Center of virtual display in global coordinates
    func virtualDisplayCenter() -> CGPoint {
        return CGPoint(
            x: virtualDisplayBounds.midX,
            y: virtualDisplayBounds.midY
        )
    }

    private func clampToVirtualDisplay(_ point: CGPoint) -> CGPoint {
        let x = max(virtualDisplayBounds.minX, min(virtualDisplayBounds.maxX - 1, point.x))
        let y = max(virtualDisplayBounds.minY, min(virtualDisplayBounds.maxY - 1, point.y))
        return CGPoint(x: x, y: y)
    }

    private func clampToDesktop(_ point: CGPoint) -> CGPoint {
        let x = max(totalDesktopBounds.minX, min(totalDesktopBounds.maxX - 1, point.x))
        let y = max(totalDesktopBounds.minY, min(totalDesktopBounds.maxY - 1, point.y))
        return CGPoint(x: x, y: y)
    }

    private func registerForChanges() {
        CGDisplayRegisterReconfigurationCallback({ _, _, userInfo in
            guard let userInfo = userInfo else { return }
            let manager = Unmanaged<DisplayLayoutManager>.fromOpaque(userInfo).takeUnretainedValue()
            fputs("Display reconfiguration detected, refreshing layout\n", stderr)
            manager.refreshLayout()
        }, Unmanaged.passUnretained(self).toOpaque())
    }
}
```

- [ ] **Step 2: Verify Swift builds**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror/swift && swift build 2>&1`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add swift/Sources/MirrorCapture/DisplayLayoutManager.swift
git commit -m "feat: DisplayLayoutManager for multi-monitor coordinate mapping"
```

---

### Task 2: Swift — Refactor InputInjector

**Files:**
- Modify: `swift/Sources/MirrorCapture/InputInjector.swift`

- [ ] **Step 1: Replace InputInjector.swift entirely**

Replace `swift/Sources/MirrorCapture/InputInjector.swift` with:

```swift
import Foundation
import CoreGraphics

class InputInjector {
    private let layout: DisplayLayoutManager
    private var modifierReleaseTimer: DispatchSourceTimer?

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
                // Locked mode: absolute
                let point = layout.absoluteToGlobal(relX: x, relY: y)
                tap(at: point)
            } else {
                // Unlocked mode: tap at current cursor
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

    // MARK: - Mouse actions

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

    // MARK: - Scroll & Pinch

    private func scroll(dx: Int32, dy: Int32) {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx)
        event?.post(tap: .cghidEventTap)
    }

    private func pinchZoom(scale: Double) {
        // Simulate Cmd+scroll for zoom (macOS trackpad zoom behavior)
        let dy = scale > 1.0 ? Int32(3) : Int32(-3)
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: dy)
        event?.flags = .maskCommand
        event?.post(tap: .cghidEventTap)
    }

    // MARK: - Keyboard

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
```

- [ ] **Step 2: Verify Swift builds**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror/swift && swift build 2>&1`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add swift/Sources/MirrorCapture/InputInjector.swift
git commit -m "feat: refactor InputInjector — dual mode, scroll, pinch, modifiers"
```

---

### Task 3: Swift — Wire DisplayLayoutManager into main.swift

**Files:**
- Modify: `swift/Sources/MirrorCapture/main.swift`

- [ ] **Step 1: Update main.swift**

Read the current `main.swift`. Find the line:
```swift
let inputInjector = InputInjector(displayID: captureDisplayID, width: config.width, height: config.height)
```

Replace with:
```swift
let displayLayout = DisplayLayoutManager(virtualDisplayID: captureDisplayID)
let inputInjector = InputInjector(layout: displayLayout)
```

- [ ] **Step 2: Verify Swift builds**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror/swift && swift build 2>&1`
Expected: Build succeeds

- [ ] **Step 3: Build release**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror/swift && swift build -c release 2>&1`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add swift/Sources/MirrorCapture/main.swift
git commit -m "feat: wire DisplayLayoutManager into main"
```

---

### Task 4: Node.js — Validate new message types

**Files:**
- Modify: `test/input.test.js`
- Modify: `src/input.js`

- [ ] **Step 1: Add tests for new message types**

Add to `test/input.test.js` in the `parseInputMessage` describe block:

```js
  it("parses move message", () => {
    const msg = '{"type":"move","dx":12.5,"dy":-8.0}';
    const result = parseInputMessage(msg);
    expect(result).toEqual({ type: "move", dx: 12.5, dy: -8.0 });
  });

  it("parses scroll message with position", () => {
    const msg = '{"type":"scroll","x":0.5,"y":0.3,"dx":0,"dy":-3.5}';
    const result = parseInputMessage(msg);
    expect(result).toEqual({ type: "scroll", x: 0.5, y: 0.3, dx: 0, dy: -3.5 });
  });

  it("parses scroll message without position", () => {
    const msg = '{"type":"scroll","dx":0,"dy":-3.5}';
    const result = parseInputMessage(msg);
    expect(result).toEqual({ type: "scroll", dx: 0, dy: -3.5 });
  });

  it("parses pinch message", () => {
    const msg = '{"type":"pinch","x":0.5,"y":0.3,"scale":1.2}';
    const result = parseInputMessage(msg);
    expect(result).toEqual({ type: "pinch", x: 0.5, y: 0.3, scale: 1.2 });
  });

  it("parses key with modifiers", () => {
    const msg = '{"type":"key","code":"c","modifiers":["cmd"]}';
    const result = parseInputMessage(msg);
    expect(result).toEqual({ type: "key", code: "c", modifiers: ["cmd"] });
  });

  it("parses tap without coordinates (unlocked mode)", () => {
    const msg = '{"type":"tap"}';
    const result = parseInputMessage(msg);
    expect(result).toEqual({ type: "tap" });
  });
```

- [ ] **Step 2: Run tests**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror && npx vitest run test/input.test.js`
Expected: All tests PASS (parseInputMessage already accepts any valid JSON with type field)

- [ ] **Step 3: Commit**

```bash
git add test/input.test.js
git commit -m "test: add tests for new input message types"
```

---

### Task 5: Flutter — Expand InputMessage + InputService

**Files:**
- Modify: `app/lib/services/input_service.dart`
- Modify: `app/test/input_service_test.dart`

- [ ] **Step 1: Add tests for new message types**

Add to `app/test/input_service_test.dart`:

```dart
    test('move serializes correctly', () {
      final msg = InputMessage.move(12.5, -8.0);
      expect(msg.toJson(), '{"type":"move","dx":12.5,"dy":-8.0}');
    });

    test('scroll with position serializes correctly', () {
      final msg = InputMessage.scrollAt(0.5, 0.3, 0, -3.5);
      expect(msg.toJson(), '{"type":"scroll","x":0.5,"y":0.3,"dx":0.0,"dy":-3.5}');
    });

    test('scroll without position serializes correctly', () {
      final msg = InputMessage.scroll(0, -3.5);
      expect(msg.toJson(), '{"type":"scroll","dx":0.0,"dy":-3.5}');
    });

    test('pinch serializes correctly', () {
      final msg = InputMessage.pinchAt(0.5, 0.3, 1.2);
      expect(msg.toJson(), '{"type":"pinch","x":0.5,"y":0.3,"scale":1.2}');
    });

    test('pinch without position serializes correctly', () {
      final msg = InputMessage.pinch(1.2);
      expect(msg.toJson(), '{"type":"pinch","scale":1.2}');
    });

    test('tap without coordinates serializes correctly', () {
      final msg = InputMessage.tapHere();
      expect(msg.toJson(), '{"type":"tap"}');
    });

    test('rightclick without coordinates serializes correctly', () {
      final msg = InputMessage.rightClickHere();
      expect(msg.toJson(), '{"type":"rightclick"}');
    });

    test('key with modifiers serializes correctly', () {
      final msg = InputMessage.keyWithModifiers('c', ['cmd']);
      expect(msg.toJson(), '{"type":"key","code":"c","modifiers":["cmd"]}');
    });

    test('drag with delta serializes correctly', () {
      final msg = InputMessage.dragDelta(5.0, -3.0, 'move');
      expect(msg.toJson(), '{"type":"drag","dx":5.0,"dy":-3.0,"phase":"move"}');
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror/app && flutter test test/input_service_test.dart`
Expected: FAIL — factory constructors not found

- [ ] **Step 3: Add new factories to InputMessage**

In `app/lib/services/input_service.dart`, add these factories to the `InputMessage` class:

```dart
  // Unlocked mode: tap at current cursor (no coordinates)
  factory InputMessage.tapHere() =>
      InputMessage._({'type': 'tap'});

  factory InputMessage.rightClickHere() =>
      InputMessage._({'type': 'rightclick'});

  // Trackpad move (delta)
  factory InputMessage.move(double dx, double dy) =>
      InputMessage._({'type': 'move', 'dx': dx, 'dy': dy});

  // Drag with delta (unlocked mode)
  factory InputMessage.dragDelta(double dx, double dy, String phase) =>
      InputMessage._({'type': 'drag', 'dx': dx, 'dy': dy, 'phase': phase});

  // Scroll at position (locked mode)
  factory InputMessage.scrollAt(double x, double y, double dx, double dy) =>
      InputMessage._({'type': 'scroll', 'x': x, 'y': y, 'dx': dx, 'dy': dy});

  // Scroll without position (unlocked mode)
  factory InputMessage.scroll(double dx, double dy) =>
      InputMessage._({'type': 'scroll', 'dx': dx, 'dy': dy});

  // Pinch at position (locked mode)
  factory InputMessage.pinchAt(double x, double y, double scale) =>
      InputMessage._({'type': 'pinch', 'x': x, 'y': y, 'scale': scale});

  // Pinch without position (unlocked mode)
  factory InputMessage.pinch(double scale) =>
      InputMessage._({'type': 'pinch', 'scale': scale});

  // Key with modifiers
  factory InputMessage.keyWithModifiers(String code, List<String> modifiers) =>
      InputMessage._({'type': 'key', 'code': code, 'modifiers': modifiers});
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror/app && flutter test test/input_service_test.dart`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/input_service.dart app/test/input_service_test.dart
git commit -m "feat: expand InputMessage with scroll, pinch, move, modifiers"
```

---

### Task 6: Flutter — AbsoluteTouchOverlay (refactor existing)

**Files:**
- Modify: `app/lib/widgets/touch_overlay.dart`

- [ ] **Step 1: Replace touch_overlay.dart**

Replace `app/lib/widgets/touch_overlay.dart` entirely:

```dart
import 'package:flutter/material.dart';
import '../services/input_service.dart';

class AbsoluteTouchOverlay extends StatefulWidget {
  final InputService inputService;
  final Widget child;

  const AbsoluteTouchOverlay({
    super.key,
    required this.inputService,
    required this.child,
  });

  @override
  State<AbsoluteTouchOverlay> createState() => _AbsoluteTouchOverlayState();
}

class _AbsoluteTouchOverlayState extends State<AbsoluteTouchOverlay> {
  bool _isDragging = false;
  int _pointerCount = 0;
  Offset? _lastScalePos;
  double _lastScale = 1.0;

  Offset _relativePosition(Offset globalPos, Size size) {
    final box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(globalPos);
    return Offset(
      (local.dx / size.width).clamp(0.0, 1.0),
      (local.dy / size.height).clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        return Listener(
          onPointerDown: (_) => _pointerCount++,
          onPointerUp: (_) => _pointerCount = (_pointerCount - 1).clamp(0, 10),
          onPointerCancel: (_) => _pointerCount = (_pointerCount - 1).clamp(0, 10),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,

            onTapUp: (details) {
              final rel = _relativePosition(details.globalPosition, size);
              widget.inputService.send(InputMessage.tap(rel.dx, rel.dy));
            },

            onLongPressStart: (details) {
              final rel = _relativePosition(details.globalPosition, size);
              widget.inputService.send(InputMessage.rightClick(rel.dx, rel.dy));
            },

            onPanStart: (details) {
              _isDragging = true;
              final rel = _relativePosition(details.globalPosition, size);
              widget.inputService.send(InputMessage.drag(rel.dx, rel.dy, 'start'));
            },

            onPanUpdate: (details) {
              if (_isDragging) {
                final rel = _relativePosition(details.globalPosition, size);
                widget.inputService.send(InputMessage.drag(rel.dx, rel.dy, 'move'));
              }
            },

            onPanEnd: (details) {
              if (_isDragging) {
                _isDragging = false;
                widget.inputService.send(InputMessage.drag(0, 0, 'end'));
              }
            },

            onScaleStart: (details) {
              _lastScalePos = details.focalPoint;
              _lastScale = 1.0;
            },

            onScaleUpdate: (details) {
              final rel = _relativePosition(details.focalPoint, size);

              // Pinch zoom
              if ((details.scale - _lastScale).abs() > 0.01) {
                widget.inputService.send(InputMessage.pinchAt(rel.dx, rel.dy, details.scale));
                _lastScale = details.scale;
              }

              // Two-finger scroll
              if (_pointerCount >= 2 && _lastScalePos != null) {
                final dy = (details.focalPoint.dy - _lastScalePos!.dy);
                final dx = (details.focalPoint.dx - _lastScalePos!.dx);
                if (dy.abs() > 1 || dx.abs() > 1) {
                  widget.inputService.send(InputMessage.scrollAt(rel.dx, rel.dy, dx, -dy));
                  _lastScalePos = details.focalPoint;
                }
              }
            },

            child: widget.child,
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 2: Update display_screen.dart import**

In `app/lib/screens/display_screen.dart`, change:
```dart
import '../widgets/touch_overlay.dart';
```
to:
```dart
import '../widgets/touch_overlay.dart';
import '../widgets/trackpad_overlay.dart';
```

And change `TouchOverlay` usage to `AbsoluteTouchOverlay` (we'll add the mode toggle in Task 9).

- [ ] **Step 3: Verify Flutter analyze**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror/app && flutter analyze 2>&1 | tail -5`

- [ ] **Step 4: Commit**

```bash
git add app/lib/widgets/touch_overlay.dart app/lib/screens/display_screen.dart
git commit -m "feat: refactor touch overlay — add scroll and pinch gestures"
```

---

### Task 7: Flutter — TrackpadOverlay

**Files:**
- Create: `app/lib/widgets/trackpad_overlay.dart`

- [ ] **Step 1: Create trackpad_overlay.dart**

Create `app/lib/widgets/trackpad_overlay.dart`:

```dart
import 'package:flutter/material.dart';
import '../services/input_service.dart';

class TrackpadOverlay extends StatefulWidget {
  final InputService inputService;
  final Widget child;
  final double sensitivity;

  const TrackpadOverlay({
    super.key,
    required this.inputService,
    required this.child,
    this.sensitivity = 1.5,
  });

  @override
  State<TrackpadOverlay> createState() => _TrackpadOverlayState();
}

class _TrackpadOverlayState extends State<TrackpadOverlay> {
  bool _isDragging = false;
  DateTime? _panStartTime;
  Offset? _panStartPos;
  double _totalPanDistance = 0;
  int _pointerCount = 0;
  Offset? _lastScalePos;
  double _lastScale = 1.0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _pointerCount++,
      onPointerUp: (_) => _pointerCount = (_pointerCount - 1).clamp(0, 10),
      onPointerCancel: (_) => _pointerCount = (_pointerCount - 1).clamp(0, 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,

        onLongPress: () {
          widget.inputService.send(InputMessage.rightClickHere());
        },

        onPanStart: (details) {
          _panStartTime = DateTime.now();
          _panStartPos = details.globalPosition;
          _totalPanDistance = 0;
        },

        onPanUpdate: (details) {
          _totalPanDistance += details.delta.distance;

          if (_pointerCount >= 2) {
            // Two-finger scroll
            widget.inputService.send(
              InputMessage.scroll(details.delta.dx, -details.delta.dy),
            );
          } else if (!_isDragging) {
            // One-finger: move cursor
            widget.inputService.send(
              InputMessage.move(
                details.delta.dx * widget.sensitivity,
                details.delta.dy * widget.sensitivity,
              ),
            );
          } else {
            // Dragging
            widget.inputService.send(
              InputMessage.dragDelta(
                details.delta.dx * widget.sensitivity,
                details.delta.dy * widget.sensitivity,
                'move',
              ),
            );
          }
        },

        onPanEnd: (details) {
          final duration = DateTime.now().difference(_panStartTime ?? DateTime.now());

          if (_isDragging) {
            // End drag
            _isDragging = false;
            widget.inputService.send(InputMessage.dragDelta(0, 0, 'end'));
          } else if (duration.inMilliseconds < 200 && _totalPanDistance < 10) {
            // Quick tap: click at current cursor
            widget.inputService.send(InputMessage.tapHere());
          }

          _panStartTime = null;
          _panStartPos = null;
        },

        onDoubleTap: () {
          // Double tap starts drag mode
          _isDragging = true;
          widget.inputService.send(InputMessage.dragDelta(0, 0, 'start'));
        },

        onScaleStart: (details) {
          _lastScalePos = details.focalPoint;
          _lastScale = 1.0;
        },

        onScaleUpdate: (details) {
          if ((details.scale - _lastScale).abs() > 0.01 && details.scale != 1.0) {
            widget.inputService.send(InputMessage.pinch(details.scale));
            _lastScale = details.scale;
          }
        },

        child: widget.child,
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/widgets/trackpad_overlay.dart
git commit -m "feat: trackpad overlay — relative cursor movement for unlocked mode"
```

---

### Task 8: Flutter — Modifier Keys Bar

**Files:**
- Create: `app/lib/widgets/modifier_keys_bar.dart`

- [ ] **Step 1: Create modifier_keys_bar.dart**

Create `app/lib/widgets/modifier_keys_bar.dart`:

```dart
import 'package:flutter/material.dart';

class ModifierKeysBar extends StatefulWidget {
  final void Function(List<String> activeModifiers) onModifiersChanged;

  const ModifierKeysBar({super.key, required this.onModifiersChanged});

  @override
  State<ModifierKeysBar> createState() => ModifierKeysBarState();
}

class ModifierKeysBarState extends State<ModifierKeysBar> {
  final Set<String> _active = {};

  List<String> get activeModifiers => _active.toList();

  void clearAll() {
    setState(() => _active.clear());
    widget.onModifiersChanged([]);
  }

  void _toggle(String mod) {
    setState(() {
      if (_active.contains(mod)) {
        _active.remove(mod);
      } else {
        _active.add(mod);
      }
    });
    widget.onModifiersChanged(_active.toList());
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildKey('Cmd', 'cmd'),
        _buildKey('Ctrl', 'ctrl'),
        _buildKey('Alt', 'alt'),
        _buildKey('Shift', 'shift'),
      ],
    );
  }

  Widget _buildKey(String label, String mod) {
    final isActive = _active.contains(mod);
    return GestureDetector(
      onTap: () => _toggle(mod),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue : Colors.grey[800],
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.grey[400],
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/widgets/modifier_keys_bar.dart
git commit -m "feat: modifier keys bar — Cmd/Ctrl/Alt/Shift toggles"
```

---

### Task 9: Flutter — Display screen integration

**Files:**
- Modify: `app/lib/screens/display_screen.dart`

- [ ] **Step 1: Update display_screen.dart**

Read the current file, then make these changes:

1. Add imports at top:
```dart
import '../widgets/trackpad_overlay.dart';
import '../widgets/modifier_keys_bar.dart';
```

2. Add state variables after `_showKeyboard`:
```dart
  bool _unlocked = false;
  List<String> _activeModifiers = [];
  final _modifierBarKey = GlobalKey<ModifierKeysBarState>();
```

3. Replace the `TouchOverlay` (or `AbsoluteTouchOverlay`) in the Stack with:
```dart
          // Stream + touch overlay (switches based on mode)
          _unlocked
              ? TrackpadOverlay(
                  inputService: cs.inputService,
                  sensitivity: 1.5,
                  child: MjpegViewer(
                    streamUrl: cs.streamUrl,
                    onError: _onStreamError,
                    fit: BoxFit.contain,
                  ),
                )
              : AbsoluteTouchOverlay(
                  inputService: cs.inputService,
                  child: MjpegViewer(
                    streamUrl: cs.streamUrl,
                    onError: _onStreamError,
                    fit: BoxFit.contain,
                  ),
                ),
```

4. In the toolbar Row, add lock/unlock button:
```dart
                      IconButton(
                        icon: Icon(
                          _unlocked ? Icons.lock_open : Icons.lock,
                          color: _unlocked ? Colors.blue : Colors.white,
                        ),
                        onPressed: () {
                          setState(() => _unlocked = !_unlocked);
                        },
                      ),
```

5. In the keyboard section, add modifier keys bar above the text field:
```dart
          if (_showKeyboard)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black87,
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ModifierKeysBar(
                      key: _modifierBarKey,
                      onModifiersChanged: (mods) {
                        setState(() => _activeModifiers = mods);
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _textController,
                            focusNode: _focusNode,
                            autofocus: true,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: 'Type here...',
                              hintStyle: TextStyle(color: Colors.grey),
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (text) {
                              if (text.isNotEmpty) {
                                if (_activeModifiers.isNotEmpty) {
                                  cs.inputService.send(
                                    InputMessage.keyWithModifiers(text, _activeModifiers),
                                  );
                                  _modifierBarKey.currentState?.clearAll();
                                } else {
                                  cs.inputService.send(InputMessage.keyText(text));
                                }
                                _textController.clear();
                              }
                            },
                            onSubmitted: (_) {
                              cs.inputService.send(InputMessage.keyCode('enter'));
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.backspace, color: Colors.white),
                          onPressed: () {
                            cs.inputService.send(InputMessage.keyCode('backspace'));
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
```

- [ ] **Step 2: Verify Flutter analyze**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror/app && flutter analyze 2>&1 | tail -5`

- [ ] **Step 3: Commit**

```bash
git add app/lib/screens/display_screen.dart
git commit -m "feat: integrate locked/unlocked toggle, modifier keys in display screen"
```

---

### Task 10: Flutter — Settings sensitivity slider

**Files:**
- Modify: `app/lib/screens/settings_screen.dart`

- [ ] **Step 1: Add sensitivity slider to settings_screen.dart**

Read the current file, then add after the quality ListTile:

```dart
          const Divider(),
          ListTile(
            title: const Text('Trackpad Sensitivity'),
            subtitle: Text('${_sensitivity.toStringAsFixed(1)}x'),
            trailing: SizedBox(
              width: 150,
              child: Slider(
                value: _sensitivity,
                min: 1.0,
                max: 3.0,
                divisions: 4,
                label: '${_sensitivity.toStringAsFixed(1)}x',
                onChanged: (v) {
                  setState(() => _sensitivity = v);
                },
              ),
            ),
          ),
```

Add state variable: `double _sensitivity = 1.5;`

- [ ] **Step 2: Commit**

```bash
git add app/lib/screens/settings_screen.dart
git commit -m "feat: add trackpad sensitivity slider to settings"
```

---

### Task 11: Integration — Build & verify

- [ ] **Step 1: Build Swift release**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror/swift && swift build -c release 2>&1`
Expected: Build succeeds

- [ ] **Step 2: Run Node.js tests**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror && npx vitest run`
Expected: All tests pass

- [ ] **Step 3: Run Flutter tests**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror/app && flutter test`
Expected: All tests pass

- [ ] **Step 4: Flutter analyze**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror/app && flutter analyze`
Expected: No errors

---

## Summary

| Task | Component | Tests |
|------|-----------|-------|
| 1 | Swift: DisplayLayoutManager | Manual |
| 2 | Swift: Refactor InputInjector | Manual |
| 3 | Swift: Wire into main.swift | Manual |
| 4 | Node.js: Validate new message types | 6 new tests |
| 5 | Flutter: Expand InputMessage | 9 new tests |
| 6 | Flutter: AbsoluteTouchOverlay (refactor) | Manual |
| 7 | Flutter: TrackpadOverlay | Manual |
| 8 | Flutter: ModifierKeysBar | Manual |
| 9 | Flutter: Display screen integration | Manual |
| 10 | Flutter: Settings sensitivity slider | Manual |
| 11 | Integration build & verify | All tests |
