import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/voice/audio_route.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('frank/audio_route');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add('${call.method} ${call.arguments}');
      return call.method == 'begin'
          ? {'kind': 'bluetooth', 'name': 'Galaxy Buds3 Pro'}
          : null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('a call takes the route, follows headsets, and lets go', () async {
    final route = await AudioRoute.begin(AudioPurpose.call);
    expect(route!.label, 'Galaxy Buds3 Pro');
    expect(AudioRoute.current.value!.headset, isTrue);

    // The buds go back in the case: Android re-picks the speaker.
    await messenger.handlePlatformMessage(
      'frank/audio_route',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('routeChanged', {'kind': 'speaker', 'name': null}),
      ),
      (_) {},
    );
    expect(AudioRoute.current.value!.label, 'Speaker');

    // A dictation that never took the route leaves the call's alone.
    await AudioRoute.end(AudioPurpose.dictation);
    expect(AudioRoute.current.value, isNotNull);

    await AudioRoute.end(AudioPurpose.call);
    expect(AudioRoute.current.value, isNull);
    expect(calls, ['begin call', 'end call']);
  });

  test('labels name where you hear Hermsy', () {
    expect(const AudioRouteInfo(kind: 'bluetooth').label, 'Bluetooth headset');
    expect(const AudioRouteInfo(kind: 'wired').label, 'Headset');
    expect(const AudioRouteInfo(kind: 'speaker').label, 'Speaker');
    expect(const AudioRouteInfo(kind: 'phone').headset, isFalse);
  });
}
