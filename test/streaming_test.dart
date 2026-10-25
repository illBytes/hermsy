import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/services/hermes_client.dart';
import 'package:hermes_app/services/sse_parser.dart';
import 'package:hermes_app/services/streaming_http_client.dart';
import 'package:http/http.dart' as http;

void main() {
  test('streaming client keeps idle sockets open for long Hermes turns', () {
    final inner = HttpClient();
    addTearDown(inner.close);
    createStreamingHttpClient(inner: inner);
    expect(inner.idleTimeout, streamingIdleTimeout);
    expect(inner.connectionTimeout, streamingConnectTimeout);
  });

  test('parses SSE events split across TCP chunks', () async {
    final events = await SseParser.parseText(
      Stream.fromIterable([
        'data: {"choices":[{"delta":{"content":"Hel',
        'lo"}}]}\n\ndata: [DONE]\n\n',
      ]),
    ).toList();

    expect(events, hasLength(2));
    expect(events.first.data, '{"choices":[{"delta":{"content":"Hello"}}]}');
    expect(events.last.data, '[DONE]');
  });

  test('flushes a trailing SSE block when the socket ends', () async {
    final events = await SseParser.parseText(
      Stream.value('data: {"choices":[{"delta":{"content":"Hi"}}]}'),
    ).toList();
    expect(events, hasLength(1));
    expect(events.single.data, contains('Hi'));
  });

  test('maps completions deltas, list content, and finish_reason', () {
    expect(
      mapCompletionsSse(
        const SseEvent(
          event: 'message',
          data: '{"choices":[{"delta":{"content":"Hi"}}]}',
        ),
      )?.text,
      'Hi',
    );
    expect(
      mapCompletionsSse(
        const SseEvent(
          event: 'message',
          data:
              '{"choices":[{"delta":{"content":[{"type":"text","text":"Hi"}]}}]}',
        ),
      )?.text,
      'Hi',
    );
    expect(
      mapCompletionsSse(
        const SseEvent(
          event: 'message',
          data: '{"choices":[{"finish_reason":"stop"}]}',
        ),
      )?.kind,
      HermesEventKind.completed,
    );
    expect(
      mapCompletionsSse(const SseEvent(event: 'message', data: '[DONE]'))?.kind,
      HermesEventKind.done,
    );
  });

  test('detects transient disconnects', () {
    expect(
      isTransientDisconnect(const SocketException('Connection closed')),
      isTrue,
    );
    expect(isTransientDisconnect('ClientException: Connection closed'), isTrue);
    expect(isTransientDisconnect('HTTP 400: bad request'), isFalse);
    expect(
      friendlyStreamError(const SocketException('Connection closed')),
      describeStreamDrop(hadText: false),
    );
  });

  test('captures X-Hermes-Session-Id from a streamed reply', () async {
    final httpClient = _ScriptedClient([
      http.StreamedResponse(
        Stream<List<int>>.fromIterable([
          utf8.encode(
            'data: {"choices":[{"delta":{"content":"Hi"}}]}\n\n'
            'data: [DONE]\n\n',
          ),
        ]),
        200,
        headers: {'x-hermes-session-id': '20260902_mobile'},
      ),
    ]);
    final client = HermesClient(
      baseUrl: 'https://relay.example',
      apiKey: 'test',
      httpClient: httpClient,
    );
    addTearDown(client.close);
    client.sessionKey = hermesSessionKey('convo_fresh');

    await client.streamCompletions(message: 'hi').toList();
    expect(client.lastSessionId, '20260902_mobile');
    expect(
      httpClient.lastRequest?.headers['X-Hermes-Session-Key'],
      'agent:main:mobile:dm:convo_fresh',
    );
    expect(httpClient.lastRequest?.headers['X-Hermes-Session-Id'], isNull);
    final first = jsonDecode((httpClient.lastRequest! as http.Request).body);
    expect(first['messages'], hasLength(1));
    expect(first['messages'][0]['content'], 'hi');

    httpClient.enqueue(
      http.StreamedResponse(
        Stream<List<int>>.fromIterable([
          utf8.encode(
            'data: {"choices":[{"delta":{"content":"Again"}}]}\n\n'
            'data: [DONE]\n\n',
          ),
        ]),
        200,
        headers: {'x-hermes-session-id': '20260902_mobile'},
      ),
    );
    await client.streamCompletions(message: 'follow up').toList();
    expect(
      httpClient.lastRequest?.headers['X-Hermes-Session-Id'],
      '20260902_mobile',
    );
    final next = jsonDecode((httpClient.lastRequest! as http.Request).body);
    expect(next['messages'], hasLength(1));
    expect(next['messages'][0]['content'], 'follow up');
  });

  test('a session id never carries over to another chat', () async {
    late HermesClient client;
    // The reply for chat A arrives after you switched to chat B.
    final httpClient = _HookClient(() {
      client.useTranscript(null);
      client.sessionKey = hermesSessionKey('convo_b');
    });
    client = HermesClient(
      baseUrl: 'https://relay.example',
      apiKey: 'test',
      httpClient: httpClient,
    );
    addTearDown(client.close);
    client.sessionKey = hermesSessionKey('convo_a');
    await client.streamCompletions(message: 'hi').toList();
    expect(client.lastSessionId, isNull, reason: "A's session is not B's");
    expect(client.transcriptSessionId, isNull);

    // Learned in A, then the chat changes: B never sends A's id.
    client.sessionKey = hermesSessionKey('convo_a');
    client.useTranscript('session_a');
    client.sessionId = null;
    client.sessionKey = hermesSessionKey('convo_b');
    expect(client.transcriptSessionId, isNull);
    client.sessionKey = hermesSessionKey('convo_a');
    expect(client.transcriptSessionId, 'session_a');
  });

  test('completions turn is only the new user line', () {
    expect(completionsTurn(message: 'later'), [
      {'role': 'user', 'content': 'later'},
    ]);
  });

  test('builds a distinct Hermes session key per chat', () {
    expect(hermesSessionKey('convo_1'), 'agent:main:mobile:dm:convo_1');
    expect(hermesSessionKey('convo_1'), isNot(hermesSessionKey('convo_2')));
    expect(hermesSessionKey(''), HermesClient.legacySessionKey);
  });

  test('stream without [DONE] is marked interrupted', () async {
    final client = HermesClient(
      baseUrl: 'https://relay.example',
      apiKey: 'test',
      httpClient: _ScriptedClient([
        http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            utf8.encode(
              'data: {"choices":[{"delta":{"content":"Hello"}}]}\n\n',
            ),
          ]),
          200,
        ),
      ]),
    );
    addTearDown(client.close);

    final events = await client
        .streamCompletions(message: 'hi')
        .toList();

    expect(events.map((e) => e.kind).toList(), [
      HermesEventKind.delta,
      HermesEventKind.interrupted,
    ]);
    expect(events.first.text, 'Hello');
  });

  test('stream with [DONE] is not interrupted', () async {
    final client = HermesClient(
      baseUrl: 'https://relay.example',
      apiKey: 'test',
      httpClient: _ScriptedClient([
        http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            utf8.encode(
              'data: {"choices":[{"delta":{"content":"Hello"}}]}\n\n'
              'data: [DONE]\n\n',
            ),
          ]),
          200,
        ),
      ]),
    );
    addTearDown(client.close);

    final events = await client
        .streamCompletions(message: 'hi')
        .toList();

    expect(events.map((e) => e.kind).toList(), [
      HermesEventKind.delta,
      HermesEventKind.done,
    ]);
  });
}

class _ScriptedClient extends http.BaseClient {
  _ScriptedClient(this._responses);

  final List<http.StreamedResponse> _responses;
  http.BaseRequest? lastRequest;

  void enqueue(http.StreamedResponse response) => _responses.add(response);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    return _responses.removeAt(0);
  }
}

/// Answers every request with a reply in session_a, running [beforeReply]
/// first.
class _HookClient extends http.BaseClient {
  _HookClient(this.beforeReply);

  final void Function() beforeReply;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    beforeReply();
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([
        utf8.encode(
          'data: {"choices":[{"delta":{"content":"Hi"}}]}\n\n'
          'data: [DONE]\n\n',
        ),
      ]),
      200,
      headers: {'x-hermes-session-id': 'session_a'},
    );
  }
}
