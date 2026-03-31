# Mirror

Turn your iPhone into a second display for Mac over USB.

Creates a virtual display on macOS, captures its content, and streams it to iPhone Safari via MJPEG over the USB network interface. No iOS app required.

## Requirements

- macOS 14+ (Sonoma)
- Node.js 18+
- Swift 5.9+
- iPhone connected via USB cable

## Install

```bash
git clone https://github.com/phongcoiydbg99/mirror.git
cd mirror
npm install
```

## Usage

1. Connect iPhone to Mac via USB
2. Trust the Mac on iPhone (first time only)

```bash
node bin/mirror.js start
```

3. Open the displayed URL in Safari on iPhone (e.g. `http://169.254.x.x:8080`)

### Options

```bash
# Custom resolution
node bin/mirror.js start --width 1170 --height 2532

# Landscape mode
node bin/mirror.js start --landscape
```

### Stop

Press `Ctrl+C` to stop.

## How it works

```
Swift CLI (CGVirtualDisplay + ScreenCaptureKit)
    ↓ MJPEG frames via stdout
Node.js HTTP Server
    ↓ USB network interface (169.254.x.x)
iPhone Safari
```

1. Swift CLI creates a virtual display using Apple's private `CGVirtualDisplay` API — macOS treats it as a real monitor
2. `ScreenCaptureKit` captures the virtual display at 30fps, encodes JPEG frames
3. Node.js serves the MJPEG stream over HTTP, bound to the USB network interface
4. iPhone Safari loads the stream via `<img>` tag

## Project Structure

```
mirror/
├── bin/mirror.js              # CLI entry point
├── src/
│   ├── cli.js                 # Argument parsing
│   ├── server.js              # HTTP server + MJPEG streaming
│   ├── usb.js                 # iPhone detection + USB network
│   └── capture.js             # Swift process management
├── swift/Sources/MirrorCapture/
│   ├── main.swift             # Swift CLI entry
│   ├── VirtualDisplay.swift   # CGVirtualDisplay wrapper
│   ├── ScreenCapture.swift    # Screen capture + JPEG encoding
│   └── include/               # Private API bridging header
└── client/index.html          # Web viewer for iPhone
```

## License

MIT
