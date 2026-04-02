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
  const videoClients = new Set();

  // Parse length-prefixed NAL units: [4-byte BE length][NAL data]
  let pending = Buffer.alloc(0);
  let expectedLen = -1;
  let nalCount = 0;
  let cachedSPS = null;
  let cachedPPS = null;

  setInterval(() => {
    const nps = (nalCount / 5).toFixed(1);
    console.log(`[stream] ${nps} NAL/s, ws: ${videoClients.size}, sps: ${cachedSPS ? cachedSPS.length + 'B' : '?'}, pps: ${cachedPPS ? cachedPPS.length + 'B' : '?'}`);
    nalCount = 0;
  }, 5000);

  mjpegInput.on("data", (chunk) => {
    // Forward raw chunk directly to WebSocket clients (already length-prefixed)
    for (const ws of videoClients) {
      if (ws.readyState === 1 && ws.bufferedAmount < 256 * 1024) {
        ws.send(chunk, { binary: true });
      }
    }

    // Lightweight parse to cache SPS/PPS for late-joining clients
    pending = pending.length === 0 ? chunk : Buffer.concat([pending, chunk]);

    while (pending.length >= 4) {
      if (expectedLen === -1) {
        expectedLen = pending.readUInt32BE(0);
        pending = pending.subarray(4);
      }

      if (pending.length < expectedLen) break;

      nalCount++;
      const nalType = pending[0] & 0x1f;
      if (nalType === 7) cachedSPS = Buffer.from(pending.subarray(0, expectedLen));
      if (nalType === 8) cachedPPS = Buffer.from(pending.subarray(0, expectedLen));

      pending = pending.subarray(expectedLen);
      expectedLen = -1;
    }

    if (pending.length > 1024 * 1024) {
      pending = Buffer.alloc(0);
      expectedLen = -1;
    }
  });

  const server = http.createServer(async (req, res) => {
    const pathname = req.url.split("?")[0];
    const clientIP = req.socket.remoteAddress;
    console.log(`[http] ${req.method} ${pathname} from ${clientIP}`);

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
  const wss = new WebSocketServer({ noServer: true });
  wss.on("connection", (ws, req) => {
    console.log(`[ws] input client connected from ${req.socket.remoteAddress}`);
    ws.on("close", () => console.log(`[ws] input client disconnected`));
    ws.on("message", (data) => {
      const raw = data.toString();
      const msg = parseInputMessage(raw);
      if (msg && onInput) {
        onInput(formatForSwift(msg));
      }
    });
  });

  // WebSocket server for video frames
  const wssVideo = new WebSocketServer({ noServer: true });
  wssVideo.on("connection", (ws, req) => {
    videoClients.add(ws);
    console.log(`[ws] video client connected from ${req.socket.remoteAddress} (total: ${videoClients.size})`);
    // Send cached parameter sets
    if (cachedSPS) {
      const lenBuf = Buffer.alloc(4);
      lenBuf.writeUInt32BE(cachedSPS.length);
      ws.send(Buffer.concat([lenBuf, cachedSPS]), { binary: true });
    }
    if (cachedPPS) {
      const lenBuf = Buffer.alloc(4);
      lenBuf.writeUInt32BE(cachedPPS.length);
      ws.send(Buffer.concat([lenBuf, cachedPPS]), { binary: true });
    }
    ws.on("close", () => {
      videoClients.delete(ws);
      console.log(`[ws] video client disconnected (total: ${videoClients.size})`);
    });
  });

  // Route WebSocket upgrades by path
  server.on("upgrade", (request, socket, head) => {
    const pathname = request.url.split("?")[0];
    if (pathname === "/input") {
      wss.handleUpgrade(request, socket, head, (ws) => {
        wss.emit("connection", ws, request);
      });
    } else if (pathname === "/video") {
      wssVideo.handleUpgrade(request, socket, head, (ws) => {
        wssVideo.emit("connection", ws, request);
      });
    } else {
      socket.destroy();
    }
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
    wssVideo.close();
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
