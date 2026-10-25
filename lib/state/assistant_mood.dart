import '../models/chat_message.dart';

/// What Frank is doing right now. The edge glow, the orb, and the header
/// status all read from this one value so they never disagree.
enum AssistantMood {
  idle,
  listening,
  transcribing,
  thinking,
  tool,
  responding,
  speaking,
  reconnecting,
  error,
}

/// True while Frank is visibly busy (anything but idle or a resting error).
bool moodIsBusy(AssistantMood mood) {
  return mood != AssistantMood.idle && mood != AssistantMood.error;
}

/// The live tool line ("🔍 Web search: weather Lagos…") of the reply that is
/// still streaming, or null when Frank is only thinking or writing.
String? activeToolLabel(List<ChatMessage> messages) {
  for (var i = messages.length - 1; i >= 0; i--) {
    final message = messages[i];
    if (!message.isAssistant || !message.streaming) {
      continue;
    }
    final tool = message.toolStatus?.trim();
    if (tool == null || tool.isEmpty || isThinkingLabel(tool)) {
      return null;
    }
    return tool;
  }
  return null;
}

AssistantMood resolveMood({
  required bool recording,
  required bool sending,
  required List<ChatMessage> messages,
  String? status,
  String? playingId,
  String? error,
}) {
  if (recording) {
    return AssistantMood.listening;
  }
  final lowered = status?.toLowerCase() ?? '';
  if (lowered.startsWith('transcrib')) {
    return AssistantMood.transcribing;
  }
  if (lowered.contains('reconnect') || lowered.contains('waiting to reconnect')) {
    return AssistantMood.reconnecting;
  }
  if (sending) {
    if (activeToolLabel(messages) != null) {
      return AssistantMood.tool;
    }
    final writing = messages.any(
      (message) =>
          message.isAssistant &&
          message.streaming &&
          message.text.trim().isNotEmpty,
    );
    return writing ? AssistantMood.responding : AssistantMood.thinking;
  }
  if (playingId != null || lowered.startsWith('speaking') || lowered.startsWith('fetching voice')) {
    return AssistantMood.speaking;
  }
  if (error != null && error.trim().isNotEmpty) {
    return AssistantMood.error;
  }
  return AssistantMood.idle;
}

/// True for Hermes's generic progress lines ("Thinking…", "Working…"),
/// which are not a named tool.
bool isThinkingLabel(String label) {
  final value = label.trim().toLowerCase();
  return value == 'thinking…' || value == 'thinking...' || value == 'working…';
}
