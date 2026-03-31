import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/input_service.dart';

void main() {
  group('InputMessage', () {
    test('tap serializes correctly', () {
      final msg = InputMessage.tap(0.5, 0.3);
      expect(msg.toJson(), '{"type":"tap","x":0.5,"y":0.3}');
    });

    test('rightclick serializes correctly', () {
      final msg = InputMessage.rightClick(0.2, 0.8);
      expect(msg.toJson(), '{"type":"rightclick","x":0.2,"y":0.8}');
    });

    test('drag serializes correctly', () {
      final msg = InputMessage.drag(0.5, 0.5, 'move');
      expect(msg.toJson(), '{"type":"drag","x":0.5,"y":0.5,"phase":"move"}');
    });

    test('key text serializes correctly', () {
      final msg = InputMessage.keyText('hello');
      expect(msg.toJson(), '{"type":"key","text":"hello"}');
    });

    test('key code serializes correctly', () {
      final msg = InputMessage.keyCode('enter');
      expect(msg.toJson(), '{"type":"key","code":"enter"}');
    });

    test('move serializes correctly', () {
      final msg = InputMessage.move(12.5, -8.0);
      expect(msg.toJson(), '{"type":"move","dx":12.5,"dy":-8.0}');
    });

    test('scroll with position serializes correctly', () {
      final msg = InputMessage.scrollAt(0.5, 0.3, 0, -3.5);
      expect(msg.toJson(), '{"type":"scroll","x":0.5,"y":0.3,"dx":0.0,"dy":-3.5}');
    });

    test('scroll without position serializes correctly', () {
      final msg = InputMessage.scroll(0, -3.5);
      expect(msg.toJson(), '{"type":"scroll","dx":0.0,"dy":-3.5}');
    });

    test('pinch with position serializes correctly', () {
      final msg = InputMessage.pinchAt(0.5, 0.3, 1.2);
      expect(msg.toJson(), '{"type":"pinch","x":0.5,"y":0.3,"scale":1.2}');
    });

    test('pinch without position serializes correctly', () {
      final msg = InputMessage.pinch(1.2);
      expect(msg.toJson(), '{"type":"pinch","scale":1.2}');
    });

    test('tap without coordinates serializes correctly', () {
      final msg = InputMessage.tapHere();
      expect(msg.toJson(), '{"type":"tap"}');
    });

    test('rightclick without coordinates serializes correctly', () {
      final msg = InputMessage.rightClickHere();
      expect(msg.toJson(), '{"type":"rightclick"}');
    });

    test('key with modifiers serializes correctly', () {
      final msg = InputMessage.keyWithModifiers('c', ['cmd']);
      expect(msg.toJson(), '{"type":"key","code":"c","modifiers":["cmd"]}');
    });

    test('drag with delta serializes correctly', () {
      final msg = InputMessage.dragDelta(5.0, -3.0, 'move');
      expect(msg.toJson(), '{"type":"drag","dx":5.0,"dy":-3.0,"phase":"move"}');
    });
  });
}
