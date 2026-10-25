import '../models/chat_message.dart';
import 'message_actions.dart';

class MessageHit {
  const MessageHit({required this.messageId, required this.index});

  final String messageId;
  final int index;
}

List<MessageHit> findMessageHits(List<ChatMessage> messages, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return const [];
  }
  final hits = <MessageHit>[];
  for (var i = messages.length - 1; i >= 0; i--) {
    final text = copyableText(messages[i]);
    if (text.toLowerCase().contains(needle)) {
      hits.add(MessageHit(messageId: messages[i].id, index: i));
    }
  }
  return hits;
}
