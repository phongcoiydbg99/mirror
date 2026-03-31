# Mirror Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a CLI tool that turns an iPhone into a real second Mac display over USB, using a virtual display + MJPEG streaming to Safari.

**Architecture:** Swift CLI creates a virtual display (CGVirtualDisplay) and captures its content (ScreenCaptureKit), piping MJPEG frames to stdout. Node.js reads that pipe, serves the stream over HTTP, and tunnels the port to iPhone via usbmuxd. iPhone Safari renders the stream full-screen.

**Tech Stack:** Node.js (server, CLI, USB), Swift (virtual display, screen capture), HTML/JS (web client), Vitest (testing)

---

## File Structure

```
mirror/
├── package.json               # Node.js project config + bin entry
├── vitest.config.js           # Vitest config
├── bin/
│   └── mirror.js              # CLI entry point (executable)
├── src/
│   ├── cli.js                 # CLI argument parsing + command dispatch
│   ├── server.js              # HTTP server serving MJPEG stream + web client
│   ├── usb.js                 # usbmuxd tunnel management
│   └── capture.js             # Spawn & manage Swift CLI subprocess
├── swift/
│   ├── Package.swift          # Swift package manifest
│   └── Sources/
│       └── MirrorCapture/
│           ├── main.swift             # CLI entry, argument parsing, run loop
│           ├── VirtualDisplay.swift   # CGVirtualDisplay create/destroy
│           └── ScreenCapture.swift    # ScreenCaptureKit capture + MJPEG encode
├── client/
│   └── index.html             # Full-screen MJPEG viewer for iPhone Safari
└── test/
    ├── cli.test.js            # CLI argument parsing tests
    ├── server.test.js         # HTTP server + MJPEG stream tests
    └── capture.test.js        # Capture manager tests
```

---

### Task 1: Project Scaffolding

**Files:**
- Create: `package.json`
- Create: `vitest.config.js`
- Create: `bin/mirror.js`
- Create: `swift/Package.swift`

- [ ] **Step 1: Initialize Node.js project**

Create `package.json`:

```json
{
  "name": "mirror",
  "version": "0.1.0",
  "description": "Use iPhone as a second Mac display over USB",
  "type": "module",
  "bin": {
    "mirror": "./bin/mirror.js"
  },
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest",
    "build:swift": "cd swift && swift build -c release",
    "postinstall": "npm run build:swift"
  },
  "devDependencies": {
    "vitest": "^3.1.0"
  },
  "engines": {
    "node": ">=18"
  }
}
```

- [ ] **Step 2: Create Vitest config**

Create `vitest.config.js`:

```js
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    globals: true,
  },
});
```

- [ ] **Step 3: Create CLI entry point**

Create `bin/mirror.js`:

```js
#!/usr/bin/env node
import { run } from "../src/cli.js";

run(process.argv.slice(2));
```

- [ ] **Step 4: Create Swift package manifest**

Create `swift/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MirrorCapture",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MirrorCapture",
            path: "Sources/MirrorCapture",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("ImageIO"),
            ]
        ),
    ]
)
```

- [ ] **Step 5: Create placeholder Swift entry point**

Create `swift/Sources/MirrorCapture/main.swift`:

```swift
import Foundation

// Placeholder — will be implemented in Task 2
print("MirrorCapture placeholder")
Foundation.exit(0)
```

- [ ] **Step 6: Verify Swift builds**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror/swift && swift build`
Expected: Build succeeds

- [ ] **Step 7: Install Node.js dependencies**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror && npm install`
Expected: vitest installed successfully

- [ ] **Step 8: Commit**

```bash
git add package.json package-lock.json vitest.config.js bin/mirror.js swift/Package.swift swift/Sources/MirrorCapture/main.swift
git commit -m "feat: project scaffolding — Node.js + Swift package"
```

---

### Task 2: Swift — Virtual Display Manager

**Files:**
- Create: `swift/Sources/MirrorCapture/VirtualDisplay.swift`
- Modify: `swift/Sources/MirrorCapture/main.swift`

Note: CGVirtualDisplay is a private Apple API. It cannot be unit tested in CI — manual testing only. The API is available on macOS 14+.

- [ ] **Step 1: Implement VirtualDisplay.swift**

Create `swift/Sources/MirrorCapture/VirtualDisplay.swift`:

```swift
import Foundation
import CoreGraphics

// CGVirtualDisplay is a private API — we dynamically load it
// Reference: https://github.com/KhaosT/CGVirtualDisplay

class VirtualDisplayManager {
    private var display: Any? = nil
    private(set) var displayID: CGDirectDisplayID = 0
    private let width: Int
    private let height: Int
    private let hiDPI: Bool

    init(width: Int, height: Int, hiDPI: Bool = true) {
        self.width = width
        self.height = height
        self.hiDPI = hiDPI
    }

    func create() throws {
        guard let descriptorClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type else {
            throw VirtualDisplayError.apiNotAvailable
        }

        let descriptor = descriptorClass.init()
        descriptor.setValue(width, forKey: "width")
        descriptor.setValue(height, forKey: "height")
        descriptor.setValue(60, forKey: "refreshRate")
        descriptor.setValue("Mirror Virtual Display", forKey: "name")
        descriptor.setValue(hiDPI, forKey: "hiDPI")

        // CGVirtualDisplaySettings
        guard let settingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type else {
            throw VirtualDisplayError.apiNotAvailable
        }

        let settings = settingsClass.init()
        settings.setValue(hiDPI, forKey: "hiDPI")

        // CGVirtualDisplay
        guard let displayClass = NSClassFromString("CGVirtualDisplay") as? NSObject.Type else {
            throw VirtualDisplayError.apiNotAvailable
        }

        let virtualDisplay = displayClass.init()
        let sel = NSSelectorFromString("initWithDescriptor:")
        guard virtualDisplay.responds(to: sel) else {
            throw VirtualDisplayError.apiNotAvailable
        }
        let created = virtualDisplay.perform(sel, with: descriptor)?.takeUnretainedValue() as? NSObject

        guard let createdDisplay = created else {
            throw VirtualDisplayError.creationFailed
        }

        if let id = createdDisplay.value(forKey: "displayID") as? CGDirectDisplayID {
            self.displayID = id
        }

        self.display = createdDisplay
        fputs("Virtual display created: \(width)x\(height) (ID: \(displayID))\n", stderr)
    }

    func destroy() {
        if let display = display as? NSObject {
            let sel = NSSelectorFromString("destroy")
            if display.responds(to: sel) {
                display.perform(sel)
            }
        }
        display = nil
        displayID = 0
        fputs("Virtual display destroyed\n", stderr)
    }
}

enum VirtualDisplayError: Error, CustomStringConvertible {
    case apiNotAvailable
    case creationFailed

    var description: String {
        switch self {
        case .apiNotAvailable:
            return "CGVirtualDisplay API not available. Requires macOS 14+"
        case .creationFailed:
            return "Failed to create virtual display"
        }
    }
}
```

- [ ] **Step 2: Update main.swift for argument parsing**

Replace `swift/Sources/MirrorCapture/main.swift`:

```swift
import Foundation

func printUsage() {
    fputs("""
    Usage: MirrorCapture --width <W> --height <H> [--no-hidpi]

    Creates a virtual display and captures its content as MJPEG to stdout.

    Options:
      --width     Display width in pixels (required)
      --height    Display height in pixels (required)
      --no-hidpi  Disable HiDPI scaling
      --help      Show this help message

    """, stderr)
}

func parseArgs() -> (width: Int, height: Int, hiDPI: Bool)? {
    let args = CommandLine.arguments
    var width: Int?
    var height: Int?
    var hiDPI = true

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

    return (w, h, hiDPI)
}

// Parse arguments
guard let config = parseArgs() else {
    Foundation.exit(1)
}

// Create virtual display
let displayManager = VirtualDisplayManager(
    width: config.width,
    height: config.height,
    hiDPI: config.hiDPI
)

do {
    try displayManager.create()
} catch {
    fputs("Error: \(error)\n", stderr)
    Foundation.exit(1)
}

// Handle SIGINT/SIGTERM for cleanup
let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
signal(SIGINT, SIG_IGN)
signalSource.setEventHandler {
    displayManager.destroy()
    Foundation.exit(0)
}
signalSource.resume()

let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
signal(SIGTERM, SIG_IGN)
termSource.setEventHandler {
    displayManager.destroy()
    Foundation.exit(0)
}
termSource.resume()

fputs("Virtual display ready. Capture will start in Task 3.\n", stderr)

// Keep process alive
RunLoop.main.run()
```

- [ ] **Step 3: Verify Swift builds**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror/swift && swift build 2>&1`
Expected: Build succeeds (there may be warnings about private API usage — that's OK)

- [ ] **Step 4: Commit**

```bash
git add swift/Sources/MirrorCapture/VirtualDisplay.swift swift/Sources/MirrorCapture/main.swift
git commit -m "feat: virtual display manager using CGVirtualDisplay API"
```

---

### Task 3: Swift — Screen Capture & MJPEG Encoder

**Files:**
- Create: `swift/Sources/MirrorCapture/ScreenCapture.swift`
- Modify: `swift/Sources/MirrorCapture/main.swift`

- [ ] **Step 1: Implement ScreenCapture.swift**

Create `swift/Sources/MirrorCapture/ScreenCapture.swift`:

```swift
import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import CoreGraphics
import ImageIO

class ScreenCapturer: NSObject, SCStreamOutput {
    private var stream: SCStream?
    private let displayID: CGDirectDisplayID
    private let fps: Int
    private var jpegQuality: Float = 0.7
    private let boundary = "mjpeg-boundary"

    init(displayID: CGDirectDisplayID, fps: Int = 30) {
        self.displayID = displayID
        self.fps = fps
        super.init()
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let targetDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound(displayID)
        }

        let filter = SCContentFilter(display: targetDisplay, excludingWindows: [])

        let config = SCStreamConfiguration()
        config.width = targetDisplay.width
        config.height = targetDisplay.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        config.queueDepth = 3

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "capture"))
        try await stream.startCapture()

        self.stream = stream
        fputs("Screen capture started: \(targetDisplay.width)x\(targetDisplay.height) @ \(fps)fps\n", stderr)
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
        fputs("Screen capture stopped\n", stderr)
    }

    func setQuality(_ quality: Float) {
        jpegQuality = max(0.1, min(1.0, quality))
    }

    // SCStreamOutput delegate
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        guard let jpegData = encodeJPEG(pixelBuffer: imageBuffer) else { return }

        // Write MJPEG frame to stdout
        let header = "--\(boundary)\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpegData.count)\r\n\r\n"
        if let headerData = header.data(using: .utf8) {
            FileHandle.standardOutput.write(headerData)
            FileHandle.standardOutput.write(jpegData)
            FileHandle.standardOutput.write(Data("\r\n".utf8))
        }
    }

    private func encodeJPEG(pixelBuffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let options: [CIImageRepresentationOption: Any] = [
            kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: jpegQuality
        ]

        return context.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: options)
    }
}

// Quality adjustment via stdin signal
class QualityController {
    private let capturer: ScreenCapturer

    init(capturer: ScreenCapturer) {
        self.capturer = capturer
    }

    func startListening() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while let line = readLine() {
                guard let self = self else { break }
                // Node.js sends "quality:<value>" via stdin
                if line.hasPrefix("quality:") {
                    let valueStr = line.dropFirst("quality:".count)
                    if let value = Float(valueStr) {
                        self.capturer.setQuality(value)
                        fputs("Quality set to \(value)\n", stderr)
                    }
                }
            }
        }
    }
}

enum CaptureError: Error, CustomStringConvertible {
    case displayNotFound(CGDirectDisplayID)

    var description: String {
        switch self {
        case .displayNotFound(let id):
            return "Display \(id) not found. Is the virtual display still active?"
        }
    }
}
```

- [ ] **Step 2: Update main.swift to start capture**

Replace the placeholder line at the end of `swift/Sources/MirrorCapture/main.swift`. Replace from `fputs("Virtual display ready. Capture will start in Task 3.\n", stderr)` onward:

```swift
// Start screen capture
let capturer = ScreenCapturer(displayID: displayManager.displayID, fps: 30)

// Print MJPEG boundary header for Node.js to parse
fputs("boundary=mjpeg-boundary\n", stderr)

// Quality controller listens on stdin
let qualityController = QualityController(capturer: capturer)
qualityController.startListening()

Task {
    do {
        try await capturer.start()
    } catch {
        fputs("Capture error: \(error)\n", stderr)
        displayManager.destroy()
        Foundation.exit(1)
    }
}

// Update signal handlers to also stop capture
signalSource.setEventHandler {
    Task {
        await capturer.stop()
        displayManager.destroy()
        Foundation.exit(0)
    }
}
termSource.setEventHandler {
    Task {
        await capturer.stop()
        displayManager.destroy()
        Foundation.exit(0)
    }
}

// Keep process alive
RunLoop.main.run()
```

- [ ] **Step 3: Verify Swift builds**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror/swift && swift build 2>&1`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add swift/Sources/MirrorCapture/ScreenCapture.swift swift/Sources/MirrorCapture/main.swift
git commit -m "feat: screen capture with MJPEG encoding to stdout"
```

---

### Task 4: Node.js — CLI Argument Parsing

**Files:**
- Create: `src/cli.js`
- Create: `test/cli.test.js`

- [ ] **Step 1: Write failing tests for CLI parsing**

Create `test/cli.test.js`:

```js
import { describe, it, expect } from "vitest";
import { parseArgs } from "../src/cli.js";

describe("parseArgs", () => {
  it("parses start command with defaults", () => {
    const result = parseArgs(["start"]);
    expect(result).toEqual({
      command: "start",
      width: null,
      height: null,
      landscape: false,
    });
  });

  it("parses start with custom resolution", () => {
    const result = parseArgs(["start", "--width", "1170", "--height", "2532"]);
    expect(result).toEqual({
      command: "start",
      width: 1170,
      height: 2532,
      landscape: false,
    });
  });

  it("parses start with landscape flag", () => {
    const result = parseArgs(["start", "--landscape"]);
    expect(result).toEqual({
      command: "start",
      width: null,
      height: null,
      landscape: true,
    });
  });

  it("parses stop command", () => {
    const result = parseArgs(["stop"]);
    expect(result).toEqual({ command: "stop" });
  });

  it("parses status command", () => {
    const result = parseArgs(["status"]);
    expect(result).toEqual({ command: "status" });
  });

  it("returns null for unknown command", () => {
    const result = parseArgs(["foo"]);
    expect(result).toBeNull();
  });

  it("returns null for empty args", () => {
    const result = parseArgs([]);
    expect(result).toBeNull();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror && npx vitest run test/cli.test.js`
Expected: FAIL — module not found

- [ ] **Step 3: Implement cli.js**

Create `src/cli.js`:

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
      }
    }

    return result;
  }

  return null;
}

export async function run(args) {
  const parsed = parseArgs(args);

  if (!parsed) {
    console.log(`Usage: mirror <start|stop|status>

Commands:
  start [options]    Start mirror display
    --width <px>     Display width (default: auto-detect)
    --height <px>    Display height (default: auto-detect)
    --landscape      Use landscape orientation
  stop               Stop mirror display
  status             Show current status`);
    process.exit(1);
  }

  // Command dispatch — implemented in later tasks
  switch (parsed.command) {
    case "start": {
      const { startMirror } = await import("./capture.js");
      await startMirror(parsed);
      break;
    }
    case "stop":
      console.log("Not yet implemented");
      break;
    case "status":
      console.log("Not yet implemented");
      break;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror && npx vitest run test/cli.test.js`
Expected: All 7 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/cli.js test/cli.test.js
git commit -m "feat: CLI argument parsing with tests"
```

---

### Task 5: Node.js — USB Tunnel (usbmuxd)

**Files:**
- Create: `src/usb.js`

Note: usbmuxd communication requires a real iPhone connected. This module is tested manually. We use the `usbmux` npm package if available, or raw socket communication with `/var/run/usbmuxd`.

- [ ] **Step 1: Install usbmux dependency**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror && npm install usbmux`

If `usbmux` package doesn't exist or doesn't work, we'll implement raw usbmuxd protocol. Check first:

Run: `npm search usbmux 2>&1 | head -5`

If no suitable package exists, we use `net` module to talk to `/var/run/usbmuxd` directly.

- [ ] **Step 2: Implement usb.js**

Create `src/usb.js`:

```js
import net from "node:net";
import { Buffer } from "node:buffer";

const USBMUXD_SOCKET = "/var/run/usbmuxd";

// usbmuxd protocol: plist-based messages over Unix socket
// Message format: [length:4][version:4][type:4][tag:4][plist payload]

function createPlistMessage(type, tag, payload) {
  const plistXml = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
${Object.entries(payload)
  .map(([key, value]) => {
    const type = typeof value === "number" ? "integer" : "string";
    return `\t<key>${key}</key>\n\t<${type}>${value}</${type}>`;
  })
  .join("\n")}
</dict>
</plist>`;

  const plistBuf = Buffer.from(plistXml, "utf8");
  const header = Buffer.alloc(16);
  header.writeUInt32LE(16 + plistBuf.length, 0); // length
  header.writeUInt32LE(1, 4); // version (plist)
  header.writeUInt32LE(type, 8); // type (8 = plist message)
  header.writeUInt32LE(tag, 12); // tag
  return Buffer.concat([header, plistBuf]);
}

function parsePlistResponse(data) {
  const xml = data.slice(16).toString("utf8");
  // Simple plist parsing — extract key-value pairs
  const result = {};
  const keyRegex = /<key>(\w+)<\/key>\s*<(\w+)>([^<]*)<\/\w+>/g;
  let match;
  while ((match = keyRegex.exec(xml)) !== null) {
    const [, key, type, value] = match;
    result[key] = type === "integer" ? parseInt(value, 10) : value;
  }
  // Check for array of dicts (device list)
  if (xml.includes("<array>")) {
    result._raw = xml;
  }
  return result;
}

export function listDevices() {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(USBMUXD_SOCKET);
    const msg = createPlistMessage(8, 1, {
      MessageType: "ListDevices",
      ClientVersionString: "mirror",
      ProgName: "mirror",
    });

    socket.on("connect", () => socket.write(msg));

    let buffer = Buffer.alloc(0);
    socket.on("data", (data) => {
      buffer = Buffer.concat([buffer, data]);
      // Read message length from header
      if (buffer.length >= 4) {
        const msgLen = buffer.readUInt32LE(0);
        if (buffer.length >= msgLen) {
          const response = parsePlistResponse(buffer.slice(0, msgLen));
          socket.end();
          // Parse device list from raw XML
          const devices = [];
          if (response._raw) {
            const deviceRegex =
              /<key>DeviceID<\/key>\s*<integer>(\d+)<\/integer>/g;
            let m;
            while ((m = deviceRegex.exec(response._raw)) !== null) {
              devices.push({ deviceID: parseInt(m[1], 10) });
            }
          }
          resolve(devices);
        }
      }
    });

    socket.on("error", (err) => {
      reject(new Error(`Cannot connect to usbmuxd: ${err.message}`));
    });

    setTimeout(() => {
      socket.destroy();
      reject(new Error("usbmuxd connection timeout"));
    }, 5000);
  });
}

export function createTunnel(deviceID, remotePort) {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(USBMUXD_SOCKET);

    const msg = createPlistMessage(8, 2, {
      MessageType: "Connect",
      ClientVersionString: "mirror",
      ProgName: "mirror",
      DeviceID: deviceID,
      PortNumber: htons(remotePort),
    });

    socket.on("connect", () => socket.write(msg));

    let responded = false;
    let buffer = Buffer.alloc(0);
    socket.on("data", (data) => {
      if (responded) return; // After connect, socket becomes the tunnel
      buffer = Buffer.concat([buffer, data]);
      if (buffer.length >= 4) {
        const msgLen = buffer.readUInt32LE(0);
        if (buffer.length >= msgLen) {
          const response = parsePlistResponse(buffer.slice(0, msgLen));
          responded = true;
          if (response.Number === 0) {
            // Success — socket is now a raw TCP tunnel to iPhone
            resolve(socket);
          } else {
            socket.end();
            reject(
              new Error(`usbmux connect failed: error ${response.Number}`)
            );
          }
        }
      }
    });

    socket.on("error", (err) => {
      reject(new Error(`USB tunnel error: ${err.message}`));
    });

    setTimeout(() => {
      if (!responded) {
        socket.destroy();
        reject(new Error("USB tunnel connection timeout"));
      }
    }, 10000);
  });
}

// usbmuxd expects port in network byte order (big-endian)
function htons(port) {
  return ((port & 0xff) << 8) | ((port >> 8) & 0xff);
}

export async function findIPhone() {
  const devices = await listDevices();
  if (devices.length === 0) {
    throw new Error("No iPhone detected. Connect via USB and try again.");
  }
  return devices[0];
}
```

- [ ] **Step 3: Commit**

```bash
git add src/usb.js
git commit -m "feat: usbmuxd tunnel for USB communication with iPhone"
```

---

### Task 6: Node.js — HTTP Server + MJPEG Streaming

**Files:**
- Create: `src/server.js`
- Create: `test/server.test.js`

- [ ] **Step 1: Write failing tests**

Create `test/server.test.js`:

```js
import { describe, it, expect, afterEach } from "vitest";
import http from "node:http";
import { createMirrorServer } from "../src/server.js";
import { PassThrough } from "node:stream";

function fetch(url) {
  return new Promise((resolve, reject) => {
    http.get(url, (res) => {
      let body = "";
      res.on("data", (chunk) => (body += chunk));
      res.on("end", () => resolve({ status: res.statusCode, body, headers: res.headers }));
    }).on("error", reject);
  });
}

function fetchPartial(url, bytes) {
  return new Promise((resolve, reject) => {
    http.get(url, (res) => {
      const chunks = [];
      let received = 0;
      res.on("data", (chunk) => {
        chunks.push(chunk);
        received += chunk.length;
        if (received >= bytes) {
          res.destroy();
          resolve({
            status: res.statusCode,
            headers: res.headers,
            body: Buffer.concat(chunks).slice(0, bytes),
          });
        }
      });
    }).on("error", (err) => {
      if (err.code === "ECONNRESET") return; // Expected when we destroy
      reject(err);
    });
  });
}

describe("createMirrorServer", () => {
  let server;

  afterEach(async () => {
    if (server) {
      await new Promise((resolve) => server.close(resolve));
      server = null;
    }
  });

  it("serves index.html at /", async () => {
    const mjpegInput = new PassThrough();
    server = await createMirrorServer({ mjpegInput, port: 0 });
    const addr = server.address();
    const res = await fetch(`http://localhost:${addr.port}/`);
    expect(res.status).toBe(200);
    expect(res.body).toContain("<html");
    expect(res.body).toContain("/stream");
  });

  it("streams MJPEG at /stream with correct content type", async () => {
    const mjpegInput = new PassThrough();
    server = await createMirrorServer({ mjpegInput, port: 0 });
    const addr = server.address();

    // Write a fake MJPEG frame
    const fakeFrame = "--mjpeg-boundary\r\nContent-Type: image/jpeg\r\nContent-Length: 4\r\n\r\ntest\r\n";
    mjpegInput.write(fakeFrame);

    const res = await fetchPartial(`http://localhost:${addr.port}/stream`, fakeFrame.length);
    expect(res.status).toBe(200);
    expect(res.headers["content-type"]).toContain("multipart/x-mixed-replace");
  });

  it("returns 404 for unknown routes", async () => {
    const mjpegInput = new PassThrough();
    server = await createMirrorServer({ mjpegInput, port: 0 });
    const addr = server.address();
    const res = await fetch(`http://localhost:${addr.port}/unknown`);
    expect(res.status).toBe(404);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror && npx vitest run test/server.test.js`
Expected: FAIL — module not found

- [ ] **Step 3: Implement server.js**

Create `src/server.js`:

```js
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const CLIENT_HTML = path.join(__dirname, "..", "client", "index.html");

export function createMirrorServer({ mjpegInput, port = 8080 }) {
  const boundary = "mjpeg-boundary";
  const clients = new Set();

  // Forward MJPEG data to all connected clients
  mjpegInput.on("data", (chunk) => {
    for (const res of clients) {
      try {
        res.write(chunk);
      } catch {
        clients.delete(res);
      }
    }
  });

  const server = http.createServer((req, res) => {
    if (req.url === "/" || req.url === "/index.html") {
      let html;
      try {
        html = fs.readFileSync(CLIENT_HTML, "utf8");
      } catch {
        // Fallback minimal HTML if file not found
        html = `<html><body><img src="/stream" style="width:100vw;height:100vh;object-fit:contain"></body></html>`;
      }
      res.writeHead(200, { "Content-Type": "text/html" });
      res.end(html);
      return;
    }

    if (req.url === "/stream") {
      res.writeHead(200, {
        "Content-Type": `multipart/x-mixed-replace; boundary=${boundary}`,
        "Cache-Control": "no-cache",
        Connection: "keep-alive",
      });
      clients.add(res);
      req.on("close", () => clients.delete(res));
      return;
    }

    res.writeHead(404);
    res.end("Not found");
  });

  return new Promise((resolve) => {
    server.listen(port, () => resolve(server));
  });
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror && npx vitest run test/server.test.js`
Expected: All 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/server.js test/server.test.js
git commit -m "feat: HTTP server with MJPEG streaming"
```

---

### Task 7: Node.js — Capture Manager

**Files:**
- Create: `src/capture.js`
- Create: `test/capture.test.js`

- [ ] **Step 1: Write failing tests**

Create `test/capture.test.js`:

```js
import { describe, it, expect } from "vitest";
import { getSwiftBinaryPath, getDefaultResolution } from "../src/capture.js";

describe("getDefaultResolution", () => {
  it("returns portrait dimensions by default", () => {
    const res = getDefaultResolution(false);
    expect(res.width).toBe(1170);
    expect(res.height).toBe(2532);
  });

  it("returns landscape dimensions when landscape is true", () => {
    const res = getDefaultResolution(true);
    expect(res.width).toBe(2532);
    expect(res.height).toBe(1170);
  });
});

describe("getSwiftBinaryPath", () => {
  it("returns a path ending with MirrorCapture", () => {
    const p = getSwiftBinaryPath();
    expect(p).toContain("MirrorCapture");
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror && npx vitest run test/capture.test.js`
Expected: FAIL — module not found

- [ ] **Step 3: Implement capture.js**

Create `src/capture.js`:

```js
import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createMirrorServer } from "./server.js";
import { findIPhone } from "./usb.js";

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

export async function startMirror({ width, height, landscape }) {
  // 1. Detect iPhone
  console.log("Detecting iPhone...");
  let device;
  try {
    device = await findIPhone();
    console.log(`✔ iPhone detected (Device ID: ${device.deviceID})`);
  } catch (err) {
    console.error(`✘ ${err.message}`);
    process.exit(1);
  }

  // 2. Resolve resolution
  const resolution =
    width && height ? { width, height } : getDefaultResolution(landscape);
  console.log(`✔ Resolution: ${resolution.width}x${resolution.height}`);

  // 3. Build Swift binary if needed
  const binaryPath = getSwiftBinaryPath();

  // 4. Spawn Swift capture process
  console.log("Starting screen capture...");
  const captureProc = spawn(binaryPath, [
    "--width",
    String(resolution.width),
    "--height",
    String(resolution.height),
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

  // 5. Start HTTP server with capture stdout as MJPEG input
  const server = await createMirrorServer({
    mjpegInput: captureProc.stdout,
    port: 8080,
  });

  const addr = server.address();
  console.log(`✔ Server running on port ${addr.port}`);
  console.log("");
  console.log(`Open Safari on iPhone → http://localhost:${addr.port}`);
  console.log("");
  console.log("Press Ctrl+C to stop");

  // 6. Handle shutdown
  const shutdown = () => {
    console.log("\nShutting down...");
    captureProc.kill("SIGTERM");
    server.close();
    process.exit(0);
  };

  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);

  // 7. Adaptive quality — monitor stdout buffer
  let lastBufferSize = 0;
  let currentQuality = 0.7;
  setInterval(() => {
    const bufSize = captureProc.stdout.readableLength;
    if (bufSize > lastBufferSize + 100000) {
      // Buffer growing — reduce quality
      currentQuality = Math.max(0.2, currentQuality - 0.1);
      captureProc.stdin.write(`quality:${currentQuality}\n`);
    } else if (bufSize < 10000 && currentQuality < 0.9) {
      // Buffer small — increase quality
      currentQuality = Math.min(0.9, currentQuality + 0.05);
      captureProc.stdin.write(`quality:${currentQuality}\n`);
    }
    lastBufferSize = bufSize;
  }, 2000);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror && npx vitest run test/capture.test.js`
Expected: All 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/capture.js test/capture.test.js
git commit -m "feat: capture manager — spawn Swift CLI, adaptive quality"
```

---

### Task 8: Web Client (iPhone Safari)

**Files:**
- Create: `client/index.html`

- [ ] **Step 1: Create index.html**

Create `client/index.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <title>Mirror</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body {
      width: 100%; height: 100%;
      background: #000;
      overflow: hidden;
      -webkit-touch-callout: none;
      -webkit-user-select: none;
      user-select: none;
    }
    #display {
      width: 100vw;
      height: 100vh;
      object-fit: contain;
      display: block;
    }
    #status {
      position: fixed;
      top: 50%; left: 50%;
      transform: translate(-50%, -50%);
      color: #666;
      font-family: -apple-system, sans-serif;
      font-size: 18px;
      text-align: center;
    }
    #fullscreen-btn {
      position: fixed;
      bottom: 40px;
      left: 50%;
      transform: translateX(-50%);
      padding: 12px 32px;
      background: #333;
      color: #fff;
      border: none;
      border-radius: 8px;
      font-size: 16px;
      font-family: -apple-system, sans-serif;
      cursor: pointer;
      z-index: 10;
    }
    #fullscreen-btn:active { background: #555; }
    .hidden { display: none !important; }
  </style>
</head>
<body>
  <div id="status">Connecting...</div>
  <img id="display" class="hidden" alt="Mirror Display">
  <button id="fullscreen-btn">Enter Full Screen</button>

  <script>
    const display = document.getElementById('display');
    const status = document.getElementById('status');
    const fullscreenBtn = document.getElementById('fullscreen-btn');
    let retryTimeout = null;

    function connect() {
      status.textContent = 'Connecting...';
      status.classList.remove('hidden');

      display.src = '/stream?' + Date.now();

      display.onload = () => {
        display.classList.remove('hidden');
        status.classList.add('hidden');
      };

      display.onerror = () => {
        display.classList.add('hidden');
        status.textContent = 'Disconnected. Reconnecting...';
        status.classList.remove('hidden');
        retryTimeout = setTimeout(connect, 2000);
      };
    }

    fullscreenBtn.addEventListener('click', () => {
      if (document.documentElement.requestFullscreen) {
        document.documentElement.requestFullscreen();
      } else if (document.documentElement.webkitRequestFullscreen) {
        document.documentElement.webkitRequestFullscreen();
      }
      fullscreenBtn.classList.add('hidden');
    });

    // Auto-hide fullscreen button after entering fullscreen
    document.addEventListener('fullscreenchange', () => {
      if (document.fullscreenElement) {
        fullscreenBtn.classList.add('hidden');
      } else {
        fullscreenBtn.classList.remove('hidden');
      }
    });
    document.addEventListener('webkitfullscreenchange', () => {
      if (document.webkitFullscreenElement) {
        fullscreenBtn.classList.add('hidden');
      } else {
        fullscreenBtn.classList.remove('hidden');
      }
    });

    // Prevent sleep
    async function preventSleep() {
      try {
        if ('wakeLock' in navigator) {
          await navigator.wakeLock.request('screen');
        }
      } catch {}
    }

    preventSleep();
    connect();
  </script>
</body>
</html>
```

- [ ] **Step 2: Commit**

```bash
git add client/index.html
git commit -m "feat: web client for iPhone Safari — full-screen MJPEG viewer"
```

---

### Task 9: Integration — Wire Everything Together

**Files:**
- Modify: `bin/mirror.js`

- [ ] **Step 1: Make bin/mirror.js executable**

Run: `chmod +x /Users/phongnguyen/phong.nv/Dev/mirror/bin/mirror.js`

- [ ] **Step 2: Build Swift binary**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror/swift && swift build -c release 2>&1`
Expected: Build succeeds

- [ ] **Step 3: Run all tests**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror && npx vitest run`
Expected: All tests pass

- [ ] **Step 4: Manual smoke test (if iPhone available)**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror && node bin/mirror.js start`

Expected output:
```
Detecting iPhone...
✔ iPhone detected (Device ID: ...)
✔ Resolution: 1170x2532
Starting screen capture...
  [capture] Virtual display created: 1170x2532 (ID: ...)
  [capture] Screen capture started: ...
✔ Server running on port 8080

Open Safari on iPhone → http://localhost:8080

Press Ctrl+C to stop
```

On iPhone: open Safari → `http://localhost:8080` → see virtual display content → tap "Enter Full Screen"

- [ ] **Step 5: Commit**

```bash
git add bin/mirror.js
git commit -m "feat: wire up CLI entry point, ready for manual testing"
```

---

### Task 10: Port Auto-Detection & Error Polish

**Files:**
- Modify: `src/capture.js`
- Modify: `src/server.js`

- [ ] **Step 1: Add port auto-detection to server.js**

In `src/server.js`, update `createMirrorServer` — when the desired port is in use, try the next one. Replace the `return new Promise` block at the end:

```js
export function createMirrorServer({ mjpegInput, port = 8080 }) {
  const boundary = "mjpeg-boundary";
  const clients = new Set();

  mjpegInput.on("data", (chunk) => {
    for (const res of clients) {
      try {
        res.write(chunk);
      } catch {
        clients.delete(res);
      }
    }
  });

  const server = http.createServer((req, res) => {
    if (req.url === "/" || req.url === "/index.html") {
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

    if (req.url === "/stream") {
      res.writeHead(200, {
        "Content-Type": `multipart/x-mixed-replace; boundary=${boundary}`,
        "Cache-Control": "no-cache",
        Connection: "keep-alive",
      });
      clients.add(res);
      req.on("close", () => clients.delete(res));
      return;
    }

    res.writeHead(404);
    res.end("Not found");
  });

  return new Promise((resolve, reject) => {
    server.on("error", (err) => {
      if (err.code === "EADDRINUSE" && port < 8100) {
        server.listen(port + 1);
      } else {
        reject(err);
      }
    });
    server.listen(port, () => resolve(server));
  });
}
```

- [ ] **Step 2: Run tests**

Run: `cd /Users/phongnguyen/phong.nv/Dev/mirror && npx vitest run`
Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git add src/server.js
git commit -m "feat: auto-detect available port when default is in use"
```

---

## Summary

| Task | Component | Tests |
|------|-----------|-------|
| 1 | Project scaffolding | — |
| 2 | Swift: Virtual Display Manager | Manual |
| 3 | Swift: Screen Capture + MJPEG | Manual |
| 4 | Node.js: CLI parsing | 7 unit tests |
| 5 | Node.js: USB tunnel (usbmuxd) | Manual |
| 6 | Node.js: HTTP server + MJPEG stream | 3 integration tests |
| 7 | Node.js: Capture manager | 3 unit tests |
| 8 | Web client (iPhone Safari) | Manual |
| 9 | Integration wiring | Manual smoke test |
| 10 | Port auto-detection | Existing tests |
