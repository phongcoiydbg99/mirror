# Fix Stream Freeze Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate race conditions in Swift capture that cause the MJPEG stream to freeze after a random interval.

**Architecture:** Add a single serial dispatch queue in Swift that serializes all access to shared state (`lastFrameData`, `socketFD`, `lastSendTime`). Fix Node.js crash detection. Remove dead adaptive quality code.

**Tech Stack:** Swift (GCD), Node.js

---

## File Map

- **Modify:** `swift/Sources/MirrorCapture/ScreenCapture.swift` — add serial queue, move timer to it, idle check
- **Modify:** `src/capture.js` — fix exit handler, remove dead code

---

### Task 1: Add serial queue and fix `lastFrameData` race in Swift

**Files:**
- Modify: `swift/Sources/MirrorCapture/ScreenCapture.swift:8-18` (properties)
- Modify: `swift/Sources/MirrorCapture/ScreenCapture.swift:68-80` (repeat timer)
- Modify: `swift/Sources/MirrorCapture/ScreenCapture.swift:130-179` (capture callback)

- [ ] **Step 1: Add `socketQueue` and `lastSendTime` properties**

In `ScreenCapture.swift`, add two new properties to the `ScreenCapturer` class, after line 17 (`private var repeatTimer: DispatchSourceTimer?`):

```swift
private let socketQueue = DispatchQueue(label: "socket-writer")
private var lastSendTime = Date.distantPast
```

- [ ] **Step 2: Move repeat timer to `socketQueue` with idle check**

Replace the entire `startRepeatTimer()` method (lines 68-80) with:

```swift
private func startRepeatTimer() {
    let timer = DispatchSource.makeTimerSource(queue: socketQueue)
    timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
    timer.setEventHandler { [weak self] in
        guard let self = self, let frame = self.lastFrameData, self.socketFD >= 0 else { return }
        // Only re-send when capture is idle (no new frame for 100ms+)
        guard Date().timeIntervalSince(self.lastSendTime) >= 0.1 else { return }
        frame.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            _ = Darwin.send(self.socketFD, base, frame.count, MSG_DONTWAIT)
        }
        self.lastSendTime = Date()
    }
    timer.resume()
    repeatTimer = timer
}
```

Key changes from original:
- `queue: socketQueue` instead of `DispatchQueue(label: "frame-repeat")`
- Added idle check: `Date().timeIntervalSince(self.lastSendTime) >= 0.1`
- Updates `lastSendTime` after sending

- [ ] **Step 3: Dispatch socket write from capture callback onto `socketQueue`**

In the `stream(_:didOutputSampleBuffer:of:)` method, replace the block that saves `lastFrameData` and writes to socket (lines 159-179) with:

```swift
        // Dispatch to serial queue for thread-safe access to lastFrameData and socketFD
        socketQueue.async { [weak self] in
            guard let self = self else { return }
            self.lastFrameData = frame
            self.lastSendTime = Date()

            if self.socketFD >= 0 {
                frame.withUnsafeBytes { ptr in
                    guard let base = ptr.baseAddress else { return }
                    let result = Darwin.send(self.socketFD, base, frame.count, MSG_DONTWAIT)
                    if result > 0 {
                        self.sendFrameCount += 1
                    } else if errno == EAGAIN || errno == EWOULDBLOCK {
                        self.dropFrameCount += 1
                    } else {
                        fputs("Socket write error: \(errno)\n", stderr)
                    }
                }
            } else {
                FileHandle.standardOutput.write(frame)
                fflush(stdout)
            }
        }
```

This replaces lines 159-179 (from `// Save for repeat timer` through the closing brace of the `if socketFD >= 0` / `else` block). The JPEG encoding and stats logging above this block stay on the capture queue unchanged.

- [ ] **Step 4: Build Swift to verify compilation**

Run:
```bash
cd /Users/phongnguyen/phong.nv/Dev/mirror && npm run build:swift
```
Expected: Build succeeds with no errors.

- [ ] **Step 5: Commit**

```bash
git add swift/Sources/MirrorCapture/ScreenCapture.swift
git commit -m "fix: serialize socket writes and lastFrameData access on single queue"
```

---

### Task 2: Fix Swift crash detection in Node.js

**Files:**
- Modify: `src/capture.js:88-93` (exit handler)

- [ ] **Step 1: Update exit handler to detect signal kills**

Replace the `captureProc.on("exit")` handler (lines 88-93) with:

```javascript
  captureProc.on("exit", (code, signal) => {
    if (signal) {
      console.error(`✘ Capture process killed by signal ${signal}`);
      process.exit(1);
    }
    if (code !== 0 && code !== null) {
      console.error(`✘ Capture process exited with code ${code}`);
      process.exit(1);
    }
  });
```

- [ ] **Step 2: Commit**

```bash
git add src/capture.js
git commit -m "fix: detect Swift process crash via signal in exit handler"
```

---

### Task 3: Remove dead adaptive quality code

**Files:**
- Modify: `src/capture.js:143-157` (adaptive quality block)

- [ ] **Step 1: Remove the adaptive quality setInterval and related variables**

Remove lines 143-157 (from `// 8. Adaptive quality` through the closing of the `setInterval`):

```javascript
  // 8. Adaptive quality — cap at 0.5 for smaller frames and better FPS
  let lastBufferSize = 0;
  let currentQuality = 0.4;
  captureProc.stdin.write(`quality:${currentQuality}\n`);
  setInterval(() => {
    const bufSize = captureProc.stdout.readableLength;
    if (bufSize > lastBufferSize + 100000) {
      currentQuality = Math.max(0.2, currentQuality - 0.1);
      captureProc.stdin.write(`quality:${currentQuality}\n`);
    } else if (bufSize < 10000 && currentQuality < 0.5) {
      currentQuality = Math.min(0.5, currentQuality + 0.05);
      captureProc.stdin.write(`quality:${currentQuality}\n`);
    }
    lastBufferSize = bufSize;
  }, 2000);
```

Replace with a single fixed quality command:

```javascript
  // Set fixed quality
  captureProc.stdin.write("quality:0.4\n");
```

- [ ] **Step 2: Commit**

```bash
git add src/capture.js
git commit -m "fix: remove dead adaptive quality code that read wrong metric"
```

---

### Task 4: Manual integration test

- [ ] **Step 1: Start the mirror**

```bash
cd /Users/phongnguyen/phong.nv/Dev/mirror && npm start
```

- [ ] **Step 2: Verify stream stability**

Connect from iPhone, let it run for 15+ minutes with extend display idle. Verify:
- `[swift]` logs print every 5 seconds with non-zero capture fps
- `[fps]` logs print every 5 seconds
- Stream does not freeze

- [ ] **Step 3: Verify crash detection**

In a separate terminal, find and kill the Swift process:
```bash
kill -SEGV $(pgrep MirrorCapture)
```
Expected: Node.js prints `✘ Capture process killed by signal SIGSEGV` and exits.

- [ ] **Step 4: Verify active/idle transition**

Start mirror, move mouse onto extend display (stream should show cursor movement), then move mouse away (stream should continue showing last frame via repeat timer without freezing).
