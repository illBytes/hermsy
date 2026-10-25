import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/models/chat_message.dart';
import 'package:hermes_app/state/assistant_mood.dart';

void main() {
  ChatMessage reply({String text = '', bool streaming = true, String? tool}) {
    return ChatMessage(
      id: 'a1',
      role: MessageRole.assistant,
      text: text,
      streaming: streaming,
      toolStatus: tool,
    );
  }

  test('listening wins over everything', () {
    expect(
      resolveMood(recording: true, sending: true, messages: [reply()]),
      AssistantMood.listening,
    );
  });

  test('sending with no text yet is thinking', () {
    expect(
      resolveMood(recording: false, sending: true, messages: [reply()]),
      AssistantMood.thinking,
    );
    expect(
      resolveMood(
        recording: false,
        sending: true,
        messages: [reply(tool: 'Thinking…')],
      ),
      AssistantMood.thinking,
    );
  });

  test('a named tool is tool use, with its label exposed', () {
    final messages = [reply(tool: '🔍 Web search: weather Lagos…')];
    expect(
      resolveMood(recording: false, sending: true, messages: messages),
      AssistantMood.tool,
    );
    expect(activeToolLabel(messages), '🔍 Web search: weather Lagos…');
  });

  test('streaming words is responding', () {
    expect(
      resolveMood(
        recording: false,
        sending: true,
        messages: [reply(text: 'Hello')],
      ),
      AssistantMood.responding,
    );
  });

  test('transcribing, reconnecting, speaking, error and idle', () {
    expect(
      resolveMood(
        recording: false,
        sending: false,
        messages: const [],
        status: 'Transcribing…',
      ),
      AssistantMood.transcribing,
    );
    expect(
      resolveMood(
        recording: false,
        sending: true,
        messages: const [],
        status: 'Reconnecting…',
      ),
      AssistantMood.reconnecting,
    );
    expect(
      resolveMood(
        recording: false,
        sending: false,
        messages: const [],
        playingId: 'a1',
      ),
      AssistantMood.speaking,
    );
    expect(
      resolveMood(
        recording: false,
        sending: false,
        messages: const [],
        error: 'Boom',
      ),
      AssistantMood.error,
    );
    expect(
      resolveMood(
        recording: false,
        sending: false,
        messages: const [],
        status: 'Using compatibility chat mode',
      ),
      AssistantMood.idle,
    );
    expect(moodIsBusy(AssistantMood.idle), isFalse);
    expect(moodIsBusy(AssistantMood.thinking), isTrue);
  });

  test('generic progress lines are not named tools', () {
    expect(isThinkingLabel('Thinking…'), isTrue);
    expect(isThinkingLabel(' working… '), isTrue);
    expect(isThinkingLabel('🔍 weather Lagos…'), isFalse);
  });

  test('tool trail survives a round trip through JSON', () {
    final message = ChatMessage(
      id: 'a2',
      role: MessageRole.assistant,
      text: 'Done',
      toolTrail: ['🔍 Web search: x…', '📄 Read file: y…'],
    );
    final again = ChatMessage.fromJson(message.toJson());
    expect(again.toolTrail, message.toolTrail);
    expect(ChatMessage.fromJson({'id': 'b', 'role': 'assistant', 'text': ''}).toolTrail, isEmpty);
  });
}
