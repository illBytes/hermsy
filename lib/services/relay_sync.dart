import 'package:shared_preferences/shared_preferences.dart';

import 'delivery_inbox.dart';
import 'relay_client.dart';

/// Inbox records made from relay messages carry this id prefix, so the
/// Inbox can tell them from files saved out of a chat.
const relayRecordPrefix = 'relay_';

DeliveryRecord relayRecord(RelayMessage message) => DeliveryRecord(
  id: '$relayRecordPrefix${message.id}',
  title: message.title,
  body: message.text,
  createdAt: message.createdAt,
  source: message.source,
  read: false,
);

bool isRelayRecord(DeliveryRecord record) =>
    record.id.startsWith(relayRecordPrefix);

/// Where the app is in the plugin's message list, per server. Kept with the
/// store it belongs to: a new store (the plugin reinstalled, or moved to
/// another Hermes) is read from the start.
class MessageCursor {
  MessageCursor(this.preferences, String baseUrl)
    : _seqKey = 'hermsy.seq.$baseUrl',
      _storeKey = 'hermsy.store.$baseUrl',
      _notifiedKey = 'hermsy.notified.$baseUrl';

  final SharedPreferences preferences;
  final String _seqKey;
  final String _storeKey;
  final String _notifiedKey;

  /// The store last read, and the last message filed from it.
  String? get store => preferences.getString(_storeKey);
  int get seq => preferences.getInt(_seqKey) ?? 0;

  Future<void> save(String store, int seq) async {
    final known = notifiedFor(store);
    await preferences.setString(_storeKey, store);
    await preferences.setInt(_seqKey, seq);
    // Filed in the Inbox counts as notified; another store's count is void.
    if (known == null || seq > known) {
      await preferences.setInt(_notifiedKey, seq);
    }
  }

  /// The last message a notification was shown for (or that the app filed
  /// itself), for [store]; null when unknown.
  int? notifiedFor(String store) => preferences.getString(_storeKey) == store
      ? preferences.getInt(_notifiedKey)
      : null;

  Future<void> notified(String store, int seq) async {
    if (preferences.getString(_storeKey) != store) {
      // A store the Inbox has not read yet: it starts from the beginning.
      await preferences.setString(_storeKey, store);
      await preferences.setInt(_seqKey, 0);
    }
    await preferences.setInt(_notifiedKey, seq);
  }
}

/// Files every message the app has not seen yet into the Inbox, so a push
/// that never arrived loses nothing.
class RelaySync {
  RelaySync({
    required this.client,
    required this.inbox,
    SharedPreferences? preferences,
  }) : _preferences = preferences;

  final RelayClient client;
  final DeliveryInbox inbox;
  SharedPreferences? _preferences;

  /// Returns the records it added, oldest first.
  Future<List<DeliveryRecord>> catchUp() async {
    final cursor = MessageCursor(
      _preferences ??= await SharedPreferences.getInstance(),
      client.config.baseUrl,
    );
    final added = <DeliveryRecord>[];
    var store = cursor.store;
    var seq = store == null ? 0 : cursor.seq;
    while (true) {
      final page = await client.messagesSince(seq);
      if (page.store != store) {
        // A store not read before: from its beginning.
        store = page.store;
        await cursor.save(store, 0);
        if (seq != 0) {
          seq = 0;
          continue;
        }
      }
      for (final message in page.messages) {
        final record = relayRecord(message);
        await inbox.add(record);
        added.add(record);
      }
      if (page.messages.isEmpty || page.next <= seq) {
        return added;
      }
      seq = page.next;
      // Saved per page, so an interrupted catch-up resumes where it was.
      await cursor.save(page.store, seq);
    }
  }
}
