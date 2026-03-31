import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const CLIENT_HTML = path.join(__dirname, "..", "client", "index.html");

export function createMirrorServer({ mjpegInput, port = 8080 }) {
  const boundary = "mjpeg-boundary";
  const clients = new Set();
  let lastChunk = null;

  // Forward MJPEG data to all connected clients
  mjpegInput.on("data", (chunk) => {
    lastChunk = chunk;
    for (const res of clients) {
      try {
        res.write(chunk);
      } catch {
        clients.delete(res);
      }
    }
  });

  const server = http.createServer((req, res) => {
    if (req.url === "/" || req.url === "/index.html") {
      let html;
      try {
        html = fs.readFileSync(CLIENT_HTML, "utf8");
      } catch {
        // Fallback minimal HTML if file not found
        html = `<html><body><img src="/stream" style="width:100vw;height:100vh;object-fit:contain"></body></html>`;
      }
      res.writeHead(200, { "Content-Type": "text/html" });
      res.end(html);
      return;
    }

    if (req.url === "/stream") {
      res.writeHead(200, {
        "Content-Type": `multipart/x-mixed-replace; boundary=${boundary}`,
        "Cache-Control": "no-cache",
        Connection: "keep-alive",
      });
      clients.add(res);
      // Send the last chunk immediately so the client gets data right away
      if (lastChunk) {
        res.write(lastChunk);
      }
      req.on("close", () => clients.delete(res));
      return;
    }

    res.writeHead(404);
    res.end("Not found");
  });

  // Track open sockets so server.close() can force-close them
  const sockets = new Set();
  server.on("connection", (socket) => {
    sockets.add(socket);
    socket.on("close", () => sockets.delete(socket));
  });

  const origClose = server.close.bind(server);
  server.close = (cb) => {
    for (const socket of sockets) {
      socket.destroy();
    }
    return origClose(cb);
  };

  return new Promise((resolve, reject) => {
    server.on("error", (err) => {
      if (err.code === "EADDRINUSE" && port < 8100) {
        server.listen(port + 1);
      } else {
        reject(err);
      }
    });
    server.listen(port, () => resolve(server));
  });
}
