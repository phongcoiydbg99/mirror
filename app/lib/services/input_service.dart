import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class InputMessage {
  final Map<String, dynamic> _data;

  InputMessage._(this._data);

  factory InputMessage.tap(double x, double y) =>
      InputMessage._({'type': 'tap', 'x': x, 'y': y});

  factory InputMessage.rightClick(double x, double y) =>
      InputMessage._({'type': 'rightclick', 'x': x, 'y': y});

  factory InputMessage.drag(double x, double y, String phase) =>
      InputMessage._({'type': 'drag', 'x': x, 'y': y, 'phase': phase});

  factory InputMessage.keyText(String text) =>
      InputMessage._({'type': 'key', 'text': text});

  factory InputMessage.keyCode(String code) =>
      InputMessage._({'type': 'key', 'code': code});

  factory InputMessage.tapHere() =>
      InputMessage._({'type': 'tap'});

  factory InputMessage.rightClickHere() =>
      InputMessage._({'type': 'rightclick'});

  factory InputMessage.move(double dx, double dy) =>
      InputMessage._({'type': 'move', 'dx': dx, 'dy': dy});

  factory InputMessage.dragDelta(double dx, double dy, String phase) =>
      InputMessage._({'type': 'drag', 'dx': dx, 'dy': dy, 'phase': phase});

  factory InputMessage.scrollAt(double x, double y, double dx, double dy) =>
      InputMessage._({'type': 'scroll', 'x': x, 'y': y, 'dx': dx, 'dy': dy});

  factory InputMessage.scroll(double dx, double dy) =>
      InputMessage._({'type': 'scroll', 'dx': dx, 'dy': dy});

  factory InputMessage.pinchAt(double x, double y, double scale) =>
      InputMessage._({'type': 'pinch', 'x': x, 'y': y, 'scale': scale});

  factory InputMessage.pinch(double scale) =>
      InputMessage._({'type': 'pinch', 'scale': scale});

  factory InputMessage.keyWithModifiers(String code, List<String> modifiers) =>
      InputMessage._({'type': 'key', 'code': code, 'modifiers': modifiers});

  String toJson() => jsonEncode(_data);
}

class InputService {
  WebSocketChannel? _channel;
  bool _connected = false;

  bool get isConnected => _connected;

  void connect(String ip, int port) {
    final uri = Uri.parse('ws://$ip:$port/input');
    _channel = WebSocketChannel.connect(uri);
    _connected = true;

    _channel!.stream.listen(
      (_) {},
      onDone: () => _connected = false,
      onError: (_) => _connected = false,
    );
  }

  void send(InputMessage msg) {
    if (_connected && _channel != null) {
      _channel!.sink.add(msg.toJson());
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _connected = false;
  }
}
