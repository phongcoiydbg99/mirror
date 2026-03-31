# Mirror App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Flutter mobile app (iOS + Android) that connects to the Mirror Mac server via QR/IP, displays the MJPEG stream, and sends touch/keyboard input back via WebSocket. Upgrade the server to accept input events and support display mode selection.

**Architecture:** Flutter app connects to Mac server over WiFi/USB. Two channels: HTTP for MJPEG stream (server→client), WebSocket for input events (client→server). Server receives input JSON, pipes to Swift CLI which injects CGEvents into macOS. QR code for easy connection.

**Tech Stack:** Flutter (Dart), Node.js (server), Swift (capture + input injection), WebSocket (ws npm), QR code (qrcode npm, mobile_scanner Flutter)

---

## File Structure

### Server (modifications + new files)
```
src/
├── cli.js                 # MODIFY: add --mode flag
├── server.js              # MODIFY: add WebSocket upgrade, QR endpoint
├── capture.js             # MODIFY: pass --mode to Swift, setup input forwarding, support WiFi-only
├── input.js               # NEW: parse input messages, forward to Swift stdin
└── usb.js                 # (unchanged)
swift/Sources/MirrorCapture/
├── main.swift             # MODIFY: add --mode flag, input protocol on stdin
├── ScreenCapture.swift    # MODIFY: support capturing main display
├── InputInjector.swift    # NEW: CGEvent input injection
└── VirtualDisplay.swift   # (unchanged)
test/
├── cli.test.js            # MODIFY: add --mode tests
├── input.test.js          # NEW: input message parsing tests
├── server.test.js         # (unchanged)
└── capture.test.js        # (unchanged)
```

### Flutter App (all new)
```
app/
├── pubspec.yaml
├── lib/
│   ├── main.dart
│   ├── screens/
│   │   ├── connect_screen.dart
│   │   ├── display_screen.dart
│   │   └── settings_screen.dart
│   ├── services/
│   │   ├── connection_service.dart
│   │   ├── input_service.dart
│   │   └── history_service.dart
│   └── widgets/
│       ├── mjpeg_viewer.dart
│       ├── touch_overlay.dart
│       └── virtual_keyboard.dart
└── test/
    ├── history_service_test.dart
    └── input_service_test.dart
```

---

## Part A: Server Upgrades

### Task 1: Swift — Input Injector

**Files:**
- Create: `swift/Sources/MirrorCapture/InputInjector.swift`

- [ ] **Step 1: Create InputInjector.swift**

Create `swift/Sources/MirrorCapture/InputInjector.swift`:

```swift
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
        // Convert relative (0-1) to absolute pixels
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
```

- [ ] **Step 2: Verify Swift builds**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror/swift && swift build 2>&1`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add swift/Sources/MirrorCapture/InputInjector.swift
git commit -m "feat: CGEvent input injector for mouse and keyboard"
```

---

### Task 2: Swift — Mode flag + Input protocol on stdin

**Files:**
- Modify: `swift/Sources/MirrorCapture/main.swift`
- Modify: `swift/Sources/MirrorCapture/ScreenCapture.swift`

- [ ] **Step 1: Update parseArgs to accept --mode**

In `swift/Sources/MirrorCapture/main.swift`, update the `parseArgs` function return type and add `--mode` parsing:

Replace the entire `parseArgs` function and its return type:

```swift
func parseArgs() -> (width: Int, height: Int, hiDPI: Bool, mode: String)? {
    let args = CommandLine.arguments
    var width: Int?
    var height: Int?
    var hiDPI = true
    var mode = "virtual"

    var i = 1
    while i < args.count {
        switch args[i] {
        case "--width":
            i += 1
            guard i < args.count, let w = Int(args[i]), w > 0 else {
                fputs("Error: --width requires a positive integer\n", stderr)
                return nil
            }
            width = w
        case "--height":
            i += 1
            guard i < args.count, let h = Int(args[i]), h > 0 else {
                fputs("Error: --height requires a positive integer\n", stderr)
                return nil
            }
            height = h
        case "--no-hidpi":
            hiDPI = false
        case "--mode":
            i += 1
            guard i < args.count, ["virtual", "mirror"].contains(args[i]) else {
                fputs("Error: --mode must be 'virtual' or 'mirror'\n", stderr)
                return nil
            }
            mode = args[i]
        case "--help":
            printUsage()
            Foundation.exit(0)
        default:
            fputs("Unknown option: \(args[i])\n", stderr)
            printUsage()
            return nil
        }
        i += 1
    }

    guard let w = width, let h = height else {
        fputs("Error: --width and --height are required\n", stderr)
        printUsage()
        return nil
    }

    return (w, h, hiDPI, mode)
}
```

- [ ] **Step 2: Update main.swift body for mode + input**

Replace everything after `guard let config = parseArgs()` in main.swift:

```swift
// Parse arguments
guard let config = parseArgs() else {
    Foundation.exit(1)
}

var displayManager: VirtualDisplayManager? = nil
var captureDisplayID: CGDirectDisplayID = 0

if config.mode == "virtual" {
    // Create virtual display
    let dm = VirtualDisplayManager(
        width: config.width,
        height: config.height,
        hiDPI: config.hiDPI
    )
    do {
        try dm.create()
    } catch {
        fputs("Error: \(error)\n", stderr)
        Foundation.exit(1)
    }
    captureDisplayID = dm.displayID
    displayManager = dm
} else {
    // Mirror mode — capture main display
    captureDisplayID = CGMainDisplayID()
    fputs("Mirror mode: capturing main display (ID: \(captureDisplayID))\n", stderr)
}

// Handle SIGINT/SIGTERM for cleanup
let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
signal(SIGINT, SIG_IGN)
signalSource.setEventHandler {
    displayManager?.destroy()
    Foundation.exit(0)
}
signalSource.resume()

let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
signal(SIGTERM, SIG_IGN)
termSource.setEventHandler {
    displayManager?.destroy()
    Foundation.exit(0)
}
termSource.resume()

// Start screen capture
let capturer = ScreenCapturer(displayID: captureDisplayID, fps: 30)

// Print MJPEG boundary header for Node.js to parse
fputs("boundary=mjpeg-boundary\n", stderr)

// Input injector
let inputInjector = InputInjector(displayID: captureDisplayID, width: config.width, height: config.height)

// Stdin listener for quality + input commands
let qualityController = QualityController(capturer: capturer)
qualityController.startListening(inputInjector: inputInjector)

Task {
    do {
        try await capturer.start()
    } catch {
        fputs("Capture error: \(error)\n", stderr)
        displayManager?.destroy()
        Foundation.exit(1)
    }
}

// Update signal handlers to also stop capture
signalSource.setEventHandler {
    Task {
        await capturer.stop()
        displayManager?.destroy()
        Foundation.exit(0)
    }
}
termSource.setEventHandler {
    Task {
        await capturer.stop()
        displayManager?.destroy()
        Foundation.exit(0)
    }
}

// Keep process alive
RunLoop.main.run()
```

- [ ] **Step 3: Update QualityController to handle input commands**

In `swift/Sources/MirrorCapture/ScreenCapture.swift`, update `QualityController.startListening` to accept an `InputInjector` parameter and handle `input:` prefix:

```swift
class QualityController {
    private let capturer: ScreenCapturer

    init(capturer: ScreenCapturer) {
        self.capturer = capturer
    }

    func startListening(inputInjector: InputInjector? = nil) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while let line = readLine() {
                guard let self = self else { break }
                if line.hasPrefix("quality:") {
                    let valueStr = line.dropFirst("quality:".count)
                    if let value = Float(valueStr) {
                        self.capturer.setQuality(value)
                        fputs("Quality set to \(value)\n", stderr)
                    }
                } else if line.hasPrefix("input:") {
                    let json = String(line.dropFirst("input:".count))
                    inputInjector?.handleInput(json)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Update printUsage**

```swift
func printUsage() {
    fputs("""
    Usage: MirrorCapture --width <W> --height <H> [--no-hidpi] [--mode virtual|mirror]

    Creates a virtual display and captures its content as MJPEG to stdout.

    Options:
      --width     Display width in pixels (required)
      --height    Display height in pixels (required)
      --no-hidpi  Disable HiDPI scaling
      --mode      Display mode: 'virtual' (default) or 'mirror'
      --help      Show this help message

    """, stderr)
}
```

- [ ] **Step 5: Verify Swift builds**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror/swift && swift build 2>&1`
Expected: Build succeeds

- [ ] **Step 6: Commit**

```bash
git add swift/Sources/MirrorCapture/main.swift swift/Sources/MirrorCapture/ScreenCapture.swift
git commit -m "feat: add --mode flag and input protocol to Swift CLI"
```

---

### Task 3: Node.js — Input message handler

**Files:**
- Create: `src/input.js`
- Create: `test/input.test.js`

- [ ] **Step 1: Write failing tests**

Create `test/input.test.js`:

```js
import { describe, it, expect } from "vitest";
import { parseInputMessage, formatForSwift } from "../src/input.js";

describe("parseInputMessage", () => {
  it("parses tap message", () => {
    const msg = '{"type":"tap","x":0.5,"y":0.3}';
    const result = parseInputMessage(msg);
    expect(result).toEqual({ type: "tap", x: 0.5, y: 0.3 });
  });

  it("parses rightclick message", () => {
    const msg = '{"type":"rightclick","x":0.2,"y":0.8}';
    const result = parseInputMessage(msg);
    expect(result).toEqual({ type: "rightclick", x: 0.2, y: 0.8 });
  });

  it("parses drag message", () => {
    const msg = '{"type":"drag","x":0.5,"y":0.5,"phase":"move"}';
    const result = parseInputMessage(msg);
    expect(result).toEqual({ type: "drag", x: 0.5, y: 0.5, phase: "move" });
  });

  it("parses key text message", () => {
    const msg = '{"type":"key","text":"hello"}';
    const result = parseInputMessage(msg);
    expect(result).toEqual({ type: "key", text: "hello" });
  });

  it("parses key code message", () => {
    const msg = '{"type":"key","code":"enter"}';
    const result = parseInputMessage(msg);
    expect(result).toEqual({ type: "key", code: "enter" });
  });

  it("returns null for invalid JSON", () => {
    expect(parseInputMessage("not json")).toBeNull();
  });

  it("returns null for missing type", () => {
    expect(parseInputMessage('{"x":0.5}')).toBeNull();
  });
});

describe("formatForSwift", () => {
  it("formats tap for Swift stdin", () => {
    const result = formatForSwift({ type: "tap", x: 0.5, y: 0.3 });
    expect(result).toBe('input:{"type":"tap","x":0.5,"y":0.3}\n');
  });

  it("formats key for Swift stdin", () => {
    const result = formatForSwift({ type: "key", text: "hi" });
    expect(result).toBe('input:{"type":"key","text":"hi"}\n');
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror && npx vitest run test/input.test.js`
Expected: FAIL — module not found

- [ ] **Step 3: Implement input.js**

Create `src/input.js`:

```js
export function parseInputMessage(raw) {
  try {
    const msg = JSON.parse(raw);
    if (!msg.type) return null;
    return msg;
  } catch {
    return null;
  }
}

export function formatForSwift(msg) {
  return `input:${JSON.stringify(msg)}\n`;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror && npx vitest run test/input.test.js`
Expected: All 9 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/input.js test/input.test.js
git commit -m "feat: input message parser and Swift formatter"
```

---

### Task 4: Node.js — WebSocket + QR endpoints

**Files:**
- Modify: `src/server.js`
- Modify: `package.json`

- [ ] **Step 1: Install new dependencies**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror && npm install ws qrcode qrcode-terminal`

- [ ] **Step 2: Update server.js to add WebSocket and QR**

Replace `src/server.js` entirely:

```js
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { WebSocketServer } from "ws";
import QRCode from "qrcode";
import { parseInputMessage, formatForSwift } from "./input.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const CLIENT_HTML = path.join(__dirname, "..", "client", "index.html");

export function createMirrorServer({ mjpegInput, port = 8080, host = "0.0.0.0", onInput = null }) {
  const boundary = "mjpeg-boundary";
  const clients = new Set();
  let lastChunk = null;

  // Forward MJPEG data to all connected clients
  mjpegInput.on("data", (chunk) => {
    lastChunk = chunk;
    for (const res of clients) {
      try {
        res.write(chunk);
      } catch {
        clients.delete(res);
      }
    }
  });

  const server = http.createServer(async (req, res) => {
    const pathname = req.url.split("?")[0];

    if (pathname === "/" || pathname === "/index.html") {
      let html;
      try {
        html = fs.readFileSync(CLIENT_HTML, "utf8");
      } catch {
        html = `<html><body><img src="/stream" style="width:100vw;height:100vh;object-fit:contain"></body></html>`;
      }
      res.writeHead(200, { "Content-Type": "text/html" });
      res.end(html);
      return;
    }

    if (pathname === "/stream") {
      res.writeHead(200, {
        "Content-Type": `multipart/x-mixed-replace; boundary=${boundary}`,
        "Cache-Control": "no-cache",
        Connection: "keep-alive",
      });
      clients.add(res);
      if (lastChunk) {
        res.write(lastChunk);
      }
      req.on("close", () => clients.delete(res));
      return;
    }

    if (pathname === "/qr") {
      const addr = server.address();
      const url = `mirror://${addr.address}:${addr.port}`;
      try {
        const png = await QRCode.toBuffer(url, { type: "png", width: 300 });
        res.writeHead(200, { "Content-Type": "image/png" });
        res.end(png);
      } catch {
        res.writeHead(500);
        res.end("QR generation failed");
      }
      return;
    }

    res.writeHead(404);
    res.end("Not found");
  });

  // WebSocket server for input events
  const wss = new WebSocketServer({ server, path: "/input" });
  wss.on("connection", (ws) => {
    ws.on("message", (data) => {
      const raw = data.toString();
      const msg = parseInputMessage(raw);
      if (msg && onInput) {
        onInput(formatForSwift(msg));
      }
    });
  });

  // Track open sockets so server.close() can force-close them
  const sockets = new Set();
  server.on("connection", (socket) => {
    sockets.add(socket);
    socket.on("close", () => sockets.delete(socket));
  });

  const origClose = server.close.bind(server);
  server.close = (cb) => {
    wss.close();
    for (const socket of sockets) {
      socket.destroy();
    }
    return origClose(cb);
  };

  return new Promise((resolve, reject) => {
    let currentPort = port;
    server.on("error", (err) => {
      if (err.code === "EADDRINUSE" && currentPort < 8100) {
        currentPort++;
        server.listen(currentPort, host);
      } else {
        reject(err);
      }
    });
    server.listen(currentPort, host, () => resolve(server));
  });
}
```

- [ ] **Step 3: Run existing tests**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror && npx vitest run`
Expected: All tests pass (server tests may need minor adjustment if import changes break them)

- [ ] **Step 4: Commit**

```bash
git add src/server.js package.json package-lock.json
git commit -m "feat: add WebSocket /input and QR /qr endpoints"
```

---

### Task 5: Node.js — CLI --mode flag + capture updates

**Files:**
- Modify: `src/cli.js`
- Modify: `src/capture.js`
- Modify: `test/cli.test.js`

- [ ] **Step 1: Add --mode tests to cli.test.js**

Add to `test/cli.test.js`:

```js
  it("parses start with mode flag", () => {
    const result = parseArgs(["start", "--mode", "mirror"]);
    expect(result).toEqual({
      command: "start",
      width: null,
      height: null,
      landscape: false,
      mode: "mirror",
    });
  });

  it("defaults mode to virtual", () => {
    const result = parseArgs(["start"]);
    expect(result.mode).toBe("virtual");
  });
```

- [ ] **Step 2: Update parseArgs in cli.js**

```js
export function parseArgs(args) {
  if (args.length === 0) return null;

  const command = args[0];

  if (command === "stop") return { command: "stop" };
  if (command === "status") return { command: "status" };

  if (command === "start") {
    const result = {
      command: "start",
      width: null,
      height: null,
      landscape: false,
      mode: "virtual",
    };

    for (let i = 1; i < args.length; i++) {
      switch (args[i]) {
        case "--width":
          i++;
          result.width = parseInt(args[i], 10);
          break;
        case "--height":
          i++;
          result.height = parseInt(args[i], 10);
          break;
        case "--landscape":
          result.landscape = true;
          break;
        case "--mode":
          i++;
          result.mode = args[i];
          break;
      }
    }

    return result;
  }

  return null;
}
```

Also update the usage string in the `run` function to include `--mode`.

- [ ] **Step 3: Update capture.js**

Update `startMirror` to accept `mode`, pass to Swift CLI, setup input forwarding, and support WiFi (no USB requirement):

```js
import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createMirrorServer } from "./server.js";
import { findIPhone, findUsbNetworkIP } from "./usb.js";
import qrcodeTerminal from "qrcode-terminal";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export function getSwiftBinaryPath() {
  return path.join(
    __dirname,
    "..",
    "swift",
    ".build",
    "release",
    "MirrorCapture"
  );
}

// Default iPhone 14 Pro resolution
export function getDefaultResolution(landscape) {
  const w = 1170;
  const h = 2532;
  return landscape ? { width: h, height: w } : { width: w, height: h };
}

function getLocalIPs() {
  const os = await_import_os();
  const interfaces = os.networkInterfaces();
  const ips = [];
  for (const [name, addrs] of Object.entries(interfaces)) {
    for (const addr of addrs) {
      if (addr.family === "IPv4" && !addr.internal) {
        ips.push({ ip: addr.address, iface: name });
      }
    }
  }
  return ips;
}

function await_import_os() {
  return require("node:os");
}

export async function startMirror({ width, height, landscape, mode = "virtual" }) {
  // 1. Resolve resolution
  const resolution =
    width && height ? { width, height } : getDefaultResolution(landscape);
  console.log(`✔ Resolution: ${resolution.width}x${resolution.height}`);
  console.log(`✔ Mode: ${mode}`);

  // 2. Build Swift binary path
  const binaryPath = getSwiftBinaryPath();

  // 3. Spawn Swift capture process
  console.log("Starting screen capture...");
  const captureProc = spawn(binaryPath, [
    "--width", String(resolution.width),
    "--height", String(resolution.height),
    "--mode", mode,
  ]);

  captureProc.stderr.on("data", (data) => {
    const msg = data.toString().trim();
    if (msg) console.log(`  [capture] ${msg}`);
  });

  captureProc.on("error", (err) => {
    console.error(`✘ Failed to start capture: ${err.message}`);
    console.error("  Run 'npm run build:swift' first.");
    process.exit(1);
  });

  captureProc.on("exit", (code) => {
    if (code !== 0 && code !== null) {
      console.error(`✘ Capture process exited with code ${code}`);
      process.exit(1);
    }
  });

  // 4. Determine host IP
  // Try USB first, fallback to WiFi
  let host = "0.0.0.0";
  const usbNet = findUsbNetworkIP();
  if (usbNet) {
    console.log(`✔ USB network: ${usbNet.ip} (${usbNet.iface})`);
  }

  // 5. Start HTTP + WebSocket server
  const server = await createMirrorServer({
    mjpegInput: captureProc.stdout,
    port: 8080,
    host,
    onInput: (stdinMsg) => {
      captureProc.stdin.write(stdinMsg);
    },
  });

  const addr = server.address();
  console.log(`✔ Server running on port ${addr.port}`);

  // 6. Show connection info
  const allIPs = getLocalIPs();
  console.log("");
  console.log("Connect from phone:");
  for (const { ip, iface } of allIPs) {
    console.log(`  http://${ip}:${addr.port}  (${iface})`);
  }
  console.log("");

  // Print QR code in terminal
  const connectURL = `mirror://${allIPs[0]?.ip || "localhost"}:${addr.port}`;
  qrcodeTerminal.generate(connectURL, { small: true }, (qr) => {
    console.log(qr);
    console.log(`QR: ${connectURL}`);
    console.log("");
    console.log("Press Ctrl+C to stop");
  });

  // 7. Handle shutdown
  const shutdown = () => {
    console.log("\nShutting down...");
    captureProc.kill("SIGTERM");
    server.close();
    process.exit(0);
  };

  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);

  // 8. Adaptive quality — monitor stdout buffer
  let lastBufferSize = 0;
  let currentQuality = 0.7;
  setInterval(() => {
    const bufSize = captureProc.stdout.readableLength;
    if (bufSize > lastBufferSize + 100000) {
      currentQuality = Math.max(0.2, currentQuality - 0.1);
      captureProc.stdin.write(`quality:${currentQuality}\n`);
    } else if (bufSize < 10000 && currentQuality < 0.9) {
      currentQuality = Math.min(0.9, currentQuality + 0.05);
      captureProc.stdin.write(`quality:${currentQuality}\n`);
    }
    lastBufferSize = bufSize;
  }, 2000);
}
```

Note: The `getLocalIPs` function uses `require("node:os")` because this is an ES module project — change it to use the import from usb.js or add a top-level import. Actually, let's fix this properly — add `import os from "node:os"` at the top and use it directly:

Replace the `getLocalIPs` and `await_import_os` functions with:

```js
import os from "node:os";

// ... (at top of file, after other imports)

function getLocalIPs() {
  const interfaces = os.networkInterfaces();
  const ips = [];
  for (const [name, addrs] of Object.entries(interfaces)) {
    for (const addr of addrs) {
      if (addr.family === "IPv4" && !addr.internal) {
        ips.push({ ip: addr.address, iface: name });
      }
    }
  }
  return ips;
}
```

- [ ] **Step 4: Run all tests**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror && npx vitest run`
Expected: All tests pass

- [ ] **Step 5: Build Swift release**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror/swift && swift build -c release 2>&1`
Expected: Build succeeds

- [ ] **Step 6: Commit**

```bash
git add src/cli.js src/capture.js test/cli.test.js
git commit -m "feat: add --mode flag, WiFi support, QR terminal display"
```

---

## Part B: Flutter App

### Task 6: Flutter project scaffolding

**Files:**
- Create: `app/pubspec.yaml`
- Create: `app/lib/main.dart`

- [ ] **Step 1: Create Flutter project**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror && flutter create app --org com.mirror --platforms ios,android`

- [ ] **Step 2: Update pubspec.yaml dependencies**

In `app/pubspec.yaml`, add under `dependencies:`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  mobile_scanner: ^6.0.0
  web_socket_channel: ^3.0.0
  shared_preferences: ^2.3.0
  http: ^1.2.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
```

- [ ] **Step 3: Install dependencies**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror/app && flutter pub get`

- [ ] **Step 4: Create main.dart**

Replace `app/lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'screens/connect_screen.dart';

void main() {
  runApp(const MirrorApp());
}

class MirrorApp extends StatelessWidget {
  const MirrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mirror',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.dark(
          primary: Colors.blue,
          secondary: Colors.blueAccent,
        ),
      ),
      home: const ConnectScreen(),
    );
  }
}
```

- [ ] **Step 5: Create placeholder screens**

Create `app/lib/screens/connect_screen.dart`:

```dart
import 'package:flutter/material.dart';

class ConnectScreen extends StatelessWidget {
  const ConnectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Connect Screen — placeholder')),
    );
  }
}
```

- [ ] **Step 6: Verify build**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror/app && flutter build apk --debug 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 7: Commit**

```bash
git add app/
git commit -m "feat: Flutter app scaffolding with dependencies"
```

---

### Task 7: Flutter — History service

**Files:**
- Create: `app/lib/services/history_service.dart`
- Create: `app/test/history_service_test.dart`

- [ ] **Step 1: Write tests**

Create `app/test/history_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/history_service.dart';

void main() {
  group('ConnectionEntry', () {
    test('toJson and fromJson round-trip', () {
      final entry = ConnectionEntry(ip: '192.168.1.10', port: 8080);
      final json = entry.toJson();
      final restored = ConnectionEntry.fromJson(json);
      expect(restored.ip, '192.168.1.10');
      expect(restored.port, 8080);
    });

    test('url returns correct format', () {
      final entry = ConnectionEntry(ip: '10.0.0.1', port: 9090);
      expect(entry.url, 'http://10.0.0.1:9090');
    });
  });

  group('HistoryService', () {
    test('parseEntries handles empty string', () {
      expect(HistoryService.parseEntries(''), isEmpty);
    });

    test('parseEntries handles valid JSON list', () {
      final json = '[{"ip":"10.0.0.1","port":8080,"lastUsed":"2026-03-31T00:00:00.000"}]';
      final entries = HistoryService.parseEntries(json);
      expect(entries.length, 1);
      expect(entries[0].ip, '10.0.0.1');
    });
  });
}
```

- [ ] **Step 2: Implement history_service.dart**

Create `app/lib/services/history_service.dart`:

```dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ConnectionEntry {
  final String ip;
  final int port;
  final DateTime lastUsed;

  ConnectionEntry({
    required this.ip,
    required this.port,
    DateTime? lastUsed,
  }) : lastUsed = lastUsed ?? DateTime.now();

  String get url => 'http://$ip:$port';

  Map<String, dynamic> toJson() => {
        'ip': ip,
        'port': port,
        'lastUsed': lastUsed.toIso8601String(),
      };

  factory ConnectionEntry.fromJson(Map<String, dynamic> json) {
    return ConnectionEntry(
      ip: json['ip'] as String,
      port: json['port'] as int,
      lastUsed: DateTime.parse(json['lastUsed'] as String),
    );
  }

  /// Parse mirror:// URL: mirror://ip:port
  static ConnectionEntry? fromMirrorUrl(String url) {
    final uri = Uri.tryParse(url.replaceFirst('mirror://', 'http://'));
    if (uri == null || uri.host.isEmpty) return null;
    return ConnectionEntry(ip: uri.host, port: uri.port);
  }
}

class HistoryService {
  static const _key = 'connection_history';
  static const _maxEntries = 10;

  static List<ConnectionEntry> parseEntries(String raw) {
    if (raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => ConnectionEntry.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<ConnectionEntry>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key) ?? '';
    return parseEntries(raw);
  }

  Future<void> addEntry(ConnectionEntry entry) async {
    final history = await getHistory();
    // Remove duplicate
    history.removeWhere((e) => e.ip == entry.ip && e.port == entry.port);
    // Add to front
    history.insert(0, entry);
    // Trim
    if (history.length > _maxEntries) {
      history.removeRange(_maxEntries, history.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(history.map((e) => e.toJson()).toList()));
  }
}
```

- [ ] **Step 3: Run tests**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror/app && flutter test test/history_service_test.dart`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add app/lib/services/history_service.dart app/test/history_service_test.dart
git commit -m "feat: connection history service with persistence"
```

---

### Task 8: Flutter — Input service (WebSocket)

**Files:**
- Create: `app/lib/services/input_service.dart`
- Create: `app/test/input_service_test.dart`

- [ ] **Step 1: Write tests**

Create `app/test/input_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/input_service.dart';

void main() {
  group('InputMessage', () {
    test('tap serializes correctly', () {
      final msg = InputMessage.tap(0.5, 0.3);
      expect(msg.toJson(), '{"type":"tap","x":0.5,"y":0.3}');
    });

    test('rightclick serializes correctly', () {
      final msg = InputMessage.rightClick(0.2, 0.8);
      expect(msg.toJson(), '{"type":"rightclick","x":0.2,"y":0.8}');
    });

    test('drag serializes correctly', () {
      final msg = InputMessage.drag(0.5, 0.5, 'move');
      expect(msg.toJson(), '{"type":"drag","x":0.5,"y":0.5,"phase":"move"}');
    });

    test('key text serializes correctly', () {
      final msg = InputMessage.keyText('hello');
      expect(msg.toJson(), '{"type":"key","text":"hello"}');
    });

    test('key code serializes correctly', () {
      final msg = InputMessage.keyCode('enter');
      expect(msg.toJson(), '{"type":"key","code":"enter"}');
    });
  });
}
```

- [ ] **Step 2: Implement input_service.dart**

Create `app/lib/services/input_service.dart`:

```dart
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class InputMessage {
  final Map<String, dynamic> _data;

  InputMessage._(this._data);

  factory InputMessage.tap(double x, double y) =>
      InputMessage._({'type': 'tap', 'x': x, 'y': y});

  factory InputMessage.rightClick(double x, double y) =>
      InputMessage._({'type': 'rightclick', 'x': x, 'y': y});

  factory InputMessage.drag(double x, double y, String phase) =>
      InputMessage._({'type': 'drag', 'x': x, 'y': y, 'phase': phase});

  factory InputMessage.keyText(String text) =>
      InputMessage._({'type': 'key', 'text': text});

  factory InputMessage.keyCode(String code) =>
      InputMessage._({'type': 'key', 'code': code});

  String toJson() => jsonEncode(_data);
}

class InputService {
  WebSocketChannel? _channel;
  bool _connected = false;

  bool get isConnected => _connected;

  void connect(String ip, int port) {
    final uri = Uri.parse('ws://$ip:$port/input');
    _channel = WebSocketChannel.connect(uri);
    _connected = true;

    _channel!.stream.listen(
      (_) {},
      onDone: () => _connected = false,
      onError: (_) => _connected = false,
    );
  }

  void send(InputMessage msg) {
    if (_connected && _channel != null) {
      _channel!.sink.add(msg.toJson());
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _connected = false;
  }
}
```

- [ ] **Step 3: Run tests**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror/app && flutter test test/input_service_test.dart`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add app/lib/services/input_service.dart app/test/input_service_test.dart
git commit -m "feat: input service — WebSocket client for touch/keyboard events"
```

---

### Task 9: Flutter — Connection service

**Files:**
- Create: `app/lib/services/connection_service.dart`

- [ ] **Step 1: Implement connection_service.dart**

Create `app/lib/services/connection_service.dart`:

```dart
import 'package:http/http.dart' as http;
import 'input_service.dart';
import 'history_service.dart';

class ConnectionService {
  final InputService inputService = InputService();
  final HistoryService historyService = HistoryService();

  String? _ip;
  int? _port;
  bool _connected = false;

  bool get isConnected => _connected;
  String get streamUrl => 'http://$_ip:$_port/stream';
  String? get ip => _ip;
  int? get port => _port;

  /// Test if server is reachable, then establish WebSocket
  Future<bool> connect(String ip, int port) async {
    try {
      final response = await http.get(
        Uri.parse('http://$ip:$port/'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return false;

      _ip = ip;
      _port = port;
      _connected = true;

      // Connect WebSocket for input
      inputService.connect(ip, port);

      // Save to history
      await historyService.addEntry(ConnectionEntry(ip: ip, port: port));

      return true;
    } catch (_) {
      return false;
    }
  }

  void disconnect() {
    inputService.disconnect();
    _connected = false;
    _ip = null;
    _port = null;
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/services/connection_service.dart
git commit -m "feat: connection service — server reachability + WebSocket setup"
```

---

### Task 10: Flutter — MJPEG viewer widget

**Files:**
- Create: `app/lib/widgets/mjpeg_viewer.dart`

- [ ] **Step 1: Implement mjpeg_viewer.dart**

Create `app/lib/widgets/mjpeg_viewer.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class MjpegViewer extends StatefulWidget {
  final String streamUrl;
  final VoidCallback? onError;
  final BoxFit fit;

  const MjpegViewer({
    super.key,
    required this.streamUrl,
    this.onError,
    this.fit = BoxFit.contain,
  });

  @override
  State<MjpegViewer> createState() => _MjpegViewerState();
}

class _MjpegViewerState extends State<MjpegViewer> {
  Uint8List? _currentFrame;
  StreamSubscription? _subscription;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _startStream();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }

  void _startStream() async {
    try {
      final request = http.Request('GET', Uri.parse(widget.streamUrl));
      final client = http.Client();
      final response = await client.send(request);

      final buffer = BytesBuilder();
      bool inImage = false;

      _subscription = response.stream.listen(
        (chunk) {
          if (_disposed) return;

          for (int i = 0; i < chunk.length; i++) {
            buffer.addByte(chunk[i]);
            final bytes = buffer.toBytes();

            // Detect JPEG start (0xFF 0xD8)
            if (bytes.length >= 2 &&
                bytes[bytes.length - 2] == 0xFF &&
                bytes[bytes.length - 1] == 0xD8 &&
                !inImage) {
              buffer.clear();
              buffer.addByte(0xFF);
              buffer.addByte(0xD8);
              inImage = true;
            }

            // Detect JPEG end (0xFF 0xD9)
            if (inImage &&
                bytes.length >= 2 &&
                bytes[bytes.length - 2] == 0xFF &&
                bytes[bytes.length - 1] == 0xD9) {
              if (mounted && !_disposed) {
                setState(() {
                  _currentFrame = Uint8List.fromList(buffer.toBytes());
                });
              }
              buffer.clear();
              inImage = false;
            }
          }
        },
        onError: (_) {
          if (!_disposed) widget.onError?.call();
        },
        onDone: () {
          if (!_disposed) widget.onError?.call();
        },
      );
    } catch (_) {
      if (!_disposed) widget.onError?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentFrame == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Image.memory(
      _currentFrame!,
      fit: widget.fit,
      gaplessPlayback: true,
      width: double.infinity,
      height: double.infinity,
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/widgets/mjpeg_viewer.dart
git commit -m "feat: MJPEG viewer widget — stream parser and renderer"
```

---

### Task 11: Flutter — Touch overlay widget

**Files:**
- Create: `app/lib/widgets/touch_overlay.dart`

- [ ] **Step 1: Implement touch_overlay.dart**

Create `app/lib/widgets/touch_overlay.dart`:

```dart
import 'package:flutter/material.dart';
import '../services/input_service.dart';

class TouchOverlay extends StatefulWidget {
  final InputService inputService;
  final Widget child;

  const TouchOverlay({
    super.key,
    required this.inputService,
    required this.child,
  });

  @override
  State<TouchOverlay> createState() => _TouchOverlayState();
}

class _TouchOverlayState extends State<TouchOverlay> {
  bool _isDragging = false;
  DateTime? _tapDownTime;
  Offset? _tapDownPos;

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

        return GestureDetector(
          behavior: HitTestBehavior.opaque,

          onTapDown: (details) {
            _tapDownTime = DateTime.now();
            _tapDownPos = details.globalPosition;
          },

          onTapUp: (details) {
            final rel = _relativePosition(details.globalPosition, size);
            final duration = DateTime.now().difference(_tapDownTime!);

            if (duration.inMilliseconds >= 500) {
              // Long press → right click
              widget.inputService.send(InputMessage.rightClick(rel.dx, rel.dy));
            } else {
              // Tap → left click
              widget.inputService.send(InputMessage.tap(rel.dx, rel.dy));
            }
          },

          onLongPress: () {
            if (_tapDownPos != null) {
              final rel = _relativePosition(_tapDownPos!, size);
              widget.inputService.send(InputMessage.rightClick(rel.dx, rel.dy));
            }
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
              // Send last known position
              widget.inputService.send(InputMessage.drag(0, 0, 'end'));
            }
          },

          child: widget.child,
        );
      },
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/widgets/touch_overlay.dart
git commit -m "feat: touch overlay — tap, long press, drag gesture handling"
```

---

### Task 12: Flutter — Connect screen

**Files:**
- Modify: `app/lib/screens/connect_screen.dart`

- [ ] **Step 1: Implement connect_screen.dart**

Replace `app/lib/screens/connect_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/connection_service.dart';
import '../services/history_service.dart';
import 'display_screen.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '8080');
  final _connectionService = ConnectionService();
  List<ConnectionEntry> _history = [];
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = await _connectionService.historyService.getHistory();
    setState(() => _history = history);
  }

  Future<void> _connect(String ip, int port) async {
    setState(() {
      _connecting = true;
      _error = null;
    });

    final success = await _connectionService.connect(ip, port);

    if (!mounted) return;

    if (success) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DisplayScreen(connectionService: _connectionService),
        ),
      );
      _loadHistory();
    } else {
      setState(() => _error = 'Cannot connect to $ip:$port');
    }

    setState(() => _connecting = false);
  }

  void _scanQR() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Scan QR Code')),
          body: MobileScanner(
            onDetect: (capture) {
              final barcode = capture.barcodes.firstOrNull;
              if (barcode?.rawValue != null) {
                final entry = ConnectionEntry.fromMirrorUrl(barcode!.rawValue!);
                if (entry != null) {
                  Navigator.of(context).pop();
                  _connect(entry.ip, entry.port);
                }
              }
            },
          ),
        ),
      ),
    );
  }

  void _connectManual() {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 8080;
    if (ip.isEmpty) {
      setState(() => _error = 'Please enter an IP address');
      return;
    }
    _connect(ip, port);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              const Text(
                'Mirror',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Connect to your computer',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // QR button
              ElevatedButton.icon(
                onPressed: _connecting ? null : _scanQR,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan QR Code'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 24),

              // Divider
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('or', style: TextStyle(color: Colors.grey)),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 24),

              // Manual IP input
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _ipController,
                      decoration: const InputDecoration(
                        labelText: 'IP Address',
                        hintText: '192.168.1.100',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _portController,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _connecting ? null : _connectManual,
                child: _connecting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Connect'),
              ),

              // Error
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],

              const SizedBox(height: 24),

              // History
              if (_history.isNotEmpty) ...[
                const Text('Recent', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: _history.length,
                    itemBuilder: (_, i) {
                      final entry = _history[i];
                      return ListTile(
                        leading: const Icon(Icons.computer),
                        title: Text('${entry.ip}:${entry.port}'),
                        onTap: () => _connect(entry.ip, entry.port),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/screens/connect_screen.dart
git commit -m "feat: connect screen — QR scan, IP input, connection history"
```

---

### Task 13: Flutter — Display screen

**Files:**
- Create: `app/lib/screens/display_screen.dart`

- [ ] **Step 1: Implement display_screen.dart**

Create `app/lib/screens/display_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/connection_service.dart';
import '../services/input_service.dart';
import '../widgets/mjpeg_viewer.dart';
import '../widgets/touch_overlay.dart';

class DisplayScreen extends StatefulWidget {
  final ConnectionService connectionService;

  const DisplayScreen({super.key, required this.connectionService});

  @override
  State<DisplayScreen> createState() => _DisplayScreenState();
}

class _DisplayScreenState extends State<DisplayScreen> with WidgetsBindingObserver {
  bool _showToolbar = false;
  bool _showKeyboard = false;
  final _textController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Hide system UI for full-screen
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // App backgrounded — connection persists, stream will auto-reconnect
    }
  }

  void _disconnect() {
    widget.connectionService.disconnect();
    Navigator.of(context).pop();
  }

  void _toggleKeyboard() {
    setState(() => _showKeyboard = !_showKeyboard);
    if (_showKeyboard) {
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
    }
  }

  void _onStreamError() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stream disconnected')),
      );
      _disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.connectionService;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // MJPEG stream + touch overlay
          TouchOverlay(
            inputService: cs.inputService,
            child: MjpegViewer(
              streamUrl: cs.streamUrl,
              onError: _onStreamError,
              fit: BoxFit.contain,
            ),
          ),

          // Top swipe area to show toolbar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 30,
            child: GestureDetector(
              onVerticalDragEnd: (_) {
                setState(() => _showToolbar = !_showToolbar);
              },
            ),
          ),

          // Toolbar
          if (_showToolbar)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  color: Colors.black87,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: _disconnect,
                      ),
                      Text(
                        '${cs.ip}:${cs.port}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      IconButton(
                        icon: Icon(
                          _showKeyboard ? Icons.keyboard_hide : Icons.keyboard,
                          color: Colors.white,
                        ),
                        onPressed: _toggleKeyboard,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Floating keyboard button (always visible)
          if (!_showToolbar)
            Positioned(
              top: 40,
              right: 16,
              child: GestureDetector(
                onTap: () => setState(() => _showToolbar = true),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.more_vert, color: Colors.white70, size: 20),
                ),
              ),
            ),

          // Keyboard input
          if (_showKeyboard)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black87,
                padding: const EdgeInsets.all(8),
                child: Row(
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
                            cs.inputService.send(InputMessage.keyText(text));
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
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/screens/display_screen.dart
git commit -m "feat: display screen — MJPEG viewer, touch overlay, keyboard input"
```

---

### Task 14: Flutter — Settings screen + navigation

**Files:**
- Create: `app/lib/screens/settings_screen.dart`
- Modify: `app/lib/screens/display_screen.dart`

- [ ] **Step 1: Create settings_screen.dart**

Create `app/lib/screens/settings_screen.dart`:

```dart
import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _quality = 'medium';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Stream Quality'),
            subtitle: Text(_quality),
            trailing: DropdownButton<String>(
              value: _quality,
              items: const [
                DropdownMenuItem(value: 'low', child: Text('Low')),
                DropdownMenuItem(value: 'medium', child: Text('Medium')),
                DropdownMenuItem(value: 'high', child: Text('High')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _quality = v);
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Add settings navigation to display_screen.dart toolbar**

In `display_screen.dart`, add settings import at the top:
```dart
import 'settings_screen.dart';
```

Add a settings button in the toolbar Row children, before the keyboard button:
```dart
IconButton(
  icon: const Icon(Icons.settings, color: Colors.white),
  onPressed: () {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  },
),
```

- [ ] **Step 3: Verify Flutter builds**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror/app && flutter build apk --debug 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add app/lib/screens/settings_screen.dart app/lib/screens/display_screen.dart
git commit -m "feat: settings screen and navigation"
```

---

### Task 15: Integration — Build & verify

- [ ] **Step 1: Build Swift release**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror/swift && swift build -c release 2>&1`
Expected: Build succeeds

- [ ] **Step 2: Run Node.js tests**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror && npx vitest run`
Expected: All tests pass

- [ ] **Step 3: Run Flutter tests**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror/app && flutter test`
Expected: All tests pass

- [ ] **Step 4: Test server with new features**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror && node bin/mirror.js start --mode mirror`
Expected: Server starts, QR code printed in terminal, shows all local IPs

- [ ] **Step 5: Commit if any fixes needed**

---

## Summary

| Task | Component | Tests |
|------|-----------|-------|
| 1 | Swift: Input Injector (CGEvent) | Manual |
| 2 | Swift: --mode flag + input protocol | Manual |
| 3 | Node.js: Input message handler | 9 unit tests |
| 4 | Node.js: WebSocket + QR endpoints | Existing tests |
| 5 | Node.js: CLI --mode + capture updates | 2 new + existing |
| 6 | Flutter: Project scaffolding | Build verify |
| 7 | Flutter: History service | 4 unit tests |
| 8 | Flutter: Input service | 5 unit tests |
| 9 | Flutter: Connection service | Manual |
| 10 | Flutter: MJPEG viewer widget | Manual |
| 11 | Flutter: Touch overlay widget | Manual |
| 12 | Flutter: Connect screen | Manual |
| 13 | Flutter: Display screen | Manual |
| 14 | Flutter: Settings screen | Manual |
| 15 | Integration build & verify | All tests |
