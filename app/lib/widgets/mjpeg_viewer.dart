import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';

class MjpegViewer extends StatefulWidget {
  final String streamUrl;
  final VoidCallback? onError;
  final BoxFit fit;

  const MjpegViewer({
    super.key,
    required this.streamUrl,
    this.onError,
    this.fit = BoxFit.contain,
  });

  @override
  State<MjpegViewer> createState() => _MjpegViewerState();
}

class _MjpegViewerState extends State<MjpegViewer> {
  Uint8List? _currentFrame;
  bool _disposed = false;
  Socket? _socket;

  @override
  void initState() {
    super.initState();
    _startStream();
  }

  @override
  void dispose() {
    _disposed = true;
    _socket?.destroy();
    super.dispose();
  }

  void _startStream() async {
    try {
      final uri = Uri.parse(widget.streamUrl);
      _socket = await Socket.connect(uri.host, uri.port,
          timeout: const Duration(seconds: 5));

      // Send raw HTTP GET request
      _socket!.write('GET ${uri.path} HTTP/1.1\r\n'
          'Host: ${uri.host}:${uri.port}\r\n'
          'Connection: keep-alive\r\n'
          '\r\n');

      debugPrint('[mjpeg] socket connected to ${uri.host}:${uri.port}');

      final buffer = BytesBuilder(copy: false);
      bool inImage = false;
      int prevByte = 0;
      int frameCount = 0;
      int totalBytes = 0;
      bool headersParsed = false;

      _socket!.listen(
        (chunk) {
          if (_disposed) return;
          totalBytes += chunk.length;

          // Skip HTTP response headers on first data
          int startIdx = 0;
          if (!headersParsed) {
            final str = String.fromCharCodes(chunk);
            final headerEnd = str.indexOf('\r\n\r\n');
            if (headerEnd >= 0) {
              headersParsed = true;
              startIdx = headerEnd + 4;
              debugPrint('[mjpeg] headers parsed, body starts at $startIdx');
            } else {
              return; // Still in headers
            }
          }

          for (int i = startIdx; i < chunk.length; i++) {
            final byte = chunk[i];

            if (prevByte == 0xFF && byte == 0xD8 && !inImage) {
              buffer.clear();
              buffer.add([0xFF, 0xD8]);
              inImage = true;
              prevByte = byte;
              continue;
            }

            if (inImage) {
              buffer.addByte(byte);

              if (prevByte == 0xFF && byte == 0xD9) {
                frameCount++;
                final frame = buffer.takeBytes();
                if (frameCount <= 5) {
                  debugPrint(
                      '[mjpeg] frame #$frameCount size=${frame.length} totalBytes=$totalBytes');
                }
                if (mounted && !_disposed) {
                  setState(() {
                    _currentFrame = Uint8List.fromList(frame);
                  });
                }
                inImage = false;
              }
            }

            prevByte = byte;
          }
        },
        onError: (e) {
          debugPrint('[mjpeg] socket error: $e');
          if (!_disposed) widget.onError?.call();
        },
        onDone: () {
          debugPrint('[mjpeg] socket closed, frames=$frameCount');
          if (!_disposed) widget.onError?.call();
        },
      );
    } catch (e) {
      debugPrint('[mjpeg] connection error: $e');
      if (!_disposed) widget.onError?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentFrame == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Image.memory(
      _currentFrame!,
      fit: widget.fit,
      gaplessPlayback: true,
      width: double.infinity,
      height: double.infinity,
    );
  }
}
