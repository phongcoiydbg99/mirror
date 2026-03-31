import Foundation

func printUsage() {
    fputs("""
    Usage: MirrorCapture --width <W> --height <H> [--no-hidpi] [--mode virtual|mirror]

    Creates a virtual display and captures its content as MJPEG to stdout.

    Options:
      --width     Display width in pixels (required)
      --height    Display height in pixels (required)
      --no-hidpi  Disable HiDPI scaling
      --mode      Display mode: 'virtual' (default) or 'mirror'
      --help      Show this help message

    """, stderr)
}

func parseArgs() -> (width: Int, height: Int, hiDPI: Bool, mode: String)? {
    let args = CommandLine.arguments
    var width: Int?
    var height: Int?
    var hiDPI = true
    var mode = "virtual"

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
        case "--mode":
            i += 1
            guard i < args.count, ["virtual", "mirror"].contains(args[i]) else {
                fputs("Error: --mode must be 'virtual' or 'mirror'\n", stderr)
                return nil
            }
            mode = args[i]
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

    return (w, h, hiDPI, mode)
}

// Parse arguments
guard let config = parseArgs() else {
    Foundation.exit(1)
}

var displayManager: VirtualDisplayManager? = nil
var captureDisplayID: CGDirectDisplayID = 0

if config.mode == "virtual" {
    // Create virtual display
    let dm = VirtualDisplayManager(
        width: config.width,
        height: config.height,
        hiDPI: config.hiDPI
    )
    do {
        try dm.create()
    } catch {
        fputs("Error: \(error)\n", stderr)
        Foundation.exit(1)
    }
    captureDisplayID = dm.displayID
    displayManager = dm
} else {
    // Mirror mode — capture main display
    captureDisplayID = CGMainDisplayID()
    fputs("Mirror mode: capturing main display (ID: \(captureDisplayID))\n", stderr)
}

// Handle SIGINT/SIGTERM for cleanup
let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
signal(SIGINT, SIG_IGN)
signalSource.setEventHandler {
    displayManager?.destroy()
    Foundation.exit(0)
}
signalSource.resume()

let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
signal(SIGTERM, SIG_IGN)
termSource.setEventHandler {
    displayManager?.destroy()
    Foundation.exit(0)
}
termSource.resume()

// Start screen capture
let capturer = ScreenCapturer(displayID: captureDisplayID, fps: 30)

// Print MJPEG boundary header for Node.js to parse
fputs("boundary=mjpeg-boundary\n", stderr)

// Input injector
let inputInjector = InputInjector(displayID: captureDisplayID, width: config.width, height: config.height)

// Stdin listener for quality + input commands
let qualityController = QualityController(capturer: capturer)
qualityController.startListening(inputInjector: inputInjector)

Task {
    do {
        try await capturer.start()
    } catch {
        fputs("Capture error: \(error)\n", stderr)
        displayManager?.destroy()
        Foundation.exit(1)
    }
}

// Update signal handlers to also stop capture
signalSource.setEventHandler {
    Task {
        await capturer.stop()
        displayManager?.destroy()
        Foundation.exit(0)
    }
}
termSource.setEventHandler {
    Task {
        await capturer.stop()
        displayManager?.destroy()
        Foundation.exit(0)
    }
}

// Keep process alive
RunLoop.main.run()
