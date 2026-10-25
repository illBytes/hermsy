import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_message.dart';
import 'audio_delivery.dart';
import 'image_delivery.dart';
import 'proactive_reply.dart';
import 'sse_parser.dart';
import 'streaming_http_client.dart';
import 'usage_report.dart';

class HermesException implements Exception {
  HermesException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class SessionsUnsupported implements Exception {}

class AudioUnsupported implements Exception {
  AudioUnsupported([this.message = 'Hermes audio API is not available.']);

  final String message;

  @override
  String toString() => message;
}

enum HermesEventKind { delta, tool, completed, done, error, interrupted }

class HermesStreamEvent {
  const HermesStreamEvent({
    required this.kind,
    this.text,
    this.toolName,
    this.toolLabel,
    this.toolEmoji,
    this.toolCompleted = false,
    this.usage,
  });

  final HermesEventKind kind;
  final String? text;
  final String? toolName;
  final String? toolLabel;
  final String? toolEmoji;
  final bool toolCompleted;
  final HermesUsage? usage;
}

class HermesHealth {
  const HermesHealth({this.platform, this.version});

  final String? platform;
  final String? version;

  factory HermesHealth.fromJson(Map<String, dynamic> json) {
    return HermesHealth(
      platform: json['platform']?.toString(),
      version: json['version']?.toString(),
    );
  }
}

class HermesSession {
  const HermesSession({
    required this.id,
    this.title,
    this.model,
    this.messageCount,
    this.inputTokens,
    this.outputTokens,
    this.estimatedCostUsd,
    this.updatedAt,
  });

  final String id;
  final String? title;
  final String? model;
  final int? messageCount;
  final int? inputTokens;
  final int? outputTokens;
  final double? estimatedCostUsd;
  final DateTime? updatedAt;

  factory HermesSession.fromJson(Map<String, dynamic> json) {
    final usage = HermesUsage.fromJson(json);
    return HermesSession(
      id: usage.sessionId ??
          (json['id'] ?? json['session_id'] ?? '').toString(),
      title: usage.title ?? json['title'] as String?,
      model: usage.model ?? json['model'] as String?,
      messageCount: usage.messageCount ?? json['message_count'] as int?,
      inputTokens: usage.inputTokens,
      outputTokens: usage.outputTokens,
      estimatedCostUsd: usage.estimatedCostUsd,
      updatedAt: _parseTime(json['updated_at'] ?? json['created_at']),
    );
  }

  HermesUsage get usage => HermesUsage(
        sessionId: id,
        title: title,
        model: model,
        inputTokens: inputTokens ?? 0,
        outputTokens: outputTokens ?? 0,
        messageCount: messageCount,
        estimatedCostUsd: estimatedCostUsd,
      );

  static HermesSession? fromPayload(dynamic payload) {
    if (payload is! Map<String, dynamic>) {
      return null;
    }
    final nested = payload['session'];
    if (nested is Map<String, dynamic>) {
      return HermesSession.fromJson(nested);
    }
    if (payload.containsKey('id') || payload.containsKey('session_id')) {
      return HermesSession.fromJson(payload);
    }
    return null;
  }
}

DateTime? _parseTime(dynamic raw) {
  if (raw is String && raw.isNotEmpty) {
    return DateTime.tryParse(raw);
  }
  if (raw is num) {
    final value = raw.toInt();
    if (value > 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value > 1000000000) {
      return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    }
  }
  return null;
}

class HermesClient {
  HermesClient({
    required this.baseUrl,
    required this.apiKey,
    http.Client? httpClient,
  }) : _http = httpClient ?? createStreamingHttpClient();

  final String baseUrl;
  final String apiKey;
  final http.Client _http;

  static const legacySessionKey = 'agent:main:mobile:dm:owner';
  String sessionKey = legacySessionKey;
  String? sessionId;
  String? lastSessionId;

  /// The chat (session key) [lastSessionId] belongs to. A session id from
  /// one chat must never carry another chat's messages.
  String? lastSessionKey;
  int? lastAudioStatus;

  String? get transcriptSessionId {
    final id =
        sessionId ?? (lastSessionKey == sessionKey ? lastSessionId : null);
    if (id == null || id.isEmpty) {
      return null;
    }
    return id;
  }

  void useTranscript(String? id) {
    final value = id != null && id.trim().isNotEmpty ? id.trim() : null;
    sessionId = value;
    lastSessionId = value;
    lastSessionKey = value == null ? null : sessionKey;
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
      'X-Hermes-Session-Key': sessionKey,
    };
    final transcript = transcriptSessionId;
    if (transcript != null) {
      headers['X-Hermes-Session-Id'] = transcript;
    }
    return headers;
  }

  Uri uri(String path) {
    final base = Uri.parse(baseUrl);
    final prefix = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(path: '$prefix$path', query: null, fragment: null);
  }

  Future<HermesHealth> ping() async {
    final response = await _http.get(uri('/health')).timeout(
          const Duration(seconds: 12),
        );
    if (response.statusCode != 200) {
      throw HermesException(
        'Hermes is not reachable (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    try {
      final payload = jsonDecode(response.body);
      if (payload is Map<String, dynamic>) {
        return HermesHealth.fromJson(payload);
      }
    } catch (_) {}
    return const HermesHealth();
  }

  Future<HermesHealth> verifyAccess() async {
    final health = await ping();
    final response = await _http
        .get(
          uri('/api/sessions').replace(queryParameters: {'limit': '1'}),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 12));
    _throwIfAuthFailed(response.statusCode, response.body);
    return health;
  }

  /// Runs the cron job named [name] now (Hermes picks it up on its next
  /// tick, within about a minute). False when there is no such job.
  Future<bool> runJobNamed(String name) async {
    final list = await _http
        .get(uri('/api/jobs'), headers: _headers)
        .timeout(const Duration(seconds: 12));
    _throwIfAuthFailed(list.statusCode, list.body);
    if (list.statusCode != 200) {
      throw HermesException(
        'Could not list scheduled jobs (${list.statusCode}).',
        statusCode: list.statusCode,
      );
    }
    final jobs = (jsonDecode(list.body) as Map<String, dynamic>)['jobs'];
    String? id;
    for (final job in jobs is List ? jobs : const []) {
      if (job is Map && job['name'] == name) {
        id = job['id'] as String?;
      }
    }
    if (id == null) {
      return false;
    }
    final run = await _http
        .post(uri('/api/jobs/$id/run'), headers: _headers)
        .timeout(const Duration(seconds: 12));
    _throwIfAuthFailed(run.statusCode, run.body);
    if (run.statusCode >= 300) {
      throw HermesException(
        'Hermes did not start the job (${run.statusCode}).',
        statusCode: run.statusCode,
      );
    }
    return true;
  }

  Future<List<HermesSession>> listSessions() async {
    final response = await _http.get(
      uri('/api/sessions').replace(queryParameters: {'limit': '50'}),
      headers: _headers,
    );
    _throwIfAuthFailed(response.statusCode, response.body);
    if (response.statusCode == 404) {
      throw SessionsUnsupported();
    }
    if (response.statusCode != 200) {
      throw HermesException(
        'Could not list sessions (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final data = payload['data'] as List<dynamic>? ?? const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(HermesSession.fromJson)
        .toList();
  }

  Future<HermesSession> createSession({required String title}) async {
    final response = await _http.post(
      uri('/api/sessions'),
      headers: _headers,
      body: jsonEncode({'title': title}),
    );
    _throwIfAuthFailed(response.statusCode, response.body);
    if (response.statusCode == 404) {
      throw SessionsUnsupported();
    }
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw HermesException(
        'Could not create a session (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    final payload = jsonDecode(response.body);
    final session = HermesSession.fromPayload(payload);
    if (session != null) {
      return session;
    }
    throw HermesException('Hermes returned an unexpected session payload.');
  }

  Future<HermesSession> getSession(String sessionId) async {
    final response = await _http.get(
      uri('/api/sessions/$sessionId'),
      headers: _headers,
    );
    _throwIfAuthFailed(response.statusCode, response.body);
    if (response.statusCode == 404) {
      throw SessionsUnsupported();
    }
    if (response.statusCode != 200) {
      throw HermesException(
        'Could not read session (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    final payload = jsonDecode(response.body);
    final session = HermesSession.fromPayload(payload);
    if (session != null) {
      return session;
    }
    throw HermesException('Hermes returned an unexpected session payload.');
  }

  Future<HermesUsage?> fetchAnalyticsUsage({int days = 7}) async {
    try {
      final response = await _http.get(
        uri('/api/analytics/usage').replace(
          queryParameters: {'days': '$days'},
        ),
        headers: _headers,
      );
      if (response.statusCode != 200) {
        return null;
      }
      final payload = jsonDecode(response.body);
      if (payload is Map<String, dynamic>) {
        return HermesUsage.fromAnalytics(payload);
      }
    } catch (_) {}
    return null;
  }

  Future<List<ChatMessage>> loadMessages(String sessionId) async {
    final response = await _http.get(
      uri('/api/sessions/$sessionId/messages'),
      headers: _headers,
    );
    _throwIfAuthFailed(response.statusCode, response.body);
    if (response.statusCode == 404) {
      throw SessionsUnsupported();
    }
    if (response.statusCode != 200) {
      throw HermesException(
        'Could not load messages (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final data = payload['data'] as List<dynamic>? ?? const [];
    final messages = <ChatMessage>[];
    for (final raw in data) {
      if (raw is! Map<String, dynamic>) {
        continue;
      }
      final role = ChatMessage.roleFrom(raw['role'] as String?);
      if (role != MessageRole.user && role != MessageRole.assistant) {
        continue;
      }
      final stored = ChatMessage.textFromContent(raw['content']);
      final images = ChatMessage.imagesFromContent(raw['content']);
      if (stored.trim().isEmpty && images.isEmpty) {
        continue;
      }
      // A reply thread's first reply carries the message it answers; show
      // that as Frank's message again, and the reply as typed.
      final split = role == MessageRole.user
          ? splitProactivePrompt(stored)
          : (quoted: null, text: stored);
      final text = split.text;
      if (split.quoted != null && messages.isEmpty) {
        messages.add(
          ChatMessage(
            id: '${proactiveMessagePrefix}hist',
            role: MessageRole.assistant,
            text: split.quoted!,
          ),
        );
      }
      messages.add(
        ChatMessage(
          id: (raw['id'] ?? 'hist_${messages.length}').toString(),
          role: role,
          text: text,
          remoteImages: images,
          // When Hermes has it, so imported history keeps its real day
          // separators and bylines instead of the moment it was opened.
          createdAt: _parseTime(
            raw['created_at'] ??
                raw['createdAt'] ??
                raw['timestamp'] ??
                raw['created'],
          )?.toLocal(),
        ),
      );
    }
    return messages;
  }

  Stream<HermesStreamEvent> streamSessionChat({
    required String sessionId,
    required String message,
    String? systemMessage,
  }) async* {
    final request = http.Request(
      'POST',
      uri('/api/sessions/$sessionId/chat/stream'),
    );
    _applyStreamHeaders(request);
    final key = sessionKey;
    request.body = jsonEncode({
      'message': message,
      'system_message': ?systemMessage,
    });

    final response = await _http.send(request);
    _rememberSession(response, key);
    if (response.statusCode == 404) {
      throw SessionsUnsupported();
    }
    final errorBody = await _peekError(response);
    _throwIfAuthFailed(response.statusCode, errorBody);
    if (response.statusCode != 200) {
      throw HermesException(
        describeHttpError(response.statusCode, errorBody),
        statusCode: response.statusCode,
      );
    }

    yield* _mapSse(response.stream, mapSessionSse);
  }

  /// [systemMessage] is added for this turn only: Hermes layers it on its
  /// own prompt and does not keep it in the session.
  Stream<HermesStreamEvent> streamCompletions({
    required String message,
    List<String> imagePaths = const [],
    String? systemMessage,
  }) async* {
    final messages = [
      if (systemMessage != null) {'role': 'system', 'content': systemMessage},
      ...completionsTurn(message: message, imagePaths: imagePaths),
    ];

    final request = http.Request('POST', uri('/v1/chat/completions'));
    _applyStreamHeaders(request);
    final key = sessionKey;
    // Omit `model`. Hermes 0.20 treats the virtual alias "hermes-agent" as a
    // real provider model id and the upstream returns HTTP 400.
    request.body = jsonEncode({
      'stream': true,
      'messages': messages,
    });

    final response = await _http.send(request);
    _rememberSession(response, key);
    final errorBody = await _peekError(response);
    _throwIfAuthFailed(response.statusCode, errorBody);
    if (response.statusCode != 200) {
      throw HermesException(
        describeHttpError(response.statusCode, errorBody),
        statusCode: response.statusCode,
      );
    }

    yield* _mapSse(response.stream, mapCompletionsSse);
  }

  /// Keeps the session Hermes answered in, unless the chat changed while
  /// the request was out: [key] is the chat that sent it.
  void _rememberSession(http.StreamedResponse response, String key) {
    final id = response.headers['x-hermes-session-id'];
    if (id != null && id.trim().isNotEmpty && key == sessionKey) {
      useTranscript(id);
    }
  }

  void _applyStreamHeaders(http.Request request) {
    request.headers.addAll(_headers);
    request.headers['Accept'] = 'text/event-stream';
    request.headers['Cache-Control'] = 'no-cache';
    // Avoid gzip/brotli: compressed SSE often arrives as one burst, or truncates
    // when the socket drops before the compressor flushes.
    request.headers['Accept-Encoding'] = 'identity';
    request.headers['Connection'] = 'keep-alive';
  }

  Stream<HermesStreamEvent> _mapSse(
    Stream<List<int>> bytes,
    HermesStreamEvent? Function(SseEvent event) map,
  ) async* {
    var sawTerminal = false;
    await for (final event in SseParser.parse(bytes)) {
      final mapped = map(event);
      if (mapped == null) {
        continue;
      }
      if (mapped.kind == HermesEventKind.done ||
          mapped.kind == HermesEventKind.completed) {
        sawTerminal = true;
      }
      yield mapped;
    }
    if (!sawTerminal) {
      yield const HermesStreamEvent(kind: HermesEventKind.interrupted);
    }
  }

  void close() => _http.close();

  void _throwIfAuthFailed(int statusCode, String body) {
    if (statusCode == 401 || statusCode == 403) {
      throw HermesException(
        'Hermes rejected the API key. Check it in Settings.',
        statusCode: statusCode,
      );
    }
    if (body.contains('invalid_api_key') || body.contains('unauthorized')) {
      throw HermesException(
        'Hermes rejected the API key. Check it in Settings.',
        statusCode: statusCode,
      );
    }
  }

  Future<String> _peekError(http.StreamedResponse response) async {
    if (response.statusCode == 200) {
      return '';
    }
    return response.stream.bytesToString();
  }

  bool? _audioApi;

  Future<bool> supportsAudioApi() async {
    if (_audioApi != null) {
      return _audioApi!;
    }
    try {
      final response = await _http
          .get(
            uri('/v1/audio/speech'),
            headers: {'Authorization': 'Bearer $apiKey'},
          )
          .timeout(const Duration(seconds: 8));
      _audioApi = response.statusCode != 404;
    } catch (_) {
      _audioApi = false;
    }
    return _audioApi!;
  }

  Future<String> transcribe(String filePath) async {
    final request = http.MultipartRequest(
      'POST',
      uri('/v1/audio/transcriptions'),
    );
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.files.add(await http.MultipartFile.fromPath('file', filePath));
    request.fields['response_format'] = 'json';
    final streamed = await _http.send(request);
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode == 404) {
      _audioApi = false;
      throw AudioUnsupported();
    }
    _throwIfAuthFailed(streamed.statusCode, body);
    if (streamed.statusCode != 200) {
      throw HermesException(
        describeHttpError(streamed.statusCode, body),
        statusCode: streamed.statusCode,
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic> && decoded['text'] is String) {
      return (decoded['text'] as String).trim();
    }
    if (decoded is String) {
      return decoded.trim();
    }
    throw HermesException('Hermes returned an empty transcript.');
  }

  Future<List<int>> synthesizeSpeech(String text) async {
    final response = await _http.post(
      uri('/v1/audio/speech'),
      headers: _headers,
      body: jsonEncode({
        'input': text,
        'response_format': 'mp3',
      }),
    );
    if (response.statusCode == 404) {
      _audioApi = false;
      throw AudioUnsupported();
    }
    _throwIfAuthFailed(response.statusCode, response.body);
    if (response.statusCode != 200) {
      throw HermesException(
        describeHttpError(response.statusCode, response.body),
        statusCode: response.statusCode,
      );
    }
    return response.bodyBytes;
  }

  Future<({List<int> bytes, String extension})?> fetchImage(ImageRef ref) async {
    lastAudioStatus = null;
    if (ref.dataUrl != null) {
      return imageBytesFromDataUrl(ref.dataUrl!);
    }
    if (ref.httpUrl != null) {
      return _getAudioBytes(
        Uri.parse(ref.httpUrl!),
        authorize: _isOwnHost(ref.httpUrl!),
        fallbackExt: imageExtension(ref.httpUrl!),
      );
    }
    final path = ref.filePath;
    if (path == null || path.isEmpty) {
      return null;
    }
    for (final download in _fileDownloadUris(path)) {
      final got = await _getAudioBytes(
        download,
        authorize: true,
        fallbackExt: imageExtension(path),
      );
      if (got != null) {
        return got;
      }
    }
    return null;
  }

  Future<({List<int> bytes, String extension})?> fetchAudio(AudioRef ref) async {
    lastAudioStatus = null;
    if (ref.dataUrl != null) {
      return audioBytesFromDataUrl(ref.dataUrl!);
    }
    if (ref.httpUrl != null) {
      return _getAudioBytes(
        Uri.parse(ref.httpUrl!),
        authorize: _isOwnHost(ref.httpUrl!),
        fallbackExt: _extensionOf(ref.httpUrl!),
      );
    }
    final path = ref.filePath;
    if (path == null || path.isEmpty) {
      return null;
    }
    for (final download in _fileDownloadUris(path)) {
      final got = await _getAudioBytes(
        download,
        authorize: true,
        fallbackExt: _extensionOf(path),
      );
      if (got != null) {
        return got;
      }
    }
    return null;
  }

  Iterable<Uri> _fileDownloadUris(String path) {
    final name = audioFileName(path);
    final cache = audioCacheRelative(path);
    final seen = <String>{};
    final uris = <Uri>[];
    void add(Uri next) {
      if (seen.add(next.toString())) {
        uris.add(next);
      }
    }

    for (final candidate in fileFetchPaths(path)) {
      add(uri(candidate));
    }
    if (cache != null) {
      add(uri('/audio/$cache'));
    }
    add(uri('/audio/$name'));
    add(uri('/audio/audio_cache/$name'));
    add(uri('/audio/cache/audio/$name'));
    add(uri('/api/files/download').replace(queryParameters: {'path': path}));
    add(uri('/api/files/stream').replace(queryParameters: {'path': path}));
    add(uri('/api/fs/read-data-url').replace(queryParameters: {'path': path}));
    add(uri('/api/fs/download').replace(queryParameters: {'path': path}));
    add(uri('/api/files/read').replace(queryParameters: {'path': path}));
    return uris;
  }

  bool _isOwnHost(String url) {
    try {
      return Uri.parse(url).host == Uri.parse(baseUrl).host;
    } catch (_) {
      return false;
    }
  }

  Future<({List<int> bytes, String extension})?> _getAudioBytes(
    Uri url, {
    required bool authorize,
    required String fallbackExt,
  }) async {
    try {
      final response = await _http.get(
        url,
        headers: authorize ? {'Authorization': 'Bearer $apiKey'} : const {},
      ).timeout(const Duration(seconds: 20));
      lastAudioStatus = _preferAudioStatus(lastAudioStatus, response.statusCode);
      if (response.statusCode != 200) {
        return null;
      }
      final type = response.headers['content-type'] ?? '';
      if (type.contains('json') && !type.contains('svg')) {
        return audioBytesFromJson(response.body, fallbackExt: fallbackExt);
      }
      final bytes = response.bodyBytes;
      final looksSvg = fallbackExt == 'svg' ||
          type.contains('svg') ||
          _looksLikeSvg(bytes);
      if ((type.contains('html') || type.contains('text/')) && !looksSvg) {
        return null;
      }
      if (bytes.length < 64 && !looksSvg) {
        return null;
      }
      return (
        bytes: bytes,
        extension: _extensionFromType(type, looksSvg ? 'svg' : fallbackExt),
      );
    } catch (_) {
      return null;
    }
  }

  int _preferAudioStatus(int? current, int next) {
    if (next == 200 || current == 200) {
      return 200;
    }
    if (current == 401 || next == 401) {
      return 401;
    }
    if (current == 403 || next == 403) {
      return 403;
    }
    return current ?? next;
  }

  bool _looksLikeSvg(List<int> bytes) {
    final head = String.fromCharCodes(bytes.take(200)).trimLeft();
    return head.startsWith('<svg') ||
        head.startsWith('<?xml') && head.contains('<svg');
  }

  String _extensionOf(String path) {
    final match = RegExp(r'\.([a-z0-9]+)$', caseSensitive: false).firstMatch(path);
    return match?.group(1)?.toLowerCase() ?? 'mp3';
  }

  String _extensionFromType(String type, String fallback) {
    if (type.contains('svg')) return 'svg';
    if (type.contains('png')) return 'png';
    if (type.contains('webp')) return 'webp';
    if (type.contains('gif')) return 'gif';
    if (type.contains('jpeg') || type.contains('jpg')) return 'jpg';
    if (type.contains('ogg')) return 'ogg';
    if (type.contains('wav')) return 'wav';
    if (type.contains('mp4') || type.contains('m4a')) return 'm4a';
    if (type.contains('mpeg') || type.contains('mp3')) return 'mp3';
    return fallback;
  }
}

/// Hermes buckets completions by this key. A fixed suffix made every Frank
/// chat continue the same server session (and the same token totals).
/// Telegram-style turn: only the new user line. Hermes already has the
/// transcript when `X-Hermes-Session-Id` is set.
List<Map<String, dynamic>> completionsTurn({
  required String message,
  List<String> imagePaths = const [],
}) {
  return [
    {
      'role': 'user',
      'content': completionContent(
        text: message,
        imagePaths: imagePaths,
      ),
    },
  ];
}

String hermesSessionKey(String conversationId) {
  final safe = conversationId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
  if (safe.isEmpty) {
    return HermesClient.legacySessionKey;
  }
  return 'agent:main:mobile:dm:$safe';
}

HermesStreamEvent? mapSessionSse(SseEvent event) {
  if (event.data == '[DONE]') {
    return const HermesStreamEvent(kind: HermesEventKind.done);
  }
  Map<String, dynamic> payload = const {};
  try {
    final decoded = jsonDecode(event.data);
    if (decoded is Map<String, dynamic>) {
      payload = decoded;
    }
  } catch (_) {
    if (event.event == 'assistant.delta' && event.data.isNotEmpty) {
      return HermesStreamEvent(kind: HermesEventKind.delta, text: event.data);
    }
  }

  switch (event.event) {
    case 'assistant.delta':
      final delta = _contentFrom(payload['delta']);
      if (delta == null || delta.isEmpty) {
        return null;
      }
      return HermesStreamEvent(kind: HermesEventKind.delta, text: delta);
    case 'tool.started':
    case 'tool.progress':
      return mapToolProgress(payload);
    case 'tool.completed':
    case 'tool.failed':
      return mapToolProgress(payload, completed: true);
    case 'assistant.completed':
    case 'run.completed':
      final content = _contentFrom(payload['content']);
      return HermesStreamEvent(
        kind: HermesEventKind.completed,
        text: content,
        usage: usageFromPayload(payload),
      );
    case 'done':
      return const HermesStreamEvent(kind: HermesEventKind.done);
    case 'error':
      return HermesStreamEvent(
        kind: HermesEventKind.error,
        text: payload['message']?.toString() ?? 'Hermes returned an error.',
      );
    default:
      return null;
  }
}

HermesStreamEvent? mapCompletionsSse(SseEvent event) {
  if (event.data.trim() == '[DONE]') {
    return const HermesStreamEvent(kind: HermesEventKind.done);
  }
  if (event.event == 'hermes.tool.progress' ||
      event.event == 'tool.started' ||
      event.event == 'tool.progress' ||
      event.event == 'tool.completed' ||
      event.event == 'tool.failed') {
    try {
      final payload = jsonDecode(event.data);
      if (payload is Map<String, dynamic>) {
        return mapToolProgress(
          payload,
          completed: event.event == 'tool.completed' ||
              event.event == 'tool.failed',
        );
      }
    } catch (_) {}
    return const HermesStreamEvent(kind: HermesEventKind.tool);
  }
  try {
    final payload = jsonDecode(event.data);
    if (payload is! Map<String, dynamic>) {
      return null;
    }
    final choices = payload['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final choice = choices.first as Map<String, dynamic>;
      final delta = choice['delta'];
      if (delta is Map) {
        final toolEvent = _toolCallDelta(delta);
        if (toolEvent != null) {
          return toolEvent;
        }
        final text = _contentFrom(delta['content']) ?? _contentFrom(delta['text']);
        if (text != null && text.isNotEmpty) {
          return HermesStreamEvent(
            kind: HermesEventKind.delta,
            text: text,
            usage: usageFromPayload(payload),
          );
        }
      }
      final message = choice['message'];
      if (message is Map) {
        final text = _contentFrom(message['content']);
        if (text != null && text.isNotEmpty) {
          return HermesStreamEvent(
            kind: HermesEventKind.completed,
            text: text,
            usage: usageFromPayload(payload),
          );
        }
      }
      final finish = choice['finish_reason']?.toString();
      if (finish != null && finish.isNotEmpty && finish != 'null') {
        return HermesStreamEvent(
          kind: HermesEventKind.completed,
          usage: usageFromPayload(payload),
        );
      }
    }
    final usageOnly = usageFromPayload(payload);
    if (usageOnly != null) {
      return HermesStreamEvent(
        kind: HermesEventKind.completed,
        usage: usageOnly,
      );
    }
  } catch (_) {}
  return null;
}

HermesStreamEvent? mapToolProgress(
  Map<String, dynamic> payload, {
  bool completed = false,
}) {
  final name = payload['tool']?.toString() ??
      payload['tool_name']?.toString() ??
      payload['name']?.toString();
  final status = payload['status']?.toString().toLowerCase() ?? '';
  final done = completed || status == 'completed' || status == 'failed';
  if (name != null && name.startsWith('_') && name != '_thinking') {
    return null;
  }
  return HermesStreamEvent(
    kind: HermesEventKind.tool,
    toolName: name,
    toolLabel: payload['label']?.toString() ??
        payload['preview']?.toString() ??
        payload['result']?.toString() ??
        payload['output']?.toString() ??
        payload['content']?.toString(),
    toolEmoji: payload['emoji']?.toString(),
    toolCompleted: done,
  );
}

HermesUsage? usageFromPayload(Map<String, dynamic> payload) {
  final usage = payload['usage'];
  if (usage is Map<String, dynamic>) {
    final parsed = HermesUsage.fromJson(usage);
    return parsed.hasTokens || parsed.hasCost ? parsed : null;
  }
  if (payload.containsKey('input_tokens') ||
      payload.containsKey('prompt_tokens') ||
      payload.containsKey('output_tokens') ||
      payload.containsKey('completion_tokens')) {
    final parsed = HermesUsage.fromJson(payload);
    return parsed.hasTokens || parsed.hasCost ? parsed : null;
  }
  return null;
}

HermesStreamEvent? _toolCallDelta(Map delta) {
  final calls = delta['tool_calls'];
  if (calls is! List || calls.isEmpty) {
    return null;
  }
  for (final raw in calls) {
    if (raw is! Map) {
      continue;
    }
    final function = raw['function'];
    final name = function is Map
        ? function['name']?.toString()
        : raw['name']?.toString();
    final args = function is Map ? function['arguments'] : raw['arguments'];
    if (name != null && name.isNotEmpty) {
      return HermesStreamEvent(
        kind: HermesEventKind.tool,
        toolName: name,
        toolLabel: spokenTextFromToolArgs(args),
      );
    }
  }
  return null;
}

String? _contentFrom(dynamic content) {
  if (content == null) {
    return null;
  }
  if (content is String) {
    return content;
  }
  final fromParts = ChatMessage.textFromContent(content);
  return fromParts.isEmpty ? null : fromParts;
}

bool isTransientDisconnect(Object error) {
  final lower = error.toString().toLowerCase();
  return lower.contains('connection closed') ||
      lower.contains('connection reset') ||
      lower.contains('broken pipe') ||
      lower.contains('connection abort') ||
      lower.contains('timed out') ||
      lower.contains('timeout') ||
      lower.contains('connection refused') ||
      lower.contains('socketexception') ||
      lower.contains('clientexception') ||
      lower.contains('http exception');
}

String describeStreamDrop({required bool hadText}) {
  if (hadText) {
    return 'Reply was cut off before Hermsy finished. Tap Retry to ask again.';
  }
  return 'Connection closed before Hermsy replied. Tap Retry.';
}

String friendlyStreamError(Object error) {
  if (isTransientDisconnect(error)) {
    return describeStreamDrop(hadText: false);
  }
  return error.toString();
}

bool isVirtualModelError(String? message) {
  if (message == null) {
    return false;
  }
  final lower = message.toLowerCase();
  return lower.contains('not a valid model') ||
      lower.contains('hermes-agent is not a valid');
}

String describeHttpError(int statusCode, String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      final error = decoded['error'];
      if (error is Map && error['message'] is String) {
        return error['message'] as String;
      }
      if (decoded['message'] is String) {
        return decoded['message'] as String;
      }
    }
  } catch (_) {}
  final trimmed = body.trim();
  if (trimmed.isNotEmpty && trimmed.length < 400) {
    return trimmed;
  }
  return 'Chat failed ($statusCode).';
}
