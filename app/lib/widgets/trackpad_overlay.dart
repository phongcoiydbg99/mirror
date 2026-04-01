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
  DateTime? _scaleStartTime;
  double _totalDistance = 0;
  int _pointerCount = 0;
  Offset? _lastFocalPoint;
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

        onDoubleTap: () {
          _isDragging = true;
          widget.inputService.send(InputMessage.dragDelta(0, 0, 'start'));
        },

        // Use onScale* only (superset of pan)
        onScaleStart: (details) {
          _scaleStartTime = DateTime.now();
          _totalDistance = 0;
          _lastFocalPoint = details.focalPoint;
          _lastScale = 1.0;
        },

        onScaleUpdate: (details) {
          final delta = _lastFocalPoint != null
              ? details.focalPoint - _lastFocalPoint!
              : Offset.zero;
          _totalDistance += delta.distance;

          if (_pointerCount >= 2) {
            // Two-finger: scroll
            widget.inputService.send(
              InputMessage.scroll(delta.dx, -delta.dy),
            );

            // Pinch zoom
            if ((details.scale - _lastScale).abs() > 0.01 && details.scale != 1.0) {
              widget.inputService.send(InputMessage.pinch(details.scale));
              _lastScale = details.scale;
            }
          } else if (_isDragging) {
            // Dragging mode
            widget.inputService.send(
              InputMessage.dragDelta(
                delta.dx * widget.sensitivity,
                delta.dy * widget.sensitivity,
                'move',
              ),
            );
          } else {
            // One-finger: move cursor
            widget.inputService.send(
              InputMessage.move(
                delta.dx * widget.sensitivity,
                delta.dy * widget.sensitivity,
              ),
            );
          }

          _lastFocalPoint = details.focalPoint;
        },

        onScaleEnd: (details) {
          final duration = DateTime.now().difference(_scaleStartTime ?? DateTime.now());

          if (_isDragging) {
            _isDragging = false;
            widget.inputService.send(InputMessage.dragDelta(0, 0, 'end'));
          } else if (duration.inMilliseconds < 200 && _totalDistance < 10) {
            // Quick tap
            widget.inputService.send(InputMessage.tapHere());
          }

          _scaleStartTime = null;
          _lastFocalPoint = null;
        },

        child: widget.child,
      ),
    );
  }
}
