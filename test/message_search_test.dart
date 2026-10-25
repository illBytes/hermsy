import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/models/chat_message.dart';
import 'package:hermes_app/services/message_search.dart';

void main() {
  final messages = [
    ChatMessage(id: 'u1', role: MessageRole.user, text: 'Plan Friday dinner'),
    ChatMessage(
      id: 'a1',
      role: MessageRole.assistant,
      text: 'Book a table at six.',
    ),
    ChatMessage(id: 'u2', role: MessageRole.user, text: 'And wine'),
  ];

  test('finds messages newest first', () {
    final hits = findMessageHits(messages, 'a');
    expect(hits.map((hit) => hit.messageId).toList(), ['u2', 'a1', 'u1']);
  });

  test('is case insensitive and ignores empty queries', () {
    expect(findMessageHits(messages, '  WINE  ').single.messageId, 'u2');
    expect(findMessageHits(messages, '   '), isEmpty);
    expect(findMessageHits(messages, 'nope'), isEmpty);
  });

  test('does not match audio markup leftovers', () {
    final voice = ChatMessage(
      id: 'a2',
      role: MessageRole.assistant,
      text: '/opt/data/.hermes/audio_cache/note.ogg',
    );
    expect(findMessageHits([voice], 'audio_cache'), isEmpty);
  });
}
