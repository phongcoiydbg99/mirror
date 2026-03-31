export function parseInputMessage(raw) {
  try {
    const msg = JSON.parse(raw);
    if (!msg.type) return null;
    return msg;
  } catch {
    return null;
  }
}

export function formatForSwift(msg) {
  return `input:${JSON.stringify(msg)}\n`;
}
