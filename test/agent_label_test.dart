import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/services/agent_label.dart';

void main() {
  test('pretty-prints a provider model id', () {
    expect(prettyModelName('google/gemini-3.7-flash'), 'Gemini 3.7 Flash');
    expect(prettyModelName('anthropic/claude-sonnet-4.6'), 'Claude Sonnet 4.6');
    expect(prettyModelName('hermes-agent'), isNull);
  });

  test('formats the header agent line', () {
    expect(formatAgentLabel(), 'Hermes');
    expect(
      formatAgentLabel(name: 'Hermes', model: 'google/gemini-3.7-flash'),
      'Hermes · Gemini 3.7 Flash',
    );
  });

  test('ignores the default main session-key agent', () {
    expect(agentNameFromSessionKey('agent:main:mobile:dm:convo_1'), isNull);
    expect(agentNameFromSessionKey('agent:research:mobile:dm:x'), 'Research');
  });
}
