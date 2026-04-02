import Foundation
import CoreGraphics
import CoreMedia
import CoreVideo
import VideoToolbox

class ScreenCapturer {
    private let displayID: CGDirectDisplayID
    private let fps: Int
    private var socketFD: Int32 = -1
    private var compressionSession: VTCompressionSession?
    private var captureTimer: DispatchSourceTimer?
    private let captureQueue = DispatchQueue(label: "capture")
    private var frameCount: Int64 = 0
    private var pixelBufferPool: CVPixelBufferPool?
    private var width: Int = 0
    private var height: Int = 0

    // Stats
    private var statsCaptureCount = 0
    private var statsSendCount = 0
    private var statsDropCount = 0
    private var statsLastTime = Date()

    init(displayID: CGDirectDisplayID, fps: Int = 30) {
        self.displayID = displayID
        self.fps = fps
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

        let flags = fcntl(fd, F_GETFL, 0)
        fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        var bufSize: Int32 = 512 * 1024
        setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &bufSize, socklen_t(MemoryLayout<Int32>.size))

        var noDelay: Int32 = 1
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &noDelay, socklen_t(MemoryLayout<Int32>.size))

        socketFD = fd
        fputs("TCP connected to 127.0.0.1:\(port) (fd=\(fd), non-blocking, 512KB buffer)\n", stderr)
    }

    func start() throws {
        let bounds = CGDisplayBounds(displayID)
        width = Int(bounds.width) / 2
        height = Int(bounds.height) / 2

        let poolAttrs: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 3
        ]
        let bufferAttrs: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        CVPixelBufferPoolCreate(nil, poolAttrs as CFDictionary, bufferAttrs as CFDictionary, &pixelBufferPool)

        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: [
                kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true
            ] as CFDictionary,
            imageBufferAttributes: bufferAttrs as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )

        guard status == noErr, let session = session else {
            throw CaptureError.encoderCreateFailed(status)
        }

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: (fps * 2) as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: (2_000_000) as CFNumber)

        VTCompressionSessionPrepareToEncodeFrames(session)
        compressionSession = session

        startCaptureTimer()

        fputs("H264 capture started: \(width)x\(height) @ \(fps)fps\n", stderr)
    }

    private func startCaptureTimer() {
        let interval = 1.0 / Double(fps)
        let timer = DispatchSource.makeTimerSource(queue: captureQueue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.captureAndEncode()
        }
        timer.resume()
        captureTimer = timer
    }

    private func captureAndEncode() {
        guard let session = compressionSession, let pool = pixelBufferPool else { return }

        guard let cgImage = CGDisplayCreateImage(displayID) else { return }

        statsCaptureCount += 1

        let now = Date()
        if now.timeIntervalSince(statsLastTime) >= 5 {
            let elapsed = now.timeIntervalSince(statsLastTime)
            let capFps = Double(statsCaptureCount) / elapsed
            let sendFps = Double(statsSendCount) / elapsed
            fputs("[swift] capture: \(String(format: "%.1f", capFps)) fps, sent: \(String(format: "%.1f", sendFps)) fps, dropped: \(statsDropCount)\n", stderr)
            statsCaptureCount = 0
            statsSendCount = 0
            statsDropCount = 0
            statsLastTime = now
        }

        var pixelBuffer: CVPixelBuffer?
        let poolStatus = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard poolStatus == kCVReturnSuccess, let pixelBuffer = pixelBuffer else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            return
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        let pts = CMTimeMake(value: frameCount, timescale: CMTimeScale(fps))
        frameCount += 1

        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: pts,
            duration: CMTimeMake(value: 1, timescale: CMTimeScale(fps)),
            frameProperties: nil,
            infoFlagsOut: nil
        ) { [weak self] status, flags, sampleBuffer in
            guard status == noErr, let sampleBuffer = sampleBuffer else { return }
            self?.handleEncodedFrame(sampleBuffer)
        }
    }

    private func handleEncodedFrame(_ sampleBuffer: CMSampleBuffer) {
        guard socketFD >= 0 else { return }

        let isKeyframe = sampleBuffer.sampleAttachments.first?[.notSync] == nil

        if isKeyframe, let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
            sendParameterSets(formatDesc)
        }

        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)

        guard let dataPointer = dataPointer else { return }

        var offset = 0
        while offset < totalLength - 4 {
            var nalLength: UInt32 = 0
            memcpy(&nalLength, dataPointer + offset, 4)
            nalLength = nalLength.bigEndian
            offset += 4

            let nalSize = Int(nalLength)
            guard offset + nalSize <= totalLength else { break }

            sendNALUnit(UnsafeRawPointer(dataPointer + offset), size: nalSize)
            offset += nalSize
        }
    }

    private func sendParameterSets(_ formatDesc: CMFormatDescription) {
        var spsSize: Int = 0
        var spsCount: Int = 0
        var spsPointer: UnsafePointer<UInt8>?
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, parameterSetIndex: 0, parameterSetPointerOut: &spsPointer, parameterSetSizeOut: &spsSize, parameterSetCountOut: &spsCount, nalUnitHeaderLengthOut: nil)
        if let spsPointer = spsPointer, spsSize > 0 {
            sendNALUnit(UnsafeRawPointer(spsPointer), size: spsSize)
        }

        var ppsSize: Int = 0
        var ppsPointer: UnsafePointer<UInt8>?
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, parameterSetIndex: 1, parameterSetPointerOut: &ppsPointer, parameterSetSizeOut: &ppsSize, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
        if let ppsPointer = ppsPointer, ppsSize > 0 {
            sendNALUnit(UnsafeRawPointer(ppsPointer), size: ppsSize)
        }
    }

    private func sendNALUnit(_ pointer: UnsafeRawPointer, size: Int) {
        var lengthBE = UInt32(size).bigEndian
        var packet = Data(bytes: &lengthBE, count: 4)
        packet.append(Data(bytes: pointer, count: size))

        packet.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            let result = Darwin.send(socketFD, base, packet.count, MSG_DONTWAIT)
            if result > 0 {
                statsSendCount += 1
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                statsDropCount += 1
            }
        }
    }

    func stop() {
        captureTimer?.cancel()
        captureTimer = nil
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
        if socketFD >= 0 {
            Darwin.close(socketFD)
            socketFD = -1
        }
        fputs("H264 capture stopped\n", stderr)
    }

    func setQuality(_ quality: Float) {
        guard let session = compressionSession else { return }
        let bitrate = Int(500_000 + Double(quality) * 3_500_000)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFNumber)
    }
}

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
    case encoderCreateFailed(OSStatus)

    var description: String {
        switch self {
        case .displayNotFound(let id):
            return "Display \(id) not found."
        case .encoderCreateFailed(let status):
            return "Failed to create H264 encoder: \(status)"
        }
    }
}
