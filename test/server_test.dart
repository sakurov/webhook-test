import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart';
import 'package:test/test.dart';

void main() {
  const port = '8081';
  const host = 'http://localhost:$port';
  const dbPath = 'webhooks_db.json';

  // Helper to ensure fresh start
  void cleanDb() {
    final file = File(dbPath);
    if (file.existsSync()) file.deleteSync();
  }

  setUpAll(() {
    cleanDb();
  });

  tearDownAll(() {
    cleanDb();
  });

  group('Webhook Server Persistence & Logic', () {
    late Process p;

    Future<void> startServer() async {
      p = await Process.start(
        'dart',
        ['run', 'bin/server.dart'],
        environment: {'PORT': port},
      );
      // Wait for server to start.
      await Future.delayed(Duration(seconds: 2));
    }

    Future<void> stopServer() async {
      p.kill();
      await p.exitCode;
    }

    test('UI Root contains dashboard title', () async {
      await startServer();
      try {
        final response = await get(Uri.parse('$host/'));
        expect(response.statusCode, 200);
        expect(response.headers['content-type'], contains('text/html'));
        expect(response.body, contains('Webhook Receiver'));
      } finally {
        await stopServer();
      }
    });

    test('Webhook persists after server restart', () async {
      // 1. Start server and send a webhook
      await startServer();
      try {
        final payload = {'persistence_test': 'secret_value'};
        await post(
          Uri.parse('$host/webhook'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        );

        final eventsRes = await get(Uri.parse('$host/api/events'));
        final events = jsonDecode(eventsRes.body) as List;
        expect(events.first['body'], contains('secret_value'));
      } finally {
        await stopServer();
      }

      // 2. Restart server and check if it's still there
      await startServer();
      try {
        final eventsRes = await get(Uri.parse('$host/api/events'));
        final events = jsonDecode(eventsRes.body) as List;

        expect(
          events,
          isNotEmpty,
          reason: 'Events should have been loaded from Disk',
        );
        expect(events.first['body'], contains('secret_value'));
      } finally {
        await stopServer();
      }
    });

    test('Handles heavy payloads and complex query params', () async {
      await startServer();
      try {
        final url = Uri.parse('$host/webhook?user=tester&mode=debug&v=1.0');
        final complexBody = {
          'metadata': {'id': 101, 'active': true},
          'data': List.generate(10, (i) => 'Item $i'),
        };

        final response = await post(
          url,
          headers: {'X-Test-Header': 'Verified'},
          body: jsonEncode(complexBody),
        );

        expect(response.statusCode, 200);

        final eventsRes = await get(Uri.parse('$host/api/events'));
        final events = jsonDecode(eventsRes.body) as List;
        final latest = events.first;

        expect(latest['queryParams']['user'], 'tester');
        expect(latest['headers']['x-test-header'], 'Verified');
        expect(latest['body'], contains('Item 9'));
      } finally {
        await stopServer();
      }
    });

    test('API Clear also clears the database file', () async {
      await startServer();
      try {
        // Send one event
        await post(Uri.parse('$host/webhook'), body: 'to be cleared');

        // Clear via API
        await post(Uri.parse('$host/api/clear'));

        final eventsRes = await get(Uri.parse('$host/api/events'));
        expect(jsonDecode(eventsRes.body), isEmpty);
      } finally {
        await stopServer();
      }

      // Verify file content is an empty list
      final file = File(dbPath);
      expect(file.readAsStringSync(), '[]');
    });
  });
}
