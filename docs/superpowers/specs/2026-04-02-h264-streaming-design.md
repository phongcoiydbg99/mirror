# H264 Streaming Pipeline — Replace MJPEG with Hardware-Accelerated H264

## Problem

The current MJPEG pipeline has two critical issues:
1. **ScreenCaptureKit stalls** — stops delivering frames after a random interval, freezing the stream with no recovery
2. **High bandwidth** — JPEG frames at 30fps consume significant bandwidth (~60KB/frame = ~14Mbps)

## Solution

Replace the entire capture-encode-transport-decode pipeline:
- **Capture**: Pull model with `CGDisplayCreateImage` (never stalls) instead of ScreenCaptureKit push model
- **Encode**: Hardware H264 via VideoToolbox instead of JPEG
- **Transport**: Length-prefixed NAL units instead of MJPEG boundaries
- **Decode**: Platform-native H264 decoders (Flutter) + Broadway.js WASM decoder (Web)

## Architecture

### Swift (Capture + Encode)

**Capture — Pull model**:
- `DispatchSourceTimer` fires every 33ms (30fps) on a serial queue
- Each tick: `CGDisplayCreateImage(displayID)` → `CGImage`
- Convert `CGImage` → `CVPixelBuffer` via `CGContext` draw into pixel buffer backed by `CVPixelBufferPool`

**Encode — VideoToolbox H264**:
- `VTCompressionSession` with hardware encoder
- Profile: Baseline (low latency, no B-frames)
- Realtime encoding enabled
- Keyframe interval: every 2 seconds (60 frames)
- Output: `CMSampleBuffer` containing H264 NAL units

**Extract NAL units**:
- Parse `CMSampleBuffer` → extract SPS, PPS (from format description) and slice NAL units (from block buffer)
- Each NAL unit sent with Annex B start code prefix removed

**Transport over TCP**:
- Wire format: `[4-byte big-endian length][NAL unit data]`
- SPS + PPS sent with every keyframe so clients can join at any time

### Node.js Server (Relay)

**Parser**:
- Replace MJPEG boundary parser with length-prefix parser
- Read 4 bytes → get NAL unit size → read that many bytes → emit NAL unit

**State**:
- Cache latest SPS and PPS NAL units
- When new WebSocket client connects to `/video`: send cached SPS + PPS immediately

**Endpoints**:
- `/video` WebSocket — broadcast raw NAL units (binary, same length-prefix format) to all clients
- `/input` WebSocket — unchanged (input events)
- `/` — serve client HTML
- Remove `/stream` MJPEG endpoint
- Remove `/frame` endpoint (no longer have JPEG frames server-side)

### Flutter Client (Android + iOS)

**Widget**: `h264_viewer.dart` replaces `mjpeg_viewer.dart`, uses `Texture` widget instead of `Image.memory`

**Platform channel** (`H264DecoderPlugin`):
- **Android** (`H264DecoderPlugin.kt`): 
  - `MediaCodec` configured for H264 decode
  - Output to `Surface` backed by Flutter `TextureEntry`
  - Methods: `initialize()`, `feedNalUnit(Uint8List)`, `dispose()`
  
- **iOS** (`H264DecoderPlugin.swift`):
  - `VTDecompressionSession` for H264 decode
  - Output to `CVPixelBuffer` backed by Flutter `TextureEntry`
  - Methods: `initialize()`, `feedNalUnit(Uint8List)`, `dispose()`

**Flow**:
1. Connect WebSocket to `/video`
2. Receive SPS + PPS → configure decoder via platform channel
3. Receive NAL units → `feedNalUnit(bytes)` → native decode → GPU texture update
4. `Texture` widget re-renders automatically

### Web Client (Broadway.js)

- Replace `<img src="/stream">` with `<canvas>` + Broadway.js (~200KB WASM H264 decoder)
- WebSocket `/video` → receive binary NAL units → feed to Broadway decoder → draw YUV frame on canvas
- Keep: input WebSocket, auto-reconnect logic, fullscreen support

## Wire Format

```
TCP (Swift → Node.js) and WebSocket (Node.js → Clients):

[4 bytes: NAL unit length (big-endian uint32)]
[N bytes: NAL unit data]
[4 bytes: NAL unit length]
[N bytes: NAL unit data]
...
```

NAL unit types sent:
- Type 7 (SPS) — with every keyframe
- Type 8 (PPS) — with every keyframe
- Type 5 (IDR slice) — keyframe
- Type 1 (Non-IDR slice) — regular frame

## What Changes

**Replace**:
- `swift/Sources/MirrorCapture/ScreenCapture.swift` → new H264 capture + encode
- `src/server.js` parser section → length-prefix parser
- `app/lib/widgets/mjpeg_viewer.dart` → `h264_viewer.dart` with `Texture` widget
- `client/index.html` → canvas + Broadway.js

**Add**:
- `app/android/.../H264DecoderPlugin.kt` — Android native decoder
- `app/ios/.../H264DecoderPlugin.swift` — iOS native decoder

**Keep unchanged**:
- Virtual display creation (`VirtualDisplay.swift`)
- Display layout manager (`DisplayLayoutManager.swift`)
- Input injection (`InputInjector.swift`, `input.js`)
- TCP transport between Swift and Node.js (`capture.js` — update args only)
- USB detection (`usb.js`)
- CLI (`cli.js`)

## Removed

- ScreenCaptureKit dependency for capture (CGDisplayCreateImage replaces it)
- JPEG encoding (`CIContext.jpegRepresentation`)
- MJPEG framing (boundary headers, Content-Length)
- MJPEG parser in Node.js
- `/stream` HTTP endpoint
- Repeat timer (pull model doesn't need it)
- Adaptive quality control (H264 bitrate control handles this)

## Testing

- Verify stream starts and Flutter displays video within 2 seconds
- Verify < 50ms end-to-end latency (measure: timestamp in Swift, compare on client)
- Verify web client renders H264 via Broadway.js
- Verify input (tap, scroll) still works bidirectionally
- Verify new client connecting mid-stream gets SPS/PPS and can decode immediately
- Verify stream never stalls (CGDisplayCreateImage pull model)
- Run for 30+ minutes to confirm stability
