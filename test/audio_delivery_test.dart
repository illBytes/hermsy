import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/services/audio_delivery.dart';

void main() {
  test('extracts MEDIA tags and bare server paths', () {
    const raw =
        '[[audio_as_voice]]\nMEDIA:/opt/data/.hermes/audio_cache/tts_1.ogg';
    final refs = extractAudioRefs(raw);
    expect(refs, isNotEmpty);
    expect(refs.first.filePath, '/opt/data/.hermes/audio_cache/tts_1.ogg');
    expect(stripAudioMarkup(raw), isEmpty);
    expect(isMostlyAudioDelivery(raw), isTrue);
  });

  test('keeps a caption and drops only the path', () {
    const raw = 'Here you go\n/home/alex/.hermes/audio_cache/note.mp3';
    expect(stripAudioMarkup(raw), 'Here you go');
    expect(extractAudioRefs(raw).single.filePath, endsWith('note.mp3'));
  });

  test('detects a voice request', () {
    expect(wantsVoiceReply('Give me a voice response'), isTrue);
    expect(wantsVoiceReply('read that aloud'), isTrue);
    expect(wantsVoiceReply('What is the weather?'), isFalse);
  });

  test('picks up a filename-only audio token', () {
    expect(extractAudioRefs('tts_note.mp3').single.filePath, 'tts_note.mp3');
    expect(looksLikeAudioPath('tts_note.mp3'), isTrue);
  });

  test('picks up a relative audio_cache filename', () {
    const raw = 'Saved audio_cache/tts_note.mp3';
    expect(extractAudioRefs(raw), isNotEmpty);
    expect(extractAudioRefs(raw).first.filePath, contains('tts_note.mp3'));
    expect(stripAudioMarkup(raw), 'Saved');
  });

  test('keeps a remote path after the visible caption is stripped', () {
    const raw = 'Here you go\n/opt/data/.hermes/audio_cache/note.ogg';
    expect(firstRemoteAudio(raw), endsWith('note.ogg'));
    expect(
      audioRefsOf('Here you go', remote: '/opt/data/.hermes/audio_cache/note.ogg'),
      isNotEmpty,
    );
  });

  test('reads spoken text from TTS tool arguments', () {
    expect(
      spokenTextFromToolArgs('{"input":"Good evening"}'),
      'Good evening',
    );
    expect(spokenTextFromToolArgs('/tmp/note.ogg'), isNull);
  });

  test('builds download paths from a Docker audio_cache file', () {
    const path = '/opt/data/.hermes/audio_cache/tts_1.ogg';
    expect(audioFileName(path), 'tts_1.ogg');
    expect(audioCacheRelative(path), 'tts_1.ogg');
    expect(audioDownloadPaths(path), contains('/audio/tts_1.ogg'));
    expect(audioDownloadPaths(path), contains(contains('/api/files/download?path=')));
  });

  test('reads a dashboard data-url JSON payload', () {
    final raw = base64Encode(List<int>.filled(80, 1));
    final got = audioBytesFromJson(
      '{"dataUrl":"data:audio/wav;base64,$raw"}',
      fallbackExt: 'ogg',
    );
    expect(got, isNotNull);
    expect(got!.extension, 'wav');
    expect(got.bytes, hasLength(80));
  });

  test('explains a Caddy 401 on /audio/', () {
    expect(audioFetchFailure(401), contains('Bearer*'));
    expect(audioFetchFailure(404), contains('root'));
    expect(audioFetchFailure(null), contains('/audio/'));
  });

  test('recognizes the Hermes speech tool', () {
    expect(isSpeechTool('text_to_speech'), isTrue);
    expect(isSpeechTool('web_search'), isFalse);
  });
}
