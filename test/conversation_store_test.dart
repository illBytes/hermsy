import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/models/chat_message.dart';
import 'package:hermes_app/services/conversation_store.dart';

void main() {
  test('titles a conversation from the first user line', () {
    expect(
      titleFrom([
        ChatMessage(id: 'a', role: MessageRole.assistant, text: 'Hi'),
        ChatMessage(id: 'b', role: MessageRole.user, text: '  Plan Friday  '),
      ]),
      'Plan Friday',
    );
  });

  test('skips slash commands when titling a conversation', () {
    expect(
      titleFrom([
        ChatMessage(id: 'a', role: MessageRole.user, text: '/usage'),
        ChatMessage(id: 'b', role: MessageRole.user, text: 'Plan Friday'),
      ]),
      'Plan Friday',
    );
  });

  test('keeps phone chats above leftover server sessions and hides duplicates', () {
    final local = [
      ConversationSummary(
        id: 'convo_new',
        title: 'Fresh chat',
        updatedAt: DateTime.utc(2026, 9, 2, 18),
        preview: 'Hello',
        remoteSessionId: 'sess_new',
      ),
      ConversationSummary(
        id: 'convo_old',
        title: 'Older chat',
        updatedAt: DateTime.utc(2026, 9, 1, 12),
        preview: 'Earlier',
      ),
    ];
    final remote = [
      ConversationSummary(
        id: hermesConversationId('sess_new'),
        title: 'Mobile',
        updatedAt: DateTime.utc(2026, 9, 2, 19),
        preview: '12 messages',
        remoteSessionId: 'sess_new',
        remoteOnly: true,
      ),
      ConversationSummary(
        id: hermesConversationId('telegram'),
        title: 'Telegram',
        updatedAt: DateTime.utc(2026, 8, 1),
        preview: 'On your server',
        remoteSessionId: 'telegram',
        remoteOnly: true,
      ),
    ];

    final merged = mergeHistory(local: local, remote: remote);
    expect(merged.map((item) => item.id).toList(), [
      'convo_new',
      'convo_old',
      hermesConversationId('telegram'),
    ]);
    expect(merged.first.isRemoteOnly, isFalse);
    expect(merged.last.isRemoteOnly, isTrue);
  });

  test('the Hermsy drawer only keeps phone chats', () {
    final phone = arrangeConversations([
      ConversationSummary(
        id: 'convo_1',
        title: 'Mobile',
        updatedAt: DateTime.utc(2026, 9, 2),
      ),
      ConversationSummary(
        id: hermesConversationId('telegram'),
        title: 'Telegram',
        updatedAt: DateTime.utc(2026, 9, 1),
        remoteOnly: true,
      ),
    ]).where((item) => !item.isRemoteOnly);
    expect(phone.map((item) => item.id).toList(), ['convo_1']);
  });

  test('keeps a custom title instead of the first user line', () {
    final messages = [
      ChatMessage(id: 'b', role: MessageRole.user, text: 'Plan Friday'),
    ];
    expect(
      titleForPersist(
        messages: messages,
        titleCustom: true,
        currentTitle: 'Dinner',
      ),
      'Dinner',
    );
    expect(
      titleForPersist(
        messages: messages,
        titleCustom: false,
        currentTitle: 'Dinner',
      ),
      'Plan Friday',
    );
  });

  test('filters chats by title or preview', () {
    final items = [
      ConversationSummary(
        id: 'a',
        title: 'Dinner',
        updatedAt: DateTime.utc(2026, 9, 2),
        preview: 'Book a table',
      ),
      ConversationSummary(
        id: 'b',
        title: 'Work',
        updatedAt: DateTime.utc(2026, 9, 1),
        preview: 'Ship the build',
      ),
    ];
    expect(filterConversations(items, 'dinner').map((item) => item.id), ['a']);
    expect(filterConversations(items, 'SHIP').map((item) => item.id), ['b']);
    expect(filterConversations(items, 'nope'), isEmpty);
  });

  test('keeps pinned chats above newer unpinned ones', () {
    final arranged = arrangeConversations([
      ConversationSummary(
        id: 'new',
        title: 'Newer',
        updatedAt: DateTime.utc(2026, 9, 2, 20),
      ),
      ConversationSummary(
        id: 'pin',
        title: 'Pinned older',
        updatedAt: DateTime.utc(2026, 9, 1),
        pinned: true,
      ),
    ]);
    expect(arranged.map((item) => item.id).toList(), ['pin', 'new']);
  });

  test('formats conversation timestamps newest-first style', () {
    final now = DateTime(2026, 9, 2, 21, 40);
    expect(
      formatConversationWhen(DateTime(2026, 9, 2, 10, 5), now: now),
      'Today · 10:05',
    );
    expect(
      formatConversationWhen(DateTime(2026, 9, 1, 9, 0), now: now),
      'Yesterday · 09:00',
    );
    expect(
      formatConversationWhen(DateTime(2026, 8, 20, 15, 30), now: now),
      'Aug 20 · 15:30',
    );
  });

  test('titles an empty chat from its draft', () {
    expect(
      titleForPersist(
        messages: const [],
        titleCustom: false,
        draftText: '  Book a table Friday  ',
      ),
      'Book a table Friday',
    );
  });

  test('preview prefers messages and falls back to a draft', () {
    expect(
      conversationPreview(
        [
          ChatMessage(id: 'a', role: MessageRole.assistant, text: 'Here is a plan.'),
        ],
        draftText: 'unused',
      ),
      'Here is a plan.',
    );
    expect(
      conversationPreview(const [], draftText: 'Book a table'),
      'Draft · Book a table',
    );
    expect(
      conversationPreview(const [], draftImagePaths: const ['/tmp/a.jpg']),
      'Draft · Photo',
    );
  });

  test('round-trips a conversation on disk', () async {
    final dir = await Directory.systemTemp.createTemp('frank_convos');
    addTearDown(() => dir.delete(recursive: true));
    final store = ConversationStore(dir);
    final record = ConversationRecord(
      id: 'convo_1',
      title: 'Plan Friday',
      updatedAt: DateTime.utc(2026, 9, 2, 18),
      remoteSessionId: 'sess_1',
      sessionKey: 'agent:main:mobile:dm:convo_1',
      draftText: 'Also bring wine',
      draftImagePaths: const ['/tmp/menu.jpg'],
      messages: [
        ChatMessage(
          id: 'u1',
          role: MessageRole.user,
          text: 'Plan Friday',
          isVoice: true,
          audioPath: '/tmp/note.m4a',
          remoteAudio: '/opt/data/.hermes/audio_cache/note.ogg',
          createdAt: DateTime.utc(2026, 9, 2, 18),
        ),
        ChatMessage(
          id: 'a1',
          role: MessageRole.assistant,
          text: 'Here is a plan.',
          createdAt: DateTime.utc(2026, 9, 2, 18, 1),
        ),
      ],
    );

    await store.write(record);
    final listed = await store.list();
    expect(listed, hasLength(1));
    expect(listed.single.title, 'Plan Friday');
    expect(listed.single.isRemoteOnly, isFalse);
    expect(listed.single.remoteSessionId, 'sess_1');
    await store.setPinned('convo_1', true);
    expect((await store.list()).single.pinned, isTrue);
    await store.setTitle('convo_1', '  Friday dinner  ');
    final renamed = await store.read('convo_1');
    expect(renamed?.title, 'Friday dinner');
    expect(renamed?.titleCustom, isTrue);
    expect((await store.list()).single.title, 'Friday dinner');

    final loaded = await store.read('convo_1');
    expect(loaded?.messages, hasLength(2));
    expect(loaded?.messages.first.isVoice, isTrue);
    expect(loaded?.messages.first.audioPath, '/tmp/note.m4a');
    expect(
      loaded?.messages.first.remoteAudio,
      '/opt/data/.hermes/audio_cache/note.ogg',
    );
    expect(loaded?.messages.last.text, 'Here is a plan.');
    expect(loaded?.sessionKey, 'agent:main:mobile:dm:convo_1');
    expect(loaded?.draftText, 'Also bring wine');
    expect(loaded?.draftImagePaths, ['/tmp/menu.jpg']);

    await store.delete('convo_1');
    expect(await store.list(), isEmpty);
  });
}
