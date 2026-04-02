import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class H264Viewer extends StatefulWidget {
  final String wsUrl;
  final VoidCallback? onError;
  final BoxFit fit;

  const H264Viewer({
    super.key,
    required this.wsUrl,
    this.onError,
    this.fit = BoxFit.contain,
  });

  @override
  State<H264Viewer> createState() => _H264ViewerState();
}

class _H264ViewerState extends State<H264Viewer> {
  static const _channel = MethodChannel('com.mirror.app/h264_decoder');
  WebSocket? _socket;
  int? _textureId;
  bool _disposed = false;
  int _nalCount = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _disposed = true;
    _socket?.close();
    _channel.invokeMethod('dispose');
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final result = await _channel.invokeMethod<Map>('initialize', {
        'width': 585,
        'height': 1266,
      });
      final textureId = result?['textureId'] as int?;
      if (textureId == null || _disposed) return;

      setState(() => _textureId = textureId);
      _connectWebSocket();
    } catch (e) {
      debugPrint('[h264] initialize error: $e');
      if (!_disposed) widget.onError?.call();
    }
  }

  void _connectWebSocket() async {
    try {
      debugPrint('[h264] connecting WebSocket: ${widget.wsUrl}');
      _socket = await WebSocket.connect(widget.wsUrl)
          .timeout(const Duration(seconds: 5));
      debugPrint('[h264] WebSocket connected');

      DateTime lastFpsLog = DateTime.now();
      int fpsCounter = 0;

      _socket!.listen(
        (data) {
          if (_disposed) return;
          if (data is List<int>) {
            final bytes = Uint8List.fromList(data);
            _processPacket(bytes);

            fpsCounter++;
            final now = DateTime.now();
            if (now.difference(lastFpsLog).inSeconds >= 5) {
              final fps = (fpsCounter / now.difference(lastFpsLog).inMilliseconds * 1000).toStringAsFixed(1);
              debugPrint('[h264] receiving $fps NAL/s, total: $_nalCount');
              fpsCounter = 0;
              lastFpsLog = now;
            }
          }
        },
        onError: (e) {
          debugPrint('[h264] WebSocket error: $e');
          if (!_disposed) widget.onError?.call();
        },
        onDone: () {
          debugPrint('[h264] WebSocket closed');
          if (!_disposed) widget.onError?.call();
        },
      );
    } catch (e) {
      debugPrint('[h264] WebSocket connect error: $e');
      if (!_disposed) widget.onError?.call();
    }
  }

  void _processPacket(Uint8List packet) {
    int offset = 0;
    while (offset + 4 <= packet.length) {
      final length = (packet[offset] << 24) |
          (packet[offset + 1] << 16) |
          (packet[offset + 2] << 8) |
          packet[offset + 3];
      offset += 4;

      if (offset + length > packet.length) break;

      final nalUnit = packet.sublist(offset, offset + length);
      offset += length;
      _nalCount++;

      _channel.invokeMethod('feedNalUnit', {'data': nalUnit});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_textureId == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Texture(
      textureId: _textureId!,
      filterQuality: FilterQuality.low,
    );
  }
}
