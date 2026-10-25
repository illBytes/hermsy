import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/relay_client.dart';
import '../services/voice_models.dart';
import '../theme/app_theme.dart';
import '../voice/on_device_voice.dart';
import '../voice/speech_player.dart';
import '../voice/speech_source.dart' show Speech;
import '../widgets/frank_backdrop.dart';
import '../widgets/ui/frank_ui.dart';

/// The engines Frank can speak with in calls.
const _engines = <({String id, String name, String detail})>[
  (
    id: 'kokoro',
    name: 'On this phone',
    detail: 'Kokoro · free and private, nothing leaves the phone',
  ),
  (
    id: 'openai',
    name: 'OpenAI',
    detail: 'gpt-4o-mini-tts · about \$0.90 per hour of Hermsy talking',
  ),
  (
    id: 'elevenlabs',
    name: 'ElevenLabs',
    detail: 'Flash v2.5 · about \$2.70 per hour of Hermsy talking',
  ),
];

/// "OpenAI · Marin · normal speed": the Settings row's summary.
String callVoiceSummary(AppSettings settings) {
  final speed = settings.callSpeed == 1.0
      ? 'normal speed'
      : '${settings.callSpeed}× speed';
  final engine = settings.callEngine;
  if (engine == 'kokoro') {
    return '${kokoroVoice(settings.callVoice).name} · $speed';
  }
  final provider = engine == 'openai' ? 'OpenAI' : 'ElevenLabs';
  final name = settings.cloudVoiceName(engine);
  return [provider, ?name, speed].join(' · ');
}

/// Picks who speaks in calls (Kokoro on the phone, or a cloud voice through
/// the relay), the voice, and the speed. Tapping a voice selects it and
/// plays a short line in it.
class VoicePickerScreen extends StatefulWidget {
  const VoicePickerScreen({
    super.key,
    required this.settings,
    this.voice,
    this.relay,
  });

  final AppSettings settings;

  /// For Kokoro previews; without the models the list still works.
  final OnDeviceVoice? voice;

  /// For cloud voices; without it only Kokoro is offered.
  final RelayClient? relay;

  @override
  State<VoicePickerScreen> createState() => _VoicePickerScreenState();
}

class _VoicePickerScreenState extends State<VoicePickerScreen> {
  /// Short, so a preview is ready in a second or two on either engine.
  static const _sample = "Hi, I'm Hermsy. How can I help?";

  /// Previews are not a call: as media they reach Bluetooth headphones at
  /// once instead of waiting for (or missing) the call link.
  final _player = SpeechPlayer(call: false);
  Map<String, CloudProvider>? _providers;
  String? _providersError;
  String? _previewing;
  String? _previewError;
  var _previewGen = 0;

  /// Previews already rendered, by voice and speed: a second tap plays at
  /// once instead of asking the engine again.
  final _cache = <String, Speech>{};

  /// How many seconds of speech each Kokoro build renders per second on
  /// this phone (keyed by full precision), measured on previews.
  final _renderSpeed = <bool, double>{};

  AppSettings get _settings => widget.settings;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProviders());
  }

  Future<void> _loadProviders() async {
    final relay = widget.relay;
    if (relay == null) {
      setState(() => _providers = const {});
      return;
    }
    try {
      final providers = await relay.speechProviders();
      if (mounted) {
        setState(() => _providers = providers);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _providers = const {};
          _providersError = '$error';
        });
      }
    }
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    widget.voice?.releaseSoon();
    super.dispose();
  }

  bool _offered(String engine) =>
      engine == 'kokoro' || (_providers?.containsKey(engine) ?? false);

  Future<void> _chooseEngine(String engine) async {
    if (!_offered(engine)) {
      return;
    }
    await _settings.setCallEngine(engine);
    // A cloud provider with no voice chosen yet starts on its first one.
    if (engine != 'kokoro' && _settings.cloudVoice(engine) == null) {
      final voices = _providers![engine]!.voices;
      if (voices.isNotEmpty) {
        await _settings.setCloudVoice(
          engine,
          voices.first.id,
          name: voices.first.name,
        );
      }
    }
  }

  Future<void> _chooseKokoro(KokoroVoice voice) async {
    await _settings.setCallVoice(voice.id);
    await _preview('kokoro:${voice.id}', () async {
      final onDevice = widget.voice!;
      final full = onDevice.fullKokoro;
      final mouth = await onDevice.mouth();
      // Timed after loading, so it is the rendering a call waits on.
      final watch = Stopwatch()..start();
      final speech = await mouth.speak(
        _sample,
        voice: voice.id,
        speed: _settings.callSpeed,
      );
      final rendered = watch.elapsedMicroseconds / 1e6;
      final spoken = speech.samples.length / speech.sampleRate;
      if (mounted && rendered > 0) {
        setState(() => _renderSpeed[full] = spoken / rendered);
      }
      return speech;
    }, enabled: widget.voice?.available ?? false);
  }

  /// Picks the Kokoro build, downloading full precision first if needed,
  /// then plays the current voice in it.
  Future<void> _chooseQuality(bool full) async {
    final store = widget.voice?.models;
    if (store == null) {
      return;
    }
    if (full && !store.isReady(kokoroFull)) {
      if (store.downloading) {
        return;
      }
      await store.download(kokoroFull, wifiOnly: _settings.voiceModelsWifiOnly);
      if (!store.isReady(kokoroFull)) {
        return;
      }
    }
    await _settings.setKokoroFull(full);
    _cache.removeWhere((key, _) => key.startsWith('kokoro:'));
    if (mounted && _settings.callEngine == 'kokoro') {
      await _previewCurrent();
    }
  }

  Future<void> _chooseCloud(String engine, CloudVoice voice) async {
    await _settings.setCloudVoice(engine, voice.id, name: voice.name);
    await _preview(
      '$engine:${voice.id}',
      () => widget.relay!.speech(
        provider: engine,
        voice: voice.id,
        text: _sample,
        speed: _settings.callSpeed,
      ),
    );
  }

  Future<void> _previewCurrent() async {
    final engine = _settings.callEngine;
    if (engine == 'kokoro') {
      await _chooseKokoro(kokoroVoice(_settings.callVoice));
      return;
    }
    final id = _settings.cloudVoice(engine);
    final voices = _providers?[engine]?.voices ?? const [];
    for (final voice in voices) {
      if (voice.id == id) {
        await _chooseCloud(engine, voice);
      }
    }
  }

  Future<void> _preview(
    String key,
    Future<Speech> Function() speak, {
    bool enabled = true,
  }) async {
    if (!enabled) {
      return;
    }
    final cacheKey = '$key@${_settings.callSpeed}';
    // Already on its way: let it arrive rather than start over.
    if (_previewing == key && !_cache.containsKey(cacheKey)) {
      return;
    }
    final gen = ++_previewGen;
    await _player.stop();
    final cached = _cache[cacheKey];
    setState(() {
      _previewing = cached == null ? key : null;
      _previewError = null;
    });
    try {
      final audio = cached ?? (_cache[cacheKey] = await speak());
      if (gen != _previewGen || !mounted) {
        return;
      }
      await _player.enqueue(
        trimSilence(audio.samples, audio.sampleRate),
        audio.sampleRate,
      );
    } catch (error) {
      _cache.remove(cacheKey);
      if (gen == _previewGen && mounted) {
        setState(() => _previewError = '$error');
      }
    } finally {
      if (gen == _previewGen && mounted) {
        setState(() => _previewing = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FrankBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ListenableBuilder(
          listenable: _settings,
          builder: (context, _) {
            final media = MediaQuery.of(context);
            final side = math.max(
              AppSpace.gutter,
              (media.size.width - 640) / 2,
            );
            final engine = _offered(_settings.callEngine)
                ? _settings.callEngine
                : 'kokoro';
            return CustomScrollView(
              slivers: [
                const LargeTitleSliverBar(title: "Hermsy's voice"),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    side,
                    AppSpace.x2,
                    side,
                    AppSpace.x10 + media.padding.bottom,
                  ),
                  sliver: SliverList.list(
                    children: [
                      Text(
                        'How Hermsy sounds in voice calls. Tap a voice to '
                        'hear it.',
                        style: TextStyle(
                          color: AppColors.secondary,
                          fontSize: 15,
                          height: 1.47,
                        ),
                      ),
                      const SizedBox(height: AppSpace.x6),
                      const MicroLabel('Engine'),
                      FrankGroup(
                        children: [
                          for (final option in _engines)
                            FrankTile(
                              title: option.name,
                              subtitle: _offered(option.id)
                                  ? option.detail
                                  : _missing(option.id),
                              onTap: _offered(option.id)
                                  ? () => _chooseEngine(option.id)
                                  : null,
                              trailing: _Check(selected: engine == option.id),
                            ),
                        ],
                      ),
                      if (engine != 'kokoro') ...[
                        const SizedBox(height: AppSpace.x3),
                        FrankGroup(
                          children: [
                            FrankSwitchTile(
                              icon: Icons.wifi_off_rounded,
                              title: "Fall back to the phone's voice",
                              subtitle:
                                  'If the cloud voice fails (no '
                                  'connection, no credit), finish the call '
                                  'with Kokoro instead of going quiet',
                              value: _settings.callFallback,
                              onChanged: _settings.setCallFallback,
                            ),
                          ],
                        ),
                      ],
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          4,
                          AppSpace.x2,
                          4,
                          0,
                        ),
                        child: Text(
                          'With a cloud voice, the text of Hermsy\'s replies '
                          'goes to that company to be spoken. What you say '
                          'is still heard on this phone.',
                          style: TextStyle(
                            color: AppColors.hint,
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ),
                      if (engine == 'kokoro' && widget.voice != null) ...[
                        const SizedBox(height: 28),
                        const MicroLabel('Kokoro quality'),
                        _quality(widget.voice!.models),
                      ],
                      const SizedBox(height: 28),
                      const MicroLabel('Speed'),
                      _Choices<double>(
                        value: _settings.callSpeed,
                        options: {
                          for (final speed in AppSettings.callSpeeds)
                            speed: speed == 1.0 ? 'Normal' : '$speed×',
                        },
                        onChanged: (speed) async {
                          await _settings.setCallSpeed(speed);
                          await _previewCurrent();
                        },
                      ),
                      const SizedBox(height: 28),
                      const MicroLabel('Wait before answering'),
                      _Choices<double>(
                        value: _settings.callPause,
                        options: AppSettings.callPauses,
                        onChanged: _settings.setCallPause,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          4,
                          AppSpace.x2,
                          4,
                          0,
                        ),
                        child: Text(
                          'How long you can pause mid-thought before Hermsy '
                          'replies. Keep talking within it and it all goes '
                          'as one message.',
                          style: TextStyle(
                            color: AppColors.hint,
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      const MicroLabel('Voice'),
                      if (_previewError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpace.x2),
                          child: Text(
                            _previewError!,
                            style: AppText.bodySmall.copyWith(
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                      _voices(engine),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Compressed or full precision, the full model's download, and how fast
  /// each renders here.
  Widget _quality(VoiceModelStore store) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final progress = store.progressOf(kokoroFull);
        final ready = store.isReady(kokoroFull);
        final full = _settings.kokoroFull && ready;
        final busy = switch (progress.state) {
          ModelState.downloading ||
          ModelState.verifying ||
          ModelState.unpacking => true,
          _ => false,
        };
        final percent = (100 * progress.received / kokoroFull.downloadBytes)
            .clamp(0, 100)
            .round();
        final fullDetail = switch (progress.state) {
          ModelState.ready =>
            'Cleaner, slower to render · '
                '${formatBytes(kokoroFull.diskBytes)} on this phone',
          ModelState.downloading => 'Downloading · $percent%',
          ModelState.verifying => 'Checking the download…',
          ModelState.unpacking => 'Unpacking…',
          ModelState.failed => 'Download failed · tap to try again',
          ModelState.missing =>
            store.pausedReason != null && progress.received > 0
                ? '${store.pausedReason} · $percent% so far, tap to resume'
                : '${formatBytes(kokoroFull.downloadBytes)} download · '
                      'cleaner, slower to render',
        };
        String speed(bool which) {
          final value = _renderSpeed[which];
          return value == null ? '' : '${value.toStringAsFixed(1)}×';
        }

        final measured = [
          if (_renderSpeed[false] != null) 'compressed ${speed(false)}',
          if (_renderSpeed[true] != null) 'full precision ${speed(true)}',
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FrankGroup(
              children: [
                FrankTile(
                  title: 'Compressed',
                  subtitle:
                      'Lighter and quicker · '
                      '${formatBytes(store.models[2].diskBytes)}',
                  onTap: () => _chooseQuality(false),
                  trailing: _Check(selected: !full),
                ),
                // Removing the download lives in Voice models, behind a
                // confirmation, not one tap away here.
                FrankTile(
                  title: 'Full precision',
                  subtitle: fullDetail,
                  onTap: busy ? null : () => _chooseQuality(true),
                  trailing: ready || busy
                      ? _Check(selected: full, busy: busy)
                      : Icon(
                          Icons.download_rounded,
                          color: AppColors.hint,
                          size: 22,
                        ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, AppSpace.x2, 4, 0),
              child: Text(
                measured.isEmpty
                    ? 'Tap a voice to hear it in each and see how fast this '
                          'phone renders it.'
                    : 'Seconds of speech rendered per second here: '
                          '${measured.join(', ')}. Under 1× and calls may '
                          'pause between sentences.',
                style: TextStyle(
                  color: AppColors.hint,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _missing(String engine) {
    if (_providers == null) {
      return 'Checking Hermes…';
    }
    if (_providersError != null) {
      return 'Could not reach the Hermsy plugin';
    }
    final key = engine == 'openai' ? 'OPENAI_API_KEY' : 'ELEVENLABS_API_KEY';
    return 'Add $key to Hermes to use it';
  }

  Widget _voices(String engine) {
    if (engine == 'kokoro') {
      return FrankGroup(
        children: [
          for (final voice in kokoroVoices)
            FrankTile(
              title: voice.name,
              subtitle: voice.description,
              onTap: () => _chooseKokoro(voice),
              trailing: _Check(
                selected: _settings.callVoice == voice.id,
                busy: _previewing == 'kokoro:${voice.id}',
              ),
            ),
        ],
      );
    }
    final provider = _providers![engine]!;
    if (provider.voices.isEmpty) {
      return Text(
        provider.error ?? 'No voices on this account.',
        style: AppText.bodySmall.copyWith(color: AppColors.danger),
      );
    }
    return FrankGroup(
      children: [
        for (final voice in provider.voices)
          FrankTile(
            title: voice.name,
            subtitle: voice.description.isEmpty ? null : voice.description,
            onTap: () => _chooseCloud(engine, voice),
            trailing: _Check(
              selected: _settings.cloudVoice(engine) == voice.id,
              busy: _previewing == '$engine:${voice.id}',
            ),
          ),
      ],
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.selected, this.busy = false});

  final bool selected;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
      );
    }
    return AnimatedOpacity(
      duration: AppMotion.quick,
      opacity: selected ? 1 : 0,
      child: Icon(Icons.check_rounded, color: AppColors.gold, size: 22),
    );
  }
}

/// A row of segments, one per option, the chosen one in gold.
class _Choices<T> extends StatelessWidget {
  const _Choices({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          for (final MapEntry(key: option, value: label) in options.entries)
            Expanded(
              child: Pressable(
                onTap: () => onChanged(option),
                semanticLabel: label,
                child: AnimatedContainer(
                  duration: AppMotion.quick,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: option == value ? AppColors.goldSoft : null,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Text(
                    label,
                    style: AppText.label.copyWith(
                      fontSize: 15,
                      color: option == value ? AppColors.gold : AppColors.text,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
