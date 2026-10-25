import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A scripted Hermes server for design screenshots. Chat replies are fed
/// step by step so a test can freeze the UI mid-thought, mid-tool, and
/// mid-reply.
class FakeHermes {
  FakeHermes({this.healthy = true, this.audioApi = true});

  bool healthy;
  bool audioApi;

  /// When set, the next chat request fails with this HTTP status.
  int? nextStatus;
  StreamController<List<int>>? _reply;

  late final http.Client client = MockClient.streaming((request, body) async {
    final path = request.url.path;
    if (path.endsWith('/health')) {
      return _json(
        healthy ? 200 : 503,
        {'status': 'ok', 'platform': 'hermes-agent', 'version': '0.20.0'},
      );
    }
    if (path.endsWith('/v1/audio/speech')) {
      return _json(audioApi ? 405 : 404, {'error': 'method'});
    }
    if (path.endsWith('/v1/models')) {
      return _json(200, {
        'data': [
          {'id': 'anthropic/claude-sonnet-5-5'},
        ],
      });
    }
    if (path.endsWith('/v1/chat/completions')) {
      await body.drain<void>();
      final failWith = nextStatus;
      if (failWith != null) {
        nextStatus = null;
        return _json(failWith, {
          'error': {'message': 'Upstream provider timed out after 120s.'},
        });
      }
      final reply = StreamController<List<int>>();
      _reply = reply;
      return http.StreamedResponse(
        reply.stream,
        200,
        headers: {
          'content-type': 'text/event-stream',
          'x-hermes-session-id': 'shot-session',
        },
      );
    }
    return _json(404, {'error': 'not found'});
  });

  bool get replying => _reply != null && !_reply!.isClosed;

  void tool(String name, String label, {String emoji = ''}) {
    _event('tool.started', {
      'tool': name,
      'label': label,
      if (emoji.isNotEmpty) 'emoji': emoji,
    });
  }

  void toolDone(String name) {
    _event('tool.completed', {'tool': name, 'status': 'completed'});
  }

  void delta(String text) {
    _data({
      'choices': [
        {
          'delta': {'content': text},
        },
      ],
    });
  }

  /// Streams [text] in small word chunks.
  void words(String text) {
    final parts = RegExp(r'\S+\s*|\s+').allMatches(text).map((m) => m.group(0)!);
    for (final part in parts) {
      delta(part);
    }
  }

  void finish() {
    _data({
      'choices': [
        {'delta': <String, dynamic>{}, 'finish_reason': 'stop'},
      ],
    });
    _write('data: [DONE]\n\n');
    _reply?.close();
    _reply = null;
  }

  void fail(String message) {
    _event('error', {'message': message});
    _reply?.close();
    _reply = null;
  }

  void _event(String name, Map<String, dynamic> payload) {
    _write('event: $name\ndata: ${jsonEncode(payload)}\n\n');
  }

  void _data(Map<String, dynamic> payload) {
    _write('data: ${jsonEncode(payload)}\n\n');
  }

  void _write(String chunk) {
    _reply?.add(utf8.encode(chunk));
  }

  static http.StreamedResponse _json(int status, Object body) {
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      headers: {'content-type': 'application/json'},
    );
  }
}
