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
  WebSocket? _socket;
  int _frameCount = 0;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _disposed = true;
    _socket?.close();
    super.dispose();
  }

  String get _wsUrl {
    // Convert http://host:port/stream to ws://host:port/video
    return widget.streamUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('/stream', '/video');
  }

  void _connect() async {
    try {
      debugPrint('[mjpeg] connecting WebSocket: $_wsUrl');
      _socket = await WebSocket.connect(_wsUrl)
          .timeout(const Duration(seconds: 5));
      debugPrint('[mjpeg] WebSocket connected');

      DateTime lastFpsLog = DateTime.now();
      int fpsCounter = 0;

      _socket!.listen(
        (data) {
          if (_disposed) return;
          if (data is List<int>) {
            _frameCount++;
            fpsCounter++;

            // Log FPS every 5 seconds
            final now = DateTime.now();
            if (now.difference(lastFpsLog).inSeconds >= 5) {
              final fps = (fpsCounter / now.difference(lastFpsLog).inMilliseconds * 1000).toStringAsFixed(1);
              debugPrint('[mjpeg] receiving $fps fps, frame size: ${(data.length / 1024).toStringAsFixed(0)}KB');
              fpsCounter = 0;
              lastFpsLog = now;
            }

            if (mounted) {
              setState(() {
                _currentFrame = Uint8List.fromList(data);
              });
            }
          }
        },
        onError: (e) {
          debugPrint('[mjpeg] WebSocket error: $e');
          if (!_disposed) widget.onError?.call();
        },
        onDone: () {
          debugPrint('[mjpeg] WebSocket closed, frames=$_frameCount');
          if (!_disposed) widget.onError?.call();
        },
      );
    } catch (e) {
      debugPrint('[mjpeg] WebSocket connect error: $e');
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
