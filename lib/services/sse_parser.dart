import 'dart:convert';

class SseEvent {
  const SseEvent({required this.event, required this.data});

  final String event;
  final String data;
}

class SseParser {
  static Stream<SseEvent> parse(Stream<List<int>> bytes) {
    return parseText(
      bytes.transform(const Utf8Decoder(allowMalformed: true)),
    );
  }

  static Stream<SseEvent> parseText(Stream<String> chunks) async* {
    final buffer = StringBuffer();
    await for (final chunk in chunks) {
      buffer.write(chunk);
      final text = buffer.toString().replaceAll('\r\n', '\n');
      final parts = text.split('\n\n');
      buffer
        ..clear()
        ..write(parts.last);
      for (var i = 0; i < parts.length - 1; i++) {
        final event = parseBlock(parts[i]);
        if (event != null) {
          yield event;
        }
      }
    }
    final trailing = parseBlock(buffer.toString().replaceAll('\r\n', '\n'));
    if (trailing != null) {
      yield trailing;
    }
  }

  static SseEvent? parseBlock(String block) {
    var event = 'message';
    final dataLines = <String>[];
    for (final raw in block.split('\n')) {
      final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      if (line.isEmpty || line.startsWith(':')) {
        continue;
      }
      if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        var value = line.substring(5);
        if (value.startsWith(' ')) {
          value = value.substring(1);
        }
        dataLines.add(value);
      }
    }
    if (dataLines.isEmpty) {
      return null;
    }
    return SseEvent(event: event, data: dataLines.join('\n'));
  }
}
