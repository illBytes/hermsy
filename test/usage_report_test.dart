import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/services/hermes_client.dart';
import 'package:hermes_app/services/sse_parser.dart';
import 'package:hermes_app/services/usage_report.dart';

void main() {
  test('reads nested session usage and OpenAI token names', () {
    final usage = HermesUsage.fromJson({
      'id': 'sess_1',
      'title': 'Mobile',
      'model': 'anthropic/claude-sonnet-4.6',
      'message_count': 8,
      'usage': {
        'prompt_tokens': 35000,
        'completion_tokens': 10000,
        'cache_read_tokens': 5000,
        'total_tokens': 50000,
        'estimated_cost_usd': 0.1234,
      },
    });

    expect(usage.sessionId, 'sess_1');
    expect(usage.inputTokens, 35000);
    expect(usage.outputTokens, 10000);
    expect(usage.cacheReadTokens, 5000);
    expect(usage.resolvedTotal, 50000);
    expect(usage.estimatedCostUsd, closeTo(0.1234, 0.0001));
  });

  test('formats a Hermes-style usage report', () {
    final text = formatUsageReport(
      session: const HermesUsage(
        sessionId: 'abc',
        model: 'anthropic/claude-sonnet-4.6',
        inputTokens: 35000,
        outputTokens: 10000,
        cacheReadTokens: 5000,
        totalTokens: 50000,
        estimatedCostUsd: 0.1234,
        messageCount: 8,
      ),
      localTurns: 4,
    );

    expect(text, contains('This Hermes session'));
    expect(text, contains('Input tokens: 35,000'));
    expect(text, contains('Cache read tokens: 5,000'));
    expect(text, contains('Output tokens: 10,000'));
    expect(text, contains('Cost: ~\$0.1234'));
    expect(text, contains('Local turns in this chat: 4'));
  });

  test('maps a completions finish chunk with usage', () {
    final event = mapCompletionsSse(
      const SseEvent(
        event: 'message',
        data:
            '{"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":50,"completion_tokens":200,"total_tokens":250}}',
      ),
    );

    expect(event?.kind, HermesEventKind.completed);
    expect(event?.usage?.inputTokens, 50);
    expect(event?.usage?.outputTokens, 200);
  });

  test('does not invent an old session when this chat is empty', () {
    final text = formatUsageReport(
      recent: const HermesUsage(
        inputTokens: 90000,
        outputTokens: 20000,
        messageCount: 4,
      ),
    );
    expect(text, contains('This chat has no Hermes session yet.'));
    expect(text, contains('This server · last 7 days'));
    expect(text, isNot(contains('This Hermes session')));
  });

  test('reads analytics summary totals', () {
    final usage = HermesUsage.fromAnalytics({
      'summary': {
        'total_input_tokens': 12000,
        'total_output_tokens': 4000,
        'estimated_cost_usd': 0.05,
        'session_count': 3,
      },
    });
    expect(usage.inputTokens, 12000);
    expect(usage.messageCount, 3);
    expect(formatUsageReport(recent: usage), contains('This server · last 7 days'));
  });
}
