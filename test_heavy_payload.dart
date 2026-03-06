import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final url = Uri.parse(
    'http://localhost:8080/webhook?category=test&priority=high&user_id=42&source=test_script',
  );

  // Generating a "big" body
  final bigBody = jsonEncode({
    'title': 'Heavy Payload Test',
    'timestamp': DateTime.now().toIso8601String(),
    'data': List.generate(
      50,
      (i) => {
        'id': i,
        'content':
            'This is some repeated content for testing large body persistence. ' *
            5,
        'metadata': {
          'tags': ['test', 'persistence', 'json'],
          'active': true,
        },
      },
    ),
    'notes':
        'This body simulation aims to test how the server handles larger JSON structures in its local DB.',
  });

  final headers = {
    'Content-Type': 'application/json',
    'X-Custom-Header-Alpha': 'Value-A',
    'X-Custom-Header-Beta': 'Value-B',
    'X-Custom-Header-Gamma': 'Value-C',
    'X-Test-Run-ID': 'run-998877',
    'Authorization': 'Bearer some-fake-token-12345',
    'Accept': 'application/json',
    'User-Agent': 'Dart-Test-Script/1.0',
  };

  print('Sending heavy webhook to $url...');
  try {
    final response = await http.post(url, headers: headers, body: bigBody);
    print('Response Code: ${response.statusCode}');
    print('Response Body: ${response.body}');

    // Check if it persisted by reading the DB file directly or checking API
    final eventsRes = await http.get(
      Uri.parse('http://localhost:8080/api/events'),
    );
    final List events = jsonDecode(eventsRes.body);
    print('\nEvents in memory: ${events.length}');
    if (events.isNotEmpty) {
      print('Latest event path: ${events[0]['path']}');
      print('Query Params count: ${events[0]['queryParams'].length}');
      print('Headers count: ${events[0]['headers'].length}');
      print('Body length: ${events[0]['body'].length} chars');
    }
  } catch (e) {
    print('Error: $e');
  }
}
