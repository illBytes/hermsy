import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/config/app_config.dart';
import 'package:hermes_app/screens/voice_picker_screen.dart';
import 'package:hermes_app/services/app_settings.dart';
import 'package:hermes_app/services/relay_client.dart';
import 'package:hermes_app/theme/app_theme.dart';
import 'package:hermes_app/voice/on_device_voice.dart';
import 'package:hermes_app/voice/mic_capture.dart';
import 'package:hermes_app/voice/speech_player.dart';
import 'package:hermes_app/voice/speech_source.dart';
import 'package:hermes_app/voice/spoken_text.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<String> speakAll(List<String> deltas) {
  final buffer = SentenceBuffer();
  return [for (final delta in deltas) ...buffer.add(delta), ...buffer.flush()];
}

void main() {
  group('SentenceBuffer', () {
    test('releases each sentence as soon as it ends', () {
      final buffer = SentenceBuffer();
      expect(buffer.add('Sure. The quo'), ['Sure.']);
      expect(buffer.add('tes are due today'), isEmpty);
      expect(buffer.add('! Anything else? '), [
        'The quotes are due today!',
        'Anything else?',
      ]);
      expect(buffer.flush(), isEmpty);
    });

    test('a stop still arriving is not split: 3.5 and e.g.', () {
      expect(speakAll(['It is 3.', '5% above target. ', 'Use e.g. cash.']), [
        'It is 3.5% above target.',
        'Use e.g. cash.',
      ]);
      expect(speakAll(['Call Mr. Okafor today.']), ['Call Mr. Okafor today.']);
    });

    test('the first chunk is short; run-ons are cut after twenty words', () {
      final words = List.generate(40, (i) => 'w$i').join(' ');
      final out = speakAll([words]);
      expect(out.map((chunk) => chunk.split(' ').length), [10, 20, 10]);
    });

    test('a reply can start speaking at its first comma', () {
      expect(
        speakAll(['Sure, the quotes are due today, and the scan is tomorrow.']),
        ['Sure, the quotes are due today,', 'and the scan is tomorrow.'],
      );
      expect(speakAll(['Yes, done.']), ['Yes, done.'], reason: 'too short');
    });

    test('code is shown, not read', () {
      final out = speakAll([
        'Here it is:\n```dart\nprint("hi");\n```\nRun that. ',
        'Then ```more()``` again.',
      ]);
      expect(out, [
        'Here it is:',
        "I've put the code on your screen.",
        'Run that.',
        'Then',
        'again.',
      ]);
    });

    test('list items and paragraphs end chunks', () {
      expect(speakAll(['Two things\n- book the scan\n- call the bank']), [
        'Two things',
        'book the scan',
        'call the bank',
      ]);
    });
  });

  group('speakable', () {
    test('drops Markdown, links, URLs and emoji', () {
      expect(
        speakable(
          '**Done** ✅ see [the quote](https://x.test) or https://y.test now',
        ),
        'Done see the quote or now',
      );
      expect(speakable('## Heading'), 'Heading');
      expect(speakable('`code` stays as words'), 'code stays as words');
      expect(speakable('snake_case_name stays'), 'snake_case_name stays');
    });

    test('punctuation alone says nothing', () {
      expect(speakable(' --- '), '');
      expect(speakable('🎉'), '');
    });
  });

  group('mic samples', () {
    test('16-bit PCM becomes floats, carrying an odd byte', () {
      final first = pcm16ToFloat(Uint8List.fromList([0x00, 0x40, 0xff]));
      expect(first.samples, [0.5]);
      expect(first.carry, 0xff);
      final second = pcm16ToFloat(
        Uint8List.fromList([0x7f]),
        carry: first.carry,
      );
      expect(second.samples.single, closeTo(32767 / 32768, 1e-6));
      expect(second.carry, isNull);
    });

    test('loudness: silence is 0, a loud tone near 1', () {
      expect(levelOf(Float32List(160)), 0);
      final loud = Float32List.fromList(List.filled(160, 0.5));
      expect(levelOf(loud), greaterThan(0.9));
      final quiet = Float32List.fromList(List.filled(160, 0.003));
      expect(levelOf(quiet), lessThan(0.1));
    });
  });

  test('speech becomes a valid 16-bit mono WAV', () {
    final bytes = wavBytes(Float32List.fromList([0, 1, -1, 2]), 24000);
    final view = ByteData.sublistView(bytes);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(view.getUint32(24, Endian.little), 24000);
    expect(view.getUint32(40, Endian.little), 8);
    expect(bytes.length, 44 + 8);
    expect(view.getInt16(46, Endian.little), 32767);
    expect(view.getInt16(48, Endian.little), -32767);
    expect(view.getInt16(50, Endian.little), 32767, reason: 'clamped');
  });

  test('silence at the edges of a clip is trimmed, keeping a little', () {
    const rate = 1000;
    final samples = Float32List(1000);
    for (var i = 300; i < 600; i++) {
      samples[i] = 0.5;
    }
    final trimmed = trimSilence(samples, rate, leadMs: 20, tailMs: 60);
    expect(trimmed.length, 20 + 300 + 60);
    expect(trimSilence(Float32List(50), rate).length, 50, reason: 'all quiet');
  });

  test('every filler kind has several lines to rotate through', () {
    for (final kind in FillerKind.values) {
      expect(callFillers[kind]!.length, greaterThanOrEqualTo(4));
      expect(callFillers[kind]!.toSet().length, callFillers[kind]!.length);
    }
  });

  testWidgets('the voice picker saves the voice and speed', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(
      preferences: await SharedPreferences.getInstance(),
    );
    await settings.load();
    expect(settings.callVoice, defaultKokoroVoice);
    expect(settings.callEngine, 'openai', reason: 'cloud by default');
    expect(settings.callFallback, isTrue);
    expect(callVoiceSummary(settings), 'OpenAI · Marin · normal speed');
    await settings.setCallEngine('kokoro');

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: VoicePickerScreen(settings: settings),
      ),
    );
    await tester.pump();
    expect(find.text('Add OPENAI_API_KEY to Hermes to use it'), findsOneWidget);
    await tester.tap(find.text('1.1×'));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Emma'), 200);
    await tester.ensureVisible(find.text('Emma'));
    await tester.pump();
    await tester.tap(find.text('Emma'));
    await tester.pump();

    expect(settings.callEngine, 'kokoro');
    expect(settings.callVoice, 21);
    expect(settings.callSpeed, 1.1);
    expect(callVoiceSummary(settings), 'Emma · 1.1× speed');
  });

  testWidgets('a cloud voice is picked once Hermes offers it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(
      preferences: await SharedPreferences.getInstance(),
    );
    await settings.load();
    final relay = RelayClient(
      const AppConfig(baseUrl: 'https://relay.test', apiKey: 'key-1234'),
      httpClient: MockClient((request) async {
        if (jsonDecode(request.body)['op'] == 'voices') {
          return http.Response(
            jsonEncode({
              'providers': {
                'openai': {
                  'name': 'OpenAI',
                  'voices': [
                    {'id': 'marin', 'name': 'Marin', 'description': 'Natural'},
                    {'id': 'coral', 'name': 'Coral', 'description': 'Bright'},
                  ],
                },
              },
            }),
            200,
          );
        }
        return _pcm(List.filled(480, 0));
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: VoicePickerScreen(settings: settings, relay: relay),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(
      find.text('Add ELEVENLABS_API_KEY to Hermes to use it'),
      findsOneWidget,
    );

    await settings.setCallEngine('kokoro');
    await tester.pump();
    expect(find.text("Fall back to the phone's voice"), findsNothing);
    await tester.tap(find.text('OpenAI'));
    await tester.pump();
    expect(settings.callEngine, 'openai');
    expect(callVoiceSummary(settings), 'OpenAI · Marin · normal speed');
    await tester.tap(find.text("Fall back to the phone's voice"));
    await tester.pump();
    expect(settings.callFallback, isFalse);

    await tester.scrollUntilVisible(find.text('Coral'), 200);
    await tester.ensureVisible(find.text('Coral'));
    await tester.pump();
    await tester.tap(find.text('Coral'));
    await tester.pump();
    expect(settings.cloudVoice('openai'), 'coral');
    expect(callVoiceSummary(settings), 'OpenAI · Coral · normal speed');
  });

  group('cloud speech', () {
    RelayClient relayAnswering(
      Future<http.Response> Function(http.Request) handler,
    ) => RelayClient(
      const AppConfig(baseUrl: 'https://relay.test', apiKey: 'key-1234'),
      httpClient: MockClient(handler),
    );

    test('the plugin returns PCM that becomes samples', () async {
      late http.Request sent;
      final relay = relayAnswering((request) async {
        sent = request;
        return _pcm([0x00, 0x40, 0x00, 0xc0]);
      });
      final audio = await relay.speech(
        provider: 'openai',
        voice: 'marin',
        text: 'Hello.',
      );
      expect(audio.sampleRate, 24000);
      expect(audio.samples, [0.5, -0.5]);
      expect(jsonDecode(sent.body)['op'], 'speak');
      expect(jsonDecode(sent.body)['voice'], 'marin');
    });

    test('after one failure the call stays on the phone voice', () async {
      var cloudCalls = 0;
      final relay = relayAnswering((request) async {
        cloudCalls++;
        return http.Response(
          jsonEncode({'error': 'OpenAI rejected the API key', 'status': 502}),
          200,
        );
      });
      final reasons = <String>[];
      final phone = _FakeSource();
      final source = CloudSpeech(
        relay: relay,
        provider: 'openai',
        voice: 'marin',
        fallback: () async => phone,
        onFallback: reasons.add,
      );
      await source.speak('One.');
      await source.speak('Two.');
      expect(cloudCalls, 1);
      expect(phone.said, ['One.', 'Two.']);
      expect(reasons.single, contains('rejected the API key'));
      expect(source.usingFallback, isTrue);
    });
  });
}

class _FakeSource implements SpeechSource {
  final said = <String>[];

  @override
  Future<Speech> speak(String text) async {
    said.add(text);
    return (samples: Float32List(10), sampleRate: 24000);
  }
}

/// The plugin's answer to `speak`: 16-bit PCM, base64-encoded.
http.Response _pcm(List<int> bytes) => http.Response(
  jsonEncode({'audio': base64Encode(bytes), 'sample_rate': 24000}),
  200,
);
