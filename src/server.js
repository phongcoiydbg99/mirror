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

  // Parse MJPEG stream: accumulate data, split on boundary, extract JPEG
  let currentFrame = null;
  let streamBuffer = Buffer.alloc(0);
  const boundaryMarker = Buffer.from(`--${boundary}`);
  let frameCount = 0;

  // Log FPS every 5 seconds
  setInterval(() => {
    const fps = (frameCount / 5).toFixed(1);
    console.log(`[fps] ${fps} fps, frame size: ${currentFrame ? (currentFrame.length / 1024).toFixed(0) + 'KB' : '?'}, video ws: ${videoClients.size}, stream: ${clients.size}`);
    frameCount = 0;
  }, 5000);

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

    // Accumulate for frame parsing
    if (streamBuffer.length === 0) {
      streamBuffer = Buffer.from(chunk);
    } else {
      streamBuffer = Buffer.concat([streamBuffer, chunk]);
    }

    // Extract complete frames between boundaries
    while (true) {
      const bIdx = streamBuffer.indexOf(boundaryMarker);
      if (bIdx === -1) break;

      const nextBIdx = streamBuffer.indexOf(boundaryMarker, bIdx + boundaryMarker.length);
      if (nextBIdx === -1) break; // wait for next boundary

      // Between two boundaries: header + \r\n\r\n + JPEG data + \r\n
      const segment = streamBuffer.subarray(bIdx, nextBIdx);
      const headerEnd = segment.indexOf("\r\n\r\n");
      if (headerEnd !== -1) {
        const jpegData = segment.subarray(headerEnd + 4);
        // Trim trailing \r\n
        const trimmed = jpegData[jpegData.length - 1] === 0x0a && jpegData[jpegData.length - 2] === 0x0d
          ? jpegData.subarray(0, jpegData.length - 2)
          : jpegData;
        if (trimmed.length > 0) {
          currentFrame = Buffer.from(trimmed);
          frameCount++;
          // Push frame to WebSocket /video clients
          for (const ws of videoClients) {
            if (ws.readyState === 1) { // WebSocket.OPEN
              ws.send(currentFrame, { binary: true });
            }
          }
        }
      }

      // Keep from second boundary onward (copy to release old buffer)
      streamBuffer = Buffer.from(streamBuffer.subarray(nextBIdx));
    }

    // Prevent buffer from growing too large — trim aggressively
    if (streamBuffer.length > 256 * 1024) {
      const lastBoundary = streamBuffer.lastIndexOf(boundaryMarker);
      if (lastBoundary > 0) {
        streamBuffer = Buffer.from(streamBuffer.subarray(lastBoundary));
      } else {
        // No boundary found — discard everything
        streamBuffer = Buffer.alloc(0);
      }
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
