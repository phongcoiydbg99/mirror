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
  Offset? _lastScalePos;
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

            onPanStart: (details) {
              _isDragging = true;
              final rel = _relativePosition(details.globalPosition, size);
              widget.inputService.send(InputMessage.drag(rel.dx, rel.dy, 'start'));
            },

            onPanUpdate: (details) {
              if (_isDragging) {
                final rel = _relativePosition(details.globalPosition, size);
                widget.inputService.send(InputMessage.drag(rel.dx, rel.dy, 'move'));
              }
            },

            onPanEnd: (details) {
              if (_isDragging) {
                _isDragging = false;
                widget.inputService.send(InputMessage.drag(0, 0, 'end'));
              }
            },

            onScaleStart: (details) {
              _lastScalePos = details.focalPoint;
              _lastScale = 1.0;
            },

            onScaleUpdate: (details) {
              final rel = _relativePosition(details.focalPoint, size);

              if ((details.scale - _lastScale).abs() > 0.01) {
                widget.inputService.send(InputMessage.pinchAt(rel.dx, rel.dy, details.scale));
                _lastScale = details.scale;
              }

              if (_pointerCount >= 2 && _lastScalePos != null) {
                final dy = (details.focalPoint.dy - _lastScalePos!.dy);
                final dx = (details.focalPoint.dx - _lastScalePos!.dx);
                if (dy.abs() > 1 || dx.abs() > 1) {
                  widget.inputService.send(InputMessage.scrollAt(rel.dx, rel.dy, dx, -dy));
                  _lastScalePos = details.focalPoint;
                }
              }
            },

            child: widget.child,
          ),
        );
      },
    );
  }
}
