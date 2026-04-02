import 'package:http/http.dart' as http;
import 'input_service.dart';
import 'history_service.dart';

class ConnectionService {
  final InputService inputService = InputService();
  final HistoryService historyService = HistoryService();

  String? _ip;
  int? _port;
  bool _connected = false;

  bool get isConnected => _connected;
  String get streamUrl => 'http://$_ip:$_port/stream';
  String get videoWsUrl => 'ws://$_ip:$_port/video';
  String? get ip => _ip;
  int? get port => _port;

  Future<bool> connect(String ip, int port) async {
    try {
      final response = await http.head(
        Uri.parse('http://$ip:$port/'),
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode != 200) return false;

      _ip = ip;
      _port = port;
      _connected = true;

      inputService.connect(ip, port);

      await historyService.addEntry(ConnectionEntry(ip: ip, port: port));

      return true;
    } catch (_) {
      return false;
    }
  }

  void disconnect() {
    inputService.disconnect();
    _connected = false;
    _ip = null;
    _port = null;
  }
}
