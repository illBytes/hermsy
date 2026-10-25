class ParsedSlash {
  const ParsedSlash({required this.name, required this.args});

  final String name;
  final String args;
}

ParsedSlash? parseSlash(String text) {
  final trimmed = text.trim();
  if (!trimmed.startsWith('/')) {
    return null;
  }
  final parts = trimmed.split(RegExp(r'\s+'));
  final name = parts.first.toLowerCase();
  if (!RegExp(r'^/[a-z0-9_-]+$').hasMatch(name)) {
    return null;
  }
  return ParsedSlash(name: name, args: parts.skip(1).join(' ').trim());
}

const supportedSlashHelp = '''
Frank commands (like Telegram):

/new, /reset, /clear — start a fresh chat
/usage — tokens and cost from Hermes for this chat
/status — connection and session info
/stop — stop the current reply
/undo — remove the last exchange
/help — this list

Voice: hold or tap the mic. Hermes transcribes it (same STT as Telegram) and can speak the reply.
Photos: tap the picture button to attach from the library or camera.

Other Hermes flags (/model, /compress, /insights, …) are Telegram and CLI only. The HTTP API does not run the gateway command dispatcher, so Frank handles the ones above locally.''';
