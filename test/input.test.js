import { describe, it, expect } from "vitest";
import { parseInputMessage, formatForSwift } from "../src/input.js";

describe("parseInputMessage", () => {
  it("parses tap message", () => {
    const msg = '{"type":"tap","x":0.5,"y":0.3}';
    const result = parseInputMessage(msg);
    expect(result).toEqual({ type: "tap", x: 0.5, y: 0.3 });
  });

  it("parses rightclick message", () => {
    const msg = '{"type":"rightclick","x":0.2,"y":0.8}';
    const result = parseInputMessage(msg);
    expect(result).toEqual({ type: "rightclick", x: 0.2, y: 0.8 });
  });

  it("parses drag message", () => {
    const msg = '{"type":"drag","x":0.5,"y":0.5,"phase":"move"}';
    const result = parseInputMessage(msg);
    expect(result).toEqual({ type: "drag", x: 0.5, y: 0.5, phase: "move" });
  });

  it("parses key text message", () => {
    const msg = '{"type":"key","text":"hello"}';
    const result = parseInputMessage(msg);
    expect(result).toEqual({ type: "key", text: "hello" });
  });

  it("parses key code message", () => {
    const msg = '{"type":"key","code":"enter"}';
    const result = parseInputMessage(msg);
    expect(result).toEqual({ type: "key", code: "enter" });
  });

  it("returns null for invalid JSON", () => {
    expect(parseInputMessage("not json")).toBeNull();
  });

  it("returns null for missing type", () => {
    expect(parseInputMessage('{"x":0.5}')).toBeNull();
  });
});

describe("formatForSwift", () => {
  it("formats tap for Swift stdin", () => {
    const result = formatForSwift({ type: "tap", x: 0.5, y: 0.3 });
    expect(result).toBe('input:{"type":"tap","x":0.5,"y":0.3}\n');
  });

  it("formats key for Swift stdin", () => {
    const result = formatForSwift({ type: "key", text: "hi" });
    expect(result).toBe('input:{"type":"key","text":"hi"}\n');
  });
});
