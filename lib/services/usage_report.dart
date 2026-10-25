class HermesUsage {
  const HermesUsage({
    this.sessionId,
    this.title,
    this.model,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheWriteTokens = 0,
    this.reasoningTokens = 0,
    this.totalTokens = 0,
    this.apiCalls,
    this.messageCount,
    this.estimatedCostUsd,
    this.actualCostUsd,
    this.costStatus,
  });

  final String? sessionId;
  final String? title;
  final String? model;
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final int reasoningTokens;
  final int totalTokens;
  final int? apiCalls;
  final int? messageCount;
  final double? estimatedCostUsd;
  final double? actualCostUsd;
  final String? costStatus;

  int get resolvedTotal =>
      totalTokens > 0
          ? totalTokens
          : inputTokens +
              outputTokens +
              cacheReadTokens +
              cacheWriteTokens +
              reasoningTokens;

  bool get hasTokens =>
      inputTokens > 0 ||
      outputTokens > 0 ||
      cacheReadTokens > 0 ||
      cacheWriteTokens > 0 ||
      resolvedTotal > 0;

  bool get hasCost =>
      (estimatedCostUsd != null && estimatedCostUsd! > 0) ||
      (actualCostUsd != null && actualCostUsd! > 0) ||
      costStatus == 'included';

  HermesUsage operator +(HermesUsage other) {
    return HermesUsage(
      sessionId: sessionId ?? other.sessionId,
      title: title ?? other.title,
      model: model ?? other.model,
      inputTokens: inputTokens + other.inputTokens,
      outputTokens: outputTokens + other.outputTokens,
      cacheReadTokens: cacheReadTokens + other.cacheReadTokens,
      cacheWriteTokens: cacheWriteTokens + other.cacheWriteTokens,
      reasoningTokens: reasoningTokens + other.reasoningTokens,
      totalTokens: resolvedTotal + other.resolvedTotal,
      apiCalls: (apiCalls ?? 0) + (other.apiCalls ?? 0),
      messageCount: other.messageCount ?? messageCount,
      estimatedCostUsd: _sumCost(estimatedCostUsd, other.estimatedCostUsd),
      actualCostUsd: _sumCost(actualCostUsd, other.actualCostUsd),
      costStatus: costStatus ?? other.costStatus,
    );
  }

  factory HermesUsage.fromJson(Map<String, dynamic> json) {
    final nested = json['usage'];
    final usage = nested is Map<String, dynamic> ? nested : json;
    return HermesUsage(
      sessionId: _asString(json['id'] ?? json['session_id'] ?? json['sessionId']),
      title: _asString(json['title']),
      model: _asString(json['model'] ?? usage['model']),
      inputTokens: _asInt(
        usage['input_tokens'] ??
            usage['prompt_tokens'] ??
            json['input_tokens'] ??
            json['prompt_tokens'] ??
            json['inputTokens'],
      ),
      outputTokens: _asInt(
        usage['output_tokens'] ??
            usage['completion_tokens'] ??
            json['output_tokens'] ??
            json['completion_tokens'] ??
            json['outputTokens'],
      ),
      cacheReadTokens: _asInt(
        usage['cache_read_tokens'] ??
            json['cache_read_tokens'] ??
            json['cacheReadTokens'],
      ),
      cacheWriteTokens: _asInt(
        usage['cache_write_tokens'] ??
            json['cache_write_tokens'] ??
            json['cacheWriteTokens'],
      ),
      reasoningTokens: _asInt(
        usage['reasoning_tokens'] ?? json['reasoning_tokens'],
      ),
      totalTokens: _asInt(
        usage['total_tokens'] ?? json['total_tokens'] ?? json['totalTokens'],
      ),
      apiCalls: _asIntOrNull(
        json['api_call_count'] ??
            json['api_calls'] ??
            usage['api_call_count'] ??
            json['request_count'],
      ),
      messageCount: _asIntOrNull(
        json['message_count'] ?? json['messages'] ?? json['messageCount'],
      ),
      estimatedCostUsd: _asDouble(
        json['estimated_cost_usd'] ??
            json['estimated_cost'] ??
            usage['estimated_cost_usd'] ??
            json['cost_usd'],
      ),
      actualCostUsd: _asDouble(json['actual_cost_usd'] ?? usage['actual_cost_usd']),
      costStatus: _asString(json['cost_status'] ?? usage['cost_status']),
    );
  }

  factory HermesUsage.fromAnalytics(Map<String, dynamic> json) {
    final summary = json['summary'];
    final source = summary is Map<String, dynamic> ? summary : json;
    return HermesUsage(
      inputTokens: _asInt(
        source['total_input_tokens'] ??
            source['input_tokens'] ??
            source['input'] ??
            json['total_input_tokens'],
      ),
      outputTokens: _asInt(
        source['total_output_tokens'] ??
            source['output_tokens'] ??
            source['output'] ??
            json['total_output_tokens'],
      ),
      cacheReadTokens: _asInt(
        source['cache_read_tokens'] ?? json['cache_read_tokens'],
      ),
      cacheWriteTokens: _asInt(
        source['cache_write_tokens'] ?? json['cache_write_tokens'],
      ),
      totalTokens: _asInt(
        source['total_tokens'] ?? json['total_tokens'],
      ),
      messageCount: _asIntOrNull(
        source['session_count'] ??
            source['sessions'] ??
            json['session_count'] ??
            json['sessions'],
      ),
      estimatedCostUsd: _asDouble(
        source['estimated_cost_usd'] ??
            source['total_cost'] ??
            source['cost'] ??
            json['estimated_cost_usd'] ??
            json['total_cost'],
      ),
      actualCostUsd: _asDouble(source['actual_cost_usd'] ?? json['actual_cost_usd']),
      costStatus: _asString(source['cost_status'] ?? json['cost_status']),
    );
  }
}

String formatUsageReport({
  HermesUsage? session,
  HermesUsage? conversation,
  HermesUsage? lastTurn,
  HermesUsage? recent,
  int localTurns = 0,
}) {
  final lines = <String>['**Usage**'];
  var wrote = false;

  if (session != null && (session.hasTokens || session.hasCost || session.model != null)) {
    lines.addAll(_block('This Hermes session', session, extra: [
      if (session.title != null && session.title!.trim().isNotEmpty)
        'Title: ${session.title}',
      if (session.sessionId != null) 'Session: ${session.sessionId}',
    ]));
    wrote = true;
  } else if (localTurns == 0) {
    lines.add('');
    lines.add('This chat has no Hermes session yet.');
  }

  if (lastTurn != null && lastTurn.hasTokens) {
    lines.addAll(_block('Last reply', lastTurn));
    wrote = true;
  }

  if (conversation != null && conversation.hasTokens) {
    lines.addAll(_block('This chat (from streamed replies)', conversation));
    wrote = true;
  }

  if (recent != null && (recent.hasTokens || recent.hasCost || recent.messageCount != null)) {
    lines.addAll(_block('This server · last 7 days', recent, extra: [
      if (recent.messageCount != null) 'Sessions: ${recent.messageCount}',
    ]));
    wrote = true;
  }

  if (!wrote) {
    lines.add('Local turns: $localTurns');
    lines.add(
      'Hermes has not reported token totals for this chat yet. '
      'Totals appear after a streamed reply that includes usage.',
    );
  } else if (localTurns > 0) {
    lines.add('Local turns in this chat: $localTurns');
  }

  return lines.join('\n');
}

List<String> _block(String heading, HermesUsage usage, {List<String> extra = const []}) {
  final lines = <String>['', heading];
  if (usage.model != null && usage.model!.trim().isNotEmpty) {
    lines.add('Model: ${usage.model}');
  }
  lines.addAll(extra);
  if (usage.messageCount != null && !extra.any((line) => line.startsWith('Sessions:'))) {
    lines.add('Messages: ${usage.messageCount}');
  }
  if (usage.inputTokens > 0) {
    lines.add('Input tokens: ${_count(usage.inputTokens)}');
  }
  if (usage.cacheReadTokens > 0) {
    lines.add('Cache read tokens: ${_count(usage.cacheReadTokens)}');
  }
  if (usage.cacheWriteTokens > 0) {
    lines.add('Cache write tokens: ${_count(usage.cacheWriteTokens)}');
  }
  if (usage.outputTokens > 0) {
    lines.add('Output tokens: ${_count(usage.outputTokens)}');
  }
  if (usage.reasoningTokens > 0) {
    lines.add('Reasoning tokens: ${_count(usage.reasoningTokens)}');
  }
  if (usage.resolvedTotal > 0) {
    lines.add('Total: ${_count(usage.resolvedTotal)}');
  }
  if (usage.apiCalls != null && usage.apiCalls! > 0) {
    lines.add('API calls: ${usage.apiCalls}');
  }
  final cost = _costLine(usage);
  if (cost != null) {
    lines.add(cost);
  }
  return lines;
}

String? _costLine(HermesUsage usage) {
  if (usage.costStatus == 'included') {
    return 'Cost: included';
  }
  final actual = usage.actualCostUsd;
  if (actual != null && actual > 0) {
    return 'Cost: \$${actual.toStringAsFixed(4)}';
  }
  final estimated = usage.estimatedCostUsd;
  if (estimated != null && estimated > 0) {
    return 'Cost: ~\$${estimated.toStringAsFixed(4)}';
  }
  if (usage.costStatus == 'unknown') {
    return 'Cost: n/a';
  }
  return null;
}

String _count(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final fromEnd = text.length - i;
    buffer.write(text[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}

double? _sumCost(double? a, double? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a + b;
}

int _asInt(dynamic raw) => _asIntOrNull(raw) ?? 0;

int? _asIntOrNull(dynamic raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw.replaceAll(',', ''));
  return null;
}

double? _asDouble(dynamic raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.replaceAll('\$', '').trim());
  return null;
}

String? _asString(dynamic raw) {
  if (raw == null) return null;
  final value = raw.toString().trim();
  return value.isEmpty ? null : value;
}
