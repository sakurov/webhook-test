import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart';
import 'package:test/test.dart';

void main() {
  final port = '8081'; // Use a different port to avoid conflicts
  final host = 'http://localhost:$port';
  late Process p;

  setUp(() async {
    p = await Process.start(
      'dart',
      ['run', 'bin/server.dart'],
      environment: {'PORT': port},
    );
    // Wait for server to start.
    await Future.delayed(Duration(seconds: 1));
  });

  tearDown(() => p.kill());

  test('UI Root', () async {
    final response = await get(Uri.parse('$host/'));
    expect(response.statusCode, 200);
    expect(response.headers['content-type'], contains('text/html'));
    expect(response.body, contains('Webhook Receiver Dashboard'));
  });

  test('Webhook POST', () async {
    final payload = {'test': 'data'};
    final response = await post(
      Uri.parse('$host/webhook'),
      body: jsonEncode(payload),
    );
    expect(response.statusCode, 200);
    expect(response.body, contains('received":true'));
  });

  test('Webhook GET', () async {
    final response = await get(Uri.parse('$host/webhook?param=value'));
    expect(response.statusCode, 200);
    expect(response.body, contains('received":true'));

    // Check if it appears in events
    final eventsRes = await get(Uri.parse('$host/api/events'));
    final events = jsonDecode(eventsRes.body) as List;
    expect(events.first['method'], 'GET');
  });

  test('API Events', () async {
    final response = await get(Uri.parse('$host/api/events'));
    expect(response.statusCode, 200);
    final events = jsonDecode(response.body) as List;
    expect(events, isNotNull);
  });
}
