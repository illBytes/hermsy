import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/screens/voice_models_screen.dart';
import 'package:hermes_app/services/app_settings.dart';
import 'package:hermes_app/services/voice_models.dart';
import 'package:hermes_app/theme/app_theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final vadBytes = utf8.encode('silero ' * 50);
final sttBytes = utf8.encode('parakeet encoder ' * 400);

/// A real .tar.bz2 holding a folder, like the Kokoro release asset.
final ttsArchive = BZip2Encoder().encodeBytes(
  TarEncoder().encodeBytes(
    Archive()
      ..add(ArchiveFile.bytes('kokoro/model.int8.onnx', utf8.encode('kokoro')))
      ..add(ArchiveFile.bytes('kokoro/espeak-ng-data/en_dict', [1, 2, 3])),
  ),
);

String sumOf(List<int> bytes) => sha256.convert(bytes).toString();

ModelFile fileFor(
  String name,
  List<int> bytes,
  String path, {
  bool archive = false,
}) => ModelFile(
  url: 'https://models.test/$name',
  path: path,
  size: bytes.length,
  sha256: sumOf(bytes),
  archive: archive,
);

final testModels = [
  VoiceModel(
    id: 'vad',
    name: 'VAD',
    role: 'Hears you',
    folder: 'vad',
    diskBytes: vadBytes.length,
    files: [fileFor('vad.onnx', vadBytes, 'vad/vad.onnx')],
  ),
  VoiceModel(
    id: 'stt',
    name: 'STT',
    role: 'Transcribes',
    folder: 'stt',
    diskBytes: sttBytes.length,
    files: [fileFor('encoder.onnx', sttBytes, 'stt/encoder.onnx')],
  ),
  VoiceModel(
    id: 'tts',
    name: 'TTS',
    role: 'Speaks',
    folder: 'kokoro',
    diskBytes: 9,
    unpacked: const ['model.int8.onnx', 'espeak-ng-data'],
    files: [
      fileFor('kokoro.tar.bz2', ttsArchive, 'kokoro.tar.bz2', archive: true),
    ],
  ),
];

/// Full-precision Kokoro, as an optional extra.
final fullArchive = BZip2Encoder().encodeBytes(
  TarEncoder().encodeBytes(
    Archive()..add(ArchiveFile.bytes('kokoro-full/model.onnx', [4, 5, 6])),
  ),
);

final testFull = VoiceModel(
  id: 'tts_full',
  name: 'TTS full',
  role: 'Speaks, cleaner',
  folder: 'kokoro-full',
  diskBytes: 3,
  files: [fileFor('full.tar.bz2', fullArchive, 'full.tar.bz2', archive: true)],
);

/// Serves the test models, honouring Range unless [ignoreRange].
class FakeModelServer {
  FakeModelServer({this.ignoreRange = false, Map<String, List<int>>? override})
    : files = {
        'vad.onnx': vadBytes,
        'encoder.onnx': sttBytes,
        'kokoro.tar.bz2': ttsArchive,
        'full.tar.bz2': fullArchive,
        ...?override,
      };

  final bool ignoreRange;
  final Map<String, List<int>> files;
  final ranges = <String?>[];

  http.Client client() => MockClient.streaming((request, body) async {
    final name = request.url.pathSegments.last;
    final bytes = files[name];
    if (bytes == null) {
      return http.StreamedResponse(const Stream.empty(), 404);
    }
    final range = request.headers['Range'];
    ranges.add(range);
    if (range != null && !ignoreRange) {
      final start = int.parse(range.substring(6, range.length - 1));
      return http.StreamedResponse(
        Stream.value(bytes.sublist(start)),
        206,
        contentLength: bytes.length - start,
      );
    }
    return http.StreamedResponse(
      Stream.value(bytes),
      200,
      contentLength: bytes.length,
    );
  });
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('voice_models');
  });

  tearDown(() async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  VoiceModelStore storeWith(FakeModelServer server, {bool onWifi = true}) =>
      VoiceModelStore(
        root: dir,
        httpClient: server.client,
        onUnmeteredNetwork: () async => onWifi,
        models: testModels,
        extras: [testFull],
      );

  test('downloads, checks and unpacks every model', () async {
    final store = storeWith(FakeModelServer());
    await store.load();
    expect(store.allReady, isFalse);

    await store.downloadAll(wifiOnly: true);

    expect(store.allReady, isTrue);
    expect(await File('${dir.path}/vad/vad.onnx').readAsBytes(), vadBytes);
    expect(
      await File('${dir.path}/kokoro/model.int8.onnx').readAsString(),
      'kokoro',
    );
    expect(
      await File('${dir.path}/kokoro/espeak-ng-data/en_dict').exists(),
      isTrue,
    );
    // The archive and the intermediate tar are gone; markers are in place.
    expect(await File('${dir.path}/kokoro.tar.bz2').exists(), isFalse);
    expect(await File('${dir.path}/kokoro.tar.bz2.tar').exists(), isFalse);
    expect(await File('${dir.path}/stt/.ready').exists(), isTrue);
    expect(await store.folderOf(testModels[1]), '${dir.path}/stt');

    // A fresh store finds them ready without downloading anything.
    final again = storeWith(FakeModelServer());
    await again.load();
    expect(again.allReady, isTrue);
    expect(again.receivedBytes, again.totalBytes);
  });

  test('resumes a partial download with a Range request', () async {
    final half = sttBytes.length ~/ 2;
    await Directory('${dir.path}/stt').create(recursive: true);
    await File(
      '${dir.path}/stt/encoder.onnx.part',
    ).writeAsBytes(sttBytes.sublist(0, half));
    final server = FakeModelServer();
    final store = storeWith(server);
    await store.load();
    expect(store.progressOf(testModels[1]).received, half);

    await store.downloadAll(wifiOnly: false);

    expect(server.ranges, contains('bytes=$half-'));
    expect(store.allReady, isTrue);
    expect(await File('${dir.path}/stt/encoder.onnx').readAsBytes(), sttBytes);
  });

  test('starts over when the server ignores the range', () async {
    await Directory('${dir.path}/stt').create(recursive: true);
    await File(
      '${dir.path}/stt/encoder.onnx.part',
    ).writeAsBytes(sttBytes.sublist(0, 10));
    final store = storeWith(FakeModelServer(ignoreRange: true));
    await store.downloadAll(wifiOnly: false);
    expect(store.allReady, isTrue);
    expect(await File('${dir.path}/stt/encoder.onnx').readAsBytes(), sttBytes);
  });

  test('a file that fails its checksum is not kept', () async {
    final tampered = List<int>.from(sttBytes)..[0] ^= 0xff;
    final store = storeWith(
      FakeModelServer(override: {'encoder.onnx': tampered}),
    );
    await store.downloadAll(wifiOnly: false);

    final stt = store.progressOf(testModels[1]);
    expect(stt.state, ModelState.failed);
    expect(stt.error, contains('checksum'));
    expect(await File('${dir.path}/stt/encoder.onnx').exists(), isFalse);
    expect(store.progressOf(testModels[0]).state, ModelState.ready);
    expect(store.allReady, isFalse);
  });

  test('waits for Wi-Fi when told to', () async {
    final server = FakeModelServer();
    final store = storeWith(server, onWifi: false);
    await store.downloadAll(wifiOnly: true);
    expect(store.pausedReason, 'Waiting for Wi-Fi');
    expect(server.ranges, isEmpty);
    expect(store.allReady, isFalse);

    await store.downloadAll(wifiOnly: false);
    expect(store.allReady, isTrue);
  });

  test('delete removes everything', () async {
    final store = storeWith(FakeModelServer());
    await store.downloadAll(wifiOnly: false);
    await store.deleteAll();
    expect(store.allReady, isFalse);
    expect(store.receivedBytes, 0);
    expect(await dir.exists(), isFalse);
  });

  test(
    'full precision is an extra: its own download, its own delete',
    () async {
      final store = storeWith(FakeModelServer());
      await store.downloadAll(wifiOnly: false);
      expect(
        store.isReady(testFull),
        isFalse,
        reason: 'not part of voice mode',
      );
      expect(store.allReady, isTrue);

      await store.download(testFull, wifiOnly: false);
      expect(store.isReady(testFull), isTrue);
      expect(await File('${dir.path}/kokoro-full/model.onnx').readAsBytes(), [
        4,
        5,
        6,
      ]);
      final again = storeWith(FakeModelServer());
      await again.load();
      expect(again.isReady(testFull), isTrue);

      await store.delete(testFull);
      expect(store.isReady(testFull), isFalse);
      expect(await Directory('${dir.path}/kokoro-full').exists(), isFalse);
      expect(store.allReady, isTrue, reason: 'the rest stays');
    },
  );

  group('import from a folder', () {
    VoiceModelStore storeCopying(
      Future<void> Function(String target) copy,
      List<String> folders,
    ) => VoiceModelStore(
      root: dir,
      httpClient: FakeModelServer().client,
      models: testModels,
      extras: [testFull],
      copyFromFolder: (target, wanted, onProgress) async {
        await copy(target);
        onProgress(1);
        return folders;
      },
    );

    Future<void> write(String path, List<int> bytes) async {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
    }

    test('a whole copy is checked and ready, nothing downloaded', () async {
      final server = FakeModelServer();
      final store = VoiceModelStore(
        root: dir,
        httpClient: server.client,
        models: testModels,
        extras: [testFull],
        copyFromFolder: (target, wanted, onProgress) async {
          expect(wanted, ['vad', 'stt', 'kokoro', 'kokoro-full']);
          await write('$target/vad/vad.onnx', vadBytes);
          await write('$target/stt/encoder.onnx', sttBytes);
          await write('$target/kokoro/model.int8.onnx', [1]);
          await Directory('$target/kokoro/espeak-ng-data').create();
          onProgress(1);
          return ['vad', 'stt', 'kokoro'];
        },
      );
      await store.load();
      final added = await store.importFromFolder();
      expect(added, ['VAD', 'STT', 'TTS']);
      expect(store.allReady, isTrue);
      expect(server.ranges, isEmpty, reason: 'no download at all');

      final again = storeCopying((_) async {}, const []);
      await again.load();
      expect(again.allReady, isTrue, reason: 'kept as ready');
    });

    test('a damaged copy is turned away and removed', () async {
      final store = storeCopying((target) async {
        await write('$target/vad/vad.onnx', vadBytes);
        await write('$target/stt/encoder.onnx', utf8.encode('not parakeet'));
        await write('$target/kokoro/model.int8.onnx', [1]);
        // espeak-ng-data missing: an archive unpacked only in part.
      }, ['vad', 'stt', 'kokoro']);
      await store.load();
      final added = await store.importFromFolder();
      expect(added, ['VAD']);
      expect(store.progressOf(testModels[1]).state, ModelState.failed);
      expect(store.progressOf(testModels[2]).state, ModelState.failed);
      expect(await Directory('${dir.path}/stt').exists(), isFalse);
      expect(await Directory('${dir.path}/kokoro').exists(), isFalse);
    });

    test('a folder without models adds nothing', () async {
      final store = storeCopying((_) async {}, const []);
      await store.load();
      expect(await store.importFromFolder(), isEmpty);
      expect(store.allReady, isFalse);
      expect(store.downloading, isFalse);
    });
  });

  test('sizes read like people say them', () {
    expect(formatBytes(793947000), '794 MB');
    expect(formatBytes(1200000000), '1.2 GB');
    expect(formatBytes(643854), '644 KB');
  });

  test('the shipped catalog adds up', () {
    for (final model in voiceModels) {
      expect(model.files, isNotEmpty);
      for (final file in model.files) {
        expect(file.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(file.url, startsWith('https://'));
      }
    }
    final total = voiceModels.fold(0, (sum, m) => sum + m.downloadBytes);
    expect(formatBytes(total), '794 MB');
    expect(kokoroFull.files.single.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(formatBytes(kokoroFull.downloadBytes), '350 MB');
  });

  testWidgets('the screen offers a download and shows the sizes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(
      preferences: await SharedPreferences.getInstance(),
    );
    await settings.load();
    final store = storeWith(FakeModelServer());
    await tester.runAsync(store.load);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: VoiceModelsScreen(store: store, settings: settings),
      ),
    );

    expect(find.textContaining('Not downloaded'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Download on Wi-Fi only'), 200);
    expect(find.text('Download on Wi-Fi only'), findsOneWidget);
    expect(find.text('Delete voice models'), findsNothing);
    expect(settings.voiceModelsWifiOnly, isTrue);
  });

  testWidgets('optional models download from the screen, one by one', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(
      preferences: await SharedPreferences.getInstance(),
    );
    await settings.load();
    final store = storeWith(FakeModelServer(), onWifi: true);
    await tester.runAsync(store.load);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: VoiceModelsScreen(store: store, settings: settings),
      ),
    );
    await tester.scrollUntilVisible(find.text('TTS full'), 200);
    expect(find.text('OPTIONAL'), findsOneWidget);
    expect(find.textContaining('tap to download'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('TTS full'));
      for (var i = 0; i < 50 && !store.isReady(testFull); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(store.isReady(testFull), isTrue);
    expect(store.allReady, isFalse, reason: 'only the one asked for');
    expect(find.textContaining('tap to remove'), findsOneWidget);
  });
}
