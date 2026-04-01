# Fix Stream Freeze — Race Condition in Swift Capture

## Problem

The MJPEG stream freezes after a variable amount of time. Symptoms:
- Image freezes at last frame (no "Disconnected" message on client)
- All FPS logs stop (both Node.js and Swift)
- Moving mouse to extend display does not revive the stream
- Ctrl+C and restart resolves it

## Root Cause

Three bugs in the current implementation:

### 1. Data race on `lastFrameData` (primary cause)

`ScreenCapture.swift` has two GCD queues accessing `lastFrameData` without synchronization:
- **Capture queue** (`"capture"`, line 101) writes `lastFrameData = frame` (line 160)
- **Repeat timer queue** (`"frame-repeat"`, line 69) reads `self.lastFrameData` (line 72)

Swift `Data` is a value type with copy-on-write, but the backing store's reference counting is not thread-safe. This causes the Swift process to crash silently (SIGSEGV or memory corruption) after a random interval.

### 2. Race condition on socket `send()`

Both queues call `send()` on the same socket FD concurrently. This interleaves MJPEG frame data, corrupting the stream for the Node.js parser.

### 3. Swift crash not detected by Node.js

`capture.js` exit handler (line 88-93) checks `code !== 0 && code !== null`. When Swift is killed by a signal (crash), `code` is `null` — the condition is false, so Node.js silently continues with no frame source.

## Solution

### Change 1: Serial queue in `ScreenCapture.swift`

Add a single serial dispatch queue `"socket-writer"` that owns all access to:
- `lastFrameData` (read and write)
- `socketFD` via `send()` calls

**Capture callback** (`stream(_:didOutputSampleBuffer:of:)`):
- JPEG encoding stays on the capture queue (CPU-bound work)
- After encoding, dispatch to `serialQueue` to: set `lastFrameData`, call `send()`, update `lastSendTime`

**Repeat timer**:
- Schedule on `serialQueue` instead of a separate `"frame-repeat"` queue
- Before sending, check `Date().timeIntervalSince(lastSendTime) >= 0.1` — only re-send when idle, avoid duplicate sends during active capture

Result: all shared state access serialized on one queue. No locks needed.

### Change 2: Detect Swift crash in `capture.js`

Update `captureProc.on("exit")` handler:
```javascript
captureProc.on("exit", (code, signal) => {
  if (signal) {
    console.error(`Capture process killed by signal ${signal}`);
    process.exit(1);
  }
  if (code !== 0 && code !== null) {
    console.error(`Capture process exited with code ${code}`);
    process.exit(1);
  }
});
```

### Change 3: Remove adaptive quality block in `capture.js`

The `setInterval` at line 147-157 reads `captureProc.stdout.readableLength`, which is always ~0 because frames are sent via TCP, not stdout. This code is dead. Remove it entirely.

## Files Changed

- `swift/Sources/MirrorCapture/ScreenCapture.swift` — serial queue, timer on same queue, idle check
- `src/capture.js` — crash detection, remove dead adaptive quality code

## Testing

- Run mirror for 15+ minutes with extend display idle
- Verify `[swift]` and `[fps]` logs continue printing consistently
- Kill Swift process manually (`kill -SEGV <pid>`) and verify Node.js exits with error message
- Verify stream recovers when switching between active/idle on extend display
