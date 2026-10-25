import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class ImageRef {
  const ImageRef({
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

const _imageExt = 'png|jpe?g|gif|webp|bmp|heic|svg';

final _mediaTag = RegExp(
  r'''[`"']?MEDIA:\s*[`"']?(\S+?\.(?:''' +
      _imageExt +
      r'''))[`"']?''',
  caseSensitive: false,
);

final _dataUrl = RegExp(
  r'data:image\/[a-z0-9.+-]+;base64,[A-Za-z0-9+/=\s]+',
  caseSensitive: false,
);

final _httpImage = RegExp(
  r'https?://\S+\.(?:' + _imageExt + r')',
  caseSensitive: false,
);

final _markdownImage = RegExp(
  r'!\[[^\]]*\]\(([^)]+)\)',
);

final _filePath = RegExp(
  r'''(?:^|[\s`"'(:=])((?:file://|(?:[A-Za-z]:)?[~\\/]|\.{0,2}[\\/])?[^\s`"')]+?\.(?:''' +
      _imageExt +
      r'''))''',
  caseSensitive: false,
);

final _anyImageToken = RegExp(
  r'''[^\s`"'()\[\]<>]+\.(?:''' + _imageExt + r')',
  caseSensitive: false,
);

String imageStem(String path) {
  final name = imageFileName(path);
  final dot = name.lastIndexOf('.');
  if (dot <= 0) {
    return name.toLowerCase();
  }
  return name.substring(0, dot).toLowerCase();
}

int _imageFormatRank(String path) {
  switch (imageExtension(path)) {
    case 'png':
      return 0;
    case 'jpg':
      return 1;
    case 'webp':
      return 2;
    case 'gif':
      return 3;
    case 'bmp':
      return 4;
    case 'heic':
      return 5;
    case 'svg':
      return 6;
    default:
      return 7;
  }
}

String? imageRefKey(ImageRef ref) {
  return ref.dataUrl ?? ref.httpUrl ?? ref.filePath;
}

/// One picture per artwork. PNG+SVG of the same banner, or the same path
/// matched with and without a trailing period, collapse to a single ref.
List<ImageRef> collapseImageRefs(Iterable<ImageRef> refs) {
  final byStem = <String, ImageRef>{};
  final extras = <ImageRef>[];
  final extraKeys = <String>{};
  for (final ref in refs) {
    final key = imageRefKey(ref);
    if (key == null || key.isEmpty) {
      continue;
    }
    if (ref.dataUrl != null) {
      if (extraKeys.add(key)) {
        extras.add(ref);
      }
      continue;
    }
    final stem = imageStem(key);
    if (stem.isEmpty) {
      continue;
    }
    final existing = byStem[stem];
    if (existing == null) {
      byStem[stem] = ref;
      continue;
    }
    if (existing.httpUrl != null && ref.httpUrl == null) {
      continue;
    }
    if (ref.httpUrl != null && existing.httpUrl == null) {
      byStem[stem] = ref;
      continue;
    }
    final existingKey = imageRefKey(existing) ?? '';
    final betterFormat = _imageFormatRank(key) < _imageFormatRank(existingKey);
    final longerPath = key.length > existingKey.length &&
        _imageFormatRank(key) == _imageFormatRank(existingKey) &&
        !key.contains('(') &&
        !key.contains('[');
    if (betterFormat || longerPath) {
      byStem[stem] = ref;
    }
  }
  return [...extras, ...byStem.values];
}

/// Workspace paths are not pictures until Frank downloads them. Once a local
/// file exists, hide those leftover `/opt/data/…png` chips.
bool shouldShowRemoteImage(String remote, {required Iterable<String> localPaths}) {
  final locals = localPaths.where((path) => path.trim().isNotEmpty).toList();
  if (remote.startsWith('http') || remote.startsWith('data:')) {
    return !locals.any((path) => imageStem(path) == imageStem(remote));
  }
  return locals.isEmpty;
}

bool alreadyHasImage(Iterable<String> paths, ImageRef ref) {
  final key = imageRefKey(ref);
  if (key == null || key.isEmpty) {
    return false;
  }
  if (paths.contains(key)) {
    return true;
  }
  final stem = imageStem(key);
  return paths.any((path) => imageStem(path) == stem);
}

List<ImageRef> extractImageRefs(String raw) {
  // Code samples often mention files (`exports/*.png`); they are not images.
  final text = _proseOnly(raw);
  final found = <ImageRef>[];
  final seen = <String>{};

  void add(ImageRef ref) {
    final key = imageRefKey(ref) ?? _cleanPath(ref.raw);
    if (key.isNotEmpty && seen.add(key)) {
      found.add(ref);
    }
  }

  for (final match in _dataUrl.allMatches(text)) {
    add(
      ImageRef(
        raw: match.group(0)!,
        dataUrl: match.group(0)!.replaceAll(RegExp(r'\s'), ''),
      ),
    );
  }
  for (final match in _markdownImage.allMatches(text)) {
    add(_refFromToken(match.group(1)!.trim(), raw: match.group(0)!));
  }
  for (final match in _httpImage.allMatches(text)) {
    add(ImageRef(raw: match.group(0)!, httpUrl: match.group(0)));
  }
  for (final match in _mediaTag.allMatches(text)) {
    add(_refFromToken(match.group(1)!, raw: match.group(0)!));
  }
  for (final match in _filePath.allMatches(text)) {
    if (_looksLikePattern(match.group(1)!)) {
      continue;
    }
    add(
      ImageRef(
        raw: match.group(1)!,
        filePath: _cleanPath(match.group(1)!),
      ),
    );
  }
  for (final match in _anyImageToken.allMatches(text)) {
    if (_looksLikePattern(match.group(0)!)) {
      continue;
    }
    add(ImageRef(raw: match.group(0)!, filePath: _cleanPath(match.group(0)!)));
  }
  return collapseImageRefs(found);
}

ImageRef imageRefFromToken(String token) =>
    _refFromToken(token, raw: token);

ImageRef _refFromToken(String token, {required String raw}) {
  if (token.startsWith('http')) {
    return ImageRef(raw: raw, httpUrl: token);
  }
  if (token.startsWith('data:')) {
    return ImageRef(raw: raw, dataUrl: token);
  }
  return ImageRef(raw: raw, filePath: _cleanPath(token));
}

String _cleanPath(String path) {
  var value = path.trim();
  if (value.startsWith('file://')) {
    value = value.substring(7);
  }
  value = value.replaceAll('\\', '/');
  return value.replaceFirst(RegExp(r'[.,;:)\]\s]+$'), '');
}

String stripImageMarkup(String text) {
  final runs = _proseAndCode(text);
  final out = StringBuffer();
  for (final run in runs) {
    out.write(run.code ? run.text : _stripProse(run.text));
  }
  return out.toString().trim();
}

String _stripProse(String text) {
  var cleaned = text.replaceAll(_markdownImage, '');
  cleaned = cleaned.replaceAll(_mediaTag, '');
  cleaned = cleaned.replaceAll(_dataUrl, '');
  cleaned = cleaned.replaceAll(_httpImage, '');
  cleaned = cleaned.replaceAllMapped(_filePath, (match) {
    final whole = match.group(0)!;
    final path = match.group(1)!;
    if (_looksLikePattern(path)) {
      return whole;
    }
    return whole.replaceFirst(path, '');
  });
  cleaned = cleaned.replaceAllMapped(_anyImageToken, (match) {
    final token = match.group(0)!;
    return _looksLikePattern(token) ? token : '';
  });
  return cleaned
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');
}

/// Glob or shell syntax (`*.png`, `${name}.png`) names a pattern, not a file.
bool _looksLikePattern(String token) => RegExp(r'[*$?{}<>|]').hasMatch(token);

/// [text] with fenced code blocks removed, for detecting images in prose.
String _proseOnly(String text) {
  return _proseAndCode(text)
      .where((run) => !run.code)
      .map((run) => run.text)
      .join('\n');
}

/// Splits [text] into prose and fenced-code runs (``` or ~~~), keeping every
/// character so the runs join back into the original.
List<({String text, bool code})> _proseAndCode(String text) {
  final runs = <({String text, bool code})>[];
  final buffer = StringBuffer();
  String? fence;

  void flush({required bool code}) {
    if (buffer.isEmpty) {
      return;
    }
    runs.add((text: buffer.toString(), code: code));
    buffer.clear();
  }

  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final newline = i < lines.length - 1 ? '\n' : '';
    final trimmed = line.trimLeft();
    if (fence == null) {
      final opener = trimmed.startsWith('```')
          ? '```'
          : trimmed.startsWith('~~~')
              ? '~~~'
              : null;
      if (opener != null) {
        flush(code: false);
        fence = opener;
      }
      buffer.write('$line$newline');
      continue;
    }
    buffer.write('$line$newline');
    if (trimmed.startsWith(fence)) {
      fence = null;
      flush(code: true);
    }
  }
  flush(code: fence != null);
  return runs;
}

List<ImageRef> imageRefsOf(String text, {List<String> remote = const []}) {
  final found = [...extractImageRefs(text)];
  for (final extra in remote) {
    final trimmed = extra.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final fromRemote = extractImageRefs(trimmed);
    if (fromRemote.isNotEmpty) {
      found.addAll(fromRemote);
      continue;
    }
    found.add(_refFromToken(trimmed, raw: trimmed));
  }
  return collapseImageRefs(found);
}

String imageFileName(String path) => _cleanPath(path).split('/').last;

String imageExtension(String path, {String fallback = 'jpg'}) {
  final name = imageFileName(path);
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) {
    return fallback;
  }
  final ext = name.substring(dot + 1).toLowerCase();
  if (ext == 'jpeg') {
    return 'jpg';
  }
  return ext;
}

String mimeForImageExt(String ext) {
  switch (ext.toLowerCase()) {
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'bmp':
      return 'image/bmp';
    case 'heic':
      return 'image/heic';
    case 'svg':
      return 'image/svg+xml';
    default:
      return 'image/jpeg';
  }
}

/// Paths Hermes writes under the Docker mount, e.g. `/opt/data/banners/x.svg`.
List<String> workspaceRelatives(String path) {
  final cleaned = _cleanPath(path);
  final name = imageFileName(cleaned);
  final found = <String>{name};
  const roots = [
    '/opt/data/',
    '/opt/data/.hermes/',
    '/root/.hermes/',
  ];
  for (final root in roots) {
    if (cleaned.startsWith(root) && cleaned.length > root.length) {
      found.add(cleaned.substring(root.length));
    }
  }
  return found.toList();
}

/// HTTPS paths Frank tries, relative to the Hermes base URL.
List<String> fileFetchPaths(String diskPath) {
  final relatives = workspaceRelatives(diskPath);
  return [
    for (final rel in relatives) '/files/$rel',
    for (final rel in relatives) '/audio/$rel',
  ];
}

String? dataUrlFromFile(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    return null;
  }
  final ext = imageExtension(path);
  return 'data:${mimeForImageExt(ext)};base64,${base64Encode(file.readAsBytesSync())}';
}

({List<int> bytes, String extension})? imageBytesFromDataUrl(String url) {
  final comma = url.indexOf(',');
  if (comma < 0) {
    return null;
  }
  try {
    final meta = url.substring(0, comma);
    final bytes = base64Decode(url.substring(comma + 1).replaceAll(RegExp(r'\s'), ''));
    var ext = 'jpg';
    final match = RegExp(r'data:image/([a-z0-9.+-]+)', caseSensitive: false)
        .firstMatch(meta);
    if (match != null) {
      ext = match.group(1)!.split('+').first.toLowerCase();
      if (ext == 'jpeg') {
        ext = 'jpg';
      }
    }
    return (bytes: bytes, extension: ext);
  } catch (_) {
    return null;
  }
}

dynamic completionContent({
  required String text,
  List<String> imagePaths = const [],
  List<String> remoteImages = const [],
}) {
  final parts = <Map<String, dynamic>>[];
  final caption = text.trim();
  if (caption.isNotEmpty) {
    parts.add({'type': 'text', 'text': caption});
  }
  for (final path in imagePaths) {
    final url = path.startsWith('data:')
        ? path
        : path.startsWith('http')
            ? path
            : dataUrlFromFile(path);
    if (url != null && url.isNotEmpty) {
      parts.add({
        'type': 'image_url',
        'image_url': {'url': url},
      });
    }
  }
  for (final remote in remoteImages) {
    if (remote.startsWith('http') || remote.startsWith('data:')) {
      parts.add({
        'type': 'image_url',
        'image_url': {'url': remote},
      });
    }
  }
  if (parts.isEmpty) {
    return caption;
  }
  if (parts.length == 1 && parts.first['type'] == 'text') {
    return caption;
  }
  return parts;
}

Future<String> persistLocalImage(String sourcePath) async {
  if (sourcePath.contains('/frank_images/')) {
    return sourcePath;
  }
  final source = File(sourcePath);
  if (!await source.exists()) {
    return sourcePath;
  }
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}/frank_images');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final ext = imageExtension(sourcePath);
  final dest = '${dir.path}/${DateTime.now().microsecondsSinceEpoch}.$ext';
  if (source.path == dest) {
    return dest;
  }
  await source.copy(dest);
  return dest;
}

Future<String> writeImageBytes(
  List<int> bytes, {
  required String extension,
}) async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}/frank_images');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final ext = extension.toLowerCase() == 'jpeg' ? 'jpg' : extension.toLowerCase();
  final path =
      '${dir.path}/${DateTime.now().microsecondsSinceEpoch}.$ext';
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}
