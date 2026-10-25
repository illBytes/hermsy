String prepareReplyMarkdown(String raw) {
  var text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  text = _splitGluedFences(text);
  text = _fenceBareRuns(text);
  return _closeOpenFence(text);
}

/// Models often glue fences to the first/last code line:
/// ` ```#include <iostream>` and `}``` `. Markdown then treats the opener
/// as a one-line scrap and leaves the rest as prose or a second block.
String _splitGluedFences(String text) {
  final out = <String>[];
  for (final line in text.split('\n')) {
    out.addAll(_unglueFenceLine(line));
  }
  return out.join('\n');
}

final _langOnly = RegExp(r'^[a-zA-Z][\w+#.-]*$');

List<String> _unglueFenceLine(String line) {
  final trimmed = line.trimLeft();
  final indent = line.substring(0, line.length - trimmed.length);
  if (trimmed.startsWith('```')) {
    final ticks = RegExp(r'^```+').stringMatch(trimmed)!;
    final rest = trimmed.substring(ticks.length).trim();
    if (rest.isEmpty || _langOnly.hasMatch(rest)) {
      return [line];
    }
    var content = rest;
    var closed = false;
    if (content.endsWith('```')) {
      content = content.substring(0, content.length - 3).trimRight();
      closed = true;
    }
    return [
      '$indent$ticks',
      if (content.isNotEmpty) content,
      if (closed) '$indent$ticks',
    ];
  }
  final gluedClose = RegExp(r'^(.*\S)[ \t]*(```+)\s*$').firstMatch(line);
  if (gluedClose != null) {
    return [gluedClose.group(1)!, gluedClose.group(2)!];
  }
  return [line];
}

String _closeOpenFence(String text) {
  var fences = 0;
  for (final line in text.split('\n')) {
    if (line.trimLeft().startsWith('```')) {
      fences += 1;
    }
  }
  if (fences.isOdd) {
    return text.endsWith('\n') ? '$text```' : '$text\n```';
  }
  return text;
}

String _fenceBareRuns(String text) {
  final lines = text.split('\n');
  final out = <String>[];
  var i = 0;
  var inFence = false;
  while (i < lines.length) {
    final line = lines[i];
    if (line.trimLeft().startsWith('```')) {
      inFence = !inFence;
      out.add(line);
      i += 1;
      continue;
    }
    if (inFence) {
      out.add(line);
      i += 1;
      continue;
    }
    final run = _bareCodeRun(lines, i);
    if (run != null) {
      out.add('```');
      out.addAll(lines.sublist(i, run));
      out.add('```');
      i = run;
      continue;
    }
    out.add(line);
    i += 1;
  }
  return out.join('\n');
}

int? _bareCodeRun(List<String> lines, int start) {
  if (!_looksLikeCodeLine(lines[start], allowBlank: false)) {
    return null;
  }
  var i = start;
  var codeLines = 0;
  while (i < lines.length) {
    final line = lines[i];
    if (line.trimLeft().startsWith('```')) {
      break;
    }
    if (line.trim().isEmpty) {
      if (i + 1 < lines.length &&
          _looksLikeCodeLine(lines[i + 1], allowBlank: false)) {
        i += 1;
        continue;
      }
      break;
    }
    if (!_looksLikeCodeLine(line, allowBlank: false)) {
      break;
    }
    codeLines += 1;
    i += 1;
  }
  if (codeLines < 3) {
    return null;
  }
  return i;
}

final _codeStart = RegExp(
  r'^(?:'
  r'[\t ]+\S|'
  r'(?:def|class|import|from|function|const|let|var|return|export|package|fun|fn|pub|void|int|char|long|bool|auto|std|if|for|while|switch|struct|enum|interface|typedef|using|include|public|private|protected|async|await|try|catch|finally|throw|new|this|self|print|console)\b|'
  r'\w+\(|'
  r'[{}\]);]|'
  r'</?[A-Za-z]|'
  r'@\w+|'
  r'#include\b|'
  r'\$\w+'
  r')',
);

bool _looksLikeCodeLine(String line, {required bool allowBlank}) {
  if (line.trim().isEmpty) {
    return allowBlank;
  }
  return _codeStart.hasMatch(line);
}
