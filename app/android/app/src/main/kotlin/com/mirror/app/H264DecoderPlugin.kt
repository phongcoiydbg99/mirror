package com.mirror.app

import android.media.MediaCodec
import android.media.MediaFormat
import android.view.Surface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

class H264DecoderPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var textureRegistry: TextureRegistry? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var decoder: MediaCodec? = null
    private var surface: Surface? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.mirror.app/h264_decoder")
        channel?.setMethodCallHandler(this)
        textureRegistry = binding.textureRegistry
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        dispose()
        channel?.setMethodCallHandler(null)
        channel = null
        textureRegistry = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                val width = call.argument<Int>("width") ?: 585
                val height = call.argument<Int>("height") ?: 1266
                initialize(width, height, result)
            }
            "feedNalUnit" -> {
                val data = call.argument<ByteArray>("data") ?: return result.error("INVALID", "No data", null)
                feedNalUnit(data, result)
            }
            "dispose" -> {
                dispose()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun initialize(width: Int, height: Int, result: MethodChannel.Result) {
        try {
            dispose()

            textureEntry = textureRegistry?.createSurfaceTexture()
            val surfaceTexture = textureEntry?.surfaceTexture() ?: return result.error("TEXTURE", "Failed to create texture", null)
            surfaceTexture.setDefaultBufferSize(width, height)
            surface = Surface(surfaceTexture)

            val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height)
            format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1)

            decoder = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            decoder?.configure(format, surface, null, 0)
            decoder?.start()

            result.success(mapOf("textureId" to textureEntry?.id()))
        } catch (e: Exception) {
            result.error("INIT_FAILED", e.message, null)
        }
    }

    private fun feedNalUnit(data: ByteArray, result: MethodChannel.Result) {
        val codec = decoder ?: return result.error("NOT_INIT", "Decoder not initialized", null)

        try {
            val startCode = byteArrayOf(0x00, 0x00, 0x00, 0x01)
            val nalWithStartCode = startCode + data

            val inputIndex = codec.dequeueInputBuffer(0)
            if (inputIndex >= 0) {
                val inputBuffer = codec.getInputBuffer(inputIndex) ?: return result.success(null)
                inputBuffer.clear()
                inputBuffer.put(nalWithStartCode)
                codec.queueInputBuffer(inputIndex, 0, nalWithStartCode.size, 0, 0)
            }

            val bufferInfo = MediaCodec.BufferInfo()
            while (true) {
                val outputIndex = codec.dequeueOutputBuffer(bufferInfo, 0)
                if (outputIndex >= 0) {
                    codec.releaseOutputBuffer(outputIndex, true)
                } else {
                    break
                }
            }

            result.success(null)
        } catch (e: Exception) {
            result.error("DECODE_FAILED", e.message, null)
        }
    }

    private fun dispose() {
        try {
            decoder?.stop()
            decoder?.release()
        } catch (_: Exception) {}
        decoder = null
        surface?.release()
        surface = null
        textureEntry?.release()
        textureEntry = null
    }
}
