import '../models/chat_message.dart';
import 'audio_delivery.dart';
import 'image_delivery.dart';
import 'slash_commands.dart';

class RetryTarget {
  const RetryTarget({
    required this.prompt,
    required this.removeFrom,
    this.fromVoice = false,
    this.audioPath,
    this.imagePaths = const [],
  });

  final String prompt;
  final int removeFrom;
  final bool fromVoice;
  final String? audioPath;
  final List<String> imagePaths;
}

String copyableText(ChatMessage message) {
  return stripImageMarkup(stripAudioMarkup(message.text)).trim();
}

bool canCopyMessage(ChatMessage message) => copyableText(message).isNotEmpty;

bool canSpeakMessage(ChatMessage message) {
  if (message.streaming && message.text.isEmpty) {
    return false;
  }
  return canCopyMessage(message) || message.hasAudio;
}

/// Only what the AI wrote can be reported: a finished reply, not Frank's own
/// notes (errors, slash command answers) and not your messages.
bool canReportMessage(ChatMessage message) =>
    message.isAssistant &&
    !message.streaming &&
    !message.error &&
    !message.id.startsWith('cmd_') &&
    canCopyMessage(message);

bool canRetryMessage(ChatMessage message, {required bool busy}) {
  if (busy || message.streaming || message.id.startsWith('cmd_')) {
    return false;
  }
  if (message.isUser && parseSlash(message.text) != null) {
    return false;
  }
  return true;
}

RetryTarget? retryTarget(List<ChatMessage> messages, ChatMessage message) {
  final index = messages.indexWhere((item) => item.id == message.id);
  if (index < 0) {
    return null;
  }

  ChatMessage? user;
  var removeFrom = index;
  if (message.isUser) {
    user = message;
  } else {
    for (var i = index; i >= 0; i--) {
      if (messages[i].isUser) {
        user = messages[i];
        removeFrom = i;
        break;
      }
    }
  }
  if (user == null) {
    return null;
  }
  if (parseSlash(user.text) != null) {
    return null;
  }
  final prompt = user.isVoice
      ? (user.text.trim().isNotEmpty ? user.text.trim() : copyableText(user))
      : user.text.trim();
  if (prompt.isEmpty && user.audioPath == null && !user.hasImages) {
    return null;
  }
  return RetryTarget(
    prompt: prompt.isEmpty
        ? (user.hasImages ? 'Photo' : 'Voice note')
        : prompt,
    removeFrom: removeFrom,
    fromVoice: user.isVoice,
    audioPath: user.audioPath,
    imagePaths: List<String>.from(user.imagePaths),
  );
}
