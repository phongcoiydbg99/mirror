import Foundation

func printUsage() {
    fputs("""
    Usage: MirrorCapture --width <W> --height <H> [--no-hidpi]

    Creates a virtual display and captures its content as MJPEG to stdout.

    Options:
      --width     Display width in pixels (required)
      --height    Display height in pixels (required)
      --no-hidpi  Disable HiDPI scaling
      --help      Show this help message

    """, stderr)
}

func parseArgs() -> (width: Int, height: Int, hiDPI: Bool)? {
    let args = CommandLine.arguments
    var width: Int?
    var height: Int?
    var hiDPI = true

    var i = 1
    while i < args.count {
        switch args[i] {
        case "--width":
            i += 1
            guard i < args.count, let w = Int(args[i]), w > 0 else {
                fputs("Error: --width requires a positive integer\n", stderr)
                return nil
            }
            width = w
        case "--height":
            i += 1
            guard i < args.count, let h = Int(args[i]), h > 0 else {
                fputs("Error: --height requires a positive integer\n", stderr)
                return nil
            }
            height = h
        case "--no-hidpi":
            hiDPI = false
        case "--help":
            printUsage()
            Foundation.exit(0)
        default:
            fputs("Unknown option: \(args[i])\n", stderr)
            printUsage()
            return nil
        }
        i += 1
    }

    guard let w = width, let h = height else {
        fputs("Error: --width and --height are required\n", stderr)
        printUsage()
        return nil
    }

    return (w, h, hiDPI)
}

// Parse arguments
guard let config = parseArgs() else {
    Foundation.exit(1)
}

// Create virtual display
let displayManager = VirtualDisplayManager(
    width: config.width,
    height: config.height,
    hiDPI: config.hiDPI
)

do {
    try displayManager.create()
} catch {
    fputs("Error: \(error)\n", stderr)
    Foundation.exit(1)
}

// Handle SIGINT/SIGTERM for cleanup
let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
signal(SIGINT, SIG_IGN)
signalSource.setEventHandler {
    displayManager.destroy()
    Foundation.exit(0)
}
signalSource.resume()

let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
signal(SIGTERM, SIG_IGN)
termSource.setEventHandler {
    displayManager.destroy()
    Foundation.exit(0)
}
termSource.resume()

fputs("Virtual display ready. Capture will start in Task 3.\n", stderr)

// Keep process alive
RunLoop.main.run()
