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
    private let writeQueue = DispatchQueue(label: "stdout-writer")
    private var isWriting = false

    init(displayID: CGDirectDisplayID, fps: Int = 30) {
        self.displayID = displayID
        self.fps = fps
        super.init()
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
        fputs("Screen capture started: \(targetDisplay.width)x\(targetDisplay.height) @ \(fps)fps\n", stderr)
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
        fputs("Screen capture stopped\n", stderr)
    }

    func setQuality(_ quality: Float) {
        jpegQuality = max(0.1, min(1.0, quality))
    }

    // SCStreamOutput delegate
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Drop frame if previous write hasn't finished (prevents pipe backpressure)
        guard !isWriting else { return }

        guard let jpegData = encodeJPEG(pixelBuffer: imageBuffer) else { return }

        // Write MJPEG frame to stdout on a separate queue to avoid blocking capture
        let header = "--\(boundary)\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpegData.count)\r\n\r\n"
        if let headerData = header.data(using: .utf8) {
            var frame = Data()
            frame.append(headerData)
            frame.append(jpegData)
            frame.append(Data("\r\n".utf8))

            isWriting = true
            writeQueue.async { [weak self] in
                FileHandle.standardOutput.write(frame)
                fflush(stdout)
                self?.isWriting = false
            }
        }
    }

    private func encodeJPEG(pixelBuffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = ciContext

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let options: [CIImageRepresentationOption: Any] = [
            kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: jpegQuality
        ]

        return context.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: options)
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
