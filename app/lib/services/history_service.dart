import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ConnectionEntry {
  final String ip;
  final int port;
  final DateTime lastUsed;

  ConnectionEntry({
    required this.ip,
    required this.port,
    DateTime? lastUsed,
  }) : lastUsed = lastUsed ?? DateTime.now();

  String get url => 'http://$ip:$port';

  Map<String, dynamic> toJson() => {
        'ip': ip,
        'port': port,
        'lastUsed': lastUsed.toIso8601String(),
      };

  factory ConnectionEntry.fromJson(Map<String, dynamic> json) {
    return ConnectionEntry(
      ip: json['ip'] as String,
      port: json['port'] as int,
      lastUsed: DateTime.parse(json['lastUsed'] as String),
    );
  }

  static ConnectionEntry? fromMirrorUrl(String url) {
    final uri = Uri.tryParse(url.replaceFirst('mirror://', 'http://'));
    if (uri == null || uri.host.isEmpty) return null;
    return ConnectionEntry(ip: uri.host, port: uri.port);
  }
}

class HistoryService {
  static const _key = 'connection_history';
  static const _maxEntries = 10;

  static List<ConnectionEntry> parseEntries(String raw) {
    if (raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => ConnectionEntry.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<ConnectionEntry>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key) ?? '';
    return parseEntries(raw);
  }

  Future<void> addEntry(ConnectionEntry entry) async {
    final history = await getHistory();
    history.removeWhere((e) => e.ip == entry.ip && e.port == entry.port);
    history.insert(0, entry);
    if (history.length > _maxEntries) {
      history.removeRange(_maxEntries, history.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(history.map((e) => e.toJson()).toList()));
  }
}
