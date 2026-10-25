/// Formats Hermes tool/skill progress the way Telegram did: a short live
/// line such as "🔍 web search: weather Lagos" before the final reply.
String formatToolActivity({
  String? name,
  String? label,
  String? emoji,
  bool completed = false,
}) {
  if (completed) {
    return '';
  }

  final tool = (name ?? '').trim();
  if (tool == '_thinking' || (tool.startsWith('_') && tool.isNotEmpty)) {
    return 'Thinking…';
  }

  final preview = (label ?? '').trim();
  final title = preview.isNotEmpty ? preview : _humanizeTool(tool);
  final icon = (emoji ?? '').trim();

  if (title.isEmpty) {
    return icon.isEmpty ? 'Working…' : '$icon Working…';
  }

  final withEllipsis = title.endsWith('…') || title.endsWith('...')
      ? title
      : '$title…';
  if (icon.isNotEmpty && !withEllipsis.startsWith(icon)) {
    return '$icon $withEllipsis';
  }
  return withEllipsis;
}

String _humanizeTool(String name) {
  if (name.isEmpty) {
    return '';
  }
  final words = name
      .replaceAll('-', '_')
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) {
        if (part.length == 1) {
          return part.toLowerCase();
        }
        return '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
      })
      .join(' ');
  return words;
}
