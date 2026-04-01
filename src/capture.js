import { spawn } from "node:child_process";
import path from "node:path";
import os from "node:os";
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

export function getDefaultResolution(landscape) {
  const w = 1170;
  const h = 2532;
  return landscape ? { width: h, height: w } : { width: w, height: h };
}

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

export async function startMirror({ width, height, landscape, mode = "virtual" }) {
  // 1. Resolve resolution
  const resolution =
    width && height ? { width, height } : getDefaultResolution(landscape);
  console.log(`✔ Resolution: ${resolution.width}x${resolution.height}`);
  console.log(`✔ Mode: ${mode}`);

  // 2. Swift binary path
  const binaryPath = getSwiftBinaryPath();

  // 3. Spawn Swift capture process
  console.log("Starting screen capture...");
  const captureProc = spawn(binaryPath, [
    "--width", String(resolution.width),
    "--height", String(resolution.height),
    "--mode", mode,
  ]);

  // Ensure stdout is always drained to prevent pipe backpressure blocking Swift
  captureProc.stdout.on("pause", () => captureProc.stdout.resume());

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

  // 4. Check USB network
  const usbNet = findUsbNetworkIP();
  if (usbNet) {
    console.log(`✔ USB network: ${usbNet.ip} (${usbNet.iface})`);
  }

  // 5. Start HTTP + WebSocket server (bind to all interfaces for WiFi + USB)
  const server = await createMirrorServer({
    mjpegInput: captureProc.stdout,
    port: 8080,
    host: "0.0.0.0",
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
}
