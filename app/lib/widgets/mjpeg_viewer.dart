import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
  StreamSubscription? _subscription;
  bool _disposed = false;
  http.Client? _client;

  @override
  void initState() {
    super.initState();
    _startStream();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _client?.close();
    super.dispose();
  }

  void _startStream() async {
    try {
      final request = http.Request('GET', Uri.parse(widget.streamUrl));
      _client = http.Client();
      final response = await _client!.send(request);

      final buffer = BytesBuilder(copy: false);
      bool inImage = false;
      int prevByte = 0;

      _subscription = response.stream.listen(
        (chunk) {
          if (_disposed) return;

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
                if (mounted && !_disposed) {
                  final frame = buffer.takeBytes();
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
        onError: (_) {
          if (!_disposed) widget.onError?.call();
        },
        onDone: () {
          if (!_disposed) widget.onError?.call();
        },
      );
    } catch (_) {
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
