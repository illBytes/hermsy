import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/services/hermes_client.dart';
import 'package:hermes_app/services/sse_parser.dart';
import 'package:hermes_app/services/tool_activity.dart';

void main() {
  test('formats Hermes tool progress the way Telegram did', () {
    expect(
      formatToolActivity(
        name: 'web_search',
        label: 'weather Lagos',
        emoji: '🔍',
      ),
      '🔍 weather Lagos…',
    );
    expect(
      formatToolActivity(name: 'skill_view', label: 'Reading skill calendar'),
      'Reading skill calendar…',
    );
    expect(formatToolActivity(name: 'web_search'), 'Web Search…');
    expect(formatToolActivity(name: '_thinking'), 'Thinking…');
    expect(formatToolActivity(name: 'web_search', completed: true), '');
  });

  test('reads hermes.tool.progress from the completions stream', () {
    final running = mapCompletionsSse(
      const SseEvent(
        event: 'hermes.tool.progress',
        data:
            '{"tool":"skill_view","emoji":"📚","label":"Reading skill calendar","status":"running"}',
      ),
    );
    expect(running?.kind, HermesEventKind.tool);
    expect(running?.toolName, 'skill_view');
    expect(running?.toolEmoji, '📚');
    expect(running?.toolLabel, 'Reading skill calendar');
    expect(running?.toolCompleted, isFalse);
    expect(
      formatToolActivity(
        name: running?.toolName,
        label: running?.toolLabel,
        emoji: running?.toolEmoji,
      ),
      '📚 Reading skill calendar…',
    );

    final done = mapCompletionsSse(
      const SseEvent(
        event: 'hermes.tool.progress',
        data: '{"tool":"skill_view","toolCallId":"1","status":"completed"}',
      ),
    );
    expect(done?.toolCompleted, isTrue);
  });

  test('reads session tool.started preview', () {
    final event = mapSessionSse(
      const SseEvent(
        event: 'tool.started',
        data: '{"tool_name":"web_search","preview":"weather Lagos"}',
      ),
    );
    expect(event?.kind, HermesEventKind.tool);
    expect(event?.toolName, 'web_search');
    expect(event?.toolLabel, 'weather Lagos');
  });
}
