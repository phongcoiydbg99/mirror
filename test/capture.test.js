import { describe, it, expect } from "vitest";
import { getSwiftBinaryPath, getDefaultResolution } from "../src/capture.js";

describe("getDefaultResolution", () => {
  it("returns portrait dimensions by default", () => {
    const res = getDefaultResolution(false);
    expect(res.width).toBe(1170);
    expect(res.height).toBe(2532);
  });

  it("returns landscape dimensions when landscape is true", () => {
    const res = getDefaultResolution(true);
    expect(res.width).toBe(2532);
    expect(res.height).toBe(1170);
  });
});

describe("getSwiftBinaryPath", () => {
  it("returns a path ending with MirrorCapture", () => {
    const p = getSwiftBinaryPath();
    expect(p).toContain("MirrorCapture");
  });
});
