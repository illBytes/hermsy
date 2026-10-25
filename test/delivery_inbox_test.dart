import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/services/delivery_inbox.dart';

void main() {
  test('titles a delivery from the first caption line', () {
    expect(
      deliveryTitleFrom(
        body: 'Vector SVG format: /opt/data/banners/x.svg',
        filePaths: const [],
        remotePaths: const ['/opt/data/banners/x.svg'],
      ),
      'Vector SVG format: /opt/data/banners/x.svg',
    );
    expect(
      deliveryTitleFrom(
        body: '',
        filePaths: const ['/tmp/x.svg'],
        remotePaths: const [],
      ),
      'File from Hermsy',
    );
  });

  test('remembers a chat file and updates the same remote path', () async {
    final dir = await Directory.systemTemp.createTemp('frank_inbox');
    addTearDown(() => dir.delete(recursive: true));
    final inbox = DeliveryInbox(dir);

    await inbox.rememberChatFiles(
      body: 'Here is the banner',
      filePaths: const ['/tmp/banner.svg'],
      remotePaths: const ['/opt/data/banners/banner.svg'],
      conversationId: 'convo_1',
    );
    await inbox.rememberChatFiles(
      body: 'Updated caption',
      filePaths: const ['/tmp/banner2.svg'],
      remotePaths: const ['/opt/data/banners/banner.svg'],
    );

    final items = await inbox.list();
    expect(items, hasLength(1));
    expect(items.single.title, 'Here is the banner');
    expect(items.single.body, 'Updated caption');
    expect(items.single.filePaths, ['/tmp/banner2.svg']);
    expect(items.single.remotePaths, ['/opt/data/banners/banner.svg']);
  });

  test('skips empty deliveries', () async {
    final dir = await Directory.systemTemp.createTemp('frank_inbox');
    addTearDown(() => dir.delete(recursive: true));
    final inbox = DeliveryInbox(dir);
    await inbox.rememberChatFiles(
      body: 'No files',
      filePaths: const [],
      remotePaths: const [],
    );
    expect(await inbox.list(), isEmpty);
  });

  test('messages from Hermes count as unread until seen', () async {
    final dir = await Directory.systemTemp.createTemp('frank_inbox');
    addTearDown(() => dir.delete(recursive: true));
    final inbox = DeliveryInbox(dir);
    DeliveryRecord message(String id) => DeliveryRecord(
      id: id,
      title: 'Job $id',
      body: 'Done.',
      createdAt: DateTime(2026, 10, 24),
      read: false,
    );

    await inbox.add(message('relay_a'));
    await inbox.add(message('relay_b'));
    // Chat files are yours already.
    await inbox.rememberChatFiles(
      body: 'Banner',
      filePaths: const ['/tmp/banner.png'],
      remotePaths: const [],
    );
    expect(DeliveryInbox.unread.value, 2);

    // Opened from its notification.
    await inbox.markRead('relay_a');
    expect(DeliveryInbox.unread.value, 1);
    // Filed again later, it stays seen.
    await inbox.add(message('relay_a'));
    expect(DeliveryInbox.unread.value, 1);

    await inbox.markAllRead();
    expect(DeliveryInbox.unread.value, 0);
    await DeliveryInbox(dir).refreshUnread();
    expect(DeliveryInbox.unread.value, 0);
  });

  test('deliveries saved before unread counting read as seen', () {
    final old = DeliveryRecord.fromJson({
      'id': 'relay_x',
      'title': 'Old',
      'body': '',
      'createdAt': '2026-10-01T00:00:00Z',
    });
    expect(old.read, isTrue);
    expect(
      DeliveryRecord.fromJson(old.copyWith(read: false).toJson()).read,
      isFalse,
    );
  });
}
