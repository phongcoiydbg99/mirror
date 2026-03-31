import { describe, it, expect } from "vitest";
import { parseArgs } from "../src/cli.js";

describe("parseArgs", () => {
  it("parses start command with defaults", () => {
    const result = parseArgs(["start"]);
    expect(result).toEqual({
      command: "start",
      width: null,
      height: null,
      landscape: false,
      mode: "virtual",
    });
  });

  it("parses start with custom resolution", () => {
    const result = parseArgs(["start", "--width", "1170", "--height", "2532"]);
    expect(result).toEqual({
      command: "start",
      width: 1170,
      height: 2532,
      landscape: false,
      mode: "virtual",
    });
  });

  it("parses start with landscape flag", () => {
    const result = parseArgs(["start", "--landscape"]);
    expect(result).toEqual({
      command: "start",
      width: null,
      height: null,
      landscape: true,
      mode: "virtual",
    });
  });

  it("parses start with mode flag", () => {
    const result = parseArgs(["start", "--mode", "mirror"]);
    expect(result).toEqual({
      command: "start",
      width: null,
      height: null,
      landscape: false,
      mode: "mirror",
    });
  });

  it("defaults mode to virtual", () => {
    const result = parseArgs(["start"]);
    expect(result.mode).toBe("virtual");
  });

  it("parses stop command", () => {
    const result = parseArgs(["stop"]);
    expect(result).toEqual({ command: "stop" });
  });

  it("parses status command", () => {
    const result = parseArgs(["status"]);
    expect(result).toEqual({ command: "status" });
  });

  it("returns null for unknown command", () => {
    const result = parseArgs(["foo"]);
    expect(result).toBeNull();
  });

  it("returns null for empty args", () => {
    const result = parseArgs([]);
    expect(result).toBeNull();
  });
});
