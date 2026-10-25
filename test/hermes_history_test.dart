import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/services/hermes_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  HermesClient clientFor(List<Map<String, Object?>> data) {
    return HermesClient(
      baseUrl: 'https://relay.example.com',
      apiKey: 'key',
      httpClient: MockClient(
        (_) async => http.Response(jsonEncode({'data': data}), 200),
      ),
    );
  }

  test('imported history keeps when Hermes sent each message', () async {
    final client = clientFor([
      {'role': 'user', 'content': 'Hi', 'timestamp': 1700000000.5},
      {
        'role': 'assistant',
        'content': 'Hello',
        'created_at': '2023-11-14T22:13:30Z',
      },
    ]);
    addTearDown(client.close);

    final messages = await client.loadMessages('s1');

    expect(
      messages.first.createdAt,
      DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
    );
    expect(
      messages.last.createdAt.toUtc(),
      DateTime.utc(2023, 11, 14, 22, 13, 30),
    );
    expect(messages.last.createdAt.isUtc, isFalse);
  });

  test('history without timestamps still loads', () async {
    final client = clientFor([
      {'role': 'user', 'content': 'Hi'},
    ]);
    addTearDown(client.close);

    final before = DateTime.now();
    final messages = await client.loadMessages('s1');

    expect(messages.single.text, 'Hi');
    expect(messages.single.createdAt.isBefore(before), isFalse);
  });
}
