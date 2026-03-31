# Mirror — iPhone as Mac Second Display

## Overview

A CLI tool that turns an iPhone into a real second display for Mac over USB. Uses macOS virtual display APIs to create a genuine extended desktop, captures the content, and streams it to iPhone's Safari browser via USB tunnel.

No iOS app required. No WiFi. No jailbreak.

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────────┐
│  Virtual Display │────▶│  Screen Capture  │────▶│  USB Stream Server  │
│    Manager       │     │  & Encoder       │     │  (HTTP over usbmux) │
└─────────────────┘     └──────────────────┘     └─────────────────────┘
                                                          │
                                                     USB cable
                                                          │
                                                  ┌───────▼───────┐
                                                  │ Safari/iPhone  │
                                                  │ (Web client)   │
                                                  └───────────────┘
```

### Components

1. **Virtual Display Manager (Swift CLI)** — Creates/removes a virtual display on macOS using `CGVirtualDisplay` API (macOS 14+). Resolution matches iPhone screen (e.g. 1170x2532 for iPhone 14 Pro). macOS treats it as a real monitor — windows can be dragged onto it.

2. **Screen Capture & Encoder (Swift CLI)** — Uses `ScreenCaptureKit` to capture virtual display content at 30fps. Encodes frames as JPEG (MJPEG stream). Adaptive quality: adjusts quality/fps based on throughput. Outputs MJPEG frames to stdout.

3. **USB Stream Server (Node.js)** — HTTP server on Mac serving MJPEG stream at `/stream`. Uses `usbmuxd` protocol to create TCP tunnel over USB to iPhone. iPhone accesses `http://localhost:8080` through the tunnel.

4. **Web Client (HTML/JS)** — Minimal full-screen page on iPhone Safari. `<img src="/stream">` loads MJPEG stream natively. Auto-reconnect on connection loss. Orientation lock support.

## Tech Stack

- **Node.js** — HTTP server, usbmux client, orchestration, CLI
- **Swift** — CGVirtualDisplay + ScreenCaptureKit (Apple APIs require Swift/ObjC). Built as CLI tool, spawned by Node.js as subprocess.
- **HTML/JS** — Web client on iPhone Safari

## Data Flow

1. User runs `mirror start`
2. Node.js spawns Swift CLI to create virtual display + start capture
3. Swift CLI captures frames, encodes JPEG, pipes to stdout with MJPEG boundary markers
4. Node.js reads stdout, serves MJPEG stream via HTTP at `/stream`
5. Node.js uses usbmuxd to tunnel port to iPhone
6. iPhone Safari opens `http://localhost:8080`, `<img>` tag loads `/stream`, displays full-screen

### Adaptive Quality

- Node.js monitors stdout pipe buffer size
- Buffer growing (iPhone can't keep up) → signal Swift CLI to reduce quality/fps
- Buffer shrinking → increase quality/fps

## CLI Interface

```bash
# Start — detect iPhone, create virtual display, start streaming
mirror start

# Custom resolution (default: auto-detect from iPhone model)
mirror start --width 1170 --height 2532

# Landscape mode
mirror start --landscape

# Stop — remove virtual display, close tunnel
mirror stop

# Check status
mirror status
```

### Startup Flow

```
$ mirror start
✔ iPhone detected (iPhone 14 Pro)
✔ Virtual display created (1170x2532)
✔ Screen capture started (30fps, quality: auto)
✔ USB tunnel established
✔ Server running

Open Safari on iPhone → http://localhost:8080

Press Ctrl+C to stop
```

### iPhone Requirements

- Connect USB to Mac
- Trust the Mac (first time only)
- Open Safari → `http://localhost:8080`
- Tap full-screen button on web page

## Project Structure

```
mirror/
├── package.json
├── bin/
│   └── mirror.js          # CLI entry point
├── src/
│   ├── server.js          # HTTP server + MJPEG streaming
│   ├── usb.js             # usbmux tunnel management
│   ├── capture.js         # Spawn & manage Swift CLI
│   └── cli.js             # CLI argument parsing
├── swift/
│   ├── Package.swift
│   └── Sources/
│       └── MirrorCapture/
│           ├── VirtualDisplay.swift
│           └── ScreenCapture.swift
└── client/
    └── index.html         # Web client for iPhone
```

## Error Handling

| Scenario | Handling |
|----------|----------|
| iPhone not connected | Clear error: "No iPhone detected. Connect via USB and try again." |
| iPhone disconnected mid-stream | Detect disconnect, pause stream, wait 30s for reconnect, then stop |
| iPhone hasn't trusted Mac | Guide user: "Tap Trust on your iPhone" |
| Safari closed/backgrounded | Stream pauses automatically, resumes when reopened |
| Mac sleep/wake | Capture auto-restarts on wake, virtual display persists |
| CGVirtualDisplay unavailable (macOS < 14) | Error: "Requires macOS 14+" |
| Port 8080 in use | Auto-find next available port, display correct port to user |

## Out of Scope

- Multiple iPhones simultaneously
- Touch input from iPhone
- Audio streaming
- Runtime orientation change (requires restart with `--landscape`)

## Testing Strategy

**Automated:**
- Unit tests for CLI argument parsing, MJPEG frame boundary parsing, adaptive quality logic
- Integration tests for HTTP server with mock MJPEG data

**Manual (checklist):**
- Connect iPhone → `mirror start` → detection works
- Virtual display appears in System Settings > Displays
- Drag window to virtual display
- Open Safari on iPhone → see virtual display content
- Unplug USB → disconnect message
- Plug back in → reconnect
- `mirror stop` → virtual display removed
- Run without iPhone → clear error

**Test framework:** Vitest

## References

- [node-mac-virtual-display](https://github.com/enfp-dev-studio/node-mac-virtual-display) — Node.js CGVirtualDisplay wrapper
- [KhaosT/CGVirtualDisplay](https://github.com/KhaosT/CGVirtualDisplay) — CGVirtualDisplay API example
- [ScreenExtender](https://github.com/MatheusLedstar/ScreenExtender) — Similar architecture (Android target)
- [Deskreen](https://github.com/pavlobu/deskreen) — WebRTC-based second display (WiFi)
- [usbmuxd](https://github.com/libimobiledevice/usbmuxd) — USB multiplexing daemon
