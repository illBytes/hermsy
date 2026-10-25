import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/services/sse_parser.dart';

void main() {
  test('parses named SSE events and ignores keepalives', () async {
    const raw = '''
: keepalive

event: assistant.delta
data: {"delta":"Hello"}

event: tool.started
data: {"tool_name":"web_search"}

event: done
data: {}

''';
    final events = await SseParser.parseText(Stream.value(raw)).toList();
    expect(events.map((e) => e.event).toList(), [
      'assistant.delta',
      'tool.started',
      'done',
    ]);
    expect(events.first.data, '{"delta":"Hello"}');
  });

  test('decodes a malformed trailing UTF-8 byte instead of failing', () async {
    final events = await SseParser.parse(
      Stream.fromIterable([
        utf8.encode('data: Hello'),
        [0xC3],
      ]),
    ).toList();
    expect(events, hasLength(1));
    expect(events.single.data, startsWith('Hello'));
  });

  test('joins multi-line data fields', () {
    final event = SseParser.parseBlock(
      'event: message\ndata: {"a":1}\ndata: {"b":2}',
    );
    expect(event?.event, 'message');
    expect(event?.data, '{"a":1}\n{"b":2}');
  });
}
