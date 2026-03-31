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
  int _frameCount = 0;
  int _errorCount = 0;

  @override
  void initState() {
    super.initState();
    _client = HttpClient();
    _client!.connectionTimeout = const Duration(seconds: 3);
    _startPolling();
  }

  @override
  void dispose() {
    _disposed = true;
    _client?.close(force: true);
    super.dispose();
  }

  // Derive /frame URL from /stream URL
  String get _frameUrl {
    return widget.streamUrl.replaceFirst('/stream', '/frame');
  }

  void _startPolling() async {
    debugPrint('[mjpeg] polling started: $_frameUrl');

    while (!_disposed) {
      try {
        final request = await _client!.getUrl(Uri.parse(_frameUrl));
        final response = await request.close();

        if (response.statusCode == 200) {
          final bytes = await response.fold<BytesBuilder>(
            BytesBuilder(),
            (builder, chunk) => builder..add(chunk),
          );
          final frame = bytes.takeBytes();

          _frameCount++;
          _errorCount = 0;

          if (_frameCount <= 3) {
            debugPrint('[mjpeg] frame #$_frameCount size=${frame.length}');
          }

          if (mounted && !_disposed) {
            setState(() {
              _currentFrame = Uint8List.fromList(frame);
            });
          }
        } else if (response.statusCode == 204) {
          // No frame yet
          await response.drain();
          await Future.delayed(const Duration(milliseconds: 100));
        } else {
          await response.drain();
          _errorCount++;
        }
      } catch (e) {
        _errorCount++;
        if (_errorCount <= 3) {
          debugPrint('[mjpeg] poll error #$_errorCount: $e');
        }
        if (_errorCount > 10) {
          debugPrint('[mjpeg] too many errors, stopping');
          if (!_disposed) widget.onError?.call();
          return;
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
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
