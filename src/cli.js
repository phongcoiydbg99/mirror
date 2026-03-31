export function parseArgs(args) {
  if (args.length === 0) return null;

  const command = args[0];

  if (command === "stop") return { command: "stop" };
  if (command === "status") return { command: "status" };

  if (command === "start") {
    const result = {
      command: "start",
      width: null,
      height: null,
      landscape: false,
      mode: "virtual",
    };

    for (let i = 1; i < args.length; i++) {
      switch (args[i]) {
        case "--width":
          i++;
          result.width = parseInt(args[i], 10);
          break;
        case "--height":
          i++;
          result.height = parseInt(args[i], 10);
          break;
        case "--landscape":
          result.landscape = true;
          break;
        case "--mode":
          i++;
          result.mode = args[i];
          break;
      }
    }

    return result;
  }

  return null;
}

export async function run(args) {
  const parsed = parseArgs(args);

  if (!parsed) {
    console.log(`Usage: mirror <start|stop|status>

Commands:
  start [options]    Start mirror display
    --width <px>     Display width (default: auto-detect)
    --height <px>    Display height (default: auto-detect)
    --landscape      Use landscape orientation
    --mode <mode>    Display mode: virtual (default) or mirror
  stop               Stop mirror display
  status             Show current status`);
    process.exit(1);
  }

  switch (parsed.command) {
    case "start": {
      const { startMirror } = await import("./capture.js");
      await startMirror(parsed);
      break;
    }
    case "stop":
      console.log("Not yet implemented");
      break;
    case "status":
      console.log("Not yet implemented");
      break;
  }
}
