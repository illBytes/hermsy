import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'at_rest_cipher.dart';

class DeliveryRecord {
  const DeliveryRecord({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.filePaths = const [],
    this.remotePaths = const [],
    this.source = 'chat',
    this.conversationId,
    this.read = true,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final List<String> filePaths;
  final List<String> remotePaths;
  final String source;
  final String? conversationId;

  /// Seen in the Inbox (or opened from its notification). Messages Hermes
  /// sends arrive unread; pictures and files from a chat you saw already.
  final bool read;

  DeliveryRecord copyWith({
    String? title,
    String? body,
    List<String>? filePaths,
    List<String>? remotePaths,
    bool? read,
  }) {
    return DeliveryRecord(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt,
      filePaths: filePaths ?? this.filePaths,
      remotePaths: remotePaths ?? this.remotePaths,
      source: source,
      conversationId: conversationId,
      read: read ?? this.read,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'createdAt': createdAt.toIso8601String(),
    'filePaths': filePaths,
    'remotePaths': remotePaths,
    'source': source,
    'conversationId': conversationId,
    'read': read,
  };

  factory DeliveryRecord.fromJson(Map<String, dynamic> json) {
    return DeliveryRecord(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Delivery',
      body: json['body'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      filePaths: _strings(json['filePaths']),
      remotePaths: _strings(json['remotePaths']),
      source: json['source'] as String? ?? 'chat',
      conversationId: json['conversationId'] as String?,
      // Saved before Frank counted unread: treat as seen.
      read: json['read'] as bool? ?? true,
    );
  }

  static List<String> _strings(dynamic raw) {
    if (raw is! List) {
      return const [];
    }
    return [
      for (final item in raw)
        if (item is String && item.trim().isNotEmpty) item,
    ];
  }
}

String deliveryTitleFrom({
  required String body,
  required List<String> filePaths,
  required List<String> remotePaths,
}) {
  final line = body
      .trim()
      .split(RegExp(r'\n+'))
      .map((item) => item.trim())
      .firstWhere((item) => item.isNotEmpty, orElse: () => '');
  if (line.isNotEmpty) {
    return line.length <= 48 ? line : '${line.substring(0, 47)}…';
  }
  if (filePaths.isNotEmpty || remotePaths.isNotEmpty) {
    return 'File from Hermsy';
  }
  return 'Delivery';
}

class DeliveryInbox {
  DeliveryInbox(this.root, {this.cipher});

  final Directory root;

  /// Encrypts the Inbox on disk. Tests leave it out and read plain JSON.
  final AtRestCipher? cipher;

  static Future<DeliveryInbox> open() async {
    final docs = await getApplicationDocumentsDirectory();
    return DeliveryInbox(
      Directory('${docs.path}/frank_inbox'),
      cipher: AtRestCipher.shared,
    );
  }

  /// Encrypts the Inbox if it is still saved from before Frank encrypted.
  Future<void> sealAll() async {
    if (cipher == null || !await _file.exists()) {
      return;
    }
    if (!AtRestCipher.isSealed(await _file.readAsBytes())) {
      await _write(await list());
    }
  }

  File get _file => File('${root.path}/deliveries.json');

  /// How many deliveries are unread, for the badge on the Inbox. Kept in
  /// step by every write; [refreshUnread] reads it at start-up.
  static final unread = ValueNotifier<int>(0);

  Future<void> refreshUnread() async {
    unread.value = (await list()).where((item) => !item.read).length;
  }

  /// Everything is seen (the Inbox was opened).
  Future<void> markAllRead() async {
    final items = await list();
    if (items.every((item) => item.read)) {
      return;
    }
    await _write([for (final item in items) item.copyWith(read: true)]);
  }

  /// One delivery is seen (opened from its notification).
  Future<void> markRead(String id) async {
    final items = await list();
    final index = items.indexWhere((item) => item.id == id && !item.read);
    if (index < 0) {
      return;
    }
    items[index] = items[index].copyWith(read: true);
    await _write(items);
  }

  Future<void> _ensure() async {
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
  }

  Future<List<DeliveryRecord>> list() async {
    await _ensure();
    if (!await _file.exists()) {
      return [];
    }
    try {
      final bytes = await _file.readAsBytes();
      final cipher = this.cipher;
      final decoded = jsonDecode(
        utf8.decode(cipher == null ? bytes : await cipher.open(bytes)),
      );
      if (decoded is! List) {
        return [];
      }
      final items =
          decoded
              .whereType<Map<String, dynamic>>()
              .map(DeliveryRecord.fromJson)
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
    } catch (_) {
      return [];
    }
  }

  Future<void> add(DeliveryRecord record) async {
    final items = await list();
    // Filed again (a caption update, a refetch): seen stays seen.
    final wasRead = items.any((item) => item.id == record.id && item.read);
    items.removeWhere((item) => item.id == record.id);
    items.insert(0, wasRead ? record.copyWith(read: true) : record);
    await _write(items);
  }

  /// Removes a delivery from this phone. The relay's copy is not touched,
  /// and catch-up never brings it back: it reads only newer messages.
  Future<void> remove(String id) async {
    final items = await list();
    items.removeWhere((item) => item.id == id);
    await _write(items);
  }

  Future<void> rememberChatFiles({
    required String body,
    required List<String> filePaths,
    required List<String> remotePaths,
    String? conversationId,
  }) async {
    if (filePaths.isEmpty && remotePaths.isEmpty) {
      return;
    }
    final items = await list();
    final key = remotePaths.isNotEmpty
        ? remotePaths.join('|')
        : filePaths.join('|');
    for (final item in items) {
      final existing = item.remotePaths.isNotEmpty
          ? item.remotePaths.join('|')
          : item.filePaths.join('|');
      if (existing == key) {
        await add(
          item.copyWith(
            body: body.trim().isNotEmpty ? body : item.body,
            filePaths: filePaths.isNotEmpty ? filePaths : item.filePaths,
          ),
        );
        return;
      }
    }
    await add(
      DeliveryRecord(
        id: 'del_${DateTime.now().microsecondsSinceEpoch}',
        title: deliveryTitleFrom(
          body: body,
          filePaths: filePaths,
          remotePaths: remotePaths,
        ),
        body: body,
        createdAt: DateTime.now(),
        filePaths: filePaths,
        remotePaths: remotePaths,
        conversationId: conversationId,
      ),
    );
  }

  Future<void> _write(List<DeliveryRecord> items) async {
    await _ensure();
    final kept = items.take(80).toList();
    final bytes = utf8.encode(
      jsonEncode([for (final item in kept) item.toJson()]),
    );
    final cipher = this.cipher;
    // Whole, then renamed into place: a crash never leaves half a file.
    final next = File('${_file.path}.tmp');
    await next.writeAsBytes(
      cipher == null ? bytes : await cipher.seal(bytes),
      flush: true,
    );
    await next.rename(_file.path);
    unread.value = kept.where((item) => !item.read).length;
  }
}
