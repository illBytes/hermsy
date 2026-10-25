import 'dart:convert';

class AudioRef {
  const AudioRef({
    required this.raw,
    this.dataUrl,
    this.httpUrl,
    this.filePath,
  });

  final String raw;
  final String? dataUrl;
  final String? httpUrl;
  final String? filePath;
}

final _audioExt = RegExp(
  r'\.(?:mp3|wav|ogg|opus|m4a|flac|aac)(?:\b|$)',
  caseSensitive: false,
);

final _mediaTag = RegExp(
  r'''[`"']?MEDIA:\s*[`"']?(\S+?\.(?:mp3|wav|ogg|opus|m4a|flac|aac))[`"']?''',
  caseSensitive: false,
);

final _dataUrl = RegExp(
  r'data:audio\/[a-z0-9.+-]+;base64,[A-Za-z0-9+/=\s]+',
  caseSensitive: false,
);

final _httpAudio = RegExp(
  r'https?://\S+\.(?:mp3|wav|ogg|opus|m4a|flac|aac)',
  caseSensitive: false,
);

final _filePath = RegExp(
  r'''(?:^|[\s`"'(:=])((?:file://|(?:[A-Za-z]:)?[~\\/]|\.{0,2}[\\/])?[^\s`"')]+?\.(?:mp3|wav|ogg|opus|m4a|flac|aac))''',
  caseSensitive: false,
);

final _anyAudioToken = RegExp(
  r'''[^\s`"']+\.(?:mp3|wav|ogg|opus|m4a|flac|aac)''',
  caseSensitive: false,
);

final _voiceMarker = RegExp(
  r'\[\[(?:audio_as_voice|as_voice|voice)\]\]',
  caseSensitive: false,
);

List<AudioRef> extractAudioRefs(String text) {
  final found = <AudioRef>[];
  final seen = <String>{};

  void add(AudioRef ref) {
    if (seen.add(ref.raw)) {
      found.add(ref);
    }
  }

  for (final match in _dataUrl.allMatches(text)) {
    add(AudioRef(raw: match.group(0)!, dataUrl: match.group(0)!.replaceAll(RegExp(r'\s'), '')));
  }
  for (final match in _httpAudio.allMatches(text)) {
    add(AudioRef(raw: match.group(0)!, httpUrl: match.group(0)));
  }
  for (final match in _mediaTag.allMatches(text)) {
    final path = match.group(1)!;
    if (path.startsWith('http')) {
      add(AudioRef(raw: match.group(0)!, httpUrl: path));
    } else if (path.startsWith('data:')) {
      add(AudioRef(raw: match.group(0)!, dataUrl: path));
    } else {
      add(AudioRef(raw: match.group(0)!, filePath: path));
    }
  }
  for (final match in _filePath.allMatches(text)) {
    add(AudioRef(raw: match.group(1)!, filePath: _cleanPath(match.group(1)!)));
  }
  for (final match in _anyAudioToken.allMatches(text)) {
    add(AudioRef(raw: match.group(0)!, filePath: _cleanPath(match.group(0)!)));
  }
  return found;
}

String _cleanPath(String path) {
  var value = path.trim();
  if (value.startsWith('file://')) {
    value = value.substring(7);
  }
  return value.replaceAll('\\', '/');
}

String stripAudioMarkup(String text) {
  var cleaned = text.replaceAll(_voiceMarker, '');
  cleaned = cleaned.replaceAll(_mediaTag, '');
  cleaned = cleaned.replaceAll(_dataUrl, '');
  cleaned = cleaned.replaceAll(_httpAudio, '');
  cleaned = cleaned.replaceAllMapped(_filePath, (match) {
    final whole = match.group(0)!;
    final path = match.group(1)!;
    return whole.replaceFirst(path, '');
  });
  cleaned = cleaned.replaceAll(_anyAudioToken, '');
  return cleaned
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

List<AudioRef> audioRefsOf(String text, {String? remote}) {
  final found = [...extractAudioRefs(text)];
  final extra = remote?.trim() ?? '';
  if (extra.isEmpty) {
    return found;
  }
  final fromRemote = extractAudioRefs(extra);
  if (fromRemote.isNotEmpty) {
    final seen = {for (final ref in found) ref.raw};
    for (final ref in fromRemote) {
      if (seen.add(ref.raw)) {
        found.add(ref);
      }
    }
    return found;
  }
  if (extra.startsWith('data:')) {
    found.add(AudioRef(raw: extra, dataUrl: extra));
  } else if (extra.startsWith('http')) {
    found.add(AudioRef(raw: extra, httpUrl: extra));
  } else {
    found.add(AudioRef(raw: extra, filePath: _cleanPath(extra)));
  }
  return found;
}

String audioFileName(String path) {
  return _cleanPath(path).split('/').last;
}

String? audioCacheRelative(String path) {
  final normalized = _cleanPath(path);
  for (final marker in ['audio_cache/', 'cache/audio/']) {
    final index = normalized.indexOf(marker);
    if (index >= 0) {
      return normalized.substring(index + marker.length);
    }
  }
  final name = audioFileName(normalized);
  return name.contains('.') ? name : null;
}

({List<int> bytes, String extension})? audioBytesFromDataUrl(String url) {
  final comma = url.indexOf(',');
  if (comma < 0) {
    return null;
  }
  try {
    final meta = url.substring(0, comma);
    final bytes = base64Decode(
      url.substring(comma + 1).replaceAll(RegExp(r'\s'), ''),
    );
    if (bytes.length < 64) {
      return null;
    }
    final ext = meta.contains('ogg')
        ? 'ogg'
        : meta.contains('wav')
            ? 'wav'
            : meta.contains('mp4') || meta.contains('m4a')
                ? 'm4a'
                : 'mp3';
    return (bytes: bytes, extension: ext);
  } catch (_) {
    return null;
  }
}

({List<int> bytes, String extension})? audioBytesFromJson(
  String body, {
  String fallbackExt = 'mp3',
}) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      return null;
    }
    final url = decoded['dataUrl'] ?? decoded['data_url'] ?? decoded['url'];
    if (url is String && url.startsWith('data:')) {
      return audioBytesFromDataUrl(url);
    }
    final raw = decoded['data'] ?? decoded['content'] ?? decoded['bytes'];
    if (raw is String && raw.isNotEmpty) {
      final bytes = base64Decode(raw.replaceAll(RegExp(r'\s'), ''));
      if (bytes.length < 64) {
        return null;
      }
      return (bytes: bytes, extension: fallbackExt);
    }
  } catch (_) {}
  return null;
}

List<String> audioDownloadPaths(String filePath) {
  final name = audioFileName(filePath);
  final relative = audioCacheRelative(filePath) ?? name;
  final encoded = Uri.encodeComponent(filePath);
  return [
    '/audio/$name',
    '/audio/$relative',
    '/audio/audio_cache/$name',
    '/audio/cache/audio/$name',
    '/api/files/download?path=$encoded',
    '/api/files/stream?path=$encoded',
    '/api/fs/read-data-url?path=$encoded',
    '/api/fs/download?path=$encoded',
    '/api/files/read?path=$encoded',
  ];
}

String audioFetchFailure(int? status) {
  if (status == 401 || status == 403) {
    return 'Caddy is serving /audio/ but rejected the Authorization header. '
        'In the site block, use `@frank header Authorization "Bearer*"` '
        '(quoted). Then run caddy reload.';
  }
  if (status == 404) {
    return 'Caddy reached /audio/ but the voice file is not at that root. '
        'Point root at the host directory Docker mounts as /opt/data '
        '(often /opt/data or ~/.hermes, not /opt/data/.hermes), then reload.';
  }
  return 'Hermes saved this voice note on the server. Hermsy could not '
      'download it from /audio/. Check the Caddy /audio/ block and that '
      'the file exists on disk.';
}

String? firstRemoteAudio(String text) {
  final refs = extractAudioRefs(text);
  if (refs.isEmpty) {
    return null;
  }
  final first = refs.first;
  return first.httpUrl ?? first.dataUrl ?? first.filePath ?? first.raw;
}

bool looksLikeAudioPath(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  if (_dataUrl.hasMatch(trimmed) || _httpAudio.hasMatch(trimmed)) {
    return true;
  }
  return extractAudioRefs(trimmed).isNotEmpty || _audioExt.hasMatch(trimmed);
}

bool isMostlyAudioDelivery(String text) {
  return stripAudioMarkup(text).trim().length < 8;
}

bool wantsVoiceReply(String prompt) {
  final text = prompt.toLowerCase();
  return RegExp(
    r'\b(voice(?:\s+note|\s+reply|\s+response|\s+message)?|speak(?:\s+it|\s+that|\s+this)?|read(?:\s+it|\s+this|\s+that)?\s+aloud|say(?:\s+it|\s+that|\s+this)|audio(?:\s+file|\s+reply)?)\b',
  ).hasMatch(text);
}

String? spokenTextFromToolArgs(dynamic raw) {
  if (raw == null) {
    return null;
  }
  if (raw is Map) {
    final text = raw['text'] ??
        raw['input'] ??
        raw['content'] ??
        raw['speech'] ??
        raw['message'];
    if (text is String && text.trim().isNotEmpty && !looksLikeAudioPath(text)) {
      return text.trim();
    }
    return null;
  }
  final value = raw.toString().trim();
  if (value.isEmpty || looksLikeAudioPath(value)) {
    return null;
  }
  if (value.startsWith('{')) {
    try {
      final decoded = jsonDecode(value);
      return spokenTextFromToolArgs(decoded);
    } catch (_) {}
  }
  return value;
}

bool isSpeechTool(String? name) {
  if (name == null) {
    return false;
  }
  final lower = name.toLowerCase();
  return lower.contains('speech') ||
      lower == 'tts' ||
      lower.contains('speak') ||
      lower.contains('voice');
}
