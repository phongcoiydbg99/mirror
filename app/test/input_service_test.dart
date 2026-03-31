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
  });
}
