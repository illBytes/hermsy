import '../models/chat_message.dart';

/// The first message of a reply thread: what Hermes sent on its own (a cron
/// result and the like). Its id carries this prefix.
const proactiveMessagePrefix = 'proactive_';

bool isProactiveMessage(ChatMessage message) =>
    message.id.startsWith(proactiveMessagePrefix);

const _open = '[Replying to your earlier message';
const _close = '\n---]\n\n';

/// What Frank sends Hermes for [text] in a conversation of [messages].
///
/// Hermes has no way to add its own earlier message to a session, so the
/// first reply in a reply thread carries it as quoted context. Hermes keeps
/// that turn in the session, so later replies need nothing extra. The
/// thread on the phone shows only what the person typed.
String hermesPromptFor(
  List<ChatMessage> messages,
  String text, {
  String? title,
}) {
  if (messages.isEmpty ||
      !isProactiveMessage(messages.first) ||
      messages.any((message) => message.isUser)) {
    return text;
  }
  final first = messages.first;
  final from = title == null || title.trim().isEmpty
      ? ''
      : ' from "${title.trim()}"';
  final stamp = first.createdAt.toLocal().toIso8601String().substring(0, 16);
  return '$_open$from, sent ${stamp.replaceFirst('T', ' ')}:\n'
      '---\n'
      '${first.text.trim()}'
      '$_close'
      '$text';
}

/// Splits a first reply as Hermes stored it back into the quoted message
/// and what the person typed, for history imported from Hermes.
({String? quoted, String text}) splitProactivePrompt(String stored) {
  if (!stored.startsWith(_open)) {
    return (quoted: null, text: stored);
  }
  final start = stored.indexOf('\n---\n');
  final end = stored.indexOf(_close);
  if (start < 0 || end < start) {
    return (quoted: null, text: stored);
  }
  return (
    quoted: stored.substring(start + 5, end).trim(),
    text: stored.substring(end + _close.length),
  );
}
