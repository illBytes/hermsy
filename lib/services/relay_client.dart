import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/brief.dart';
import '../voice/mic_capture.dart' show pcm16ToFloat;

/// One proactive message (a cron result and the like) held by the plugin.
class RelayMessage {
  const RelayMessage({
    required this.id,
    required this.seq,
    required this.title,
    required this.text,
    required this.source,
    required this.createdAt,
    this.jobName,
  });

  final String id;

  /// The plugin's running number; catch-up asks for everything after the
  /// last one seen.
  final int seq;
  final String title;
  final String text;

  /// `cron` for scheduled jobs, `agent` for anything else Hermes sent.
  final String source;
  final String? jobName;
  final DateTime createdAt;

  factory RelayMessage.fromJson(Map<String, dynamic> json) {
    return RelayMessage(
      id: json['id'] as String,
      seq: (json['seq'] as num).toInt(),
      title: json['title'] as String? ?? 'Hermsy',
      text: json['text'] as String? ?? '',
      source: json['source'] as String? ?? 'agent',
      jobName: json['job_name'] as String?,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// A cloud voice Hermes can speak with.
class CloudVoice {
  const CloudVoice({
    required this.id,
    required this.name,
    required this.description,
  });

  final String id;
  final String name;
  final String description;
}

/// A voice provider Hermes has a key for, and its voices.
class CloudProvider {
  const CloudProvider({
    required this.id,
    required this.name,
    required this.voices,
    this.error,
  });

  /// `openai` or `elevenlabs`.
  final String id;
  final String name;
  final List<CloudVoice> voices;

  /// Why its voices could not be listed (a bad key), if they could not.
  final String? error;
}

class RelayException implements Exception {
  RelayException(this.message, {this.missing = false});

  final String message;

  /// The Hermsy plugin is not on this Hermes (or Hermes is too old for it).
  final bool missing;

  @override
  String toString() => message;
}

/// A Hermsy job on the server (the Brief, the Chief of Staff), as setup
/// found it.
class PluginJob {
  const PluginJob({required this.name, this.schedule, this.enabled = true});

  final String name;
  final String? schedule;
  final bool enabled;

  static PluginJob? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    return PluginJob(
      name: json['name'] as String? ?? '',
      schedule: json['schedule'] as String?,
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

/// What the Hermsy plugin on this Hermes can do.
class PluginStatus {
  const PluginStatus({
    required this.version,
    required this.store,
    required this.push,
    this.voices = const [],
    this.timezone,
    this.brief,
    this.chiefOfStaff,
  });

  final String version;

  /// Names the plugin's message store; a new one is read from the start.
  final String store;

  /// Phones are woken when something arrives.
  final bool push;

  /// Cloud voice providers Hermes has keys for (`openai`, `elevenlabs`).
  final List<String> voices;
  final String? timezone;
  final PluginJob? brief;
  final PluginJob? chiefOfStaff;

  factory PluginStatus.fromJson(Map<String, dynamic> json) {
    final setup = json['setup'] as Map<String, dynamic>? ?? const {};
    return PluginStatus(
      version: json['version'] as String? ?? '?',
      store: json['store'] as String? ?? '',
      push: json['push'] as bool? ?? false,
      voices: [for (final v in json['voices'] as List? ?? const []) '$v'],
      timezone: json['timezone'] as String?,
      brief: PluginJob.fromJson(setup['brief']),
      chiefOfStaff: PluginJob.fromJson(setup['chief_of_staff']),
    );
  }
}

/// The Hermsy plugin on the person's Hermes: the Inbox, the Brief, phone
/// registration, cloud voices and setup. Reached through Hermes's own API
/// server (`POST /api/platforms/hermsy/events`) with the same API key as
/// chat, so there is no other address to configure.
class RelayClient {
  RelayClient(this.config, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final AppConfig config;
  final http.Client _http;

  Uri get _events => Uri.parse('${config.baseUrl}/api/platforms/hermsy/events');

  /// One request to the plugin; its answer, or a [RelayException] saying
  /// what [doing] ran into.
  Future<Map<String, dynamic>> _call(
    String op,
    String doing, {
    Map<String, Object?> body = const {},
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final response = await _http
        .post(
          _events,
          headers: {
            'Authorization': 'Bearer ${config.apiKey}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'op': op, ...body}),
        )
        .timeout(timeout);
    Map<String, dynamic>? json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {}
    if (response.statusCode == 404 ||
        (response.statusCode == 503 &&
            '${json?['error']}'.contains('platform'))) {
      throw RelayException(
        'Could not $doing: the Hermsy plugin is not running on this Hermes.',
        missing: true,
      );
    }
    if (response.statusCode == 401) {
      throw RelayException('Could not $doing: Hermes rejected the API key.');
    }
    if (response.statusCode != 200 || json == null) {
      throw RelayException('Could not $doing (HTTP ${response.statusCode}).');
    }
    final error = json['error'];
    if (error != null) {
      throw RelayException('Could not $doing: $error');
    }
    return json;
  }

  /// What the plugin can do and which jobs are set up.
  Future<PluginStatus> hello() async =>
      PluginStatus.fromJson(await _call('hello', 'reach the Hermsy plugin'));

  /// Creates the jobs asked for, at times in [timezone] (an IANA name).
  Future<PluginStatus> setup({
    bool brief = false,
    bool chiefOfStaff = false,
    String? timezone,
  }) async {
    await _call(
      'setup',
      'set it up',
      body: {
        'brief': brief,
        'chief_of_staff': chiefOfStaff,
        if (timezone != null) 'timezone': timezone,
      },
      timeout: const Duration(seconds: 30),
    );
    return hello();
  }

  /// Tells the plugin where to push. Safe to repeat: it only refreshes.
  Future<void> registerDevice(
    String token, {
    String platform = 'android',
  }) async {
    await _call(
      'register_device',
      'register this phone',
      body: {'token': token, 'platform': platform},
    );
  }

  Future<void> removeDevice(String token) async {
    await _call(
      'remove_device',
      'unregister this phone',
      body: {'token': token},
    );
  }

  Future<RelayMessage> message(String id) async => RelayMessage.fromJson(
    await _call(
      'message',
      'fetch the message',
      body: {'id': id},
      timeout: const Duration(seconds: 10),
    ),
  );

  /// Messages after [seq], oldest first, the cursor to pass next time, and
  /// the store they come from.
  Future<({List<RelayMessage> messages, int next, String store})> messagesSince(
    int seq, {
    int limit = 50,
  }) async {
    final body = await _call(
      'messages',
      'catch up',
      body: {'since': seq, 'limit': limit},
    );
    return (
      messages: [
        for (final item in body['messages'] as List)
          RelayMessage.fromJson(item as Map<String, dynamic>),
      ],
      next: (body['next'] as num).toInt(),
      store: body['store'] as String? ?? '',
    );
  }

  /// The newest Brief, or null before the first one is written.
  Future<Brief?> latestBrief() async {
    final brief = (await _call('brief', 'load the brief'))['brief'];
    return brief is Map<String, dynamic> ? Brief.fromJson(brief) : null;
  }

  /// The cloud voices Hermes has keys for, by provider id.
  Future<Map<String, CloudProvider>> speechProviders() async {
    final body = await _call(
      'voices',
      'list voices',
      timeout: const Duration(seconds: 15),
    );
    final providers = body['providers'] as Map<String, dynamic>? ?? const {};
    return {
      for (final MapEntry(:key, :value) in providers.entries)
        key: CloudProvider(
          id: key,
          name: (value as Map<String, dynamic>)['name'] as String? ?? key,
          error: value['error'] as String?,
          voices: [
            for (final voice in value['voices'] as List? ?? const [])
              CloudVoice(
                id: (voice as Map<String, dynamic>)['id'] as String,
                name: voice['name'] as String? ?? 'Voice',
                description: voice['description'] as String? ?? '',
              ),
          ],
        ),
    };
  }

  /// [text] spoken by [provider]'s [voice], as samples and their rate.
  Future<({Float32List samples, int sampleRate})> speech({
    required String provider,
    required String voice,
    required String text,
    double speed = 1.0,
  }) async {
    final body = await _call(
      'speak',
      'speak',
      body: {
        'provider': provider,
        'voice': voice,
        'text': text,
        'speed': speed,
      },
      timeout: const Duration(seconds: 20),
    );
    final audio = base64Decode(body['audio'] as String);
    final rate = (body['sample_rate'] as num?)?.toInt() ?? 24000;
    return (samples: pcm16ToFloat(audio).samples, sampleRate: rate);
  }

  void close() => _http.close();
}

/// A one-line preview for a notification: the first non-empty line with
/// Markdown marks dropped, cut to [max] characters.
String relayPreview(String text, {int max = 140}) {
  final line = text
      .split('\n')
      .map(_plain)
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  return line.length <= max
      ? line
      : '${line.substring(0, max - 1).trimRight()}…';
}

/// The whole text as plain lines, for the expanded notification.
String relayPlainText(String text) => text
    .split('\n')
    .map(_plain)
    .join('\n')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

String _plain(String line) => line
    .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!)
    .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s+'), '')
    .replaceAll(RegExp(r'^\s*>\s?'), '')
    .replaceAll(RegExp(r'^\s*[-*+]\s+'), '• ')
    .replaceAll(RegExp(r'\*\*|__|`'), '')
    .trim();
