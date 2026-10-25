import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/app_settings.dart';
import '../services/voice_models.dart';
import 'speech_worker.dart';

/// One of Kokoro v1.0's English voices.
class KokoroVoice {
  const KokoroVoice(this.id, this.name, this.description);

  /// Kokoro's speaker id.
  final int id;
  final String name;
  final String description;
}

/// The English voices that sound most natural, best first. Kokoro has 28;
/// the rest are flat or robotic enough to leave out.
const kokoroVoices = <KokoroVoice>[
  KokoroVoice(3, 'Heart', 'American woman · warm, the most natural'),
  KokoroVoice(2, 'Bella', 'American woman · bright'),
  KokoroVoice(6, 'Nicole', 'American woman · soft, close'),
  KokoroVoice(21, 'Emma', 'British woman · clear'),
  KokoroVoice(1, 'Aoede', 'American woman · calm'),
  KokoroVoice(5, 'Kore', 'American woman · steady'),
  KokoroVoice(9, 'Sarah', 'American woman · friendly'),
  KokoroVoice(7, 'Nova', 'American woman · crisp'),
  KokoroVoice(14, 'Fenrir', 'American man · deep, young'),
  KokoroVoice(18, 'Puck', 'American man · lively'),
  KokoroVoice(16, 'Michael', 'American man · mature'),
  KokoroVoice(22, 'Isabella', 'British woman · composed'),
  KokoroVoice(26, 'George', 'British man · mature'),
  KokoroVoice(25, 'Fable', 'British man · storyteller'),
];

/// Frank's voice until you pick another: Heart.
const defaultKokoroVoice = 3;

KokoroVoice kokoroVoice(int id) => kokoroVoices.firstWhere(
  (voice) => voice.id == id,
  orElse: () => kokoroVoices.first,
);

/// The on-device voice: Parakeet and Silero for listening, Kokoro for
/// speaking, each loaded into its own background isolate the first time it
/// is needed and kept while voice is in use. [release] frees the memory
/// (Parakeet alone holds about 700 MB).
class OnDeviceVoice extends ChangeNotifier {
  OnDeviceVoice(this.models, {this.settings}) {
    models.addListener(_onModels);
    settings?.addListener(_onSettings);
  }

  final VoiceModelStore models;

  /// Which Kokoro speaks ([AppSettings.kokoroFull]).
  final AppSettings? settings;

  /// The Kokoro build the speaking workers hold, once loaded.
  bool? _mouthsFull;

  /// Full precision when it is chosen and on the phone; else compressed.
  bool get fullKokoro =>
      (settings?.kokoroFull ?? false) && models.isReady(kokoroFull);
  Future<SpeechWorker>? _ears;
  Future<SpeechWorker>? _mouth;
  Future<SpeechWorker>? _secondMouth;
  Timer? _idle;

  /// True once every model is downloaded and checked.
  bool get available => models.allReady;

  /// The listening worker, loaded on first use.
  Future<SpeechWorker> ears() {
    _idle?.cancel();
    return _ears ??= _load('ears', (worker) async {
      final vad = await models.folderOf(models.models[0]);
      final stt = await models.folderOf(models.models[1]);
      await worker.loadEars(
        EarsPaths(
          vad: '$vad/silero_vad.onnx',
          encoder: '$stt/encoder.int8.onnx',
          decoder: '$stt/decoder.int8.onnx',
          joiner: '$stt/joiner.int8.onnx',
          tokens: '$stt/tokens.txt',
        ),
      );
    }, () => _ears = null);
  }

  /// The speaking worker, loaded on first use.
  Future<SpeechWorker> mouth() {
    _idle?.cancel();
    return _mouth ??= _loadMouth('mouth', () => _mouth = null);
  }

  /// Both speaking workers. On a phone Kokoro renders at about real time,
  /// so a call renders consecutive sentences on two workers at once to keep
  /// speech ready before it is needed.
  Future<List<SpeechWorker>> mouths() async {
    _idle?.cancel();
    final second = _secondMouth ??= _loadMouth(
      'mouth 2',
      () => _secondMouth = null,
    );
    return Future.wait([mouth(), second]);
  }

  void _onModels() {
    // The full model finishing, or going, can change which Kokoro speaks.
    _onSettings();
    notifyListeners();
  }

  /// A different Kokoro was chosen: the speaking workers load it next time.
  void _onSettings() {
    final loaded = _mouthsFull;
    if (loaded != null && loaded != fullKokoro) {
      unawaited(_releaseMouths());
    }
  }

  Future<void> _releaseMouths() async {
    final workers = [_mouth, _secondMouth];
    _mouth = null;
    _secondMouth = null;
    _mouthsFull = null;
    for (final worker in workers) {
      try {
        (await worker)?.dispose();
      } catch (_) {}
    }
  }

  Future<SpeechWorker> _loadMouth(String name, VoidCallback forget) {
    final full = _mouthsFull = fullKokoro;
    return _load(name, (worker) async {
      final tts = await models.folderOf(full ? kokoroFull : models.models[2]);
      await worker.loadMouth(
        MouthPaths(
          model: full ? '$tts/model.onnx' : '$tts/model.int8.onnx',
          voices: '$tts/voices.bin',
          tokens: '$tts/tokens.txt',
          dataDir: '$tts/espeak-ng-data',
          lexicon: '$tts/lexicon-us-en.txt',
        ),
      );
    }, forget);
  }

  Future<SpeechWorker> _load(
    String name,
    Future<void> Function(SpeechWorker worker) load,
    VoidCallback forget,
  ) async {
    final worker = await SpeechWorker.spawn(name);
    try {
      await load(worker);
      return worker;
    } catch (_) {
      worker.dispose();
      forget();
      rethrow;
    }
  }

  /// Frees the models after [after] unless voice is used again first.
  void releaseSoon({Duration after = const Duration(minutes: 3)}) {
    _idle?.cancel();
    _idle = Timer(after, release);
  }

  Future<void> release() async {
    _idle?.cancel();
    final workers = [_ears, _mouth, _secondMouth];
    _ears = null;
    _mouth = null;
    _secondMouth = null;
    _mouthsFull = null;
    for (final worker in workers) {
      try {
        (await worker)?.dispose();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    models.removeListener(_onModels);
    settings?.removeListener(_onSettings);
    unawaited(release());
    super.dispose();
  }
}
