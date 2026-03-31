import 'package:flutter/material.dart';
import '../services/input_service.dart';

class TrackpadOverlay extends StatefulWidget {
  final InputService inputService;
  final Widget child;
  final double sensitivity;

  const TrackpadOverlay({
    super.key,
    required this.inputService,
    required this.child,
    this.sensitivity = 1.5,
  });

  @override
  State<TrackpadOverlay> createState() => _TrackpadOverlayState();
}

class _TrackpadOverlayState extends State<TrackpadOverlay> {
  bool _isDragging = false;
  DateTime? _panStartTime;
  double _totalPanDistance = 0;
  int _pointerCount = 0;
  double _lastScale = 1.0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _pointerCount++,
      onPointerUp: (_) => _pointerCount = (_pointerCount - 1).clamp(0, 10),
      onPointerCancel: (_) => _pointerCount = (_pointerCount - 1).clamp(0, 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,

        onLongPress: () {
          widget.inputService.send(InputMessage.rightClickHere());
        },

        onPanStart: (details) {
          _panStartTime = DateTime.now();
          _totalPanDistance = 0;
        },

        onPanUpdate: (details) {
          _totalPanDistance += details.delta.distance;

          if (_pointerCount >= 2) {
            widget.inputService.send(
              InputMessage.scroll(details.delta.dx, -details.delta.dy),
            );
          } else if (!_isDragging) {
            widget.inputService.send(
              InputMessage.move(
                details.delta.dx * widget.sensitivity,
                details.delta.dy * widget.sensitivity,
              ),
            );
          } else {
            widget.inputService.send(
              InputMessage.dragDelta(
                details.delta.dx * widget.sensitivity,
                details.delta.dy * widget.sensitivity,
                'move',
              ),
            );
          }
        },

        onPanEnd: (details) {
          final duration = DateTime.now().difference(_panStartTime ?? DateTime.now());

          if (_isDragging) {
            _isDragging = false;
            widget.inputService.send(InputMessage.dragDelta(0, 0, 'end'));
          } else if (duration.inMilliseconds < 200 && _totalPanDistance < 10) {
            widget.inputService.send(InputMessage.tapHere());
          }

          _panStartTime = null;
        },

        onDoubleTap: () {
          _isDragging = true;
          widget.inputService.send(InputMessage.dragDelta(0, 0, 'start'));
        },

        onScaleStart: (details) {
          _lastScale = 1.0;
        },

        onScaleUpdate: (details) {
          if ((details.scale - _lastScale).abs() > 0.01 && details.scale != 1.0) {
            widget.inputService.send(InputMessage.pinch(details.scale));
            _lastScale = details.scale;
          }
        },

        child: widget.child,
      ),
    );
  }
}
