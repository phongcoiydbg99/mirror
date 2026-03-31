import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/history_service.dart';

void main() {
  group('ConnectionEntry', () {
    test('toJson and fromJson round-trip', () {
      final entry = ConnectionEntry(ip: '192.168.1.10', port: 8080);
      final json = entry.toJson();
      final restored = ConnectionEntry.fromJson(json);
      expect(restored.ip, '192.168.1.10');
      expect(restored.port, 8080);
    });

    test('url returns correct format', () {
      final entry = ConnectionEntry(ip: '10.0.0.1', port: 9090);
      expect(entry.url, 'http://10.0.0.1:9090');
    });

    test('fromMirrorUrl parses correctly', () {
      final entry = ConnectionEntry.fromMirrorUrl('mirror://192.168.1.5:8080');
      expect(entry, isNotNull);
      expect(entry!.ip, '192.168.1.5');
      expect(entry.port, 8080);
    });

    test('fromMirrorUrl returns null for invalid url', () {
      expect(ConnectionEntry.fromMirrorUrl('invalid'), isNull);
    });
  });

  group('HistoryService', () {
    test('parseEntries handles empty string', () {
      expect(HistoryService.parseEntries(''), isEmpty);
    });

    test('parseEntries handles valid JSON list', () {
      final json = '[{"ip":"10.0.0.1","port":8080,"lastUsed":"2026-03-31T00:00:00.000"}]';
      final entries = HistoryService.parseEntries(json);
      expect(entries.length, 1);
      expect(entries[0].ip, '10.0.0.1');
    });
  });
}
