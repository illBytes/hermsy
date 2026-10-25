import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// One file a voice model needs. An [archive] is a `.tar.bz2` that unpacks
/// into the model's folder and is then deleted.
class ModelFile {
  const ModelFile({
    required this.url,
    required this.path,
    required this.size,
    required this.sha256,
    this.archive = false,
  });

  final String url;

  /// Where it lands, relative to the models folder.
  final String path;
  final int size;
  final String sha256;
  final bool archive;
}

class VoiceModel {
  const VoiceModel({
    required this.id,
    required this.name,
    required this.role,
    required this.folder,
    required this.files,
    required this.diskBytes,
    this.unpacked = const [],
  });

  final String id;
  final String name;

  /// What it does in voice mode, in a few words.
  final String role;

  /// Its folder under the models folder; sherpa-onnx loads from here.
  final String folder;
  final List<ModelFile> files;

  /// Space it takes once unpacked.
  final int diskBytes;

  /// For a model that arrives as an archive: what must be in its folder
  /// once unpacked, to check a copy of it (see [VoiceModelStore.import]).
  final List<String> unpacked;

  int get downloadBytes => files.fold(0, (sum, file) => sum + file.size);
}

const _parakeetRepo =
    'https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/resolve/1ab9323565ddb038682214b292f588070a538ce2';
const _parakeetFolder = 'sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8';
const _releases = 'https://github.com/k2-fsa/sherpa-onnx/releases/download';

/// The three models voice mode runs on the phone. Sizes and SHA-256 sums
/// are pinned: Parakeet to a fixed Hugging Face commit, the others to the
/// sherpa-onnx release assets (checked 2026-10-24).
const voiceModels = <VoiceModel>[
  VoiceModel(
    id: 'vad',
    name: 'Silero VAD',
    role: 'Hears when you start and stop talking',
    folder: 'silero-vad',
    diskBytes: 643854,
    files: [
      ModelFile(
        url: '$_releases/asr-models/silero_vad.onnx',
        path: 'silero-vad/silero_vad.onnx',
        size: 643854,
        sha256:
            '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6',
      ),
    ],
  ),
  VoiceModel(
    id: 'stt',
    name: 'Parakeet TDT 0.6B',
    role: 'Turns your speech into text',
    folder: _parakeetFolder,
    diskBytes: 661190513,
    // Plain files rather than the 482 MB .tar.bz2: unpacking that would
    // keep the phone's CPU busy for minutes.
    files: [
      ModelFile(
        url: '$_parakeetRepo/encoder.int8.onnx',
        path: '$_parakeetFolder/encoder.int8.onnx',
        size: 652184296,
        sha256:
            'a32b12d17bbbc309d0686fbbcc2987b5e9b8333a7da83fa6b089f0a2acd651ab',
      ),
      ModelFile(
        url: '$_parakeetRepo/decoder.int8.onnx',
        path: '$_parakeetFolder/decoder.int8.onnx',
        size: 7257753,
        sha256:
            'b6bb64963457237b900e496ee9994b59294526439fbcc1fecf705b31a15c6b4e',
      ),
      ModelFile(
        url: '$_parakeetRepo/joiner.int8.onnx',
        path: '$_parakeetFolder/joiner.int8.onnx',
        size: 1739080,
        sha256:
            '7946164367946e7f9f29a122407c3252b680dbae9a51343eb2488d057c3c43d2',
      ),
      ModelFile(
        url: '$_parakeetRepo/tokens.txt',
        path: '$_parakeetFolder/tokens.txt',
        size: 9384,
        sha256:
            'ec182b70dd42113aff6c5372c75cac58c952443eb22322f57bbd7f53977d497d',
      ),
    ],
  ),
  VoiceModel(
    id: 'tts',
    name: 'Kokoro 82M',
    role: 'Speaks Hermsy\'s replies',
    folder: 'kokoro-int8-multi-lang-v1_0',
    diskBytes: 189882497,
    unpacked: [
      'model.int8.onnx',
      'voices.bin',
      'tokens.txt',
      'lexicon-us-en.txt',
      'espeak-ng-data/phontab',
    ],
    // 417 entries (voices, lexicons, espeak-ng data): one archive.
    files: [
      ModelFile(
        url: '$_releases/tts-models/kokoro-int8-multi-lang-v1_0.tar.bz2',
        path: 'kokoro-int8-multi-lang-v1_0.tar.bz2',
        size: 132303094,
        sha256:
            '4c3052abaa60943a341f193888cf6abd68787dae6ab8ae5c925a706caa247e4e',
        archive: true,
      ),
    ],
  ),
];

/// Kokoro without the 8-bit compression: the same voices, cleaner, bigger
/// and slower to render. Optional: Settings picks which Kokoro speaks.
const kokoroFull = VoiceModel(
  id: 'tts_full',
  name: 'Kokoro 82M, full precision',
  role: 'Speaks Hermsy\'s replies, cleaner',
  folder: 'kokoro-multi-lang-v1_0',
  diskBytes: 401239297,
  unpacked: [
    'model.onnx',
    'voices.bin',
    'tokens.txt',
    'lexicon-us-en.txt',
    'espeak-ng-data/phontab',
  ],
  files: [
    ModelFile(
      url: '$_releases/tts-models/kokoro-multi-lang-v1_0.tar.bz2',
      path: 'kokoro-multi-lang-v1_0.tar.bz2',
      size: 349906910,
      sha256:
          'c5f7e2d2caf082bc1d20fb70334a61d99d20b484500aad32e7cf84c128ea3298',
      archive: true,
    ),
  ],
);

enum ModelState { missing, downloading, verifying, unpacking, ready, failed }

class ModelProgress {
  const ModelProgress(this.state, {this.received = 0, this.error});

  final ModelState state;

  /// Bytes on the phone so far, partial files included.
  final int received;
  final String? error;
}

/// Why downloads stopped without failing.
class DownloadPaused implements Exception {
  const DownloadPaused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// Downloads, checks and keeps the voice models in the app support folder.
///
/// Downloads resume where they stopped (HTTP Range on a `.part` file), each
/// file is checked against its SHA-256 before it is kept, and a model counts
/// as ready only once a `.ready` marker sits in its folder.
class VoiceModelStore extends ChangeNotifier {
  VoiceModelStore({
    Directory? root,
    http.Client Function()? httpClient,
    Future<bool> Function()? onUnmeteredNetwork,
    this.models = voiceModels,
    this.extras = const [kokoroFull],
    ModelFolderCopy? copyFromFolder,
  }) : _copyFromFolder = copyFromFolder ?? _pickAndCopy,
       _root = root,
       _httpClient = httpClient ?? http.Client.new,
       _onUnmeteredNetwork = onUnmeteredNetwork ?? _wifiOrEthernet;

  /// What voice mode needs.
  final List<VoiceModel> models;

  /// Optional models, downloaded one at a time on request ([download]).
  final List<VoiceModel> extras;
  final ModelFolderCopy _copyFromFolder;
  Directory? _root;
  final http.Client Function() _httpClient;
  final Future<bool> Function() _onUnmeteredNetwork;

  final Map<String, ModelProgress> _progress = {};
  bool _running = false;
  bool _cancelled = false;
  http.Client? _client;
  String? _paused;

  bool get downloading => _running;

  /// How far an import from a folder has copied (0–1), while it runs.
  double? get copying => _copying;
  double? _copying;

  /// Why the last download stopped early ("Waiting for Wi-Fi"), if it did.
  String? get pausedReason => _paused;

  ModelProgress progressOf(VoiceModel model) =>
      _progress[model.id] ?? const ModelProgress(ModelState.missing);

  bool get allReady =>
      models.every((model) => progressOf(model).state == ModelState.ready);

  bool isReady(VoiceModel model) => progressOf(model).state == ModelState.ready;

  int get totalBytes => models.fold(0, (sum, m) => sum + m.downloadBytes);

  int get receivedBytes => models.fold(0, (sum, model) {
    final progress = progressOf(model);
    return sum +
        (progress.state == ModelState.ready
            ? model.downloadBytes
            : progress.received);
  });

  int get diskBytes => models.fold(0, (sum, m) => sum + m.diskBytes);

  Future<Directory> root() async {
    return _root ??= Directory(
      '${(await getApplicationSupportDirectory()).path}/voice_models',
    );
  }

  /// The folder sherpa-onnx loads [model] from.
  Future<String> folderOf(VoiceModel model) async =>
      '${(await root()).path}/${model.folder}';

  /// Reads what is already on the phone.
  Future<void> load() async {
    final dir = await root();
    for (final model in [...models, ...extras]) {
      if (await File('${dir.path}/${model.folder}/.ready').exists()) {
        _progress[model.id] = const ModelProgress(ModelState.ready);
        continue;
      }
      var received = 0;
      for (final file in model.files) {
        received += await _bytesOnDisk(dir, file);
      }
      _progress[model.id] = ModelProgress(
        ModelState.missing,
        received: received,
      );
    }
    notifyListeners();
  }

  /// Downloads every model that is not ready yet, one file at a time.
  /// With [wifiOnly], it stops (and says so) when the phone is not on Wi-Fi.
  Future<void> downloadAll({required bool wifiOnly}) =>
      _downloadEach(models, wifiOnly: wifiOnly);

  /// Downloads one model, such as an extra.
  Future<void> download(VoiceModel model, {required bool wifiOnly}) =>
      _downloadEach([model], wifiOnly: wifiOnly);

  /// Removes one model and anything left of its download.
  Future<void> delete(VoiceModel model) async {
    final dir = await root();
    final folder = Directory('${dir.path}/${model.folder}');
    if (await folder.exists()) {
      await folder.delete(recursive: true);
    }
    for (final file in model.files) {
      for (final path in [
        '${dir.path}/${file.path}',
        '${dir.path}/${file.path}.part',
      ]) {
        final leftover = File(path);
        if (await leftover.exists()) {
          await leftover.delete();
        }
      }
    }
    _progress[model.id] = const ModelProgress(ModelState.missing);
    notifyListeners();
  }

  /// Copies models from a folder the person picks: put there from a
  /// computer (tool/voice_models_to_phone.py) or by another copy of the
  /// app, so a new install need not download them. Each copy is checked
  /// before it counts: the pinned SHA-256s, or for an unpacked archive that
  /// every file it needs is there. Returns the names of the models added.
  Future<List<String>> importFromFolder({
    ValueChanged<double>? onProgress,
  }) async {
    if (_running) {
      return const [];
    }
    _running = true;
    notifyListeners();
    final imported = <String>[];
    try {
      final dir = await root();
      await dir.create(recursive: true);
      final all = [...models, ...extras];
      final copied = await _copyFromFolder(
        dir.path,
        [for (final model in all) model.folder],
        (fraction) {
          // A tick per percent is enough for the bar.
          if (_copying == null || (fraction - _copying!).abs() >= 0.01) {
            _copying = fraction;
            notifyListeners();
          }
          onProgress?.call(fraction);
        },
      );
      _copying = null;
      for (final model in all) {
        if (!copied.contains(model.folder)) {
          continue;
        }
        _set(model, ModelState.verifying, received: model.downloadBytes);
        if (await _isWholeCopy(dir, model)) {
          await File('${dir.path}/${model.folder}/.ready').writeAsString('ok');
          _set(model, ModelState.ready);
          imported.add(model.name);
        } else {
          final folder = Directory('${dir.path}/${model.folder}');
          if (await folder.exists()) {
            await folder.delete(recursive: true);
          }
          _set(
            model,
            ModelState.failed,
            error: '${model.name} in that folder is incomplete or damaged',
          );
        }
      }
    } finally {
      _running = false;
      _copying = null;
      notifyListeners();
    }
    return imported;
  }

  Future<bool> _isWholeCopy(Directory dir, VoiceModel model) async {
    for (final file in model.files.where((file) => !file.archive)) {
      final kept = File('${dir.path}/${file.path}');
      if (!await kept.exists() || await kept.length() != file.size) {
        return false;
      }
      if (await _sha256InIsolate(kept.path) != file.sha256) {
        return false;
      }
    }
    for (final path in model.unpacked) {
      final inside = '${dir.path}/${model.folder}/$path';
      if (!await File(inside).exists() && !await Directory(inside).exists()) {
        return false;
      }
    }
    return true;
  }

  Future<void> _downloadEach(
    List<VoiceModel> models, {
    required bool wifiOnly,
  }) async {
    if (_running) {
      return;
    }
    _running = true;
    _cancelled = false;
    _paused = null;
    _client = _httpClient();
    notifyListeners();
    try {
      for (final model in models) {
        if (_cancelled) {
          break;
        }
        if (progressOf(model).state == ModelState.ready) {
          continue;
        }
        await _download(model, wifiOnly: wifiOnly);
      }
    } on DownloadPaused catch (pause) {
      _paused = pause.reason;
    } finally {
      _client?.close();
      _client = null;
      _running = false;
      notifyListeners();
    }
  }

  /// Stops after the bytes already received; the next download resumes.
  void cancel() {
    if (!_running) {
      return;
    }
    _cancelled = true;
    _client?.close();
  }

  /// Removes every model and partial download.
  Future<void> deleteAll() async {
    cancel();
    while (_running) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final dir = await root();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _progress.clear();
    _paused = null;
    notifyListeners();
  }

  Future<void> _download(VoiceModel model, {required bool wifiOnly}) async {
    final dir = await root();
    var done = 0;
    try {
      for (final file in model.files) {
        if (_cancelled) {
          throw const DownloadPaused('Paused');
        }
        if (wifiOnly && !await _onUnmeteredNetwork()) {
          throw const DownloadPaused('Waiting for Wi-Fi');
        }
        final kept = File('${dir.path}/${file.path}');
        final complete =
            await kept.exists() && await kept.length() == file.size;
        // Plain files were checked before they were renamed into place. An
        // archive left from an unfinished unpack is checked again below.
        if (complete && !file.archive) {
          done += file.size;
          continue;
        }
        if (!complete) {
          final base = done;
          await _fetch(
            file,
            kept,
            onBytes: (bytes) {
              _set(model, ModelState.downloading, received: base + bytes);
            },
          );
        }
        _set(model, ModelState.verifying, received: done + file.size);
        if (await _sha256InIsolate(kept.path) != file.sha256) {
          await kept.delete();
          throw StateError('${file.path.split('/').last} failed its checksum');
        }
        if (file.archive) {
          _set(model, ModelState.unpacking, received: done + file.size);
          await _unpackInIsolate(kept.path, dir.path);
          await kept.delete();
        }
        done += file.size;
      }
      await File('${dir.path}/${model.folder}/.ready').writeAsString('ok');
      _set(model, ModelState.ready);
    } on DownloadPaused {
      _set(model, ModelState.missing, received: await _receivedOf(model));
      rethrow;
    } catch (error) {
      if (_cancelled) {
        _set(model, ModelState.missing, received: await _receivedOf(model));
        throw const DownloadPaused('Paused');
      }
      _set(
        model,
        ModelState.failed,
        received: await _receivedOf(model),
        error: _friendly(error),
      );
    }
  }

  /// Streams [file] into `<kept>.part`, resuming from what is there, then
  /// renames it into place. Checking is left to the caller.
  Future<void> _fetch(
    ModelFile file,
    File kept, {
    required void Function(int bytes) onBytes,
  }) async {
    final part = File('${kept.path}.part');
    await part.parent.create(recursive: true);
    var have = await part.exists() ? await part.length() : 0;
    if (have > file.size) {
      await part.delete();
      have = 0;
    }
    if (have < file.size) {
      final request = http.Request('GET', Uri.parse(file.url));
      if (have > 0) {
        request.headers['Range'] = 'bytes=$have-';
      }
      final response = await _client!.send(request);
      if (response.statusCode == 200) {
        // The server ignored the range: start over.
        have = 0;
      } else if (response.statusCode != 206) {
        throw HttpException('HTTP ${response.statusCode} for ${file.url}');
      }
      final sink = part.openWrite(
        mode: have == 0 ? FileMode.writeOnly : FileMode.writeOnlyAppend,
      );
      var received = have;
      var lastReport = DateTime.fromMillisecondsSinceEpoch(0);
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          final now = DateTime.now();
          if (now.difference(lastReport) > const Duration(milliseconds: 250)) {
            lastReport = now;
            onBytes(received);
          }
        }
      } finally {
        await sink.close();
      }
      if (received != file.size) {
        throw HttpException('Download stopped early (${file.path})');
      }
    }
    onBytes(file.size);
    if (await kept.exists()) {
      await kept.delete();
    }
    await part.rename(kept.path);
  }

  Future<int> _receivedOf(VoiceModel model) async {
    final dir = await root();
    var total = 0;
    for (final file in model.files) {
      total += await _bytesOnDisk(dir, file);
    }
    return total;
  }

  static Future<int> _bytesOnDisk(Directory dir, ModelFile file) async {
    final kept = File('${dir.path}/${file.path}');
    if (await kept.exists()) {
      return await kept.length();
    }
    final part = File('${kept.path}.part');
    return await part.exists() ? await part.length() : 0;
  }

  void _set(
    VoiceModel model,
    ModelState state, {
    int received = 0,
    String? error,
  }) {
    _progress[model.id] = ModelProgress(
      state,
      received: received,
      error: error,
    );
    notifyListeners();
  }

  static String _friendly(Object error) {
    if (error is SocketException || error is http.ClientException) {
      return 'Lost the connection. Tap Download to resume.';
    }
    if (error is FileSystemException) {
      return 'Could not save the file. Is the phone out of space?';
    }
    return '$error';
  }

  static Future<bool> _wifiOrEthernet() async {
    final kinds = await Connectivity().checkConnectivity();
    return kinds.contains(ConnectivityResult.wifi) ||
        kinds.contains(ConnectivityResult.ethernet);
  }
}

/// Copies the model [folders] found in a folder the person picks into
/// [target], reporting 0–1 progress; returns the folders it copied.
typedef ModelFolderCopy =
    Future<List<String>> Function(
      String target,
      List<String> folders,
      ValueChanged<double> onProgress,
    );

/// Android's folder picker and copy (ModelImport.kt).
Future<List<String>> _pickAndCopy(
  String target,
  List<String> folders,
  ValueChanged<double> onProgress,
) async {
  const channel = MethodChannel('frank/model_import');
  channel.setMethodCallHandler((call) async {
    if (call.method == 'progress') {
      onProgress((call.arguments as num).toDouble());
    }
  });
  final copied = await channel.invokeListMethod<String>('pick', {
    'target': target,
    'folders': folders,
  });
  return copied ?? const [];
}

// Top-level so the isolate closures capture only their arguments: a closure
// inside the store would carry the store (and its listeners) along.
Future<String> _sha256InIsolate(String path) =>
    Isolate.run(() => _sha256Of(path));

Future<void> _unpackInIsolate(String archivePath, String out) =>
    Isolate.run(() => _unpack(archivePath, out));

Future<String> _sha256Of(String path) async {
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString();
}

/// Unpacks a `.tar.bz2` into [out]. The tar goes next to the archive, not
/// to the system temp folder, which an Android app may not be able to write.
Future<void> _unpack(String archivePath, String out) async {
  final tar = '$archivePath.tar';
  final input = InputFileStream(archivePath);
  final output = OutputFileStream(tar);
  try {
    BZip2Decoder().decodeStream(input, output);
  } finally {
    await input.close();
    await output.close();
  }
  try {
    await extractFileToDisk(tar, out);
  } finally {
    await File(tar).delete();
  }
}

/// "794 MB", "1.2 GB": sizes as people read them.
String formatBytes(int bytes) {
  const mb = 1000 * 1000;
  if (bytes >= 1000 * mb) {
    return '${(bytes / (1000 * mb)).toStringAsFixed(1)} GB';
  }
  if (bytes >= mb) {
    return '${(bytes / mb).round()} MB';
  }
  return '${(bytes / 1000).round()} KB';
}
