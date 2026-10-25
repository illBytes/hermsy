import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/chat_message.dart';
import '../services/agent_label.dart';
import '../services/app_settings.dart';
import '../services/audio_delivery.dart';
import '../services/conversation_store.dart';
import '../services/delivery_inbox.dart';
import '../services/hermes_client.dart';
import '../services/image_delivery.dart';
import '../services/message_actions.dart';
import '../services/proactive_reply.dart';
import '../services/resume_reply.dart';
import '../services/frank_haptics.dart';
import '../services/slash_commands.dart';
import '../services/tool_activity.dart';
import '../services/usage_report.dart';
import '../services/voice_service.dart';
import '../voice/mic_capture.dart';
import '../voice/on_device_voice.dart';
import '../voice/spoken_text.dart' show withoutEndMarker;
import 'assistant_mood.dart';

class ChatController extends ChangeNotifier {
  ChatController({
    required this.config,
    required this.client,
    this._preferences,
    ConversationStore? store,
    DeliveryInbox? inbox,
    VoiceService? voice,
    this.haptics,
    this.settings,
    this.onDeviceVoice,
  })  : voice = voice ?? VoiceService(),
        _store = store,
        _inbox = inbox;

  final AppConfig config;
  final HermesClient client;
  final VoiceService voice;
  final FrankHaptics? haptics;
  final AppSettings? settings;

  /// Parakeet on the phone. Once its models are downloaded the mic dictates
  /// with it into the composer instead of sending a voice note.
  final OnDeviceVoice? onDeviceVoice;

  SharedPreferences? _preferences;
  ConversationStore? _store;
  DeliveryInbox? _inbox;
  final _messages = _CountedList<ChatMessage>();
  // The visible messages, rebuilt only after the list itself changes (not on
  // every streamed token, which edits a message in place).
  List<ChatMessage> _visible = const [];
  int _visibleVersion = -1;
  StreamSubscription<HermesStreamEvent>? _stream;
  // Session chat on Hermes 0.20 stamps the virtual alias "hermes-agent" onto
  // new sessions and the provider then 400s. Completions without a model uses
  // whatever the gateway is already configured to run.
  bool _useCompletionsFallback = true;
  bool _didTransientRetry = false;
  bool _userStopped = false;
  bool _handlingDrop = false;
  bool _bootstrapped = false;
  bool _foreground = true;
  bool _pausedByBackground = false;
  bool _resuming = false;
  int _streamGen = 0;
  String? _lastPrompt;

  /// [_lastPrompt] as sent to Hermes: a reply thread's first message also
  /// carries the message it answers.
  String? _lastWire;

  /// The per-turn instruction [send] was given (a call's), for retries.
  String? _lastSystem;

  /// While a live call runs: replies are spoken on the phone by the call,
  /// so Hermes's own speech is not fetched or played. Listeners hear when
  /// it starts and ends.
  bool get inCall => _inCall;
  var _inCall = false;
  set inCall(bool value) {
    if (value == _inCall) {
      return;
    }
    _inCall = value;
    notifyListeners();
  }

  final _turnEvents = StreamController<TurnEvent>.broadcast();

  /// The reply as it streams in, for the live call to speak.
  Stream<TurnEvent> get turnEvents => _turnEvents.stream;

  final _dictations = StreamController<String>.broadcast();

  /// Words the on-device mic heard, for the composer to insert.
  Stream<String> get dictations => _dictations.stream;
  List<String> _lastImagePaths = const [];
  String? _pendingSpeechText;
  StreamSubscription<void>? _playback;
  StreamSubscription<double>? _levelFeed;
  StreamSubscription<String>? _wordsFeed;
  // Bumped by every voice take and every cancel, so a result that arrives
  // for a take that was dropped or replaced is ignored.
  int _voiceGen = 0;
  // Bumped when a pending server transcription is cancelled.
  int _transcribeGen = 0;
  // An on-device take is open: listening, or waiting for its final words.
  bool _dictating = false;
  bool _transcribing = false;
  // The server recorder is still opening (permission prompt, platform start).
  Future<String?>? _micOpening;
  // Completes once the latest server take has finished opening the mic and,
  // if it was cancelled meanwhile, closing it again. The next take waits for
  // it, so a stale take's cleanup never stops a newer recording.
  Future<void>? _micSettling;
  // The reply speakMessage is synthesizing, before its audio plays.
  String? _pendingSpeechId;
  // Bumped by stopSpeaking (and a new speak/play), so speech that is still
  // downloading or synthesizing does not start playing afterwards.
  int _speechGen = 0;

  String? sessionId;
  String? conversationId;
  String? sessionKey;
  String? status;
  String? error;
  String? playingId;

  /// The reply that [speakMessage] is still preparing (synthesizing or
  /// downloading), so its Speak control can already offer Stop.
  String? get pendingSpeechId => _pendingSpeechId;
  bool connected = false;
  bool loading = true;
  bool sending = false;
  bool recording = false;
  bool hasAudioApi = false;
  bool historyLoading = false;
  bool _replyWithVoice = false;
  bool _skipAutoSpeak = false;
  String? conversationTitle;
  bool titleCustom = false;

  /// The name Hermes gave this chat's session (see [_adoptHermesTitle]).
  String? hermesTitle;

  /// When to look for Hermes's title after a reply: it writes a quick one
  /// at once and a better one from its model a few seconds later.
  @visibleForTesting
  List<Duration> titleChecks = const [
    Duration(seconds: 2),
    Duration(seconds: 6),
    Duration(seconds: 15),
  ];
  String draftText = '';
  List<String> draftImagePaths = [];
  DateTime? _conversationUpdatedAt;
  Timer? _draftPersist;
  HermesUsage conversationUsage = const HermesUsage();
  HermesUsage? lastTurnUsage;
  String agentName = 'Hermes';
  String? agentModel;
  List<ConversationSummary> history = [];

  String get agentLabel => formatAgentLabel(name: agentName, model: agentModel);

  String? get modelLabel => prettyModelName(agentModel);

  List<ChatMessage> get messages {
    if (_visibleVersion != _messages.version) {
      _visible = List.unmodifiable(_messages.where((m) => m.isVisible));
      _visibleVersion = _messages.version;
    }
    return _visible;
  }

  /// Mic loudness from 0 (silence) to 1 (shouting), smoothed, while Frank is
  /// listening. The edge glow, orb, and composer waveform breathe with it.
  final ValueNotifier<double> voiceLevel = ValueNotifier<double>(0);

  /// Words heard so far while on-device dictation is listening. Empty when
  /// the server records instead (Hermes transcribes after you stop).
  final ValueNotifier<String> liveTranscript = ValueNotifier<String>('');

  /// Total characters streamed into Frank's replies since this controller
  /// started. It only grows, so the glow can diff it to pulse per token.
  final ValueNotifier<int> streamedChars = ValueNotifier<int>(0);

  /// True when the mic uses on-device dictation instead of server STT. During
  /// a take it reports the path that take actually uses.
  bool get onDeviceDictation =>
      recording || _dictating ? _dictating : !hasAudioApi && !_dictatesOnPhone;

  bool get _dictatesOnPhone => onDeviceVoice?.available ?? false;

  MicCapture? _localTake;
  Completer<void>? _localOpening;
  final _localSamples = <Float32List>[];
  StreamSubscription<Float32List>? _localSampleFeed;
  StreamSubscription<double>? _localLevelFeed;

  /// One answer to "what is Frank doing?" for the glow, orb, and header.
  AssistantMood get mood => resolveMood(
        recording: recording,
        sending: sending,
        messages: _messages,
        status: status,
        playingId: playingId,
        error: error,
      );

  /// The tool line of the streaming reply ("🔍 Web search: …"), if any.
  String? get toolLabel => activeToolLabel(_messages);

  static const _sessionPrefKey = 'hermes.session_id';

  /// The chat [_sessionPrefKey] belongs to; a stored session is reused only
  /// by that chat.
  static const _sessionKeyPrefKey = 'hermes.session_key';
  static const _conversationPrefKey = 'frank.conversation_id';

  /// Per Inbox record: the conversation that replies to it.
  static const _replyThreadPrefKey = 'frank.reply_thread.';

  Future<void> start() async {
    if (sending || _pausedByBackground) {
      return;
    }
    if (_bootstrapped && connected) {
      unawaited(resumeAfterForeground());
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      if (!config.looksConfigured) {
        throw HermesException(
          'Set the Hermes URL and API key in Settings.',
        );
      }
      _preferences ??= await SharedPreferences.getInstance();
      _store ??= await ConversationStore.open();
      await _restoreConversation(importRemote: false);
      final health = await client.ping();
      agentName = agentNameFromHealth(health.platform);
      connected = true;
      hasAudioApi = await client.supportsAudioApi();
      if (conversationId == null) {
        await _restoreConversation(importRemote: true);
      }
      await refreshHistory();
      await _refreshAgent();
      status = null;
      _bootstrapped = true;
    } on SessionsUnsupported {
      _useCompletionsFallback = true;
      connected = true;
      status = 'Using compatibility chat mode';
      history = await _store?.list() ?? history;
      await _refreshAgent();
      _bootstrapped = true;
    } catch (err) {
      connected = false;
      error = err.toString();
      history = await _store?.list() ?? history;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> send(
    String raw, {
    bool fromVoice = false,
    String? audioPath,
    List<String> imagePaths = const [],
    String? systemMessage,
  }) async {
    final text = raw.trim();
    final keptImages = <String>[];
    for (final path in imagePaths) {
      if (path.trim().isEmpty) {
        continue;
      }
      try {
        keptImages.add(await persistLocalImage(path));
      } catch (_) {
        keptImages.add(path);
      }
    }
    if ((text.isEmpty && keptImages.isEmpty) || sending) {
      return;
    }

    _clearDraft();

    final slash = parseSlash(text);
    if (slash != null && keptImages.isEmpty) {
      await _handleSlash(slash, original: text);
      return;
    }

    final wire = hermesPromptFor(_messages, text, title: conversationTitle);
    sending = true;
    _didTransientRetry = false;
    _userStopped = false;
    _lastPrompt = text;
    _lastWire = wire;
    _lastSystem = systemMessage;
    _lastImagePaths = keptImages;
    _bindSessionKey();
    _replyWithVoice = (fromVoice || audioPath != null) && hasAudioApi;
    error = null;
    haptics?.send();
    final user = ChatMessage(
      id: _id('user'),
      role: MessageRole.user,
      text: text,
      isVoice: fromVoice || audioPath != null,
      audioPath: audioPath,
      imagePaths: keptImages,
    );
    final assistant = ChatMessage(
      id: _id('asst'),
      role: MessageRole.assistant,
      text: '',
      streaming: true,
    );
    _messages.addAll([user, assistant]);
    status = 'Hermsy is typing';
    notifyListeners();
    unawaited(_persist());

    try {
      if (!_useCompletionsFallback && sessionId == null) {
        await _ensureSession();
      }
      final useCompletions = _useCompletionsFallback ||
          sessionId == null ||
          keptImages.isNotEmpty;
      final stream = useCompletions
          ? client.streamCompletions(
              message: wire,
              imagePaths: keptImages,
              systemMessage: systemMessage,
            )
          : client.streamSessionChat(
              sessionId: sessionId!,
              message: wire,
              systemMessage: systemMessage,
            );

      await _stream?.cancel();
      _attachStream(
        stream: stream,
        user: user,
        assistant: assistant,
        text: wire,
      );
    } on SessionsUnsupported {
      _useCompletionsFallback = true;
      await _retryWithCompletions(user, assistant, wire);
    } catch (err) {
      _fail(assistant, friendlyStreamError(err));
    }
  }

  Future<void> retry() async {
    if (sending || loading) {
      return;
    }
    final last = _messages.isNotEmpty ? _messages.last : null;
    if (last != null && last.isAssistant && (last.error || error != null)) {
      await retryMessage(last);
      return;
    }
    await start();
  }

  Future<void> stopReply() async {
    if (!sending) {
      return;
    }
    _userStopped = true;
    _streamGen++;
    await _stream?.cancel();
    _stream = null;
    sending = false;
    status = null;
    for (final message in _messages) {
      if (message.streaming) {
        message.streaming = false;
        message.toolStatus = null;
        if (message.text.trim().isEmpty) {
          message.text = 'Stopped.';
        }
      }
    }
    _turnEvents.add(const TurnEvent.done());
    notifyListeners();
    unawaited(_persist());
  }

  Future<void> retryMessage(ChatMessage message) async {
    if (sending || loading) {
      return;
    }
    final target = retryTarget(_messages, message);
    if (target == null) {
      return;
    }
    _messages.removeRange(target.removeFrom, _messages.length);
    error = null;
    notifyListeners();
    await send(
      target.prompt,
      fromVoice: target.fromVoice,
      audioPath: target.audioPath,
      imagePaths: target.imagePaths,
    );
  }

  Future<void> speakMessage(ChatMessage message) async {
    if (message.hasAudio ||
        message.remoteAudio != null ||
        extractAudioRefs(message.text).isNotEmpty) {
      await playMessage(message);
      return;
    }
    final spoken = copyableText(message);
    if (spoken.isEmpty) {
      return;
    }
    final speech = ++_speechGen;
    _pendingSpeechId = message.id;
    try {
      _listenPlayback();
      await voice.preparePlayback();
      if (speech != _speechGen) {
        return;
      }
      status = 'Speaking…';
      notifyListeners();
      final bytes = await client.synthesizeSpeech(spoken);
      message.audioPath = await voice.writeSpeechBytes(bytes, extension: 'mp3');
      message.isVoice = true;
      hasAudioApi = true;
      if (speech != _speechGen) {
        // Stopped while synthesizing: keep the voice note, stay quiet.
        unawaited(_persist());
        return;
      }
      _pendingSpeechId = null;
      playingId = message.id;
      notifyListeners();
      unawaited(_persist());
      await voice.play(message.audioPath!);
    } on AudioUnsupported {
      hasAudioApi = false;
      error = 'Hermes has no speech API to read this aloud.';
    } catch (err) {
      if (speech == _speechGen) {
        error = 'Could not speak that message. $err';
      }
    } finally {
      if (speech == _speechGen) {
        _pendingSpeechId = null;
        _clearSpeechStatus();
      }
      notifyListeners();
    }
  }

  Future<void> newChat({bool saveCurrent = true}) async {
    _userStopped = true;
    await _stream?.cancel();
    _stream = null;
    await _flushDraftPersist();
    if (saveCurrent) {
      await _persist();
    }
    sending = false;
    status = null;
    error = null;
    conversationTitle = null;
    titleCustom = false;
    hermesTitle = null;
    _clearDraft();
    _conversationUpdatedAt = null;
    _messages.clear();
    conversationId = _id('convo');
    sessionId = null;
    client.useTranscript(null);
    conversationUsage = const HermesUsage();
    lastTurnUsage = null;
    _useSessionKey(hermesSessionKey(conversationId!));
    await _preferences?.remove(_sessionPrefKey);
    await _preferences?.remove(_sessionKeyPrefKey);
    await _preferences?.setString(_conversationPrefKey, conversationId!);
    notifyListeners();
  }

  /// Opens the thread for replying to [record], a message Hermes sent on its
  /// own: the thread it already has, or a new one that starts with the
  /// message. The first reply hands Hermes the message as context.
  Future<void> replyTo(DeliveryRecord record) async {
    if (sending) {
      return;
    }
    final key = '$_replyThreadPrefKey${record.id}';
    final existing = _preferences?.getString(key);
    if (existing != null) {
      final saved = await _store?.read(existing);
      if (saved != null) {
        if (saved.id != conversationId) {
          await openConversation(saved.summary);
        }
        return;
      }
    }
    await newChat();
    conversationTitle = record.title;
    titleCustom = true;
    _messages.add(
      ChatMessage(
        id: '$proactiveMessagePrefix${record.id}',
        role: MessageRole.assistant,
        text: record.body,
        createdAt: record.createdAt,
      ),
    );
    await _preferences?.setString(key, conversationId!);
    notifyListeners();
    await _persist();
  }

  Future<void> refreshHistory() async {
    historyLoading = true;
    notifyListeners();
    history = arrangeConversations(await _store?.list() ?? []);
    historyLoading = false;
    notifyListeners();
  }

  Future<void> openConversation(ConversationSummary item) async {
    if (sending || item.id == conversationId) {
      return;
    }
    _userStopped = true;
    await _stream?.cancel();
    _stream = null;
    await _flushDraftPersist();
    await _persist();
    sending = false;
    status = null;
    error = null;

    final local = await _store?.read(item.id);
    if (local != null) {
      _applyRecord(local);
      unawaited(_refreshAgent().then((_) => notifyListeners()));
      notifyListeners();
      // A chat from before Frank used Hermes's names picks its name up.
      if (local.hermesTitle == null) {
        unawaited(_adoptHermesTitle(checks: const [Duration.zero]));
      }
      return;
    }

    final remoteId = item.remoteSessionId ??
        (item.id.startsWith('hermes_') ? item.id.substring(7) : null);
    if (remoteId == null) {
      error = 'That conversation is no longer on this phone.';
      notifyListeners();
      return;
    }

    try {
      final messages = await client.loadMessages(remoteId);
      final record = ConversationRecord(
        id: hermesConversationId(remoteId),
        title: item.title,
        updatedAt: DateTime.now(),
        messages: messages,
        remoteSessionId: remoteId,
      );
      await _store?.write(record);
      _applyRecord(record);
      await refreshHistory();
    } catch (err) {
      error = err.toString();
    }
    notifyListeners();
  }

  Future<void> deleteConversation(ConversationSummary item) async {
    history = [
      for (final entry in history)
        if (entry.id != item.id) entry,
    ];
    notifyListeners();
    if (item.id == conversationId) {
      await newChat(saveCurrent: false);
    }
    await _store?.delete(item.id);
  }

  Future<void> renameConversation(ConversationSummary item, String raw) async {
    final title = sanitizeConversationTitle(raw);
    if (title == null || item.isRemoteOnly) {
      return;
    }
    if (item.id == conversationId) {
      conversationTitle = title;
      titleCustom = true;
    }
    history = [
      for (final entry in history)
        entry.id == item.id
            ? entry.copyWith(title: title, titleCustom: true)
            : entry,
    ];
    notifyListeners();
    await _store?.setTitle(item.id, title);
  }

  Future<void> togglePin(ConversationSummary item) async {
    if (item.isRemoteOnly) {
      return;
    }
    final pinned = !item.pinned;
    history = arrangeConversations([
      for (final entry in history)
        entry.id == item.id ? entry.copyWith(pinned: pinned) : entry,
    ]);
    notifyListeners();
    await _store?.setPinned(item.id, pinned);
  }

  bool get canDeleteChat => conversationId != null || _messages.isNotEmpty;

  Future<void> deleteCurrentChat() async {
    final id = conversationId;
    if (id != null) {
      await deleteConversation(
        ConversationSummary(
          id: id,
          title: '',
          updatedAt: DateTime.now(),
        ),
      );
      return;
    }
    await newChat(saveCurrent: false);
  }

  Future<void> startVoice() async {
    // A take that is still transcribing (or settling its final words) owns
    // the pipeline until its words are sent; a second take would be dropped.
    if (sending || recording || _dictating || _transcribing) {
      return;
    }
    if (_dictatesOnPhone) {
      await _startPhoneDictation();
      return;
    }
    final take = ++_voiceGen;
    final onDevice = !hasAudioApi;
    error = null;
    recording = true;
    _dictating = onDevice;
    _haltSpeech();
    // Frank stops talking now, not once the mic opens: if the mic cannot
    // open (permission denied), the voice must not play on without a Stop.
    unawaited(_quietPlayback());
    status = onDevice ? 'Listening…' : 'Recording… hold or tap again to send';
    _followVoiceSignals();
    haptics?.muted = true;
    haptics?.listenStart();
    notifyListeners();
    try {
      if (!onDevice) {
        final previous = _micSettling;
        final settled = Completer<void>();
        _micSettling = settled.future;
        try {
          final opening = _micOpening = _openMic(take, after: previous);
          String? opened;
          try {
            opened = await opening;
          } finally {
            if (identical(_micOpening, opening)) {
              _micOpening = null;
            }
          }
          if (take != _voiceGen && opened != null) {
            // Cancelled before the mic finished opening: keep nothing.
            await voice.cancelRecording();
          }
        } finally {
          settled.complete();
          if (identical(_micSettling, settled.future)) {
            _micSettling = null;
          }
        }
        return;
      }
      final transcript = await voice.listenOnDevice();
      if (take != _voiceGen) {
        return;
      }
      _dictating = false;
      recording = false;
      status = null;
      _resetVoiceSignals();
      notifyListeners();
      if (transcript.trim().isEmpty) {
        error = 'No speech detected.';
        haptics?.error();
        notifyListeners();
        return;
      }
      await send(transcript, fromVoice: true);
    } catch (err) {
      if (take != _voiceGen) {
        return;
      }
      _dictating = false;
      recording = false;
      status = null;
      _resetVoiceSignals();
      error = err.toString();
      haptics?.error();
      notifyListeners();
    }
  }

  /// Dictation with Parakeet: the mic records into memory, and on stop the
  /// words go into the composer ([dictations]) to edit before sending.
  Future<void> _startPhoneDictation() async {
    final take = ++_voiceGen;
    error = null;
    recording = true;
    _haltSpeech();
    unawaited(_quietPlayback());
    status = 'Listening…';
    haptics?.muted = true;
    haptics?.listenStart();
    notifyListeners();
    // Parakeet loads while you talk, so it is ready when you stop.
    unawaited(onDeviceVoice!.ears().then((_) {}, onError: (_) {}));
    final opening = _localOpening = Completer<void>();
    try {
      final capture = await MicCapture.start();
      if (take != _voiceGen) {
        await capture.stop();
        return;
      }
      _localTake = capture;
      _localSamples.clear();
      _localSampleFeed = capture.samples.listen(_localSamples.add);
      _localLevelFeed = capture.levels.listen((level) {
        if (recording) {
          voiceLevel.value = level;
        }
      });
    } catch (err) {
      if (take == _voiceGen) {
        recording = false;
        status = null;
        _resetVoiceSignals();
        error = '$err';
        haptics?.error();
        notifyListeners();
      }
    } finally {
      opening.complete();
      if (identical(_localOpening, opening)) {
        _localOpening = null;
      }
    }
  }

  /// Closes the dictation mic and returns what it recorded.
  Future<Float32List> _closePhoneTake() async {
    await _localOpening?.future;
    final capture = _localTake;
    _localTake = null;
    try {
      await capture?.stop();
    } catch (_) {}
    await _localSampleFeed?.cancel();
    await _localLevelFeed?.cancel();
    _localSampleFeed = null;
    _localLevelFeed = null;
    final total = _localSamples.fold(0, (sum, chunk) => sum + chunk.length);
    final all = Float32List(total);
    var offset = 0;
    for (final chunk in _localSamples) {
      all.setAll(offset, chunk);
      offset += chunk.length;
    }
    _localSamples.clear();
    return all;
  }

  Future<void> _stopPhoneDictation() async {
    recording = false;
    _resetVoiceSignals();
    haptics?.listenSend();
    _transcribing = true;
    status = 'Transcribing…';
    notifyListeners();
    final ticket = _transcribeGen;
    void settle() {
      _transcribing = false;
      status = null;
    }

    try {
      final samples = await _closePhoneTake();
      // Under a third of a second is a tap, not speech.
      if (samples.length < 16000 ~/ 3) {
        if (ticket == _transcribeGen) {
          settle();
          notifyListeners();
        }
        return;
      }
      final ears = await onDeviceVoice!.ears();
      final text = await ears.transcribe(samples);
      if (ticket != _transcribeGen) {
        return;
      }
      settle();
      if (text.trim().isEmpty) {
        error = 'No speech detected.';
        haptics?.error();
      } else {
        _dictations.add(text.trim());
      }
      notifyListeners();
    } catch (err) {
      if (ticket != _transcribeGen) {
        return;
      }
      settle();
      error = 'Could not transcribe on this phone: $err';
      haptics?.error();
      notifyListeners();
    } finally {
      onDeviceVoice!.releaseSoon();
    }
  }

  /// Opens the server recorder for [take] once the take before it has fully
  /// opened and closed. Null when the take was cancelled while it waited.
  Future<String?> _openMic(int take, {Future<void>? after}) async {
    if (after != null) {
      await after;
    }
    if (take != _voiceGen) {
      return null;
    }
    return voice.startRecording();
  }

  Future<void> _quietPlayback() async {
    try {
      await voice.stopPlayback();
    } catch (_) {}
  }

  /// Stops Frank's voice wherever it started: playback, and speech that is
  /// still downloading or being synthesized.
  Future<void> stopSpeaking() async {
    _haltSpeech();
    notifyListeners();
    try {
      await voice.stopPlayback();
    } catch (_) {}
  }

  /// Drops the recording or dictation without sending anything: no
  /// transcription, no message, and the server recording is deleted. Also
  /// drops a server transcription that is still in flight.
  Future<void> cancelVoice() async {
    if (_localTake != null ||
        _localOpening != null ||
        (_transcribing && _dictatesOnPhone)) {
      _voiceGen++;
      _transcribeGen++;
      _transcribing = false;
      recording = false;
      status = null;
      _resetVoiceSignals();
      haptics?.listenCancel();
      notifyListeners();
      await _closePhoneTake();
      return;
    }
    final wasRecording = recording;
    final dictating = _dictating;
    final transcribing = _transcribing && !wasRecording;
    if (!wasRecording && !dictating && !transcribing) {
      return;
    }
    _voiceGen++;
    if (transcribing) {
      _transcribeGen++;
      _transcribing = false;
    }
    recording = false;
    _dictating = false;
    status = null;
    _resetVoiceSignals();
    haptics?.listenCancel();
    notifyListeners();
    try {
      if (dictating) {
        await voice.cancelDeviceListen();
      } else if (wasRecording) {
        await voice.cancelRecording();
      }
    } catch (_) {}
  }

  Future<void> stopVoice() async {
    if (!recording) {
      return;
    }
    if (_localTake != null || _localOpening != null) {
      await _stopPhoneDictation();
      return;
    }
    recording = false;
    _resetVoiceSignals(keepWords: _dictating);
    haptics?.listenSend();
    if (_dictating) {
      // The recognizer settles its final words, then startVoice sends them.
      status = 'Transcribing…';
      notifyListeners();
      try {
        await voice.stopDeviceListen();
      } catch (_) {}
      return;
    }
    // From release until the words are sent (or fail), this take owns the
    // voice pipeline: Frank reads as transcribing at once (no idle gap while
    // the recorder finalizes), a new take waits, and Cancel drops this one.
    _transcribing = true;
    status = 'Transcribing…';
    notifyListeners();
    final ticket = _transcribeGen;
    bool dropped() => ticket != _transcribeGen;
    void settle() {
      _transcribing = false;
      status = null;
    }

    final opening = _micOpening;
    if (opening != null) {
      // Released while the mic was still opening: stop only once it is open.
      try {
        await opening;
      } catch (_) {
        if (!dropped()) {
          settle();
          notifyListeners();
        }
        return; // startVoice reports why it could not open.
      }
    }
    try {
      final path = await voice.stopRecording();
      if (dropped()) {
        if (path != null) {
          await voice.discard(path);
        }
        return;
      }
      if (path == null) {
        settle();
        notifyListeners();
        return;
      }
      final transcript = await client.transcribe(path);
      if (dropped()) {
        await voice.discard(path);
        return;
      }
      if (transcript.isEmpty) {
        settle();
        error = 'No speech detected.';
        haptics?.error();
        notifyListeners();
        return;
      }
      final kept = await voice.keepRecording(path);
      if (dropped()) {
        return;
      }
      settle();
      await send(transcript, fromVoice: true, audioPath: kept);
    } on AudioUnsupported {
      hasAudioApi = false;
      if (dropped()) {
        return;
      }
      settle();
      error = 'Hermes has no speech API on this version. Tap the mic to use on-device dictation.';
      haptics?.error();
      notifyListeners();
    } catch (err) {
      if (dropped()) {
        return;
      }
      _transcribing = false;
      status = null;
      error = err.toString();
      haptics?.error();
      notifyListeners();
    }
  }

  void _followVoiceSignals() {
    _levelFeed ??= voice.levels.listen((level) {
      // Late samples can trail the mic closing; the level rests at 0 then.
      if (recording) {
        voiceLevel.value = level;
      }
    });
    _wordsFeed ??= voice.partials.listen((words) {
      if (_dictating) {
        liveTranscript.value = words;
      }
    });
  }

  /// The mic closed: the level rests at 0, ambient haptics come back, and
  /// the live words clear unless [keepWords] (they stay on screen until the
  /// final words are sent).
  void _resetVoiceSignals({bool keepWords = false}) {
    voiceLevel.value = 0;
    if (!keepWords) {
      liveTranscript.value = '';
    }
    haptics?.muted = false;
  }

  void _haltSpeech() {
    _speechGen++;
    playingId = null;
    _pendingSpeechId = null;
    _clearSpeechStatus();
  }

  void _clearSpeechStatus() {
    if (status == 'Speaking…' || status == 'Fetching voice…') {
      status = null;
    }
  }

  Future<void> playMessage(ChatMessage message) async {
    _speechGen++;
    _listenPlayback();
    if (playingId == message.id) {
      await voice.stopPlayback();
      playingId = null;
      notifyListeners();
      return;
    }
    try {
      await voice.preparePlayback();
      final local = message.audioPath;
      if (local != null &&
          await File(local).exists() &&
          voice.canPlayExtension(local.split('.').last)) {
        playingId = message.id;
        notifyListeners();
        await voice.play(local);
        return;
      }
      await _deliverAudio(message, play: true);
    } catch (err) {
      playingId = null;
      error = 'Could not play that voice note. $err';
      notifyListeners();
    }
  }

  Future<void> _handleSlash(ParsedSlash slash, {required String original}) async {
    if (slash.name == '/new' || slash.name == '/reset' || slash.name == '/clear') {
      await newChat();
      return;
    }
    _messages.add(
      ChatMessage(id: _id('user'), role: MessageRole.user, text: original),
    );
    notifyListeners();

    try {
      final reply = await _slashReply(slash);
      if (reply != null) {
        _messages.add(
          ChatMessage(id: _id('cmd'), role: MessageRole.assistant, text: reply),
        );
      }
    } catch (err) {
      _messages.add(
        ChatMessage(
          id: _id('cmd'),
          role: MessageRole.assistant,
          text: err.toString(),
          error: true,
        ),
      );
    }
    notifyListeners();
    unawaited(_persist());
  }

  Future<String?> _slashReply(ParsedSlash slash) async {
    switch (slash.name) {
      case '/help':
        return supportedSlashHelp;
      case '/new':
      case '/reset':
      case '/clear':
        await newChat();
        return 'Started a new chat.';
      case '/stop':
        await stopReply();
        return 'Stopped.';
      case '/undo':
        _undoLastExchange();
        return 'Removed the last exchange.';
      case '/usage':
        return _usageText();
      case '/status':
        return _statusText();
      default:
        return '${slash.name} is a Telegram/CLI gateway command.\n'
            'Hermsy talks to the HTTP API, which does not run that dispatcher.\n\n'
            'Try /help for the commands that work here.';
    }
  }

  void _undoLastExchange() {
    if (_messages.isNotEmpty && _messages.last.isUser) {
      _messages.removeLast();
    }
    while (_messages.isNotEmpty && _messages.last.isAssistant) {
      _messages.removeLast();
    }
    if (_messages.isNotEmpty && _messages.last.isUser) {
      _messages.removeLast();
    }
  }

  Future<String> _usageText() async {
    _rememberHermesSession();
    final localTurns = _messages.where((m) => m.isUser).length;
    HermesUsage? sessionUsage;
    final id = sessionId ?? client.transcriptSessionId;
    if (id != null && id.isNotEmpty) {
      try {
        sessionUsage = (await client.getSession(id)).usage;
      } catch (_) {}
    }
    HermesUsage? recent;
    try {
      recent = await client.fetchAnalyticsUsage(days: 7);
    } catch (_) {}
    return formatUsageReport(
      session: sessionUsage,
      conversation: conversationUsage.hasTokens ? conversationUsage : null,
      lastTurn: lastTurnUsage,
      recent: recent,
      localTurns: localTurns,
    );
  }

  void _rememberHermesSession() {
    final id = client.lastSessionId;
    // Only a session learned in this chat (see HermesClient.lastSessionKey).
    if (id == null || id.isEmpty || client.lastSessionKey != sessionKey) {
      return;
    }
    if (sessionId == id) {
      client.useTranscript(id);
      return;
    }
    sessionId = id;
    client.useTranscript(id);
    _rememberStoredSession(id);
  }

  void _applyUsage(HermesUsage? usage) {
    if (usage == null) {
      return;
    }
    _rememberModel(usage.model);
    if (!usage.hasTokens && !usage.hasCost) {
      return;
    }
    lastTurnUsage = usage;
    conversationUsage = conversationUsage + usage;
  }

  void _rememberModel(String? model) {
    if (prettyModelName(model) == null) {
      return;
    }
    if (agentModel == model) {
      return;
    }
    agentModel = model;
  }

  Future<void> _refreshAgent() async {
    final named = agentNameFromSessionKey(sessionKey ?? client.sessionKey);
    if (named != null) {
      agentName = named;
    }
    if (sessionId != null && sessionId!.isNotEmpty) {
      try {
        _rememberModel((await client.getSession(sessionId!)).model);
        return;
      } catch (_) {}
    }
    try {
      for (final session in await client.listSessions()) {
        if (prettyModelName(session.model) != null) {
          _rememberModel(session.model);
          return;
        }
      }
    } catch (_) {}
  }

  Future<String> _statusText() async {
    final lines = <String>[
      'Status',
      'Connected: $connected',
      'Server: ${config.baseUrl}',
      'Chat path: OpenAI-compatible API (not Telegram)',
    ];
    if (sessionId != null) {
      lines.add('Session: $sessionId');
      try {
        final session = await client.getSession(sessionId!);
        if (session.title != null) {
          lines.add('Title: ${session.title}');
        }
        if (session.model != null) {
          lines.add('Stored model label: ${session.model}');
        }
        lines.add('Messages: ${session.messageCount ?? _messages.length}');
      } catch (_) {}
    } else {
      lines.add('Session: none');
    }
    return lines.join('\n');
  }

  @override
  void dispose() {
    unawaited(_turnEvents.close());
    unawaited(_dictations.close());
    unawaited(_localTake?.stop());
    _draftPersist?.cancel();
    unawaited(_stream?.cancel());
    unawaited(_playback?.cancel());
    unawaited(_levelFeed?.cancel());
    unawaited(_wordsFeed?.cancel());
    haptics?.muted = false;
    voice.dispose();
    voiceLevel.dispose();
    liveTranscript.dispose();
    streamedChars.dispose();
    client.close();
    super.dispose();
  }

  Future<void> saveDraft() => _flushDraftPersist();

  void setDraft({
    String? text,
    List<String>? imagePaths,
    bool persistNow = false,
  }) {
    var changed = false;
    if (text != null && text != draftText) {
      draftText = text;
      changed = true;
    }
    if (imagePaths != null && !listEquals(imagePaths, draftImagePaths)) {
      draftImagePaths = List<String>.from(imagePaths);
      changed = true;
    }
    if (!changed) {
      return;
    }
    if (persistNow) {
      _draftPersist?.cancel();
      _draftPersist = null;
      unawaited(_persist(draftOnly: true));
      return;
    }
    _scheduleDraftPersist();
  }

  void setForeground(bool value) {
    _foreground = value;
    if (!value) {
      unawaited(_flushDraftPersist());
      unawaited(_persist());
      return;
    }
    unawaited(resumeAfterForeground());
  }

  Future<void> resumeAfterForeground() async {
    if (_resuming || _userStopped) {
      return;
    }
    final dropped = looksLikeDroppedReply(error);
    if (!_pausedByBackground && !dropped && !sending) {
      return;
    }
    if (sending && !_pausedByBackground && _stream != null) {
      return;
    }
    _resuming = true;
    try {
      await _recoverOrRetry();
    } finally {
      _resuming = false;
    }
  }

  Future<void> _recoverOrRetry() async {
    _pausedByBackground = false;
    _handlingDrop = false;
    ChatMessage? assistant;
    for (final message in _messages) {
      if (message.isAssistant) {
        assistant = message;
      }
    }
    if (assistant == null && _lastPrompt == null && _lastImagePaths.isEmpty) {
      return;
    }
    status = 'Reconnecting…';
    error = null;
    sending = true;
    assistant?.streaming = true;
    assistant?.error = false;
    notifyListeners();

    try {
      final id = sessionId ?? client.transcriptSessionId;
      if (id != null && id.isNotEmpty) {
        final remote = await client.loadMessages(id);
        final recovered = betterRemoteAssistant(
          local: _messages,
          remote: remote,
        );
        if (recovered != null && assistant != null) {
          assistant.text = recovered;
          _finish(assistant);
          return;
        }
      }
    } catch (_) {}

    if ((_lastPrompt == null || _lastPrompt!.isEmpty) &&
        _lastImagePaths.isEmpty) {
      if (assistant != null) {
        _fail(assistant, describeStreamDrop(hadText: assistant.text.trim().isNotEmpty));
      } else {
        sending = false;
        status = null;
        notifyListeners();
      }
      return;
    }

    ChatMessage? user;
    for (final message in _messages) {
      if (message.isUser) {
        user = message;
      }
    }
    user ??= ChatMessage(
      id: _id('user'),
      role: MessageRole.user,
      text: _lastPrompt ?? '',
      imagePaths: _lastImagePaths,
    );
    assistant ??= ChatMessage(
      id: _id('asst'),
      role: MessageRole.assistant,
      text: '',
      streaming: true,
    );
    if (!_messages.contains(user) || !_messages.contains(assistant)) {
      _messages
        ..clear()
        ..addAll([user, assistant]);
    }
    _didTransientRetry = true;
    _bindSessionKey();
    // The turn runs again from the start, tools included.
    assistant.toolTrail.clear();
    try {
      await _stream?.cancel();
      _attachStream(
        stream: client.streamCompletions(
          message: _lastWire ?? _lastPrompt ?? '',
          imagePaths: _lastImagePaths,
          systemMessage: _lastSystem,
        ),
        user: user,
        assistant: assistant,
        text: _lastWire ?? _lastPrompt ?? '',
      );
    } catch (err) {
      _fail(assistant, friendlyStreamError(err));
    }
  }

  void _listenPlayback() {
    _playback ??= voice.onComplete.listen((_) {
      playingId = null;
      notifyListeners();
    });
  }

  Future<void> _deliverAudio(ChatMessage assistant, {required bool play}) async {
    if (assistant.error || _userStopped) {
      _replyWithVoice = false;
      return;
    }
    if (assistant.text.trim() == 'Stopped.') {
      _replyWithVoice = false;
      return;
    }
    _rememberRemoteAudio(assistant);
    final refs = audioRefsOf(assistant.text, remote: assistant.remoteAudio);
    final asked = _replyWithVoice || wantsVoiceReply(_lastPrompt ?? '');
    final autoSpeak = settings?.speakReplies == true && !_skipAutoSpeak;
    if (refs.isEmpty &&
        !asked &&
        !autoSpeak &&
        assistant.audioPath == null &&
        !assistant.isVoice) {
      _replyWithVoice = false;
      return;
    }
    if (asked ||
        refs.isNotEmpty ||
        assistant.audioPath != null ||
        assistant.isVoice) {
      assistant.isVoice = true;
      notifyListeners();
    }

    final speech = _speechGen;
    try {
      _listenPlayback();
      await voice.preparePlayback();
      status = refs.isNotEmpty ? 'Fetching voice…' : 'Speaking…';
      notifyListeners();
      List<int>? bytes;
      var extension = 'mp3';
      for (final ref in refs) {
        final got = await client.fetchAudio(ref);
        if (got != null) {
          bytes = got.bytes;
          extension = got.extension;
          break;
        }
      }
      if (bytes == null && refs.isEmpty) {
        final spoken = _spokenText(assistant);
        if (spoken != null) {
          status = 'Speaking…';
          notifyListeners();
          bytes = await client.synthesizeSpeech(spoken);
          extension = 'mp3';
          hasAudioApi = true;
        }
      }
      if (bytes == null) {
        if (asked || refs.isNotEmpty) {
          error = refs.isNotEmpty
              ? audioFetchFailure(client.lastAudioStatus)
              : 'Hermsy has nothing to play for this reply.';
        } else if (autoSpeak) {
          _skipAutoSpeak = true;
        }
        return;
      }
      assistant
        ..audioPath = await voice.writeSpeechBytes(bytes, extension: extension)
        ..isVoice = true;
      notifyListeners();
      unawaited(_persist());
      if (play && speech == _speechGen) {
        playingId = assistant.id;
        notifyListeners();
        await voice.play(assistant.audioPath!);
      }
    } on AudioUnsupported {
      hasAudioApi = false;
      if (asked) {
        error =
            'Hermes saved this voice note on the server, and this install has no speech download API.';
      } else if (autoSpeak) {
        _skipAutoSpeak = true;
      }
    } catch (err) {
      if (asked) {
        error = 'Could not play that voice note. $err';
      } else if (autoSpeak) {
        _skipAutoSpeak = true;
      }
    } finally {
      _clearSpeechStatus();
      _replyWithVoice = false;
      notifyListeners();
    }
  }

  void _rememberRemoteImages(ChatMessage message) {
    final tokens = <String>{
      ...message.remoteImages,
      for (final ref in extractImageRefs(message.text))
        if (imageRefKey(ref) != null) imageRefKey(ref)!,
    };
    final collapsed = collapseImageRefs([
      for (final token in tokens)
        if (token.isNotEmpty) imageRefFromToken(token),
    ]);
    message.remoteImages
      ..clear()
      ..addAll([
        for (final ref in collapsed)
          if (imageRefKey(ref) != null) imageRefKey(ref)!,
      ]);
  }

  Future<void> _deliverImages(ChatMessage message) async {
    _rememberRemoteImages(message);
    final refs = imageRefsOf(message.text, remote: message.remoteImages);
    if (refs.isEmpty) {
      return;
    }
    var added = false;
    for (final ref in refs) {
      if (alreadyHasImage(message.imagePaths, ref)) {
        continue;
      }
      if (ref.httpUrl != null && ref.httpUrl!.startsWith('http')) {
        if (!message.remoteImages.contains(ref.httpUrl)) {
          message.remoteImages.add(ref.httpUrl!);
          added = true;
        }
      }
      try {
        final got = await client.fetchImage(ref);
        if (got == null) {
          continue;
        }
        final path = await writeImageBytes(
          got.bytes,
          extension: got.extension,
        );
        if (!alreadyHasImage(message.imagePaths, ref) &&
            !message.imagePaths.contains(path)) {
          message.imagePaths.add(path);
          added = true;
        }
      } catch (_) {}
    }
    if (added) {
      notifyListeners();
      unawaited(_persist());
      unawaited(_recordDelivery(message));
    }
  }

  Future<void> _recordDelivery(ChatMessage message) async {
    if (message.imagePaths.isEmpty) {
      return;
    }
    try {
      final inbox = _inbox ??= await DeliveryInbox.open();
      await inbox.rememberChatFiles(
        body: stripImageMarkup(message.text),
        filePaths: List<String>.from(message.imagePaths),
        remotePaths: [
          for (final token in message.remoteImages)
            if (token.isNotEmpty && !token.startsWith('data:')) token,
        ],
        conversationId: conversationId,
      );
    } catch (_) {}
  }

  void _rememberRemoteAudio(ChatMessage message) {
    final remote = firstRemoteAudio(message.text);
    if (remote != null) {
      message.isVoice = true;
      message.remoteAudio ??= remote;
    }
  }

  String? _spokenText(ChatMessage assistant) {
    const fallback =
        'Hermes left the voice file on the server, and Hermsy could not play it.';
    final caption = stripAudioMarkup(assistant.text).trim();
    if (caption.isNotEmpty &&
        caption != fallback &&
        !looksLikeAudioPath(caption)) {
      return caption;
    }
    final pending = _pendingSpeechText?.trim();
    if (pending != null &&
        pending.isNotEmpty &&
        !looksLikeAudioPath(pending)) {
      return pending;
    }
    return null;
  }

  Future<void> _restoreConversation({required bool importRemote}) async {
    final storedId = _preferences?.getString(_conversationPrefKey);
    if (storedId != null && storedId.isNotEmpty) {
      final record = await _store?.read(storedId);
      if (record != null) {
        _applyRecord(record);
        return;
      }
    }
    final recents = await _store?.list() ?? [];
    if (recents.isNotEmpty) {
      final record = await _store?.read(recents.first.id);
      if (record != null) {
        _applyRecord(record);
        return;
      }
    }
    if (!importRemote) {
      return;
    }
    try {
      await _ensureSession();
      if (sessionId == null) {
        return;
      }
      final imported = await client.loadMessages(sessionId!);
      if (imported.isEmpty) {
        return;
      }
      final record = ConversationRecord(
        id: hermesConversationId(sessionId!),
        title: titleFrom(imported),
        updatedAt: DateTime.now(),
        messages: imported,
        remoteSessionId: sessionId,
      );
      await _store?.write(record);
      _applyRecord(record);
    } on SessionsUnsupported {
      // Completions-only installs start empty.
    }
  }

  void _applyRecord(ConversationRecord record) {
    conversationId = record.id;
    sessionId = record.remoteSessionId ??
        (record.id.startsWith('hermes_') ? record.id.substring(7) : sessionId);
    _messages
      ..clear()
      ..addAll(record.messages);
    conversationTitle = record.title;
    titleCustom = record.titleCustom;
    hermesTitle = record.hermesTitle;
    draftText = record.draftText;
    draftImagePaths = List<String>.from(record.draftImagePaths);
    _conversationUpdatedAt = record.updatedAt;
    _useSessionKey(record.sessionKey);
    _preferences?.setString(_conversationPrefKey, record.id);
    if (sessionId != null) {
      _rememberStoredSession(sessionId!);
    }
    client.useTranscript(sessionId);
  }

  void _clearDraft() {
    _draftPersist?.cancel();
    _draftPersist = null;
    draftText = '';
    draftImagePaths = [];
  }

  void _scheduleDraftPersist() {
    _draftPersist?.cancel();
    _draftPersist = Timer(const Duration(milliseconds: 400), () {
      unawaited(_persist(draftOnly: true));
    });
  }

  Future<void> _flushDraftPersist() async {
    if (_draftPersist == null) {
      return;
    }
    _draftPersist?.cancel();
    _draftPersist = null;
    await _persist(draftOnly: true);
  }

  Future<void> _persisting = Future<void>.value();

  /// Saves the chat. Saves run one after another: two at once would both
  /// rewrite the chat list's index and could leave it torn.
  Future<void> _persist({bool draftOnly = false}) {
    final next = _persisting.then((_) => _persistNow(draftOnly: draftOnly));
    _persisting = next.catchError((Object _) {});
    return next;
  }

  Future<void> _persistNow({bool draftOnly = false}) async {
    final store = _store;
    if (store == null) {
      return;
    }
    final saved = _messages
        .where(
          (m) =>
              m.isVisible &&
              (m.isUser || !m.streaming) &&
              (m.hasAudio || m.hasImages || m.text.trim().isNotEmpty),
        )
        .toList();
    final draft = draftText.trim();
    final images = [
      for (final path in draftImagePaths)
        if (path.trim().isNotEmpty) path,
    ];
    if (saved.isEmpty && draft.isEmpty && images.isEmpty) {
      return;
    }
    conversationId ??= _id('convo');
    sessionKey ??= hermesSessionKey(conversationId!);
    var pinned = false;
    for (final item in history) {
      if (item.id == conversationId && item.pinned) {
        pinned = true;
        break;
      }
    }
    final keepDate = draftOnly && _conversationUpdatedAt != null;
    final updatedAt = keepDate ? _conversationUpdatedAt! : DateTime.now();
    final record = ConversationRecord(
      id: conversationId!,
      title: titleForPersist(
        messages: saved,
        titleCustom: titleCustom,
        currentTitle: conversationTitle,
        hermesTitle: hermesTitle,
        draftText: draft,
      ),
      updatedAt: updatedAt,
      messages: saved,
      remoteSessionId: sessionId,
      sessionKey: sessionKey,
      pinned: pinned,
      titleCustom: titleCustom,
      hermesTitle: hermesTitle,
      draftText: draft,
      draftImagePaths: images,
    );
    conversationTitle = record.title;
    _conversationUpdatedAt = updatedAt;
    await store.write(record);
    await _preferences?.setString(_conversationPrefKey, record.id);
    history = arrangeConversations(await store.list());
  }

  void _rememberStoredSession(String id) {
    _preferences?.setString(_sessionPrefKey, id);
    final key = sessionKey;
    if (key != null) {
      _preferences?.setString(_sessionKeyPrefKey, key);
    }
  }

  Future<void> _ensureSession() async {
    _bindSessionKey();
    final stored = _preferences?.getString(_sessionPrefKey);
    if (stored != null &&
        stored.isNotEmpty &&
        _preferences?.getString(_sessionKeyPrefKey) == sessionKey) {
      sessionId = stored;
      client.useTranscript(stored);
      return;
    }

    final stamp = DateTime.now()
        .toIso8601String()
        .replaceFirst('T', ' ')
        .substring(0, 16);
    final created = await client.createSession(
      title: 'Hermsy · $stamp',
    );
    sessionId = created.id;
    client.useTranscript(created.id);
    _rememberStoredSession(created.id);
  }

  void _bindSessionKey() {
    conversationId ??= _id('convo');
    sessionKey ??= hermesSessionKey(conversationId!);
    client.sessionKey = sessionKey!;
    client.useTranscript(sessionId);
  }

  void _useSessionKey(String? key) {
    sessionKey = (key != null && key.isNotEmpty)
        ? key
        : HermesClient.legacySessionKey;
    client.sessionKey = sessionKey!;
    client.useTranscript(sessionId);
  }

  Future<void> _retryWithCompletions(
    ChatMessage user,
    ChatMessage assistant,
    String text,
  ) async {
    // The turn runs again from the start, tools included.
    assistant.toolTrail.clear();
    try {
      await _stream?.cancel();
      _attachStream(
        stream: client.streamCompletions(
          message: text,
          imagePaths: _lastImagePaths,
          systemMessage: _lastSystem,
        ),
        user: user,
        assistant: assistant,
        text: text,
      );
    } catch (err) {
      _fail(assistant, friendlyStreamError(err));
    }
  }

  void _attachStream({
    required Stream<HermesStreamEvent> stream,
    required ChatMessage user,
    required ChatMessage assistant,
    required String text,
  }) {
    _handlingDrop = false;
    var sawTerminal = false;
    final gen = ++_streamGen;
    _stream = stream.listen(
      (event) {
        if (gen != _streamGen) {
          return;
        }
        _rememberHermesSession();
        if (event.kind == HermesEventKind.done ||
            event.kind == HermesEventKind.completed) {
          sawTerminal = true;
        }
        if (event.kind == HermesEventKind.interrupted) {
          unawaited(
            _onStreamDrop(user: user, assistant: assistant, text: text),
          );
          return;
        }
        _applyEvent(assistant, event);
      },
      onError: (Object err) {
        if (gen != _streamGen) {
          return;
        }
        if (err is SessionsUnsupported ||
            isVirtualModelError(err.toString())) {
          _useCompletionsFallback = true;
          unawaited(_retryWithCompletions(user, assistant, text));
          return;
        }
        unawaited(
          _onStreamDrop(
            user: user,
            assistant: assistant,
            text: text,
            error: err,
          ),
        );
      },
      onDone: () {
        if (gen != _streamGen || _userStopped) {
          return;
        }
        if (assistant.streaming && !sawTerminal) {
          unawaited(
            _onStreamDrop(user: user, assistant: assistant, text: text),
          );
          return;
        }
        if (assistant.streaming) {
          _finish(assistant);
        }
      },
      cancelOnError: false,
    );
  }

  Future<void> _onStreamDrop({
    required ChatMessage user,
    required ChatMessage assistant,
    required String text,
    Object? error,
  }) async {
    if (_userStopped || !sending || _handlingDrop) {
      return;
    }
    _handlingDrop = true;
    if (!_foreground && !_userStopped) {
      _pausedByBackground = true;
      _handlingDrop = false;
      await _stream?.cancel();
      _stream = null;
      status = 'Waiting to reconnect';
      notifyListeners();
      unawaited(_persist());
      return;
    }
    final hadText = assistant.text.trim().isNotEmpty;
    if (!hadText && !_didTransientRetry) {
      _didTransientRetry = true;
      // The turn runs again from the start, tools included.
      assistant.toolTrail.clear();
      status = 'Reconnecting…';
      notifyListeners();
      _streamGen++;
      try {
        await _stream?.cancel();
        _attachStream(
          stream: client.streamCompletions(
            message: text,
            imagePaths: _lastImagePaths,
            systemMessage: _lastSystem,
          ),
          user: user,
          assistant: assistant,
          text: text,
        );
      } catch (err) {
        _fail(assistant, friendlyStreamError(err));
      }
      return;
    }
    if (!hadText) {
      _fail(assistant, friendlyStreamError(error ?? describeStreamDrop(hadText: false)));
      return;
    }
    _interrupt(assistant);
  }

  void _applyEvent(ChatMessage assistant, HermesStreamEvent event) {
    switch (event.kind) {
      case HermesEventKind.delta:
        if (event.text != null) {
          _turnEvents.add(TurnEvent.delta(event.text!));
          assistant.text += event.text!;
          assistant.streaming = true;
          streamedChars.value += event.text!.length;
          _rememberRemoteAudio(assistant);
          _rememberRemoteImages(assistant);
          if (assistant.toolStatus == null) {
            status = null;
          }
        }
      case HermesEventKind.tool:
        _turnEvents.add(
          TurnEvent.tool(
            formatToolActivity(
              name: event.toolName,
              label: event.toolLabel,
              emoji: event.toolEmoji,
            ),
            completed: event.toolCompleted,
          ),
        );
        if (event.toolCompleted) {
          assistant.toolStatus = null;
          status = assistant.text.trim().isEmpty ? 'Hermsy is typing' : null;
        } else {
          if (isSpeechTool(event.toolName)) {
            assistant.isVoice = true;
            final label = (event.toolLabel ?? '').trim();
            if (label.isNotEmpty) {
              if (extractAudioRefs(label).isNotEmpty) {
                assistant.remoteAudio ??= firstRemoteAudio(label);
                if (!assistant.text.contains(label)) {
                  assistant.text = assistant.text.trim().isEmpty
                      ? label
                      : '${assistant.text.trim()}\n$label';
                }
              } else {
                _pendingSpeechText = label;
              }
            }
          }
          assistant.toolStatus = formatToolActivity(
            name: event.toolName,
            label: event.toolLabel,
            emoji: event.toolEmoji,
          );
          if (_recordTool(assistant, assistant.toolStatus!)) {
            haptics?.tool();
          }
          status = assistant.toolStatus;
        }
      case HermesEventKind.completed:
        if (event.text != null && event.text!.trim().isNotEmpty) {
          assistant.text = event.text!;
        }
        assistant.toolStatus = null;
        _applyUsage(event.usage);
      case HermesEventKind.done:
        _finish(assistant);
        return;
      case HermesEventKind.error:
        _fail(assistant, event.text ?? 'Hermes returned an error.');
        return;
      case HermesEventKind.interrupted:
        return;
    }
    notifyListeners();
  }

  /// Adds a started tool to the reply's trail (not "Thinking…", not a repeat
  /// of the line before). True when it was added.
  bool _recordTool(ChatMessage assistant, String line) {
    final tool = line.trim();
    if (tool.isEmpty || isThinkingLabel(tool)) {
      return false;
    }
    final trail = assistant.toolTrail;
    if (trail.isNotEmpty && trail.last == tool) {
      return false;
    }
    trail.add(tool);
    return true;
  }

  void _interrupt(ChatMessage assistant) {
    assistant
      ..streaming = false
      ..toolStatus = null;
    sending = false;
    status = null;
    error = describeStreamDrop(hadText: true);
    _stream = null;
    notifyListeners();
    unawaited(_persist());
  }

  void _finish(ChatMessage assistant) {
    assistant.streaming = false;
    assistant.toolStatus = null;
    // A call's goodbye hangs up with a marker that is never shown.
    assistant.text = withoutEndMarker(assistant.text);
    if (assistant.text.trim().isEmpty &&
        !assistant.error &&
        !assistant.isVoice &&
        !assistant.hasImages) {
      assistant.text = 'Hermes finished without a reply.';
    }
    sending = false;
    status = null;
    _stream = null;
    _rememberHermesSession();
    if (prettyModelName(agentModel) == null) {
      unawaited(_refreshAgent().then((_) => notifyListeners()));
    }
    haptics?.done();
    _turnEvents.add(const TurnEvent.done());
    notifyListeners();
    unawaited(_persist());
    if (!inCall) {
      unawaited(_deliverAudio(assistant, play: true));
    }
    unawaited(_deliverImages(assistant));
    unawaited(_adoptHermesTitle());
  }

  /// Hermes names a session from its first exchanges. Unless you renamed
  /// the chat, Frank uses that name instead of your first words. Once a
  /// chat has a name from Hermes, only its first exchanges look again
  /// (Hermes may improve it then).
  Future<void> _adoptHermesTitle({List<Duration>? checks}) async {
    final convo = conversationId;
    final id = sessionId ?? client.transcriptSessionId;
    if (titleCustom ||
        convo == null ||
        id == null ||
        id.isEmpty ||
        (hermesTitle != null && _messages.where((m) => m.isUser).length > 2)) {
      return;
    }
    for (final wait in checks ?? titleChecks) {
      await Future<void>.delayed(wait);
      if (conversationId != convo || titleCustom) {
        return;
      }
      final String? title;
      try {
        title = hermesChatTitle((await client.getSession(id)).title);
      } catch (_) {
        return;
      }
      if (conversationId != convo || titleCustom) {
        return;
      }
      if (title == null || title == hermesTitle) {
        continue;
      }
      hermesTitle = title;
      conversationTitle = title;
      notifyListeners();
      await _persist();
    }
  }

  void _fail(ChatMessage assistant, String message) {
    assistant
      ..streaming = false
      ..error = true
      ..text = assistant.text.trim().isEmpty ? message : assistant.text;
    sending = false;
    status = null;
    error = message;
    _stream = null;
    haptics?.error();
    _turnEvents.add(TurnEvent.failed(message));
    notifyListeners();
    unawaited(_persist());
  }

  String _id(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}';
}

/// A list that counts its structural changes, so [ChatController.messages]
/// can hand out one cached visible list until messages are added, removed
/// or replaced. Every mutation the base class offers funnels through
/// `[]=`, `length=`, `add` or `addAll`.
/// One step of a reply as it streams: text, tool activity, or the end.
class TurnEvent {
  const TurnEvent.delta(String this.text)
    : tool = null,
      toolCompleted = false,
      done = false,
      error = null;
  const TurnEvent.tool(String this.tool, {bool completed = false})
    : text = null,
      toolCompleted = completed,
      done = false,
      error = null;
  const TurnEvent.done()
    : text = null,
      tool = null,
      toolCompleted = false,
      done = true,
      error = null;
  const TurnEvent.failed(String this.error)
    : text = null,
      tool = null,
      toolCompleted = false,
      done = true;

  final String? text;
  final String? tool;
  final bool toolCompleted;

  /// The reply ended (finished, failed or stopped).
  final bool done;
  final String? error;
}

class _CountedList<E> extends ListBase<E> {
  final List<E> _items = [];
  int version = 0;

  @override
  int get length => _items.length;

  @override
  set length(int value) {
    _items.length = value;
    version++;
  }

  @override
  E operator [](int index) => _items[index];

  @override
  void operator []=(int index, E value) {
    _items[index] = value;
    version++;
  }

  @override
  void add(E element) {
    _items.add(element);
    version++;
  }

  @override
  void addAll(Iterable<E> iterable) {
    _items.addAll(iterable);
    version++;
  }
}
