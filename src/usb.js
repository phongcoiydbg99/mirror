import net from "node:net";
import { Buffer } from "node:buffer";

const USBMUXD_SOCKET = "/var/run/usbmuxd";

// usbmuxd protocol: plist-based messages over Unix socket
// Message format: [length:4][version:4][type:4][tag:4][plist payload]

function createPlistMessage(type, tag, payload) {
  const plistXml = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
${Object.entries(payload)
  .map(([key, value]) => {
    const type = typeof value === "number" ? "integer" : "string";
    return `\t<key>${key}</key>\n\t<${type}>${value}</${type}>`;
  })
  .join("\n")}
</dict>
</plist>`;

  const plistBuf = Buffer.from(plistXml, "utf8");
  const header = Buffer.alloc(16);
  header.writeUInt32LE(16 + plistBuf.length, 0); // length
  header.writeUInt32LE(1, 4); // version (plist)
  header.writeUInt32LE(type, 8); // type (8 = plist message)
  header.writeUInt32LE(tag, 12); // tag
  return Buffer.concat([header, plistBuf]);
}

function parsePlistResponse(data) {
  const xml = data.slice(16).toString("utf8");
  // Simple plist parsing — extract key-value pairs
  const result = {};
  const keyRegex = /<key>(\w+)<\/key>\s*<(\w+)>([^<]*)<\/\w+>/g;
  let match;
  while ((match = keyRegex.exec(xml)) !== null) {
    const [, key, type, value] = match;
    result[key] = type === "integer" ? parseInt(value, 10) : value;
  }
  // Check for array of dicts (device list)
  if (xml.includes("<array>")) {
    result._raw = xml;
  }
  return result;
}

export function listDevices() {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(USBMUXD_SOCKET);
    const msg = createPlistMessage(8, 1, {
      MessageType: "ListDevices",
      ClientVersionString: "mirror",
      ProgName: "mirror",
    });

    socket.on("connect", () => socket.write(msg));

    let buffer = Buffer.alloc(0);
    socket.on("data", (data) => {
      buffer = Buffer.concat([buffer, data]);
      // Read message length from header
      if (buffer.length >= 4) {
        const msgLen = buffer.readUInt32LE(0);
        if (buffer.length >= msgLen) {
          const response = parsePlistResponse(buffer.slice(0, msgLen));
          socket.end();
          // Parse device list from raw XML
          const devices = [];
          if (response._raw) {
            const deviceRegex =
              /<key>DeviceID<\/key>\s*<integer>(\d+)<\/integer>/g;
            let m;
            while ((m = deviceRegex.exec(response._raw)) !== null) {
              devices.push({ deviceID: parseInt(m[1], 10) });
            }
          }
          resolve(devices);
        }
      }
    });

    socket.on("error", (err) => {
      reject(new Error(`Cannot connect to usbmuxd: ${err.message}`));
    });

    setTimeout(() => {
      socket.destroy();
      reject(new Error("usbmuxd connection timeout"));
    }, 5000);
  });
}

export function createTunnel(deviceID, remotePort) {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(USBMUXD_SOCKET);

    const msg = createPlistMessage(8, 2, {
      MessageType: "Connect",
      ClientVersionString: "mirror",
      ProgName: "mirror",
      DeviceID: deviceID,
      PortNumber: htons(remotePort),
    });

    socket.on("connect", () => socket.write(msg));

    let responded = false;
    let buffer = Buffer.alloc(0);
    socket.on("data", (data) => {
      if (responded) return; // After connect, socket becomes the tunnel
      buffer = Buffer.concat([buffer, data]);
      if (buffer.length >= 4) {
        const msgLen = buffer.readUInt32LE(0);
        if (buffer.length >= msgLen) {
          const response = parsePlistResponse(buffer.slice(0, msgLen));
          responded = true;
          if (response.Number === 0) {
            // Success — socket is now a raw TCP tunnel to iPhone
            resolve(socket);
          } else {
            socket.end();
            reject(
              new Error(`usbmux connect failed: error ${response.Number}`)
            );
          }
        }
      }
    });

    socket.on("error", (err) => {
      reject(new Error(`USB tunnel error: ${err.message}`));
    });

    setTimeout(() => {
      if (!responded) {
        socket.destroy();
        reject(new Error("USB tunnel connection timeout"));
      }
    }, 10000);
  });
}

// usbmuxd expects port in network byte order (big-endian)
function htons(port) {
  return ((port & 0xff) << 8) | ((port >> 8) & 0xff);
}

export async function findIPhone() {
  const devices = await listDevices();
  if (devices.length === 0) {
    throw new Error("No iPhone detected. Connect via USB and try again.");
  }
  return devices[0];
}
