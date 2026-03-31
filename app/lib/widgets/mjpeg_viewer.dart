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
  HttpClient? _client;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _startStream();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _client?.close(force: true);
    super.dispose();
  }

  void _startStream() async {
    try {
      _client = HttpClient();
      _client!.connectionTimeout = const Duration(seconds: 5);
      final request = await _client!.getUrl(Uri.parse(widget.streamUrl));
      final response = await request.close();

      debugPrint('[mjpeg] connected, status: ${response.statusCode}');

      final buffer = BytesBuilder(copy: false);
      bool inImage = false;
      int prevByte = 0;
      int frameCount = 0;
      int chunkCount = 0;

      _subscription = response.listen(
        (chunk) {
          if (_disposed) return;
          chunkCount++;
          if (chunkCount <= 5) {
            debugPrint('[mjpeg] chunk #$chunkCount size=${chunk.length}');
          }

          for (int i = 0; i < chunk.length; i++) {
            final byte = chunk[i];

            // Detect JPEG start: 0xFF 0xD8
            if (prevByte == 0xFF && byte == 0xD8 && !inImage) {
              buffer.clear();
              buffer.add([0xFF, 0xD8]);
              inImage = true;
              prevByte = byte;
              continue;
            }

            if (inImage) {
              buffer.addByte(byte);

              // Detect JPEG end: 0xFF 0xD9
              if (prevByte == 0xFF && byte == 0xD9) {
                frameCount++;
                final frame = buffer.takeBytes();
                if (frameCount <= 3) {
                  debugPrint('[mjpeg] frame #$frameCount size=${frame.length}');
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
          debugPrint('[mjpeg] error: $e');
          if (!_disposed) widget.onError?.call();
        },
        onDone: () {
          debugPrint('[mjpeg] stream done');
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
