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

  it("parses move message", () => {
    const msg = '{"type":"move","dx":12.5,"dy":-8.0}';
    const result = parseInputMessage(msg);
    expect(result).toEqual({ type: "move", dx: 12.5, dy: -8.0 });
  });

  it("parses scroll message with position", () => {
    const msg = '{"type":"scroll","x":0.5,"y":0.3,"dx":0,"dy":-3.5}';
    const result = parseInputMessage(msg);
    expect(result).toEqual({ type: "scroll", x: 0.5, y: 0.3, dx: 0, dy: -3.5 });
  });

  it("parses scroll message without position", () => {
    const msg = '{"type":"scroll","dx":0,"dy":-3.5}';
    const result = parseInputMessage(msg);
    expect(result).toEqual({ type: "scroll", dx: 0, dy: -3.5 });
  });

  it("parses pinch message", () => {
    const msg = '{"type":"pinch","x":0.5,"y":0.3,"scale":1.2}';
    const result = parseInputMessage(msg);
    expect(result).toEqual({ type: "pinch", x: 0.5, y: 0.3, scale: 1.2 });
  });

  it("parses key with modifiers", () => {
    const msg = '{"type":"key","code":"c","modifiers":["cmd"]}';
    const result = parseInputMessage(msg);
    expect(result).toEqual({ type: "key", code: "c", modifiers: ["cmd"] });
  });

  it("parses tap without coordinates (unlocked mode)", () => {
    const msg = '{"type":"tap"}';
    const result = parseInputMessage(msg);
    expect(result).toEqual({ type: "tap" });
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
