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
  let lastChunk = null;

  // Parse MJPEG stream into individual JPEG frames
  let currentFrame = null;
  const frameChunks = [];
  let inFrame = false;
  let prevByte = 0;

  mjpegInput.on("data", (chunk) => {
    lastChunk = chunk;
    // Forward raw stream to /stream clients
    for (const res of clients) {
      try {
        res.write(chunk);
      } catch {
        clients.delete(res);
      }
    }

    // Parse frames for /frame endpoint — collect chunk slices, not byte-by-byte
    let frameStart = -1;
    for (let i = 0; i < chunk.length; i++) {
      const byte = chunk[i];

      // Detect JPEG start: FF D8
      if (prevByte === 0xff && byte === 0xd8 && !inFrame) {
        frameChunks.length = 0;
        frameChunks.push(Buffer.from([0xff, 0xd8]));
        inFrame = true;
        frameStart = i + 1; // next byte starts the body
        prevByte = byte;
        continue;
      }

      // Detect JPEG end: FF D9
      if (inFrame && prevByte === 0xff && byte === 0xd9) {
        // Push remaining slice up to and including this byte
        if (frameStart >= 0 && frameStart <= i) {
          frameChunks.push(chunk.subarray(frameStart, i + 1));
        } else {
          frameChunks.push(Buffer.from([byte]));
        }
        currentFrame = Buffer.concat(frameChunks);
        frameChunks.length = 0;
        inFrame = false;
        frameStart = -1;
        prevByte = byte;
        continue;
      }

      prevByte = byte;
    }

    // If still in frame, save remaining chunk slice
    if (inFrame && frameStart >= 0 && frameStart < chunk.length) {
      frameChunks.push(chunk.subarray(frameStart));
    } else if (inFrame && frameStart === -1) {
      // Entire chunk is mid-frame
      frameChunks.push(chunk);
    }
    frameStart = 0; // reset for next chunk
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
  const wss = new WebSocketServer({ server, path: "/input" });
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

  // Track open sockets so server.close() can force-close them
  const sockets = new Set();
  server.on("connection", (socket) => {
    sockets.add(socket);
    socket.on("close", () => sockets.delete(socket));
  });

  const origClose = server.close.bind(server);
  server.close = (cb) => {
    wss.close();
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
