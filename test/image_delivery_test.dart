import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/models/chat_message.dart';
import 'package:hermes_app/services/image_delivery.dart';
import 'package:hermes_app/services/message_actions.dart';

void main() {
  test('extracts MEDIA image tags and strips them from captions', () {
    const raw =
        'Here it is\nMEDIA:/opt/data/.hermes/workspace/photo.png';
    final refs = extractImageRefs(raw);
    expect(refs, isNotEmpty);
    expect(refs.first.filePath, endsWith('photo.png'));
    expect(stripImageMarkup(raw), 'Here it is');
  });

  test('extracts markdown and https images', () {
    const raw =
        'See ![cat](https://example.com/cat.jpg) and https://cdn.example/dog.webp';
    final refs = extractImageRefs(raw);
    expect(refs.map((ref) => ref.httpUrl), contains('https://example.com/cat.jpg'));
    expect(refs.map((ref) => ref.httpUrl), contains('https://cdn.example/dog.webp'));
    expect(stripImageMarkup(raw), 'See  and');
  });

  test('encodes a local file as a vision content part', () async {
    final dir = await Directory.systemTemp.createTemp('frank_img');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/shot.png');
    await file.writeAsBytes(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
    ));

    final content = completionContent(
      text: 'What is this?',
      imagePaths: [file.path],
    );
    expect(content, isA<List>());
    final parts = content as List;
    expect(parts.first, {'type': 'text', 'text': 'What is this?'});
    expect(parts.last['type'], 'image_url');
    expect(
      (parts.last['image_url'] as Map)['url'],
      startsWith('data:image/png;base64,'),
    );
  });

  test('reads image urls from multimodal content', () {
    expect(
      ChatMessage.imagesFromContent([
        {'type': 'text', 'text': 'Look'},
        {
          'type': 'image_url',
          'image_url': {'url': 'https://example.com/a.png'},
        },
      ]),
      ['https://example.com/a.png'],
    );
  });

  test('keeps one picture when Hermes lists PNG and SVG of the same banner', () {
    const raw = '''
The banner has been rendered and saved to:
- PNG format: /opt/data/banners/the_day_is_here_banner.png
- Vector SVG format: /opt/data/banners/the_day_is_here_banner.svg.
Also the_day_is_here_banner.svg
''';
    final refs = extractImageRefs(raw);
    expect(refs, hasLength(1));
    expect(refs.single.filePath, '/opt/data/banners/the_day_is_here_banner.png');
    expect(
      alreadyHasImage(
        const ['/tmp/frank_images/the_day_is_here_banner.png'],
        refs.single,
      ),
      isTrue,
    );
  });

  test('extracts a workspace SVG path from a generate-image reply', () {
    const raw = '''
The banner has been rendered and saved to:
- PNG format.
- Vector SVG format: /opt/data/banners/the_day_is_here_banner.svg.
''';
    final refs = extractImageRefs(raw);
    expect(refs.single.filePath, '/opt/data/banners/the_day_is_here_banner.svg');
    expect(
      workspaceRelatives(refs.single.filePath!),
      containsAll(['the_day_is_here_banner.svg', 'banners/the_day_is_here_banner.svg']),
    );
    expect(
      fileFetchPaths(refs.single.filePath!),
      containsAll([
        '/files/banners/the_day_is_here_banner.svg',
        '/audio/banners/the_day_is_here_banner.svg',
      ]),
    );
    expect(stripImageMarkup(raw), isNot(contains('/opt/data')));
  });

  test('hides leftover workspace paths after a local download', () {
    expect(
      shouldShowRemoteImage(
        '/opt/data/banners/the_day_is_here_banner.png',
        localPaths: const ['/tmp/frank_images/1756.png'],
      ),
      isFalse,
    );
    expect(
      shouldShowRemoteImage(
        '/opt/data/banners/the_day_is_here_banner.png',
        localPaths: const [],
      ),
      isTrue,
    );
  });

  test('retries a photo-only user message', () {
    final user = ChatMessage(
      id: 'u1',
      role: MessageRole.user,
      text: '',
      imagePaths: ['/tmp/a.jpg'],
    );
    final assistant = ChatMessage(
      id: 'a1',
      role: MessageRole.assistant,
      text: 'A cat.',
    );
    final target = retryTarget([user, assistant], assistant);
    expect(target?.prompt, 'Photo');
    expect(target?.imagePaths, ['/tmp/a.jpg']);
  });

  test('code samples keep their file names and are not images', () {
    const reply = 'Rename them:\n\n```bash\nfor f in exports/*.png; do\n'
        '  mv "\$f" "\${f%.png}_a57.png"\ndone\n```\n\nSaved /opt/data/banners/day.svg too.';
    final refs = extractImageRefs(reply);
    expect(refs.map((ref) => ref.filePath), ['/opt/data/banners/day.svg']);

    final shown = stripImageMarkup(reply);
    expect(shown, contains('for f in exports/*.png; do'));
    expect(shown, contains('"\${f%.png}_a57.png"'));
    expect(shown, isNot(contains('/opt/data/banners/day.svg')));
  });

  test('glob and shell patterns outside code are not images', () {
    const reply = 'Matches exports/*.png and \${name}.png, but shows /tmp/real.png';
    final refs = extractImageRefs(reply);
    expect(refs.map((ref) => ref.filePath), ['/tmp/real.png']);
    expect(stripImageMarkup(reply), contains('exports/*.png'));
  });

  test('an unclosed fence still protects the code while streaming', () {
    const reply = 'Here:\n```\ncp a.png b.png';
    expect(extractImageRefs(reply), isEmpty);
    expect(stripImageMarkup(reply), contains('cp a.png b.png'));
  });
}
