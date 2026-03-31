# Mirror — Input Interaction Design

## Overview

Refactor input handling to support two modes: Locked (absolute touch on virtual display, free tier) and Unlocked (trackpad mode for full desktop control, premium). Add scroll, pinch zoom, and modifier key support. Fix coordinate mapping for multi-monitor setups.

## Input Modes

### Locked Mode (Free) — Absolute Touch
- Touch position maps directly to virtual display coordinates
- Coordinate conversion: relative (0-1) → pixel on virtual display → global coordinate (+ display offset)
- Cursor is clamped within virtual display bounds — never leaves
- Gestures: tap (left click), long press (right click), drag, two-finger scroll, pinch zoom

### Unlocked Mode (Premium) — Trackpad
- Finger movement sends delta (dx, dy) to move cursor relatively from current position
- Tap = click at current cursor position (no coordinate sent)
- Cursor moves freely across all monitors
- Gestures: tap (click in place), drag, two-finger scroll, pinch zoom
- Sensitivity multiplier configurable (1x–3x, default 1.5x)

Toggle: button on Flutter toolbar. Default locked.

## Gesture Protocol

### Locked Mode messages (absolute)
```json
{"type": "tap", "x": 0.5, "y": 0.3}
{"type": "rightclick", "x": 0.5, "y": 0.3}
{"type": "drag", "x": 0.5, "y": 0.3, "phase": "start|move|end"}
{"type": "scroll", "x": 0.5, "y": 0.3, "dx": 0, "dy": -3.5}
{"type": "pinch", "x": 0.5, "y": 0.3, "scale": 1.2}
```

### Unlocked Mode messages (relative/trackpad)
```json
{"type": "move", "dx": 12.5, "dy": -8.0}
{"type": "tap"}
{"type": "rightclick"}
{"type": "drag", "dx": 5.0, "dy": -3.0, "phase": "start|move|end"}
{"type": "scroll", "dx": 0, "dy": -3.5}
{"type": "pinch", "scale": 1.2}
```

### Keyboard (both modes)
```json
{"type": "key", "text": "hello"}
{"type": "key", "code": "enter"}
{"type": "key", "code": "c", "modifiers": ["cmd"]}
{"type": "key", "code": "v", "modifiers": ["cmd"]}
{"type": "key", "code": "z", "modifiers": ["cmd"]}
{"type": "key", "code": "a", "modifiers": ["cmd", "shift"]}
```

Key difference:
- Locked: `x, y` (absolute position on virtual display)
- Unlocked: `dx, dy` (delta movement), `tap` has no coordinates (click at current cursor)
- Scroll/pinch in locked has `x, y` (scroll at that point), unlocked has none (scroll at current cursor)

## Coordinate Mapping

### macOS global coordinate system
- Each display has bounds from `CGDisplayBounds(displayID)`: origin + size
- CGEvent uses top-left origin coordinate system

### Server startup flow
1. Query `CGGetActiveDisplayList` → all display IDs
2. Query `CGDisplayBounds(displayID)` for each → origin + size
3. Store virtual display bounds: `originX`, `originY`, `width`, `height`
4. Register `CGDisplayReconfigurationCallBack` to re-query on layout changes

### Locked mode coordinate conversion
```
input (0.5, 0.3) relative
→ pixel on virtual display: (0.5 × width, 0.3 × height)
→ global: (pixel.x + originX, pixel.y + originY)
→ clamp within virtual display bounds
→ CGEvent post at global coordinate
```

### Unlocked mode coordinate conversion
```
input delta (12.5, -8.0)
→ current cursor: CGEvent.mouseLocation
→ new position: (current.x + dx, current.y + dy)
→ clamp within total desktop bounds (union of all displays)
→ CGEvent post at new position
```

### Edge cases
- Locked mode: clamp within virtual display bounds
- Unlocked mode: clamp within total desktop bounds (union of all displays)
- Display arrangement changes at runtime: re-query via `CGDisplayReconfigurationCallBack`

## Server Changes (Swift InputInjector)

### New capabilities
- `DisplayLayoutManager`: query and cache display bounds, listen for reconfiguration
- `handleInput` receives mode context (locked/unlocked) — either from message itself or server state
- Scroll events: `CGEvent(scrollWheelEvent2:)` with `deltaAxis1`/`deltaAxis2`
- Pinch events: convert to scroll with Cmd modifier (macOS trackpad zoom behavior)
- Modifier keys: set `CGEventFlags` on key events (`.maskCommand`, `.maskControl`, `.maskAlternate`, `.maskShift`)

### New message types to handle
- `move` (trackpad delta)
- `scroll` (with dx, dy)
- `pinch` (convert to Cmd+scroll)
- `key` with `modifiers` array

## Flutter Client Changes

### Touch overlay refactor
Split into two widgets:
- `AbsoluteTouchOverlay` — locked mode, sends absolute coordinates
- `TrackpadOverlay` — unlocked mode, sends deltas

Both detect:
- One-finger: tap, long press, pan/drag
- Two-finger: scroll (vertical/horizontal), pinch zoom

### Trackpad-specific behavior
- Pan movement × sensitivity multiplier → `move` delta
- Quick tap (< 200ms, movement < 10px) → `tap` (no coords)
- Long press (> 500ms) → `rightclick`

### Modifier keys UI
- Below virtual keyboard: row of Cmd, Ctrl, Alt, Shift buttons
- Sticky toggle: tap Cmd → highlight → type key → sends key with modifier → auto-release Cmd
- Visual indicator: highlighted button shows active modifier

### Settings additions
- Trackpad sensitivity: slider 1x–3x (default 1.5x)
- Mode toggle on toolbar: lock/unlock icon

## Error Handling

| Scenario | Handling |
|---|---|
| Virtual display removed | Server sends `{"error": "display_lost"}`, client shows message |
| Switch from unlocked to locked | Move cursor to center of virtual display before locking |
| Display arrangement changes | Re-query display bounds, update coordinate mapping |
| Pinch on app that doesn't support zoom | Send Cmd+scroll (macOS trackpad zoom) |
| Accessibility permission not granted | Server detects and reports: "Grant Accessibility permission" |
| Modifier key stuck (network lag) | Auto-release all modifiers after 5 seconds of inactivity |

## Out of Scope

- Multi-touch 3+ fingers
- Pressure sensitivity (3D Touch / Force Touch)
- Stylus / Apple Pencil support
- Haptic feedback
- Custom gesture mapping
