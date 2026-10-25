import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/chat_message.dart';
import 'at_rest_cipher.dart';
import 'relay_client.dart' show relayPlainText;

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.preview = '',
    this.remoteSessionId,
    this.remoteOnly = false,
    this.pinned = false,
    this.titleCustom = false,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final String preview;
  final String? remoteSessionId;
  final bool remoteOnly;
  final bool pinned;
  final bool titleCustom;

  bool get isRemoteOnly => remoteOnly;

  ConversationSummary copyWith({
    String? title,
    DateTime? updatedAt,
    String? preview,
    String? remoteSessionId,
    bool? remoteOnly,
    bool? pinned,
    bool? titleCustom,
  }) {
    return ConversationSummary(
      id: id,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      preview: preview ?? this.preview,
      remoteSessionId: remoteSessionId ?? this.remoteSessionId,
      remoteOnly: remoteOnly ?? this.remoteOnly,
      pinned: pinned ?? this.pinned,
      titleCustom: titleCustom ?? this.titleCustom,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt.toIso8601String(),
        'preview': preview,
        'remoteSessionId': remoteSessionId,
        'remoteOnly': remoteOnly,
        'pinned': pinned,
        'titleCustom': titleCustom,
      };

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    return ConversationSummary(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Conversation',
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      preview: json['preview'] as String? ?? '',
      remoteSessionId: json['remoteSessionId'] as String?,
      remoteOnly: json['remoteOnly'] == true,
      pinned: json['pinned'] == true,
      titleCustom: json['titleCustom'] == true,
    );
  }
}

class ConversationRecord {
  ConversationRecord({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messages,
    this.remoteSessionId,
    this.sessionKey,
    this.pinned = false,
    this.titleCustom = false,
    this.hermesTitle,
    this.draftText = '',
    List<String>? draftImagePaths,
  }) : draftImagePaths = draftImagePaths ?? <String>[];

  final String id;
  String title;
  DateTime updatedAt;
  List<ChatMessage> messages;
  String? remoteSessionId;
  String? sessionKey;
  bool pinned;
  bool titleCustom;

  /// The name Hermes gave the session, used unless [titleCustom].
  String? hermesTitle;
  String draftText;
  List<String> draftImagePaths;

  bool get hasDraft =>
      draftText.trim().isNotEmpty || draftImagePaths.isNotEmpty;

  ConversationSummary get summary => ConversationSummary(
        id: id,
        title: title,
        updatedAt: updatedAt,
        preview: conversationPreview(
          messages,
          draftText: draftText,
          draftImagePaths: draftImagePaths,
        ),
        remoteSessionId: remoteSessionId,
        pinned: pinned,
        titleCustom: titleCustom,
      );
}

class ConversationStore {
  ConversationStore(this.root, {this.cipher});

  final Directory root;

  /// Encrypts the chats on disk. Tests leave it out and read plain JSON.
  final AtRestCipher? cipher;

  static Future<ConversationStore> open() async {
    final docs = await getApplicationDocumentsDirectory();
    return ConversationStore(
      Directory('${docs.path}/frank_conversations'),
      cipher: AtRestCipher.shared,
    );
  }

  Future<String> _readText(File file) async {
    final bytes = await file.readAsBytes();
    final cipher = this.cipher;
    return utf8.decode(cipher == null ? bytes : await cipher.open(bytes));
  }

  /// Writes a whole file at once (beside it, then renamed over it), so a
  /// crash mid-write never leaves half a file, which encrypted would be
  /// unreadable.
  Future<void> _writeText(File file, String text) async {
    final cipher = this.cipher;
    final bytes = utf8.encode(text);
    final next = File('${file.path}.tmp');
    await next.writeAsBytes(
      cipher == null ? bytes : await cipher.seal(bytes),
      flush: true,
    );
    await next.rename(file.path);
  }

  /// Encrypts any chat still saved from before Frank encrypted.
  Future<void> sealAll() async {
    final cipher = this.cipher;
    if (cipher == null || !await root.exists()) {
      return;
    }
    await for (final entry in root.list()) {
      if (entry is! File || !entry.path.endsWith('.json')) {
        continue;
      }
      final bytes = await entry.readAsBytes();
      if (!AtRestCipher.isSealed(bytes)) {
        await _writeText(entry, utf8.decode(bytes));
      }
    }
  }

  Future<void> _ensure() async {
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
  }

  File get _indexFile => File('${root.path}/index.json');

  File _fileFor(String id) => File('${root.path}/$id.json');

  Future<List<ConversationSummary>> list() async {
    await _ensure();
    if (!await _indexFile.exists()) {
      return [];
    }
    try {
      final decoded = jsonDecode(await _readText(_indexFile));
      if (decoded is! List) {
        return [];
      }
      final items = decoded
          .whereType<Map<String, dynamic>>()
          .map(ConversationSummary.fromJson)
          .toList();
      return arrangeConversations(items);
    } catch (_) {
      return [];
    }
  }

  Future<ConversationRecord?> read(String id) async {
    await _ensure();
    final file = _fileFor(id);
    if (!await file.exists()) {
      return null;
    }
    try {
      final decoded = jsonDecode(await _readText(file));
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final raw = decoded['messages'];
      final messages = <ChatMessage>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map<String, dynamic>) {
            messages.add(ChatMessage.fromJson(item));
          }
        }
      }
      return ConversationRecord(
        id: decoded['id'] as String? ?? id,
        title: decoded['title'] as String? ?? titleFrom(messages),
        updatedAt: DateTime.tryParse(decoded['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        messages: messages,
        remoteSessionId: decoded['remoteSessionId'] as String?,
        sessionKey: decoded['sessionKey'] as String?,
        pinned: decoded['pinned'] == true,
        titleCustom: decoded['titleCustom'] == true,
        hermesTitle: decoded['hermesTitle'] as String?,
        draftText: decoded['draftText'] as String? ?? '',
        draftImagePaths: _stringList(decoded['draftImagePaths']),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(ConversationRecord record) async {
    await _ensure();
    final payload = {
      'id': record.id,
      'title': record.title,
      'updatedAt': record.updatedAt.toIso8601String(),
      'remoteSessionId': record.remoteSessionId,
      'sessionKey': record.sessionKey,
      'pinned': record.pinned,
      'titleCustom': record.titleCustom,
      'hermesTitle': record.hermesTitle,
      'draftText': record.draftText,
      'draftImagePaths': record.draftImagePaths,
      'messages': [
        for (final message in record.messages) message.toJson(),
      ],
    };
    await _writeText(_fileFor(record.id), jsonEncode(payload));
    final items = await list();
    var pinned = record.pinned;
    for (final item in items) {
      if (item.id == record.id && item.pinned) {
        pinned = true;
        break;
      }
    }
    items.removeWhere((item) => item.id == record.id);
    items.insert(0, record.summary.copyWith(pinned: pinned));
    await _writeText(_indexFile, 
      jsonEncode([
        for (final item in arrangeConversations(items)) item.toJson(),
      ]),
    );
  }

  Future<void> setTitle(String id, String raw) async {
    final title = sanitizeConversationTitle(raw);
    if (title == null) {
      return;
    }
    final record = await read(id);
    if (record != null) {
      record
        ..title = title
        ..titleCustom = true;
      await write(record);
      return;
    }
    await _ensure();
    final items = [
      for (final item in await list())
        item.id == id ? item.copyWith(title: title, titleCustom: true) : item,
    ];
    if (items.every((item) => item.id != id)) {
      return;
    }
    await _writeText(_indexFile, 
      jsonEncode([
        for (final item in arrangeConversations(items)) item.toJson(),
      ]),
    );
  }

  Future<void> setPinned(String id, bool pinned) async {
    await _ensure();
    final items = [
      for (final item in await list())
        item.id == id ? item.copyWith(pinned: pinned) : item,
    ];
    if (items.every((item) => item.id != id)) {
      return;
    }
    await _writeText(_indexFile, 
      jsonEncode([
        for (final item in arrangeConversations(items)) item.toJson(),
      ]),
    );
  }

  Future<void> delete(String id) async {
    await _ensure();
    final file = _fileFor(id);
    if (await file.exists()) {
      await file.delete();
    }
    final items = await list();
    items.removeWhere((item) => item.id == id);
    await _writeText(_indexFile, 
      jsonEncode([for (final item in items) item.toJson()]),
    );
  }
}

String titleForPersist({
  required List<ChatMessage> messages,
  required bool titleCustom,
  String? currentTitle,
  String? hermesTitle,
  String draftText = '',
}) {
  if (titleCustom) {
    final kept = currentTitle?.trim() ?? '';
    if (kept.isNotEmpty) {
      return kept;
    }
  }
  final named = hermesChatTitle(hermesTitle);
  if (named != null) {
    return named;
  }
  final fromMessages = titleFrom(messages);
  if (fromMessages != 'Conversation') {
    return fromMessages;
  }
  final draft = draftText.trim();
  if (draft.isNotEmpty) {
    return _clip(draft);
  }
  return 'Conversation';
}

List<String> _stringList(dynamic raw) {
  if (raw is! List) {
    return <String>[];
  }
  return [
    for (final item in raw)
      if (item is String && item.trim().isNotEmpty) item,
  ];
}

List<ConversationSummary> filterConversations(
  List<ConversationSummary> items,
  String query,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return items;
  }
  return [
    for (final item in items)
      if (item.title.toLowerCase().contains(needle) ||
          item.preview.toLowerCase().contains(needle))
        item,
  ];
}

String? sanitizeConversationTitle(String raw) {
  final text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (text.isEmpty) {
    return null;
  }
  if (text.length <= 60) {
    return text;
  }
  return '${text.substring(0, 59)}…';
}

/// A session title from Hermes, cleaned, or null when it is not a real
/// name: empty, or the placeholder Frank gives a session it creates.
String? hermesChatTitle(String? raw) {
  final given = raw?.trim() ?? '';
  // Frank, as Hermsy was called, named its sessions "Frank · <date>".
  if (raw == null ||
      given.startsWith('Hermsy · ') ||
      given.startsWith('Frank · ')) {
    return null;
  }
  final title = sanitizeConversationTitle(raw);
  return title == 'Conversation' ? null : title;
}

String titleFrom(List<ChatMessage> messages) {
  for (final message in messages) {
    if (!message.isUser) {
      continue;
    }
    final text = message.text.trim();
    if (text.isEmpty || text.startsWith('/')) {
      if (message.hasImages) {
        return 'Photo';
      }
      continue;
    }
    return _clip(text);
  }
  return 'Conversation';
}

List<ConversationSummary> mergeHistory({
  required List<ConversationSummary> local,
  required List<ConversationSummary> remote,
}) {
  final seen = <String>{};
  void mark(ConversationSummary item) {
    seen.add(item.id);
    final remoteId = item.remoteSessionId;
    if (remoteId != null && remoteId.isNotEmpty) {
      seen.add(remoteId);
      seen.add(hermesConversationId(remoteId));
    }
    if (item.id.startsWith('hermes_') && item.id.length > 7) {
      seen.add(item.id.substring(7));
    }
  }

  for (final item in local) {
    mark(item);
  }

  final extra = <ConversationSummary>[];
  for (final item in remote) {
    final remoteId = item.remoteSessionId ??
        (item.id.startsWith('hermes_') && item.id.length > 7
            ? item.id.substring(7)
            : item.id);
    if (seen.contains(item.id) || seen.contains(remoteId)) {
      continue;
    }
    extra.add(item);
    mark(item);
  }

  return arrangeConversations([...local, ...extra]);
}

List<ConversationSummary> arrangeConversations(List<ConversationSummary> items) {
  int byDate(ConversationSummary a, ConversationSummary b) {
    return b.updatedAt.compareTo(a.updatedAt);
  }

  final pinned = items.where((item) => item.pinned).toList()..sort(byDate);
  final phone = items.where((item) => !item.pinned && !item.isRemoteOnly).toList()
    ..sort(byDate);
  final server = items.where((item) => !item.pinned && item.isRemoteOnly).toList()
    ..sort(byDate);
  return [...pinned, ...phone, ...server];
}

String formatConversationWhen(DateTime time, {DateTime? now}) {
  if (time.millisecondsSinceEpoch <= 0) {
    return '';
  }
  final local = time.toLocal();
  final clock = now?.toLocal() ?? DateTime.now();
  final timeLabel =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  final day = DateTime(local.year, local.month, local.day);
  final today = DateTime(clock.year, clock.month, clock.day);
  if (day == today) {
    return 'Today · $timeLabel';
  }
  if (day == today.subtract(const Duration(days: 1))) {
    return 'Yesterday · $timeLabel';
  }
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final month = months[local.month - 1];
  if (local.year == clock.year) {
    return '$month ${local.day} · $timeLabel';
  }
  return '$month ${local.day}, ${local.year}';
}

String conversationPreview(
  List<ChatMessage> messages, {
  String draftText = '',
  List<String> draftImagePaths = const [],
}) {
  final fromMessages = previewFrom(messages);
  if (fromMessages.isNotEmpty) {
    return fromMessages;
  }
  return draftPreview(draftText, draftImagePaths);
}

String draftPreview(String text, List<String> imagePaths) {
  final draft = text.trim();
  if (draft.isNotEmpty) {
    return 'Draft · ${_clip(draft, 64)}';
  }
  if (imagePaths.isNotEmpty) {
    return 'Draft · Photo';
  }
  return '';
}

String previewFrom(List<ChatMessage> messages) {
  for (final message in messages.reversed) {
    if (message.text.trim().isNotEmpty) {
      // A preview is plain text: no **bold** or list marks.
      return _clip(relayPlainText(message.text), 72);
    }
    if (message.hasImages) {
      return 'Photo';
    }
  }
  return '';
}

String _clip(String raw, [int max = 42]) {
  final text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (text.length <= max) {
    return text;
  }
  return '${text.substring(0, max - 1)}…';
}

String hermesConversationId(String sessionId) => 'hermes_$sessionId';
