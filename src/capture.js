import { spawn } from "node:child_process";
import net from "node:net";
import path from "node:path";
import os from "node:os";
import { fileURLToPath } from "node:url";
import { PassThrough } from "node:stream";
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

  // 2. Create TCP server for Swift to send MJPEG frames (avoids pipe buffer limits)
  const mjpegStream = new PassThrough();
  const framePort = await new Promise((resolve) => {
    const frameSrv = net.createServer((socket) => {
      console.log("✔ Swift capture connected via TCP");
      socket.on("data", (chunk) => mjpegStream.write(chunk));
      socket.on("error", () => {});
    });
    frameSrv.listen(0, "127.0.0.1", () => {
      resolve(frameSrv.address().port);
    });
  });

  // 3. Swift binary path
  const binaryPath = getSwiftBinaryPath();

  // 4. Spawn Swift capture process
  console.log("Starting screen capture...");
  const captureProc = spawn(binaryPath, [
    "--width", String(resolution.width),
    "--height", String(resolution.height),
    "--mode", mode,
    "--tcp-port", String(framePort),
  ]);

  captureProc.stdin.on("error", () => {}); // Ignore EPIPE when process exits

  captureProc.stderr.on("data", (data) => {
    const msg = data.toString().trim();
    if (msg) console.log(`  [capture] ${msg}`);
  });

  captureProc.on("error", (err) => {
    console.error(`✘ Failed to start capture: ${err.message}`);
    console.error("  Run 'npm run build:swift' first.");
    process.exit(1);
  });

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

  // 5. Check USB network
  const usbNet = findUsbNetworkIP();
  if (usbNet) {
    console.log(`✔ USB network: ${usbNet.ip} (${usbNet.iface})`);
  }

  // 6. Start HTTP + WebSocket server
  const server = await createMirrorServer({
    mjpegInput: mjpegStream,
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

  // Set fixed quality
  captureProc.stdin.write("quality:0.4\n");
}
