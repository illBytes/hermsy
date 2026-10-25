import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../voice/audio_route.dart';

/// Below this, a mic level reads as silence so room noise stays dark.
const double voiceLevelGate = 0.06;

/// Maps a recorder reading in dBFS (-160 silent … 0 clipping) to a 0–1
/// loudness: -52 dB and quieter is silence, -6 dB and louder is full, with a
/// gentle curve so normal speech fills the middle of the range.
double levelFromDecibels(double decibels) {
  if (!decibels.isFinite) {
    return 0;
  }
  return _shapeLevel((decibels + 52) / 46);
}

double _shapeLevel(double linear) {
  final shaped = math.pow(linear.clamp(0.0, 1.0), 0.7).toDouble();
  return shaped < voiceLevelGate ? 0 : shaped;
}

/// Turns on-device dictation sound levels into 0–1 loudness.
///
/// Android reports a loose RMS dB (about -2 silent to 10 loud) and iOS true
/// dBFS (about -50 to -20 for a room and a voice), and both drift with the
/// room and the phone. This starts from the platform's typical range, then
/// keeps a rolling floor (falls fast, rises slowly) and ceiling (jumps to
/// peaks, relaxes slowly), never closer than [minSpan] apart, and measures
/// each reading between them.
class SoundLevelNormalizer {
  SoundLevelNormalizer({this.minSpan = 6, this.quiet = -2, this.loud = 10})
      : _floor = quiet,
        _ceiling = loud;

  /// iOS reports dBFS, which spans much more than Android's RMS dB.
  SoundLevelNormalizer.dbfs() : this(minSpan: 18, quiet: -50, loud: -20);

  /// The smallest floor-to-ceiling distance, in the platform's units, so
  /// room hiss never stretches to full scale.
  final double minSpan;

  /// Typical silent and loud readings: the range before the room is learned.
  final double quiet;
  final double loud;

  double _floor;
  double _ceiling;

  /// The 0–1 loudness of [raw], updating the rolling range.
  double normalize(double raw) {
    if (!raw.isFinite) {
      return 0;
    }
    _floor += (raw - _floor) * (raw < _floor ? 0.5 : 0.004);
    _ceiling = raw > _ceiling ? raw : _ceiling - (_ceiling - raw) * 0.004;
    _ceiling = math.max(_ceiling, _floor + minSpan);
    final position = (raw - _floor) / (_ceiling - _floor);
    // A small knee keeps the hiss that sits just above the floor dark.
    return _shapeLevel((position - _knee) / (1 - _knee));
  }

  /// Forget the room and start again from the typical range.
  void reset() {
    _floor = quiet;
    _ceiling = loud;
  }

  static const _knee = 0.16;
}

class VoiceService {
  VoiceService({
    AudioRecorder? recorder,
    AudioPlayer? player,
    SpeechToText? speech,
  })  : _recorder = recorder ?? AudioRecorder(),
        _player = player ?? AudioPlayer(),
        _speech = speech ?? SpeechToText();

  final AudioRecorder _recorder;
  final AudioPlayer _player;
  final SpeechToText _speech;
  bool _playbackReady = false;

  final _levels = StreamController<double>.broadcast();
  final _partials = StreamController<String>.broadcast();
  StreamSubscription<Amplitude>? _amplitude;
  double _level = 0;
  String? _recordingPath;

  Completer<String>? _dictation;
  int _dictationGen = 0;
  String _heard = '';
  Timer? _settle;
  // The dictation take whose stop arrived; see [stopDeviceListen].
  int _stopRequested = -1;
  final _soundLevels =
      Platform.isIOS ? SoundLevelNormalizer.dbfs() : SoundLevelNormalizer();

  static const _amplitudeInterval = Duration(milliseconds: 40);

  /// Mic loudness from 0 (silence) to 1 while recording or dictating, lightly
  /// smoothed (quick rise, softer fall). Sends 0 when the mic closes.
  Stream<double> get levels => _levels.stream;

  /// Words heard so far by on-device dictation, revised as the recognizer
  /// refines them.
  Stream<String> get partials => _partials.stream;

  static final playbackContext = AudioContext(
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playAndRecord,
      options: const {
        AVAudioSessionOptions.defaultToSpeaker,
        AVAudioSessionOptions.allowBluetooth,
        AVAudioSessionOptions.mixWithOthers,
      },
    ),
    android: const AudioContextAndroid(
      audioFocus: AndroidAudioFocus.gain,
      contentType: AndroidContentType.speech,
      usageType: AndroidUsageType.media,
      audioMode: AndroidAudioMode.normal,
    ),
  );

  Future<bool> requestMic() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<String> startRecording() async {
    if (!await requestMic()) {
      throw Exception('Microphone permission denied.');
    }
    await stopPlayback();
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/frank_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    // Through a connected headset's mic, when there is one.
    await AudioRoute.begin(AudioPurpose.dictation);
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          androidConfig: AndroidRecordConfig(manageBluetooth: false),
        ),
        path: path,
      );
    } catch (_) {
      await AudioRoute.end(AudioPurpose.dictation);
      rethrow;
    }
    _recordingPath = path;
    _playbackReady = false;
    _watchAmplitude();
    return path;
  }

  Future<String?> stopRecording() async {
    _quietLevels();
    final path = await _recorder.stop();
    await AudioRoute.end(AudioPurpose.dictation);
    _recordingPath = null;
    _playbackReady = false;
    return path;
  }

  /// Stops the recorder and deletes what it captured. Safe to call when
  /// nothing is recording.
  Future<void> cancelRecording() async {
    _quietLevels();
    final path = _recordingPath;
    _recordingPath = null;
    _playbackReady = false;
    try {
      await _recorder.cancel();
    } catch (_) {}
    await AudioRoute.end(AudioPurpose.dictation);
    if (path != null) {
      await discard(path);
    }
  }

  /// Deletes a recording Frank no longer needs. A missing file is fine.
  Future<void> discard(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// Dictates on the device until the speaker pauses, [stopDeviceListen] is
  /// called, or 45 seconds pass, and returns the words. Partial words stream
  /// on [partials] meanwhile. Resolves with an empty string when nothing was
  /// heard or [cancelDeviceListen] dropped the take.
  Future<String> listenOnDevice() async {
    final gen = ++_dictationGen;
    if (!await requestMic()) {
      throw Exception('Microphone permission denied.');
    }
    final ready = await _speech.initialize();
    if (!ready) {
      throw Exception('On-device speech recognition is not available.');
    }
    if (gen != _dictationGen) {
      return '';
    }
    // Frank never talks over your dictation.
    if (_player.state == PlayerState.playing) {
      await stopPlayback();
      if (gen != _dictationGen) {
        return '';
      }
    }
    if (_stopRequested == gen) {
      // Released before the recognizer started: nothing was heard, and the
      // mic must not open after the finger has already let go.
      _quietLevels();
      return '';
    }
    _settle?.cancel();
    final previous = _dictation;
    if (previous != null && !previous.isCompleted) {
      previous.complete('');
    }
    final done = Completer<String>();
    _dictation = done;
    _heard = '';
    _level = 0;
    _soundLevels.reset();

    bool current() => identical(_dictation, done);
    void finish(String words) {
      if (done.isCompleted) {
        return;
      }
      _settle?.cancel();
      done.complete(words.trim());
    }

    // initialize() only takes listeners on its first call, so set them per
    // take: they end the take promptly when the recognizer gives up without
    // a final result instead of waiting for the timeout.
    _speech.statusListener = (status) {
      if (!current()) {
        return;
      }
      if (status == SpeechToText.notListeningStatus ||
          status == SpeechToText.doneStatus) {
        _quietLevels();
      }
      if (status == SpeechToText.doneStatus) {
        finish(_heard);
      }
    };
    _speech.errorListener = (error) {
      if (current() && error.permanent) {
        _quietLevels();
        _settleSoon(done);
      }
    };

    try {
      await _listen(done, current, finish);
    } catch (_) {
      if (current()) {
        _dictation = null;
      }
      _quietLevels();
      rethrow;
    }
    if (!current()) {
      // Cancelled while the recognizer was starting: make sure it stops.
      await _speech.cancel();
    } else if (_stopRequested == gen && !done.isCompleted) {
      // Released while the recognizer was starting (its stop came too early
      // to land): stop it now and settle with whatever it heard.
      _quietLevels();
      _settleSoon(done);
      await _speech.stop();
    }
    return done.future.timeout(
      const Duration(seconds: 50),
      onTimeout: () async {
        _quietLevels();
        await _speech.stop();
        return '';
      },
    );
  }

  Future<void> _listen(
    Completer<String> done,
    bool Function() current,
    void Function(String words) finish,
  ) {
    return _speech.listen(
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 45),
        pauseFor: const Duration(seconds: 3),
        listenMode: ListenMode.dictation,
        partialResults: true,
      ),
      onResult: (result) {
        if (!current() || done.isCompleted) {
          return;
        }
        _heard = result.recognizedWords;
        if (!_partials.isClosed) {
          _partials.add(_heard);
        }
        if (result.finalResult) {
          finish(result.recognizedWords);
        }
      },
      onSoundLevelChange: (level) {
        if (current() && !done.isCompleted) {
          _emitLevel(_soundLevels.normalize(level));
        }
      },
    );
  }

  /// Ends dictation and lets the recognizer deliver its final words to the
  /// pending [listenOnDevice].
  Future<void> stopDeviceListen() async {
    _quietLevels();
    // A take that is still starting (permission, initialize, listen) checks
    // this once it gets there, so a release during startup is never lost.
    _stopRequested = _dictationGen;
    final pending = _dictation;
    if (pending != null && !pending.isCompleted) {
      _settleSoon(pending);
    }
    await _speech.stop();
  }

  /// Ends dictation and drops whatever was heard. The pending
  /// [listenOnDevice] resolves with an empty string.
  Future<void> cancelDeviceListen() async {
    _dictationGen++;
    _quietLevels();
    _settle?.cancel();
    final pending = _dictation;
    _dictation = null;
    _heard = '';
    if (pending != null && !pending.isCompleted) {
      pending.complete('');
    }
    try {
      await _speech.cancel();
    } catch (_) {}
  }

  Stream<void> get onComplete => _player.onPlayerComplete;

  Future<String> keepRecording(String path) async {
    final source = File(path);
    if (!await source.exists()) {
      return path;
    }
    final dir = await _audioDir();
    final ext = path.contains('.') ? path.split('.').last : 'm4a';
    final dest = File(
      '${dir.path}/frank_${DateTime.now().millisecondsSinceEpoch}.$ext',
    );
    await source.copy(dest.path);
    return dest.path;
  }

  Future<String> writeSpeechBytes(List<int> bytes, {String? extension}) async {
    final audioDir = await _audioDir();
    final ext = (extension ?? 'mp3').replaceAll('.', '');
    final file = File(
      '${audioDir.path}/frank_${DateTime.now().millisecondsSinceEpoch}.$ext',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  bool canPlayExtension(String extension) {
    final ext = extension.replaceAll('.', '').toLowerCase();
    if (Platform.isIOS && (ext == 'ogg' || ext == 'opus')) {
      return false;
    }
    return true;
  }

  Future<void> play(String path) async {
    await preparePlayback();
    await _player.stop();
    final source = path.startsWith('http')
        ? UrlSource(path)
        : DeviceFileSource(path);
    await _player.play(
      source,
      ctx: playbackContext,
      mode: PlayerMode.mediaPlayer,
    );
  }

  Future<void> preparePlayback() async {
    if (_playbackReady) {
      return;
    }
    try {
      await AudioPlayer.global.setAudioContext(playbackContext);
      await _player.setAudioContext(playbackContext);
      _playbackReady = true;
    } catch (_) {}
  }

  Future<Directory> _audioDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${dir.path}/frank_audio');
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }
    return audioDir;
  }

  Future<void> stopPlayback() => _player.stop();

  void _watchAmplitude() {
    unawaited(_amplitude?.cancel());
    _level = 0;
    _amplitude = _recorder.onAmplitudeChanged(_amplitudeInterval).listen(
          (amplitude) => _emitLevel(levelFromDecibels(amplitude.current)),
          onError: (Object _) {},
        );
  }

  void _emitLevel(double target) {
    _level += (target - _level) * (target > _level ? 0.75 : 0.45);
    if (_level < 0.004) {
      _level = 0;
    }
    if (!_levels.isClosed) {
      _levels.add(_level);
    }
  }

  void _quietLevels() {
    unawaited(_amplitude?.cancel());
    _amplitude = null;
    if (_level == 0) {
      return;
    }
    _level = 0;
    if (!_levels.isClosed) {
      _levels.add(0);
    }
  }

  /// The recognizer usually confirms the end within two seconds; if it goes
  /// quiet instead, settle with the words heard so far.
  void _settleSoon(Completer<String> pending) {
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 2600), () {
      if (!pending.isCompleted) {
        pending.complete(_heard.trim());
      }
    });
  }

  void dispose() {
    _settle?.cancel();
    unawaited(_amplitude?.cancel());
    final pending = _dictation;
    if (pending != null && !pending.isCompleted) {
      pending.complete('');
      unawaited(_speech.cancel());
    }
    _levels.close();
    _partials.close();
    _recorder.dispose();
    _player.dispose();
  }
}
