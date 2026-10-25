import '../models/chat_message.dart';

/// If Hermes finished the turn after the phone dropped SSE, use that text.
String? betterRemoteAssistant({
  required List<ChatMessage> local,
  required List<ChatMessage> remote,
}) {
  ChatMessage? localAssistant;
  for (final message in local) {
    if (message.isAssistant) {
      localAssistant = message;
    }
  }
  ChatMessage? remoteAssistant;
  for (final message in remote) {
    if (message.isAssistant && message.text.trim().isNotEmpty) {
      remoteAssistant = message;
    }
  }
  final remoteText = remoteAssistant?.text.trim() ?? '';
  if (remoteText.isEmpty) {
    return null;
  }
  final localText = localAssistant?.text.trim() ?? '';
  if (remoteText.length > localText.length) {
    return remoteAssistant!.text;
  }
  return null;
}

bool looksLikeDroppedReply(String? error) {
  if (error == null || error.isEmpty) {
    return false;
  }
  final lower = error.toLowerCase();
  return lower.contains('cut off') ||
      lower.contains('connection closed') ||
      lower.contains('tap retry');
}
