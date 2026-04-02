import Flutter
import VideoToolbox
import CoreVideo

class H264DecoderPlugin: NSObject, FlutterPlugin, FlutterTexture {
    private var textureRegistry: FlutterTextureRegistry?
    private var textureId: Int64 = -1
    private var latestPixelBuffer: CVPixelBuffer?
    private var decompressionSession: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    private var spsData: Data?
    private var ppsData: Data?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.mirror.app/h264_decoder", binaryMessenger: registrar.messenger())
        let instance = H264DecoderPlugin()
        instance.textureRegistry = registrar.textures()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            result(["textureId": registerTexture()])
        case "feedNalUnit":
            guard let args = call.arguments as? [String: Any],
                  let data = args["data"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID", message: "No data", details: nil))
                return
            }
            feedNalUnit(data.data, result: result)
        case "dispose":
            dispose()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let pixelBuffer = latestPixelBuffer else { return nil }
        return Unmanaged.passRetained(pixelBuffer)
    }

    private func registerTexture() -> Int64 {
        textureId = textureRegistry?.register(self) ?? -1
        return textureId
    }

    private func feedNalUnit(_ data: Data, result: @escaping FlutterResult) {
        let nalType = data[0] & 0x1f

        if nalType == 7 || nalType == 8 {
            handleParameterSet(data, nalType: nalType)
            result(nil)
            return
        }

        guard let session = decompressionSession, let formatDesc = formatDescription else {
            result(nil)
            return
        }

        // Create AVCC-formatted data: [4-byte length][NAL]
        var nalData = Data()
        var length = UInt32(data.count).bigEndian
        nalData.append(Data(bytes: &length, count: 4))
        nalData.append(data)

        var blockBuffer: CMBlockBuffer?
        nalData.withUnsafeMutableBytes { ptr in
            CMBlockBufferCreateWithMemoryBlock(
                allocator: nil,
                memoryBlock: ptr.baseAddress,
                blockLength: nalData.count,
                blockAllocator: kCFAllocatorNull,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: nalData.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
        }

        guard let blockBuffer = blockBuffer else {
            result(nil)
            return
        }

        var sampleBuffer: CMSampleBuffer?
        var sampleSize = nalData.count
        CMSampleBufferCreateReady(
            allocator: nil,
            dataBuffer: blockBuffer,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )

        guard let sampleBuffer = sampleBuffer else {
            result(nil)
            return
        }

        var flagOut: VTDecodeInfoFlags = []
        VTDecompressionSessionDecodeFrame(session, sampleBuffer: sampleBuffer, flags: [._EnableAsynchronousDecompression], infoFlagsOut: &flagOut) { [weak self] status, flags, imageBuffer, pts, duration in
            guard status == noErr, let pixelBuffer = imageBuffer else { return }
            self?.latestPixelBuffer = pixelBuffer
            if let id = self?.textureId, id >= 0 {
                DispatchQueue.main.async {
                    self?.textureRegistry?.textureFrameAvailable(id)
                }
            }
        }
        result(nil)
    }

    private func handleParameterSet(_ data: Data, nalType: UInt8) {
        if nalType == 7 { spsData = data }
        if nalType == 8 { ppsData = data }

        guard let sps = spsData, let pps = ppsData else { return }

        var newFormatDesc: CMVideoFormatDescription?

        sps.withUnsafeBytes { spsPtr in
            pps.withUnsafeBytes { ppsPtr in
                let parameterSets: [UnsafePointer<UInt8>] = [
                    spsPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    ppsPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
                ]
                let parameterSetSizes = [sps.count, pps.count]

                CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: nil,
                    parameterSetCount: 2,
                    parameterSetPointers: parameterSets,
                    parameterSetSizes: parameterSetSizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &newFormatDesc
                )
            }
        }

        guard let newFormatDesc = newFormatDesc else { return }
        formatDescription = newFormatDesc

        if let old = decompressionSession {
            VTDecompressionSessionInvalidate(old)
        }

        let destAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        var session: VTDecompressionSession?
        VTDecompressionSessionCreate(
            allocator: nil,
            formatDescription: newFormatDesc,
            decoderSpecification: nil,
            imageBufferAttributes: destAttrs as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &session
        )

        guard let session = session else { return }
        decompressionSession = session

        VTDecompressionSessionSetProperty(session, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
    }

    private func dispose() {
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }
        if textureId >= 0 {
            textureRegistry?.unregisterTexture(textureId)
            textureId = -1
        }
        latestPixelBuffer = nil
        formatDescription = nil
        spsData = nil
        ppsData = nil
    }
}
