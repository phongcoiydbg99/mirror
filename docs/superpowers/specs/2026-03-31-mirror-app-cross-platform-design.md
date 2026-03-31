# Mirror App — Cross-Platform Mobile Client + Server Upgrades

## Overview

Evolve Mirror from a web-based iPhone-only client into a native Flutter app (iOS + Android) with touch input, keyboard support, QR code connection, and display mode selection. Upgrade the Mac server to accept input events via WebSocket.

This is sub-project 1. Sub-project 2 (Windows server) will follow separately.

## Architecture

```
┌──────────────────────────────────────────────┐
│              Mac Server (Node.js)             │
│                                               │
│  Swift CLI ──stdout──▶ HTTP /stream (MJPEG)  │── WiFi/USB ──▶  Flutter App
│                                               │                   │
│  Input Injector ◀──── WebSocket /input  ◀────│◀─ WiFi/USB ─────  │ touch/keyboard
│  (CGEvent API)                                │                   │
│                                               │                   │
│  QR Code (IP + port)                          │                   │ QR scanner
└──────────────────────────────────────────────┘                   └────────────┘
```

Two parallel channels:
1. **MJPEG stream** (HTTP, server→client) — display content
2. **WebSocket** (bidirectional, `/input`) — touch and keyboard events

Connection methods:
- **WiFi**: same network, scan QR or enter IP manually
- **USB**: detect USB network interface (169.254.x.x)

## Flutter App

### Screens

**1. Connect Screen** (entry point)
- "Scan QR Code" button → opens camera
- Manual IP:Port text input
- Recent connections list (auto-saved, tap to reconnect)

**2. Display Screen** (main)
- Full-screen MJPEG stream
- Touch overlay captures tap/long press/drag → sends via WebSocket
- Floating button (top corner) to open keyboard or go back
- Swipe from top edge → show toolbar (disconnect, settings, keyboard)

**3. Settings** (simple)
- Quality selection (low/medium/high)
- Orientation lock (portrait/landscape/auto)

### Touch → Input Mapping

| Phone gesture | Computer action |
|---|---|
| Tap | Left click |
| Long press (0.5s) | Right click |
| Two-finger tap | Right click (alternative) |
| Drag | Mouse move + hold left click |
| Keyboard input | Send keystrokes |

### WebSocket Message Format (JSON)

```json
{"type": "tap", "x": 0.5, "y": 0.3}
{"type": "rightclick", "x": 0.5, "y": 0.3}
{"type": "drag", "x": 0.5, "y": 0.3, "phase": "start|move|end"}
{"type": "key", "text": "hello"}
{"type": "key", "code": "enter"}
```

Coordinates `x`, `y` are relative (0.0–1.0), independent of resolution.

### Dependencies

- `mobile_scanner` — QR code scanning
- `flutter_mjpeg` or raw `Image.network` — MJPEG stream display
- `web_socket_channel` — WebSocket client
- `shared_preferences` — connection history
- Min SDK: iOS 14, Android 8 (API 26)

## Server Upgrades

### 1. WebSocket Server (Node.js)

Runs on same HTTP server, upgrades connections at `/input`. Receives JSON messages from Flutter app, parses and forwards to Swift CLI via stdin.

### 2. Input Injector (Swift CLI extension)

Receives input commands from Node.js via stdin with `input:` prefix:
```
input:{"type":"tap","x":0.5,"y":0.3}
```

Uses `CGEvent` API (CoreGraphics) to inject:
- `CGEvent.mouseMove` — move cursor
- `CGEvent.leftMouseDown/Up` — left click
- `CGEvent.rightMouseDown/Up` — right click
- `CGEventKeyboardSetUnicodeString` — type text
- `CGEvent.keyDown/Up` — special keys (enter, esc, tab, etc.)

Converts relative coordinates (0.0–1.0) to absolute pixels on the virtual display.

Requires macOS Accessibility permission.

### 3. QR Code Endpoint

- `GET /qr` returns QR code image (PNG)
- QR contains: `mirror://<ip>:<port>`
- Also prints ASCII QR in terminal on server start

### 4. Display Mode Selection

CLI flag: `mirror start --mode virtual|mirror`
- `virtual` (default): creates virtual display (CGVirtualDisplay)
- `mirror`: captures main display, no virtual display created

Swift CLI `--mode mirror` flag: capture main display instead of virtual display.

### Server Dependencies (npm, new)

- `ws` — WebSocket server
- `qrcode` — generate QR PNG for `/qr` endpoint
- `qrcode-terminal` — print QR in terminal

## Project Structure

```
mirror/
├── app/                       # Flutter app
│   ├── lib/
│   │   ├── main.dart
│   │   ├── screens/
│   │   │   ├── connect_screen.dart
│   │   │   ├── display_screen.dart
│   │   │   └── settings_screen.dart
│   │   ├── services/
│   │   │   ├── connection_service.dart
│   │   │   ├── input_service.dart
│   │   │   └── history_service.dart
│   │   └── widgets/
│   │       ├── mjpeg_viewer.dart
│   │       ├── touch_overlay.dart
│   │       └── virtual_keyboard.dart
│   ├── pubspec.yaml
│   └── ...
├── src/                       # Node.js server (upgraded)
│   ├── cli.js                 # +mode flag
│   ├── server.js              # +WebSocket /input, +QR /qr endpoint
│   ├── usb.js
│   ├── capture.js
│   └── input.js               # NEW: forward input events → Swift CLI
├── swift/Sources/MirrorCapture/
│   ├── main.swift             # +mode flag, +input protocol
│   ├── VirtualDisplay.swift
│   ├── ScreenCapture.swift
│   └── InputInjector.swift    # NEW: CGEvent input injection
├── client/index.html          # Web client (kept as fallback)
└── test/
    ├── cli.test.js
    ├── server.test.js
    ├── capture.test.js
    └── input.test.js          # NEW
```

## Error Handling

| Scenario | Handling |
|---|---|
| WiFi disconnect mid-stream | Flutter shows "Reconnecting...", retries 5 times, then returns to Connect Screen |
| USB disconnected mid-stream | Same as WiFi disconnect |
| Server stops/crashes | Flutter detects WebSocket close → retry → return to Connect Screen |
| QR scan fails | Show message, allow manual IP entry |
| QR scans but connection fails | "Cannot connect to <ip>:<port>. Check if server is running." |
| Input injection fails (permission) | Server logs: "Grant Accessibility permission in System Settings" |
| Multiple clients connect | Accepted — stream broadcasts to all, input from any client accepted |
| App goes to background | Disconnect stream to save battery, auto reconnect on resume |

## Out of Scope

- Windows server (sub-project 2)
- Multi-touch gestures (pinch zoom, rotate)
- Audio streaming
- File transfer

## Testing Strategy

**Flutter:**
- Widget tests for each screen
- Unit tests for services (connection, input, history)

**Node.js:**
- Unit tests for WebSocket message parsing
- Unit tests for input forwarding
- Existing tests remain

**Swift:**
- Manual testing for input injection (requires Accessibility permission)

**Manual testing checklist:**
- Scan QR → connect → see stream
- Enter IP manually → connect → see stream
- Tap on stream → click happens on Mac
- Long press → right click
- Drag → mouse drag
- Open keyboard → type text → appears on Mac
- Disconnect WiFi → reconnect message → reconnect
- Kill server → app returns to Connect Screen
- Switch virtual/mirror mode
