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

      _socket!.listen(
        (data) {
          if (_disposed) return;
          if (data is List<int>) {
            _frameCount++;
            if (_frameCount <= 3) {
              debugPrint('[mjpeg] frame #$_frameCount size=${data.length}');
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
