import { describe, it, expect, afterEach } from "vitest";
import http from "node:http";
import { createMirrorServer } from "../src/server.js";
import { PassThrough } from "node:stream";

function fetch(url) {
  return new Promise((resolve, reject) => {
    http.get(url, (res) => {
      let body = "";
      res.on("data", (chunk) => (body += chunk));
      res.on("end", () => resolve({ status: res.statusCode, body, headers: res.headers }));
    }).on("error", reject);
  });
}

function fetchPartial(url, bytes) {
  return new Promise((resolve, reject) => {
    http.get(url, (res) => {
      const chunks = [];
      let received = 0;
      res.on("data", (chunk) => {
        chunks.push(chunk);
        received += chunk.length;
        if (received >= bytes) {
          res.destroy();
          resolve({
            status: res.statusCode,
            headers: res.headers,
            body: Buffer.concat(chunks).slice(0, bytes),
          });
        }
      });
    }).on("error", (err) => {
      if (err.code === "ECONNRESET") return; // Expected when we destroy
      reject(err);
    });
  });
}

describe("createMirrorServer", () => {
  let server;

  afterEach(async () => {
    if (server) {
      await new Promise((resolve) => server.close(resolve));
      server = null;
    }
  });

  it("serves index.html at /", async () => {
    const mjpegInput = new PassThrough();
    server = await createMirrorServer({ mjpegInput, port: 0 });
    const addr = server.address();
    const res = await fetch(`http://localhost:${addr.port}/`);
    expect(res.status).toBe(200);
    expect(res.body).toContain("<html");
    expect(res.body).toContain("/stream");
  });

  it("streams MJPEG at /stream with correct content type", async () => {
    const mjpegInput = new PassThrough();
    server = await createMirrorServer({ mjpegInput, port: 0 });
    const addr = server.address();

    // Write a fake MJPEG frame
    const fakeFrame = "--mjpeg-boundary\r\nContent-Type: image/jpeg\r\nContent-Length: 4\r\n\r\ntest\r\n";
    mjpegInput.write(fakeFrame);

    const res = await fetchPartial(`http://localhost:${addr.port}/stream`, fakeFrame.length);
    expect(res.status).toBe(200);
    expect(res.headers["content-type"]).toContain("multipart/x-mixed-replace");
  });

  it("returns 404 for unknown routes", async () => {
    const mjpegInput = new PassThrough();
    server = await createMirrorServer({ mjpegInput, port: 0 });
    const addr = server.address();
    const res = await fetch(`http://localhost:${addr.port}/unknown`);
    expect(res.status).toBe(404);
  });
});
