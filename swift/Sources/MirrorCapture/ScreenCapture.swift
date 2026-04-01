import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import CoreGraphics
import ImageIO

class ScreenCapturer: NSObject, SCStreamOutput {
    private var stream: SCStream?
    private let displayID: CGDirectDisplayID
    private let fps: Int
    private var jpegQuality: Float = 0.7
    private let boundary = "mjpeg-boundary"
    private let ciContext = CIContext()
    private var socketFD: Int32 = -1

    init(displayID: CGDirectDisplayID, fps: Int = 30) {
        self.displayID = displayID
        self.fps = fps
        super.init()
    }

    func connectTCP(port: Int) {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            fputs("Failed to create socket\n", stderr)
            return
        }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard result == 0 else {
            fputs("Failed to connect to 127.0.0.1:\(port)\n", stderr)
            Darwin.close(fd)
            return
        }

        // Set non-blocking mode
        let flags = fcntl(fd, F_GETFL, 0)
        fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        // Increase send buffer to 512KB
        var bufSize: Int32 = 512 * 1024
        setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &bufSize, socklen_t(MemoryLayout<Int32>.size))

        // Disable Nagle's algorithm for low latency
        var noDelay: Int32 = 1
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &noDelay, socklen_t(MemoryLayout<Int32>.size))

        socketFD = fd
        fputs("TCP connected to 127.0.0.1:\(port) (fd=\(fd), non-blocking, 512KB buffer)\n", stderr)
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let targetDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound(displayID)
        }

        let filter = SCContentFilter(display: targetDisplay, excludingWindows: [])

        let config = SCStreamConfiguration()
        // Capture at half resolution for smaller frames and better performance
        config.width = targetDisplay.width / 2
        config.height = targetDisplay.height / 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        config.queueDepth = 3

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "capture"))
        try await stream.startCapture()

        self.stream = stream
        fputs("Screen capture started: \(config.width)x\(config.height) @ \(fps)fps\n", stderr)
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
        if socketFD >= 0 {
            Darwin.close(socketFD)
            socketFD = -1
        }
        fputs("Screen capture stopped\n", stderr)
    }

    func setQuality(_ quality: Float) {
        jpegQuality = max(0.1, min(1.0, quality))
    }

    // SCStreamOutput delegate
    private var captureFrameCount = 0
    private var sendFrameCount = 0
    private var dropFrameCount = 0
    private var lastStatsTime = Date()

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        captureFrameCount += 1

        // Log stats every 5 seconds
        let now = Date()
        if now.timeIntervalSince(lastStatsTime) >= 5 {
            let elapsed = now.timeIntervalSince(lastStatsTime)
            let capFps = Double(captureFrameCount) / elapsed
            let sendFps = Double(sendFrameCount) / elapsed
            fputs("[swift] capture: \(String(format: "%.1f", capFps)) fps, sent: \(String(format: "%.1f", sendFps)) fps, dropped: \(dropFrameCount)\n", stderr)
            captureFrameCount = 0
            sendFrameCount = 0
            dropFrameCount = 0
            lastStatsTime = now
        }

        guard let jpegData = encodeJPEG(pixelBuffer: imageBuffer) else { return }

        let header = "--\(boundary)\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpegData.count)\r\n\r\n"
        guard let headerData = header.data(using: .utf8) else { return }

        var frame = Data()
        frame.append(headerData)
        frame.append(jpegData)
        frame.append(Data("\r\n".utf8))

        if socketFD >= 0 {
            // Non-blocking write to TCP socket — never blocks, drops partial frames
            frame.withUnsafeBytes { ptr in
                guard let base = ptr.baseAddress else { return }
                let result = Darwin.send(socketFD, base, frame.count, MSG_DONTWAIT)
                if result > 0 {
                    sendFrameCount += 1
                } else if errno == EAGAIN || errno == EWOULDBLOCK {
                    dropFrameCount += 1
                } else {
                    fputs("Socket write error: \(errno)\n", stderr)
                }
            }
        } else {
            // Fallback to stdout
            FileHandle.standardOutput.write(frame)
            fflush(stdout)
        }
    }

    private func encodeJPEG(pixelBuffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let options: [CIImageRepresentationOption: Any] = [
            kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: jpegQuality
        ]

        return ciContext.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: options)
    }
}

// Quality adjustment via stdin signal
class QualityController {
    private let capturer: ScreenCapturer

    init(capturer: ScreenCapturer) {
        self.capturer = capturer
    }

    func startListening(inputInjector: InputInjector? = nil) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while let line = readLine() {
                guard let self = self else { break }
                if line.hasPrefix("quality:") {
                    let valueStr = line.dropFirst("quality:".count)
                    if let value = Float(valueStr) {
                        self.capturer.setQuality(value)
                        fputs("Quality set to \(value)\n", stderr)
                    }
                } else if line.hasPrefix("input:") {
                    let json = String(line.dropFirst("input:".count))
                    inputInjector?.handleInput(json)
                }
            }
        }
    }
}

enum CaptureError: Error, CustomStringConvertible {
    case displayNotFound(CGDirectDisplayID)

    var description: String {
        switch self {
        case .displayNotFound(let id):
            return "Display \(id) not found. Is the virtual display still active?"
        }
    }
}
