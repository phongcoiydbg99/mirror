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

  @override
  void initState() {
    super.initState();
    _startStream();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }

  void _startStream() async {
    try {
      final request = http.Request('GET', Uri.parse(widget.streamUrl));
      final client = http.Client();
      final response = await client.send(request);

      final buffer = BytesBuilder();
      bool inImage = false;

      _subscription = response.stream.listen(
        (chunk) {
          if (_disposed) return;

          for (int i = 0; i < chunk.length; i++) {
            buffer.addByte(chunk[i]);
            final bytes = buffer.toBytes();

            if (bytes.length >= 2 &&
                bytes[bytes.length - 2] == 0xFF &&
                bytes[bytes.length - 1] == 0xD8 &&
                !inImage) {
              buffer.clear();
              buffer.addByte(0xFF);
              buffer.addByte(0xD8);
              inImage = true;
            }

            if (inImage &&
                bytes.length >= 2 &&
                bytes[bytes.length - 2] == 0xFF &&
                bytes[bytes.length - 1] == 0xD9) {
              if (mounted && !_disposed) {
                setState(() {
                  _currentFrame = Uint8List.fromList(buffer.toBytes());
                });
              }
              buffer.clear();
              inImage = false;
            }
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
