import 'package:flutter/material.dart';
import '../services/input_service.dart';

class TouchOverlay extends StatefulWidget {
  final InputService inputService;
  final Widget child;

  const TouchOverlay({
    super.key,
    required this.inputService,
    required this.child,
  });

  @override
  State<TouchOverlay> createState() => _TouchOverlayState();
}

class _TouchOverlayState extends State<TouchOverlay> {
  bool _isDragging = false;
  DateTime? _tapDownTime;
  Offset? _tapDownPos;

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

        return GestureDetector(
          behavior: HitTestBehavior.opaque,

          onTapDown: (details) {
            _tapDownTime = DateTime.now();
            _tapDownPos = details.globalPosition;
          },

          onTapUp: (details) {
            final rel = _relativePosition(details.globalPosition, size);
            widget.inputService.send(InputMessage.tap(rel.dx, rel.dy));
          },

          onLongPress: () {
            if (_tapDownPos != null) {
              final rel = _relativePosition(_tapDownPos!, size);
              widget.inputService.send(InputMessage.rightClick(rel.dx, rel.dy));
            }
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

          child: widget.child,
        );
      },
    );
  }
}
