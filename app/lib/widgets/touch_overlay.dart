import 'package:flutter/material.dart';
import '../services/input_service.dart';

class AbsoluteTouchOverlay extends StatefulWidget {
  final InputService inputService;
  final Widget child;

  const AbsoluteTouchOverlay({
    super.key,
    required this.inputService,
    required this.child,
  });

  @override
  State<AbsoluteTouchOverlay> createState() => _AbsoluteTouchOverlayState();
}

class _AbsoluteTouchOverlayState extends State<AbsoluteTouchOverlay> {
  bool _isDragging = false;
  int _pointerCount = 0;
  Offset? _lastFocalPoint;
  double _lastScale = 1.0;

  Offset _relativePosition(Offset globalPos, Size size) {
    final box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(globalPos);
    return Offset(
      (local.dx / size.width).clamp(0.0, 1.0),
      (local.dy / size.height).clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        return Listener(
          onPointerDown: (_) => _pointerCount++,
          onPointerUp: (_) => _pointerCount = (_pointerCount - 1).clamp(0, 10),
          onPointerCancel: (_) => _pointerCount = (_pointerCount - 1).clamp(0, 10),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,

            onTapUp: (details) {
              final rel = _relativePosition(details.globalPosition, size);
              widget.inputService.send(InputMessage.tap(rel.dx, rel.dy));
            },

            onLongPressStart: (details) {
              final rel = _relativePosition(details.globalPosition, size);
              widget.inputService.send(InputMessage.rightClick(rel.dx, rel.dy));
            },

            // Use onScale* for both drag (1 finger) and pinch/scroll (2 fingers)
            onScaleStart: (details) {
              _lastFocalPoint = details.focalPoint;
              _lastScale = 1.0;
              if (_pointerCount <= 1) {
                _isDragging = true;
                final rel = _relativePosition(details.focalPoint, size);
                widget.inputService.send(InputMessage.drag(rel.dx, rel.dy, 'start'));
              }
            },

            onScaleUpdate: (details) {
              final rel = _relativePosition(details.focalPoint, size);

              if (_pointerCount >= 2) {
                // Pinch zoom
                if ((details.scale - _lastScale).abs() > 0.01 && details.scale != 1.0) {
                  widget.inputService.send(InputMessage.pinchAt(rel.dx, rel.dy, details.scale));
                  _lastScale = details.scale;
                }

                // Two-finger scroll
                if (_lastFocalPoint != null) {
                  final dy = details.focalPoint.dy - _lastFocalPoint!.dy;
                  final dx = details.focalPoint.dx - _lastFocalPoint!.dx;
                  if (dy.abs() > 1 || dx.abs() > 1) {
                    widget.inputService.send(InputMessage.scrollAt(rel.dx, rel.dy, dx, -dy));
                  }
                }
              } else if (_isDragging) {
                // One-finger drag
                widget.inputService.send(InputMessage.drag(rel.dx, rel.dy, 'move'));
              }

              _lastFocalPoint = details.focalPoint;
            },

            onScaleEnd: (details) {
              if (_isDragging) {
                _isDragging = false;
                widget.inputService.send(InputMessage.drag(0, 0, 'end'));
              }
            },

            child: widget.child,
          ),
        );
      },
    );
  }
}
