import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/widgets/message_actions_sheet.dart';
import 'package:hermes_app/models/chat_message.dart';
import 'package:hermes_app/services/message_actions.dart';

void main() {
  test('retries from the user prompt before an assistant bubble', () {
    final user = ChatMessage(
      id: 'u1',
      role: MessageRole.user,
      text: 'Plan Friday',
    );
    final assistant = ChatMessage(
      id: 'a1',
      role: MessageRole.assistant,
      text: 'Here is a plan.',
    );
    final target = retryTarget([user, assistant], assistant);
    expect(target?.prompt, 'Plan Friday');
    expect(target?.removeFrom, 0);
  });

  test('does not retry a slash command exchange', () {
    final user = ChatMessage(id: 'u1', role: MessageRole.user, text: '/usage');
    final assistant = ChatMessage(
      id: 'cmd_1',
      role: MessageRole.assistant,
      text: 'Usage',
    );
    expect(retryTarget([user, assistant], assistant), isNull);
    expect(canRetryMessage(assistant, busy: false), isFalse);
  });

  test('copy strips audio markup', () {
    final message = ChatMessage(
      id: 'a1',
      role: MessageRole.assistant,
      text: 'Here you go\n/opt/data/.hermes/audio_cache/note.ogg',
    );
    expect(copyableText(message), 'Here you go');
    expect(canSpeakMessage(message), isTrue);
  });

  test('the actions sheet preview reads as plain text', () {
    const reply = 'Sure — here is **the** script:\n\n```bash\nmv a b\n```\n\n'
        '> Run it from [the root](https://x.dev). Only touches `exports/`.';
    expect(
      previewExcerpt(reply),
      'Sure — here is the script: mv a b Run it from the root. Only touches exports/.',
    );
    expect(previewExcerpt('x' * 600).length, 401);
  });
}
