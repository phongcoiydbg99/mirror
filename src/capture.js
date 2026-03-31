import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createMirrorServer } from "./server.js";
import { findIPhone, findUsbNetworkIP } from "./usb.js";

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

  // 5. Find USB network interface IP
  const usbNet = findUsbNetworkIP();
  if (!usbNet) {
    console.error("✘ No USB network interface found (169.254.x.x).");
    console.error("  Make sure iPhone is connected via USB and trusted.");
    captureProc.kill("SIGTERM");
    process.exit(1);
  }
  console.log(`✔ USB network: ${usbNet.ip} (${usbNet.iface})`);

  // 6. Start HTTP server bound to USB network IP
  const server = await createMirrorServer({
    mjpegInput: captureProc.stdout,
    port: 8080,
    host: usbNet.ip,
  });

  const addr = server.address();
  console.log(`✔ Server running on ${addr.address}:${addr.port}`);
  console.log("");
  console.log(`Open Safari on iPhone → http://${addr.address}:${addr.port}`);
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
