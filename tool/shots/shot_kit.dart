import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where screenshots land. Override with SHOTS_DIR.
final String shotsDir = Platform.environment['SHOTS_DIR'] ??
    '${Directory.systemTemp.path}/frank_shots';

/// Loads real fonts so text renders like the phone (Roboto, Material icons,
/// a monospace stand-in) instead of the test font's boxes.
Future<void> loadShotFonts() async {
  final home = Platform.environment['HOME'];
  final material = '$home/development/flutter/bin/cache/artifacts/material_fonts';

  Future<ByteData> bytes(String path) async {
    final data = File(path).readAsBytesSync();
    return ByteData.view(Uint8List.fromList(data).buffer);
  }

  // Unnamed text falls back to the tester font ('FlutterTest', drawn as
  // boxes); on a phone it falls back to the system font, so mirror that.
  for (final family in ['Roboto', 'FlutterTest']) {
    await _loadRoboto(family, material, bytes);
  }

  final icons = FontLoader('MaterialIcons')
    ..addFont(bytes('$material/MaterialIcons-Regular.otf'));
  await icons.load();

  const monoCandidates = [
    '/System/Library/Fonts/Supplemental/Courier New.ttf',
    '/System/Library/Fonts/Supplemental/Andale Mono.ttf',
  ];
  for (final path in monoCandidates) {
    if (File(path).existsSync()) {
      for (final family in ['monospace', 'Roboto Mono', 'Menlo', 'SF Mono', 'Courier New']) {
        final loader = FontLoader(family)..addFont(bytes(path));
        await loader.load();
      }
      break;
    }
  }
}

/// Sizes the test view like a Galaxy S26 Ultra (1440x3120 @ 3.75).
void usePhoneView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 3120);
  tester.view.devicePixelRatio = 3.75;
  tester.view.padding = const FakeViewPadding(top: 136, bottom: 64);
  tester.view.viewPadding = const FakeViewPadding(top: 136, bottom: 64);
  addTearDown(tester.view.reset);
}

/// Sizes the test view for Google Play phone screenshots: 1080x1920
/// (9:16, the ratio Play asks for), a typical phone's 2.625 pixel ratio.
void useStoreView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 2.625;
  tester.view.padding = const FakeViewPadding(top: 63, bottom: 42);
  tester.view.viewPadding = const FakeViewPadding(top: 63, bottom: 42);
  addTearDown(tester.view.reset);
}

/// Writes the [boundary] subtree to `<shotsDir>/<name>.png`, at 2x unless
/// [pixelRatio] says otherwise (store shots use the view's own ratio).
Future<void> saveShot(
  WidgetTester tester,
  GlobalKey boundary,
  String name, {
  double pixelRatio = 2.0,
}) async {
  await tester.runAsync(() async {
    final object = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await object.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(shotsDir).createSync(recursive: true);
    File('$shotsDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

/// Advances frames for [duration] at 60Hz so animations, and the glow
/// (which clamps each frame to 1/30s), move in real time.
Future<void> settleFor(WidgetTester tester, Duration duration, {int? steps}) async {
  final count = steps ?? (duration.inMilliseconds / 16).ceil().clamp(1, 1000);
  final step = duration ~/ count;
  for (var i = 0; i < count; i++) {
    await tester.pump(step);
  }
}

/// Lets real async work (fake HTTP, file I/O) run, then pumps a frame.
Future<void> realAsync(WidgetTester tester, [Duration wait = const Duration(milliseconds: 60)]) async {
  await tester.runAsync(() => Future<void>.delayed(wait));
  await tester.pump();
}

Future<void> _loadRoboto(
  String family,
  String material,
  Future<ByteData> Function(String path) bytes,
) async {
  final loader = FontLoader(family);
  for (final weight in [
    'Thin',
    'Light',
    'Regular',
    'Medium',
    'Bold',
    'Black',
    'Italic',
    'MediumItalic',
    'BoldItalic',
  ]) {
    final file = File('$material/Roboto-$weight.ttf');
    if (file.existsSync()) {
      loader.addFont(bytes(file.path));
    }
  }
  await loader.load();
}
