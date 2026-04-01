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
  const videoClients = new Set();
  let lastChunk = null;

  // Parse MJPEG frames using Content-Length header — no growing buffer
  let currentFrame = null;
  let frameCount = 0;
  let pending = Buffer.alloc(0); // small leftover between chunks
  let expectedLen = -1; // bytes remaining for current frame body
  let lastDataTime = Date.now();

  // Log FPS every 5 seconds
  let dataEventCount = 0;
  setInterval(() => {
    const fps = (frameCount / 5).toFixed(1);
    const dps = (dataEventCount / 5).toFixed(1);
    console.log(`[fps] ${fps} fps, data: ${dps}/s, pending: ${pending.length}, expLen: ${expectedLen}, frame: ${currentFrame ? (currentFrame.length / 1024).toFixed(0) + 'KB' : '?'}, ws: ${videoClients.size}`);
    frameCount = 0;
    dataEventCount = 0;
  }, 5000);

  mjpegInput.on("data", (chunk) => {
    lastChunk = chunk;
    // Forward raw stream to /stream clients (Safari MJPEG)
    for (const res of clients) {
      try {
        res.write(chunk);
      } catch {
        clients.delete(res);
      }
    }

    // Reset parser if stale (no data for 3+ seconds means capture paused)
    const now = Date.now();
    if (now - lastDataTime > 3000) {
      pending = Buffer.alloc(0);
      expectedLen = -1;
    }
    lastDataTime = now;

    dataEventCount++;

    // Append to pending
    pending = pending.length === 0 ? chunk : Buffer.concat([pending, chunk]);

    // Parse frames
    while (pending.length > 0) {
      if (expectedLen === -1) {
        // Looking for header: --boundary\r\n...Content-Length: N\r\n\r\n
        const headerEnd = pending.indexOf("\r\n\r\n");
        if (headerEnd === -1) break; // incomplete header, wait for more data

        const headerStr = pending.subarray(0, headerEnd).toString();
        const match = headerStr.match(/Content-Length:\s*(\d+)/i);
        if (match) {
          expectedLen = parseInt(match[1], 10);
          pending = pending.subarray(headerEnd + 4);
        } else {
          // No Content-Length — skip to next boundary
          const nextBoundary = pending.indexOf("--" + boundary, 1);
          if (nextBoundary > 0) {
            pending = pending.subarray(nextBoundary);
          } else {
            pending = Buffer.alloc(0);
          }
          break;
        }
      }

      if (expectedLen > 0) {
        if (pending.length >= expectedLen) {
          // Complete frame
          currentFrame = Buffer.from(pending.subarray(0, expectedLen));
          frameCount++;

          // Push to WebSocket /video clients
          for (const ws of videoClients) {
            if (ws.readyState === 1) {
              ws.send(currentFrame, { binary: true });
            }
          }

          // Skip frame data + trailing \r\n
          let skip = expectedLen;
          if (pending.length > skip + 1 && pending[skip] === 0x0d && pending[skip + 1] === 0x0a) {
            skip += 2;
          }
          pending = pending.subarray(skip);
          expectedLen = -1;
        } else {
          break; // incomplete frame, wait for more data
        }
      }
    }

    // Safety: if pending grows or parser seems stuck, reset
    if (pending.length > 512 * 1024 || (pending.length > 0 && expectedLen === -1 && pending.indexOf("\r\n\r\n") === -1 && pending.length > 1024)) {
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

    if (pathname === "/stream") {
      res.writeHead(200, {
        "Content-Type": `multipart/x-mixed-replace; boundary=${boundary}`,
        "Cache-Control": "no-cache",
        Connection: "keep-alive",
      });
      clients.add(res);
      console.log(`[stream] client connected from ${clientIP} (total: ${clients.size})`);
      if (lastChunk) {
        res.write(lastChunk);
      }
      req.on("close", () => {
        clients.delete(res);
        console.log(`[stream] client disconnected from ${clientIP} (total: ${clients.size})`);
      });
      return;
    }

    if (pathname === "/frame") {
      if (currentFrame) {
        res.writeHead(200, {
          "Content-Type": "image/jpeg",
          "Content-Length": currentFrame.length,
          "Cache-Control": "no-cache",
        });
        res.end(currentFrame);
      } else {
        res.writeHead(204);
        res.end();
      }
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
    // Send latest frame immediately
    if (currentFrame) {
      ws.send(currentFrame, { binary: true });
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
