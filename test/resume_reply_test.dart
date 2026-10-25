import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/models/chat_message.dart';
import 'package:hermes_app/services/resume_reply.dart';

void main() {
  test('uses a longer assistant reply from the Hermes session', () {
    expect(
      betterRemoteAssistant(
        local: [
          ChatMessage(id: 'u', role: MessageRole.user, text: 'Make a banner'),
          ChatMessage(id: 'a', role: MessageRole.assistant, text: 'Working'),
        ],
        remote: [
          ChatMessage(id: 'u2', role: MessageRole.user, text: 'Make a banner'),
          ChatMessage(
            id: 'a2',
            role: MessageRole.assistant,
            text: 'Working on it. Here is the banner.',
          ),
        ],
      ),
      'Working on it. Here is the banner.',
    );
  });

  test('returns null when the session has nothing newer', () {
    expect(
      betterRemoteAssistant(
        local: [
          ChatMessage(
            id: 'a',
            role: MessageRole.assistant,
            text: 'Already finished this reply.',
          ),
        ],
        remote: [
          ChatMessage(id: 'a2', role: MessageRole.assistant, text: 'Already'),
        ],
      ),
      isNull,
    );
  });

  test('recognizes the dropped-stream retry copy', () {
    expect(
      looksLikeDroppedReply(
        'Reply was cut off before Hermsy finished. Tap Retry to ask again.',
      ),
      isTrue,
    );
    expect(looksLikeDroppedReply('Wrong PIN'), isFalse);
  });
}
