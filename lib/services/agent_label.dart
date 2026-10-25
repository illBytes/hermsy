String formatAgentLabel({String? name, String? model}) {
  final agent = (name == null || name.trim().isEmpty) ? 'Hermes' : name.trim();
  final pretty = prettyModelName(model);
  if (pretty == null) {
    return agent;
  }
  if (pretty.toLowerCase() == agent.toLowerCase()) {
    return pretty;
  }
  return '$agent · $pretty';
}

String? prettyModelName(String? raw) {
  if (raw == null) {
    return null;
  }
  final id = raw.trim();
  if (id.isEmpty || id == 'hermes-agent') {
    return null;
  }
  final slug = id.split('/').last.replaceAll('_', '-');
  if (slug.isEmpty) {
    return null;
  }
  return slug.split('-').where((part) => part.isNotEmpty).map(_titlePart).join(' ');
}

String? agentNameFromSessionKey(String? key) {
  if (key == null || key.isEmpty) {
    return null;
  }
  final parts = key.split(':');
  if (parts.length >= 2 && parts[0] == 'agent') {
    final id = parts[1].trim();
    if (id.isEmpty || id == 'main') {
      return null;
    }
    return _titlePart(id);
  }
  return null;
}

String agentNameFromHealth(String? platform) {
  if (platform == null || platform.trim().isEmpty) {
    return 'Hermes';
  }
  final value = platform.trim();
  if (value == 'hermes-agent' || value.toLowerCase() == 'hermes') {
    return 'Hermes';
  }
  return prettyModelName(value) ?? 'Hermes';
}

String _titlePart(String raw) {
  final part = raw.trim();
  if (part.isEmpty) {
    return part;
  }
  final lower = part.toLowerCase();
  if (lower == 'gpt') {
    return 'GPT';
  }
  if (RegExp(r'^\d').hasMatch(part)) {
    return part;
  }
  return '${part[0].toUpperCase()}${part.substring(1)}';
}
