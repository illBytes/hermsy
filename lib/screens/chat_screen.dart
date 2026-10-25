import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/chat_message.dart';
import '../presence/presence_engine.dart';
import '../services/brief_store.dart';
import '../services/conversation_store.dart';
import '../services/image_delivery.dart';
import '../services/message_actions.dart';
import '../services/message_search.dart';
import '../state/assistant_mood.dart';
import '../state/chat_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_drawer.dart';
import '../widgets/chat_empty_state.dart';
import '../widgets/chat_error_strip.dart';
import '../widgets/chat_header.dart';
import '../widgets/composer_bar.dart';
import '../widgets/confirm_delete_chat.dart';
import '../widgets/conversation_sheet.dart';
import '../widgets/day_separator.dart';
import '../widgets/frank_backdrop.dart';
import '../widgets/listening_stage.dart';
import '../widgets/message_actions_sheet.dart';
import '../widgets/message_bubble.dart';
import '../widgets/prompt_rename_chat.dart';
import '../widgets/report_reply.dart';
import '../widgets/scroll_to_latest.dart';
import '../widgets/thread_find_bar.dart';
import '../widgets/ui/frank_ui.dart';
import 'brief_screen.dart';
import 'call_screen.dart';
import 'inbox_screen.dart';
import 'message_reader_screen.dart';
import 'voice_models_screen.dart';

/// Messages from the same speaker this close together sit as one group.
const _groupWindow = Duration(minutes: 2);

/// How far from the newest message the jump-to-latest button appears.
const _awayDistance = 400.0;

/// Within this distance of the newest message, streaming text is followed.
const _followDistance = 120.0;

/// The jump-to-latest disc (44dp) and its gap above the composer.
const _latestButtonClearance = AppSpace.x3 + 44.0;

/// How far past the system back-gesture strip the drawer's edge swipe
/// reaches. Narrow on purpose: code blocks and tables start at the 20dp
/// reading gutter and scroll sideways, and a wide edge zone would take
/// those swipes for the drawer.
const _drawerEdgeReach = 36.0;

/// True while the framework builds, lays out or paints. A controller can
/// notify mid-frame (the drawer refreshes history as it opens), and the
/// screen's listeners then wait for the frame to finish before rebuilding.
bool get _midFrame =>
    SchedulerBinding.instance.schedulerPhase ==
    SchedulerPhase.persistentCallbacks;

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.controller,
    required this.onLock,
    this.onChangePin,
    this.onSettings,
    this.brief,
  });

  final ChatController controller;

  /// Frank's Brief; its header button shows only with it.
  final BriefStore? brief;
  final VoidCallback onLock;
  final VoidCallback? onChangePin;
  final VoidCallback? onSettings;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _composer = TextEditingController();
  final _find = TextEditingController();
  final _findFocus = FocusNode();
  final _scroll = ScrollController(keepScrollOffset: false);
  final _scaffold = GlobalKey<ScaffoldState>();
  final _pendingImages = <String>[];
  final _bubbleKeys = <String, GlobalKey>{};

  /// Message ids already on screen; anything else animates in once.
  final _seen = <String>{};

  /// Measured height of the floating composer (including the safe area).
  final _composerHeight = ValueNotifier<double>(88);

  /// Measured height of the header plus the error strip under it (including
  /// the status bar); 0 until the first layout. Text scaling can grow the
  /// header, and a notice must never cover the oldest messages.
  final _topHeight = ValueNotifier<double>(0);

  /// Either measured inset changed: the thread re-pads.
  late final Listenable _insets = Listenable.merge([
    _composerHeight,
    _topHeight,
  ]);
  final _away = ValueNotifier<bool>(false);
  final _unseen = ValueNotifier<bool>(false);
  final _scrolledUnder = ValueNotifier<bool>(false);

  /// How the mic is held, shared by the composer and the listening stage.
  final _capture = ValueNotifier<VoiceCapture>(VoiceCapture.none);

  String? _boundConversationId;
  var _applyingDraft = false;
  var _finding = false;
  var _findIndex = 0;
  List<MessageHit> _hits = const [];

  /// Id of the notice the user dismissed; it stays hidden until it changes.
  String? _dismissedNotice;
  String? _lastError;
  var _errorFromVoice = false;
  var _wasListening = false;
  Object? _latestSignature;
  String? _latestUserId;
  var _chatQueued = false;

  ChatController get _chat => widget.controller;

  @override
  void initState() {
    super.initState();
    _composer.addListener(_onComposerChanged);
    _find.addListener(_onFindChanged);
    _scroll.addListener(_onScroll);
    _applyDraftIfNeeded(rebuild: false);
    _chat.start();
    _chat.addListener(_onChat);
    _dictations = _chat.dictations.listen(_insertDictation);
  }

  StreamSubscription<String>? _dictations;

  /// Puts dictated words at the cursor, spaced from the words around them,
  /// for you to edit before sending.
  void _insertDictation(String words) {
    final value = _composer.value;
    final text = value.text;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: text.length);
    final before = text.substring(0, selection.start);
    final after = text.substring(selection.end);
    final lead = before.isEmpty || before.endsWith(' ') || before.endsWith('\n')
        ? ''
        : ' ';
    final trail = after.isEmpty || after.startsWith(' ') ? '' : ' ';
    final inserted = '$lead$words$trail';
    _composer.value = TextEditingValue(
      text: '$before$inserted$after',
      selection: TextSelection.collapsed(
        offset: before.length + inserted.length,
      ),
    );
  }

  @override
  void dispose() {
    _chat.removeListener(_onChat);
    _dictations?.cancel();
    _composer.removeListener(_onComposerChanged);
    _find.removeListener(_onFindChanged);
    _scroll.removeListener(_onScroll);
    _composer.dispose();
    _find.dispose();
    _findFocus.dispose();
    _scroll.dispose();
    _composerHeight.dispose();
    _topHeight.dispose();
    _away.dispose();
    _unseen.dispose();
    _scrolledUnder.dispose();
    _capture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The in-app Reduce motion setting reaches this screen app-wide through
    // MediaQuery.disableAnimations (see main.dart).
    return PopScope(
      canPop: !_finding,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _finding) {
          _closeFind();
        }
      },
      child: FrankBackdrop(
        child: Scaffold(
          key: _scaffold,
          backgroundColor: Colors.transparent,
          drawer: ChatDrawer(
            controller: _chat,
            onOpenSettings: _openSettings,
            onLock: _lockFromDrawer,
            onOpenInbox: _openInbox,
          ),
          drawerEdgeDragWidth:
              MediaQuery.systemGestureInsetsOf(context).left +
                  _drawerEdgeReach,
          drawerScrimColor: AppColors.scrim,
          onDrawerChanged: (open) {
            if (open) {
              _chat.saveDraft();
            }
          },
          body: Builder(builder: _buildBody),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final headerHeight = MediaQuery.paddingOf(context).top + ChatHeader.height;
    return Stack(
      children: [
        Positioned.fill(child: _buildThread(headerHeight)),
        ValueListenableBuilder<double>(
          valueListenable: _composerHeight,
          builder: (context, composer, child) => Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: composer,
            child: child!,
          ),
          child: const IgnorePointer(child: _ComposerFade()),
        ),
        Positioned.fill(child: _buildListening()),
        _buildScrollToLatest(),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _MeasureSize(
            onChange: (size) => _composerHeight.value = size.height,
            child: _buildComposer(),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _MeasureSize(
            onChange: (size) => _topHeight.value = size.height,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [_buildHeader(), _buildErrorStrip()],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Thread

  Widget _buildThread(double headerHeight) {
    return _Live(
      listenable: _chat,
      builder: (context) {
        final items = _chat.messages;
        double top() =>
            _topHeight.value > 0 ? _topHeight.value : headerHeight;
        if (items.isEmpty) {
          return ListenableBuilder(
            listenable: _insets,
            builder: (context, child) => Padding(
              padding: EdgeInsets.only(
                top: top(),
                bottom: _composerHeight.value,
              ),
              child: child,
            ),
            child: ChatEmptyState(
              connected: _chat.connected,
              connecting: _chat.loading,
              modelLabel: _chat.modelLabel,
              host: hostOf(_chat.config.baseUrl),
              recent: _recentChats(),
              onOpenRecent: _openRecent,
              onTalk: _chat.sending ||
                      _chat.mood == AssistantMood.transcribing
                  ? null
                  : _startVoice,
              onCommands: _openCommands,
              onRetry: _reconnect,
              onSettings: widget.onSettings,
            ),
          );
        }
        final indexById = <String, int>{
          for (var i = 0; i < items.length; i++) items[i].id: items.length - 1 - i,
        };
        return ListenableBuilder(
          listenable: _insets,
          builder: (context, _) {
            return TweenAnimationBuilder<double>(
              tween: Tween(end: _composerHeight.value + AppSpace.x3),
              duration: AppMotion.short,
              curve: AppMotion.standard,
              builder: (context, bottom, _) {
                return NotificationListener<ScrollMetricsNotification>(
                  onNotification: (notification) {
                    if (notification.depth == 0) {
                      _updateScrolledUnder(notification.metrics);
                    }
                    return false;
                  },
                  child: ListView.custom(
                    controller: _scroll,
                    reverse: true,
                    scrollCacheExtent: _finding
                        ? const ScrollCacheExtent.pixels(4000)
                        : null,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.only(
                      top: top() + AppSpace.x2,
                      bottom: bottom,
                    ),
                    childrenDelegate: SliverChildBuilderDelegate(
                      (context, index) => _buildItem(items, index),
                      childCount: items.length,
                      findChildIndexCallback: (key) {
                        return key is ValueKey<String>
                            ? indexById[key.value]
                            : null;
                      },
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildItem(List<ChatMessage> items, int index) {
    final position = items.length - 1 - index;
    final message = items[position];
    final previous = position > 0 ? items[position - 1] : null;
    final newDay =
        previous == null || !isSameDay(previous.createdAt, message.createdAt);
    final grouped = !newDay &&
        previous.role == message.role &&
        message.createdAt.difference(previous.createdAt).abs() <= _groupWindow;
    final assistant = message.isAssistant;
    final busy = _chat.sending || _chat.loading;
    final retry = (assistant || message.error) &&
        canRetryMessage(message, busy: busy);

    return _Entrance(
      key: ValueKey<String>(message.id),
      animate: _seen.add(message.id),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (newDay)
            DaySeparator(date: message.createdAt)
          else
            SizedBox(height: grouped ? AppSpace.groupGap : AppSpace.turnGap),
          MessageBubble(
            key: _keyFor(message.id),
            message: message,
            playing: _chat.playingId == message.id ||
                _chat.pendingSpeechId == message.id,
            highlighted: _finding &&
                _hits.isNotEmpty &&
                _hits[_findIndex].messageId == message.id,
            showHeader: assistant && !grouped,
            grouped: grouped,
            isLatest: index == 0,
            onPlay: () => _chat.playMessage(message),
            onLongPress: () => _openMessageActions(message),
            onCopy: assistant && canCopyMessage(message)
                ? () => _copyMessage(message)
                : null,
            onSpeak: assistant && canSpeakMessage(message)
                ? () => _toggleSpeech(message)
                : null,
            onRetry: retry ? () => _chat.retryMessage(message) : null,
            onReport: assistant && canReportMessage(message)
                ? () => _reportMessage(message)
                : null,
          ),
        ],
      ),
    );
  }

  List<ConversationSummary> _recentChats() {
    final current = _chat.conversationId;
    final items = [
      for (final item in _chat.history)
        if (item.id != current &&
            item.title.trim().isNotEmpty &&
            item.title != 'Conversation')
          item,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items.take(2).toList();
  }

  // ---------------------------------------------------------------------------
  // Header, error strip, listening, composer

  Widget _buildHeader() {
    return _Select<_HeaderView>(
      listenable: _chat,
      select: _headerView,
      builder: (context, view) {
        return ChatHeader(
          title: view.title,
          status: view.status,
          mood: view.mood,
          // The mic level only means something while Frank listens; in the
          // other moods the orb runs its own speech swell and token pump.
          level: view.mood == AssistantMood.listening ? _chat.voiceLevel : null,
          lit: view.connected,
          orbEnabled: view.orbEnabled,
          orbLabel: view.orbLabel,
          onOpenDrawer: _openDrawer,
          onOrbTap: _onOrbTap,
          onOpenConversation: _openConversationSheet,
          onStatusAction: () => _runStatusAction(view.status.action),
          onFind: view.canFind ? _toggleFind : null,
          onBrief: widget.brief == null || _chat.settings == null
              ? null
              : _openBrief,
          onNewChat: view.canNewChat ? _newChat : null,
          finding: _finding,
          scrolledUnder: _scrolledUnder,
          findBar: ThreadFindBar(
            controller: _find,
            focusNode: _findFocus,
            matchLabel: _findMatchLabel(),
            hasQuery: _find.text.trim().isNotEmpty,
            hasMatches: _hits.isNotEmpty,
            onPrevious: () => _moveFind(-1),
            onNext: () => _moveFind(1),
            onClose: _closeFind,
          ),
        );
      },
    );
  }

  _HeaderView _headerView() {
    final mood = _chat.mood;
    final notice = _currentNotice();
    final status = chatStatusFor(
      mood: mood,
      loading: _chat.loading,
      connected: _chat.connected,
      onDevice: _chat.onDeviceDictation,
      toolLabel: _chat.toolLabel,
      modelLabel: _chat.modelLabel,
      showError: notice != null && notice.kind != ChatNoticeKind.voice,
    );
    final idle = mood == AssistantMood.idle || mood == AssistantMood.error;
    final canTalk =
        idle && _chat.connected && !_chat.loading && !_chat.sending;
    // The orb only wears the error palette while the error is on screen;
    // offline it rests, dimmed.
    final showsError = mood == AssistantMood.error &&
        _chat.connected &&
        notice != null &&
        notice.kind != ChatNoticeKind.voice;
    return (
      title: _title(),
      status: status,
      mood: mood == AssistantMood.error && !showsError
          ? AssistantMood.idle
          : mood,
      connected: _chat.connected || _chat.loading,
      orbEnabled: canTalk ||
          mood == AssistantMood.listening ||
          mood == AssistantMood.speaking,
      orbLabel: switch (mood) {
        AssistantMood.listening => 'Send voice',
        AssistantMood.speaking => 'Stop speaking',
        _ when canTalk => 'Talk to Hermsy',
        _ => 'Hermsy',
      },
      canFind: _chat.messages.isNotEmpty,
      canNewChat: !_chat.sending,
    );
  }

  String _title() {
    final title = _chat.conversationTitle?.trim() ?? '';
    if (_chat.messages.isEmpty || title.isEmpty || title == 'Conversation') {
      return 'Hermsy';
    }
    return title;
  }

  Widget _buildErrorStrip() {
    return _Select<ChatNotice?>(
      listenable: _chat,
      select: _currentNotice,
      builder: (context, notice) {
        return ChatErrorStrip(
          notice: notice,
          onRetry: notice?.kind == ChatNoticeKind.connection
              ? _reconnect
              : _chat.retry,
          onSettings: widget.onSettings,
          onDismiss: (dismissed) {
            setState(() => _dismissedNotice = dismissed.id);
          },
        );
      },
    );
  }

  ChatNotice? _currentNotice() {
    final items = _chat.messages;
    final last = items.isEmpty ? null : items.last;
    final notice = chatNoticeFor(
      error: _chat.error,
      connected: _chat.connected,
      loading: _chat.loading,
      hasMessages: items.isNotEmpty,
      lastReplyFailed: last != null && last.isAssistant && last.error,
      fromVoice: _errorFromVoice,
      host: hostOf(_chat.config.baseUrl),
    );
    if (notice == null || notice.id == _dismissedNotice) {
      return null;
    }
    return notice;
  }

  Widget _buildListening() {
    return _Select<_ListeningView>(
      listenable: _chat,
      select: () {
        final transcribing = _chat.mood == AssistantMood.transcribing;
        return (
          active: _chat.recording || transcribing,
          transcribing: transcribing,
          onDevice: _chat.onDeviceDictation,
        );
      },
      builder: (context, view) {
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: view.active ? 1 : 0,
                  duration: const Duration(milliseconds: 240),
                  curve: AppMotion.standard,
                  child: const _ListeningScrim(),
                ),
              ),
            ),
            ValueListenableBuilder<double>(
              valueListenable: _composerHeight,
              builder: (context, composer, child) => Positioned(
                left: 0,
                right: 0,
                bottom: composer,
                child: child!,
              ),
              child: ListeningStage(
                active: view.active,
                level: _chat.voiceLevel,
                transcript: _chat.liveTranscript,
                onDevice: view.onDevice,
                transcribing: view.transcribing,
                capture: _capture,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildScrollToLatest() {
    return ValueListenableBuilder<double>(
      valueListenable: _composerHeight,
      builder: (context, composer, child) => Positioned(
        right: AppSpace.gutter,
        bottom: composer + AppSpace.x3,
        child: child!,
      ),
      child: ListenableBuilder(
        listenable: Listenable.merge([_away, _unseen]),
        builder: (context, _) => ScrollToLatestButton(
          visible: _away.value,
          unseen: _unseen.value,
          onPressed: _jumpToLatest,
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return _Select<_ComposerView>(
      listenable: _chat,
      select: () => (
        loading: _chat.loading,
        recording: _chat.recording,
        sending: _chat.sending,
        transcribing: _chat.mood == AssistantMood.transcribing,
        onDevice: _chat.onDeviceDictation,
      ),
      builder: (context, view) {
        return ListenableBuilder(
          listenable: _composer,
          builder: (context, _) {
            return ComposerBar(
              controller: _composer,
              enabled: !view.loading,
              recording: view.recording,
              sending: view.sending,
              showMic: _composer.text.trim().isEmpty && _pendingImages.isEmpty,
              onSend: _send,
              onStop: _stopReply,
              onRecordStart: _chat.startVoice,
              onRecordStop: _chat.stopVoice,
              onCancelRecording: _chat.cancelVoice,
              level: _chat.voiceLevel,
              transcript: _chat.liveTranscript,
              onDeviceDictation: view.onDevice,
              transcribing: view.transcribing,
              onAttach: _attachImage,
              pendingImages: List<String>.unmodifiable(_pendingImages),
              onRemoveImage: _removePendingImage,
              capture: _capture,
              onCall: _chat.onDeviceVoice == null ? null : _startCall,
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Controller and scroll tracking

  void _onChat() {
    if (!mounted) {
      return;
    }
    if (_midFrame) {
      if (!_chatQueued) {
        _chatQueued = true;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _chatQueued = false;
          if (mounted) {
            _syncWithChat();
            setState(() {});
          }
        });
      }
      return;
    }
    _syncWithChat();
  }

  void _syncWithChat() {
    _applyDraftIfNeeded();
    _trackError();
    _trackLatest();
  }

  void _trackError() {
    final listening =
        _chat.recording || _chat.mood == AssistantMood.transcribing;
    final error = _chat.error;
    if (error != _lastError) {
      _errorFromVoice = error != null && (_wasListening || listening);
      _lastError = error;
      if (error == null) {
        _dismissedNotice = null;
      }
    }
    _wasListening = listening;
  }

  Object? _signature() {
    final items = _chat.messages;
    if (items.isEmpty) {
      return null;
    }
    final last = items.last;
    return (
      items.length,
      last.id,
      last.text.length,
      last.streaming,
      last.toolStatus,
    );
  }

  String? _newestUserId() {
    final items = _chat.messages;
    for (var i = items.length - 1; i >= 0; i--) {
      if (items[i].isUser) {
        return items[i].id;
      }
    }
    return null;
  }

  void _trackLatest() {
    final signature = _signature();
    if (signature == _latestSignature) {
      return;
    }
    _latestSignature = signature;
    if (signature == null) {
      _away.value = false;
      _unseen.value = false;
      _scrolledUnder.value = false;
      return;
    }
    final userId = _newestUserId();
    if (userId != _latestUserId) {
      _latestUserId = userId;
      if (userId != null) {
        // You just spoke: bring the thread back to the newest message.
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToLatest());
        return;
      }
    }
    if (_away.value) {
      _unseen.value = true;
      return;
    }
    _followIfNear();
  }

  void _followIfNear() {
    if (!_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    if (position.pixels <= 0 ||
        position.pixels > _followDistance ||
        position.isScrollingNotifier.value ||
        position.userScrollDirection != ScrollDirection.idle) {
      return;
    }
    _scroll.animateTo(
      0,
      duration: AppMotion.quick,
      curve: AppMotion.standard,
    );
  }

  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    final away = position.pixels > _awayDistance;
    if (away != _away.value) {
      _away.value = away;
      if (!away) {
        _unseen.value = false;
      }
    }
    _updateScrolledUnder(position);
  }

  void _updateScrolledUnder(ScrollMetrics metrics) {
    // The list is reversed: content above the viewport is "after".
    _scrolledUnder.value = metrics.extentAfter > AppSpace.x2;
  }

  void _jumpToLatest() {
    if (!mounted || !_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    if (position.pixels <= 0) {
      return;
    }
    if (AppMotion.reduced(context)) {
      _scroll.jumpTo(0);
      return;
    }
    // Long threads: skip most of the distance, then glide the last screen.
    final screen = position.viewportDimension;
    if (position.pixels > screen * 2) {
      _scroll.jumpTo(screen);
    }
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: AppMotion.standard,
    );
  }

  // ---------------------------------------------------------------------------
  // Drafts

  void _onComposerChanged() {
    if (_applyingDraft) {
      return;
    }
    _chat.setDraft(
      text: _composer.text,
      imagePaths: List<String>.from(_pendingImages),
    );
  }

  void _applyDraftIfNeeded({bool rebuild = true}) {
    if (_boundConversationId == _chat.conversationId) {
      return;
    }
    _boundConversationId = _chat.conversationId;
    _applyingDraft = true;
    _composer.removeListener(_onComposerChanged);
    _find.removeListener(_onFindChanged);
    _composer.value = TextEditingValue(
      text: _chat.draftText,
      selection: TextSelection.collapsed(offset: _chat.draftText.length),
    );
    _pendingImages
      ..clear()
      ..addAll(_chat.draftImagePaths);
    if (_finding) {
      _find.clear();
      _finding = false;
      _findIndex = 0;
      _hits = const [];
    }
    _composer.addListener(_onComposerChanged);
    _find.addListener(_onFindChanged);
    _applyingDraft = false;

    // A freshly opened thread lands on its newest message without replaying
    // entrance motion for what was already there.
    _bubbleKeys.clear();
    _seen
      ..clear()
      ..addAll(_chat.messages.map((message) => message.id));
    _latestSignature = _signature();
    _latestUserId = _newestUserId();
    _away.value = false;
    _unseen.value = false;
    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }
    if (rebuild) {
      setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  // Actions

  void _send() {
    if (_chat.sending) {
      return;
    }
    final text = _composer.text;
    final images = List<String>.from(_pendingImages);
    if (text.trim().isEmpty && images.isEmpty) {
      return;
    }
    // The composer fires the send bloom from its own button.
    _applyingDraft = true;
    _composer.clear();
    setState(_pendingImages.clear);
    _applyingDraft = false;
    _chat.send(text, imagePaths: images);
  }

  void _stopReply() {
    PresenceScope.maybeOf(context)?.event(PresenceEvent.stop);
    _chat.stopReply();
  }

  void _startVoice(Offset origin) {
    if (_chat.sending ||
        _chat.recording ||
        _chat.loading ||
        _chat.mood == AssistantMood.transcribing) {
      return;
    }
    PresenceScope.maybeOf(context)?.event(
      PresenceEvent.listenStart,
      origin: origin,
    );
    _chat.startVoice();
  }

  /// The header orb is Frank's "AI button": talk, send what you said, or
  /// stop a spoken reply.
  void _onOrbTap(Offset origin) {
    switch (_chat.mood) {
      case AssistantMood.listening:
        // Stop first, so the glow already reads transcribing when the send
        // beat lands; the beat leaves from the orb.
        _chat.stopVoice();
        PresenceScope.maybeOf(context)?.event(
          PresenceEvent.listenSend,
          origin: origin,
        );
      case AssistantMood.speaking:
        _chat.stopSpeaking();
      default:
        _startVoice(origin);
    }
  }

  void _runStatusAction(ChatStatusAction action) {
    switch (action) {
      case ChatStatusAction.retry:
        _reconnect();
      case ChatStatusAction.stopSpeaking:
        _chat.stopSpeaking();
      case ChatStatusAction.none:
        _openConversationSheet();
    }
  }

  void _reconnect() {
    _chat.haptics?.tap();
    _chat.start();
  }

  void _newChat() {
    _chat.haptics?.tap();
    _chat.newChat();
  }

  void _openRecent(ConversationSummary item) {
    _chat.haptics?.tap();
    _chat.openConversation(item);
  }

  /// Opens the slash palette by starting a command in an empty composer.
  /// With a draft (text or photos) in the way, it runs /help instead and
  /// leaves the draft alone.
  void _openCommands() {
    _chat.haptics?.tap();
    if (_composer.text.trim().isNotEmpty || _pendingImages.isNotEmpty) {
      _runCommand('/help');
      return;
    }
    _composer.value = const TextEditingValue(
      text: '/',
      selection: TextSelection.collapsed(offset: 1),
    );
  }

  /// Runs a slash command from the chrome (not the composer). Sending
  /// clears the controller's draft, so the draft still on screen is handed
  /// back to it, keeping it for this chat.
  Future<void> _runCommand(String command) async {
    final text = _composer.text;
    final images = List<String>.from(_pendingImages);
    final sent = _chat.send(command);
    if (text.trim().isNotEmpty || images.isNotEmpty) {
      _chat.setDraft(text: text, imagePaths: images, persistNow: true);
    }
    await sent;
  }

  /// Speak a reply, or stop it when it is the one already playing (or still
  /// being prepared).
  void _toggleSpeech(ChatMessage message) {
    if (_chat.playingId == message.id ||
        _chat.pendingSpeechId == message.id) {
      _chat.stopSpeaking();
      return;
    }
    _chat.speakMessage(message);
  }

  /// A short floating note that clears the composer (and the jump-to-latest
  /// disc when it shows), which the Scaffold cannot see in the body stack.
  void _showNote(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      return;
    }
    final above = _composerHeight.value -
        MediaQuery.paddingOf(context).bottom +
        (_away.value ? _latestButtonClearance : 0) +
        AppSpace.x2;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          margin: EdgeInsets.fromLTRB(
            AppSpace.gutter,
            0,
            AppSpace.gutter,
            math.max(AppSpace.x2, above),
          ),
        ),
      );
  }

  void _copyMessage(ChatMessage message) {
    Clipboard.setData(ClipboardData(text: copyableText(message)));
    _chat.haptics?.tap();
  }

  void _reportMessage(ChatMessage message) {
    unawaited(
      reportReply(
        context,
        reply: copyableText(message),
        sentAt: message.createdAt,
      ),
    );
  }

  Future<void> _openMessageActions(ChatMessage message) async {
    final canCopy = canCopyMessage(message);
    final canSpeak = canSpeakMessage(message);
    final canRetry = canRetryMessage(
      message,
      busy: _chat.sending || _chat.loading,
    );
    if (!canCopy && !canSpeak && !canRetry && !canReportMessage(message)) {
      return;
    }
    _chat.haptics?.tap();
    await showFrankSheet<void>(
      context,
      builder: (sheetContext) {
        void close() => Navigator.of(sheetContext).pop();
        return MessageActionsSheet(
          preview: canCopy ? copyableText(message) : null,
          onCopy: canCopy
              ? () {
                  Clipboard.setData(ClipboardData(text: copyableText(message)));
                  close();
                  _showNote('Copied');
                }
              : null,
          onSelectText: canCopy
              ? () {
                  close();
                  _openMessageReader(message);
                }
              : null,
          onSpeak: canSpeak
              ? () {
                  close();
                  _chat.speakMessage(message);
                }
              : null,
          onRetry: canRetry
              ? () {
                  close();
                  _chat.retryMessage(message);
                }
              : null,
          onReport: canReportMessage(message)
              ? () {
                  close();
                  _reportMessage(message);
                }
              : null,
        );
      },
    );
  }

  ConversationSummary? _currentSummary() {
    final id = _chat.conversationId;
    if (id == null) {
      return null;
    }
    for (final item in _chat.history) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  Future<void> _openConversationSheet() async {
    final summary = _currentSummary();
    final id = _chat.conversationId;
    final count = _chat.messages.length;
    ConversationSummary? renameTarget;
    if (summary != null) {
      renameTarget = summary.isRemoteOnly ? null : summary;
    } else if (id != null && count > 0) {
      renameTarget = ConversationSummary(
        id: id,
        title: _title(),
        updatedAt: DateTime.now(),
        titleCustom: _chat.titleCustom,
      );
    }
    final pinTarget =
        summary != null && !summary.isRemoteOnly ? summary : null;
    final title = _title();
    final busy = _chat.sending || _chat.loading;
    _chat.haptics?.tap();
    await showFrankSheet<void>(
      context,
      builder: (sheetContext) {
        return ConversationSheet(
          title: count == 0
              ? 'New chat'
              : title == 'Hermsy'
                  ? 'This chat'
                  : title,
          subtitle: [
            count == 0
                ? 'No messages yet'
                : count == 1
                    ? '1 message'
                    : '$count messages',
            _chat.agentLabel,
          ].join(' · '),
          pinned: pinTarget?.pinned ?? false,
          onRename: renameTarget == null
              ? null
              : () => _renameChat(renameTarget!),
          onTogglePin:
              pinTarget == null ? null : () => _chat.togglePin(pinTarget),
          onFind: count == 0 ? null : _toggleFind,
          onUsage: busy ? null : () => _runCommand('/usage'),
          onStatus: busy ? null : () => _runCommand('/status'),
          onDelete: _chat.canDeleteChat && !_chat.sending
              ? _deleteCurrentChat
              : null,
        );
      },
    );
  }

  Future<void> _renameChat(ConversationSummary item) async {
    final next = await promptRenameChat(context, currentTitle: item.title);
    if (next != null) {
      await _chat.renameConversation(item, next);
    }
  }

  // ---------------------------------------------------------------------------
  // Find

  GlobalKey _keyFor(String id) {
    return _bubbleKeys.putIfAbsent(id, GlobalKey.new);
  }

  void _toggleFind() {
    if (_finding) {
      _closeFind();
      return;
    }
    if (_chat.messages.isEmpty) {
      return;
    }
    _chat.haptics?.tap();
    setState(() => _finding = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _findFocus.requestFocus();
      }
    });
  }

  void _closeFind() {
    _find.clear();
    _findFocus.unfocus();
    setState(() {
      _finding = false;
      _findIndex = 0;
      _hits = const [];
    });
  }

  void _onFindChanged() {
    final hits = findMessageHits(_chat.messages, _find.text);
    setState(() {
      _hits = hits;
      _findIndex = 0;
    });
    _scrollToCurrentHit();
  }

  void _moveFind(int delta) {
    if (_hits.isEmpty) {
      return;
    }
    setState(() {
      _findIndex = (_findIndex + delta) % _hits.length;
      if (_findIndex < 0) {
        _findIndex += _hits.length;
      }
    });
    _scrollToCurrentHit();
  }

  String _findMatchLabel() {
    if (_find.text.trim().isEmpty) {
      return '';
    }
    if (_hits.isEmpty) {
      return 'No matches';
    }
    return '${_findIndex + 1}/${_hits.length}';
  }

  Future<void> _scrollToCurrentHit() async {
    if (_hits.isEmpty) {
      return;
    }
    final id = _hits[_findIndex].messageId;
    final items = _chat.messages;
    final messageIndex = items.indexWhere((item) => item.id == id);
    if (messageIndex < 0) {
      return;
    }
    final listIndex = items.length - 1 - messageIndex;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }
    final existing = _keyFor(id).currentContext;
    if (existing != null && existing.mounted) {
      await Scrollable.ensureVisible(
        existing,
        alignment: 0.3,
        duration: const Duration(milliseconds: 220),
        curve: AppMotion.standard,
      );
      return;
    }
    if (!_scroll.hasClients) {
      return;
    }
    final estimated = (listIndex * 150.0).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.jumpTo(estimated);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }
    final ready = _keyFor(id).currentContext;
    if (ready != null && ready.mounted) {
      await Scrollable.ensureVisible(
        ready,
        alignment: 0.3,
        duration: const Duration(milliseconds: 180),
        curve: AppMotion.standard,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Photos

  void _removePendingImage(String path) {
    setState(() => _pendingImages.remove(path));
    _chat.setDraft(
      text: _composer.text,
      imagePaths: List<String>.from(_pendingImages),
      persistNow: true,
    );
  }

  Future<void> _attachImage() async {
    if (_chat.sending || _chat.loading || _chat.recording) {
      return;
    }
    _chat.haptics?.tap();
    final source = await showFrankSheet<ImageSource>(
      context,
      builder: (sheetContext) {
        return FrankSheet(
          title: 'Add a photo',
          children: [
            QuickTileRow(
              children: [
                QuickTile(
                  icon: Icons.photo_library_rounded,
                  label: 'Photo library',
                  onTap: () =>
                      Navigator.of(sheetContext).pop(ImageSource.gallery),
                ),
                QuickTile(
                  icon: Icons.photo_camera_rounded,
                  label: 'Camera',
                  onTap: () =>
                      Navigator.of(sheetContext).pop(ImageSource.camera),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (source == null) {
      return;
    }
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 78,
      );
      if (picked == null || !mounted) {
        return;
      }
      final kept = await persistLocalImage(picked.path);
      if (!mounted) {
        return;
      }
      setState(() => _pendingImages.add(kept));
      _chat.setDraft(
        text: _composer.text,
        imagePaths: List<String>.from(_pendingImages),
        persistNow: true,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showNote('Could not attach that photo');
    }
  }

  // ---------------------------------------------------------------------------
  // Navigation

  void _openDrawer() {
    _chat.saveDraft().then((_) => _chat.refreshHistory());
    _scaffold.currentState?.openDrawer();
  }

  Future<void> _openSettings() async {
    _scaffold.currentState?.closeDrawer();
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (mounted) {
      widget.onSettings?.call();
    }
  }

  void _lockFromDrawer() {
    _scaffold.currentState?.closeDrawer();
    widget.onLock();
  }

  Future<void> _deleteCurrentChat() async {
    if (!_chat.canDeleteChat || _chat.sending) {
      return;
    }
    _chat.haptics?.tap();
    if (!await confirmDeleteChat(context)) {
      return;
    }
    await _chat.deleteCurrentChat();
  }

  void _openMessageReader(ChatMessage message) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MessageReaderScreen(message: message),
      ),
    );
  }

  /// A live call needs the on-device models; until they are downloaded the
  /// wave explains that and offers the download.
  Future<void> _startCall() async {
    final voice = _chat.onDeviceVoice!;
    FocusScope.of(context).unfocus();
    if (_chat.sending) {
      await _chat.stopReply();
    }
    if (!mounted) {
      return;
    }
    if (!voice.available) {
      final settings = _chat.settings;
      final download = await showFrankConfirm(
        context,
        title: 'Voice calls need the voice models',
        message:
            'Hermsy listens and speaks on this phone during a call, '
            'using models of about 794 MB. Download them in Settings first.',
        confirmLabel: 'Open voice models',
      );
      if (download && mounted && settings != null) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) =>
                VoiceModelsScreen(store: voice.models, settings: settings),
          ),
        );
      }
      return;
    }
    await showCallScreen(context, chat: _chat, voice: voice);
  }

  Future<void> _openBrief() async {
    FocusScope.of(context).unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => BriefScreen(
          store: widget.brief!,
          settings: _chat.settings!,
          chat: _chat,
        ),
      ),
    );
  }

  Future<void> _openInbox() async {
    _scaffold.currentState?.closeDrawer();
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => InboxScreen(onReply: _chat.replyTo),
      ),
    );
  }
}

/// Settles the thread into the canvas behind the floating composer, so
/// text never runs crisp beneath it or through the gesture bar inset.
class _ComposerFade extends StatelessWidget {
  const _ComposerFade();

  @override
  Widget build(BuildContext context) {
    final canvas = AppColors.background;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            canvas.withValues(alpha: 0),
            canvas.withValues(alpha: 0.78),
            canvas.withValues(alpha: 0.94),
          ],
          stops: const [0, 0.5, 1],
        ),
      ),
    );
  }
}

/// Dims the thread while Frank listens: 40% everywhere, deepening toward
/// the composer so the listening stage reads cleanly over the messages.
class _ListeningScrim extends StatelessWidget {
  const _ListeningScrim();

  @override
  Widget build(BuildContext context) {
    final canvas = AppColors.background;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // Keep the top of the thread readable for context, and make the
          // stage's lower half nearly solid so its words never fight the
          // chat text underneath.
          colors: [
            canvas.withValues(alpha: 0.45),
            canvas.withValues(alpha: 0.55),
            canvas.withValues(alpha: 0.94),
            canvas.withValues(alpha: 0.97),
          ],
          stops: const [0, 0.3, 0.58, 1],
        ),
      ),
    );
  }
}

typedef _HeaderView = ({
  String title,
  ChatStatus status,
  AssistantMood mood,
  bool connected,
  bool orbEnabled,
  String orbLabel,
  bool canFind,
  bool canNewChat,
});

typedef _ListeningView = ({bool active, bool transcribing, bool onDevice});

typedef _ComposerView = ({
  bool loading,
  bool recording,
  bool sending,
  bool transcribing,
  bool onDevice,
});

/// Rebuilds [builder] only when [select] returns a different value after
/// [listenable] notifies, so per-token updates skip the header, strip and
/// composer. A parent rebuild always rebuilds it.
class _Select<T> extends StatefulWidget {
  const _Select({
    super.key,
    required this.listenable,
    required this.select,
    required this.builder,
  });

  final Listenable listenable;
  final T Function() select;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<_Select<T>> createState() => _SelectState<T>();
}

class _SelectState<T> extends State<_Select<T>> {
  late T _value = widget.select();
  var _queued = false;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant _Select<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
    _value = widget.select();
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (_midFrame) {
      if (!_queued) {
        _queued = true;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _queued = false;
          if (mounted) {
            _changed();
          }
        });
      }
      return;
    }
    final next = widget.select();
    if (next != _value) {
      setState(() => _value = next);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}

/// Rebuilds on every notification of [listenable] (the thread follows each
/// streamed token), waiting for the frame to finish if it arrives mid-build.
class _Live extends StatefulWidget {
  const _Live({required this.listenable, required this.builder});

  final Listenable listenable;
  final WidgetBuilder builder;

  @override
  State<_Live> createState() => _LiveState();
}

class _LiveState extends State<_Live> {
  var _queued = false;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant _Live oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!_midFrame) {
      setState(() {});
      return;
    }
    if (_queued) {
      return;
    }
    _queued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// New messages fade in and rise 12dp while the thread makes room for them
/// (220ms). Messages already present when a thread opens appear as is.
class _Entrance extends StatefulWidget {
  const _Entrance({super.key, required this.animate, required this.child});

  final bool animate;
  final Widget child;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double> _progress = kAlwaysCompleteAnimation;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      final controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 220),
      );
      _controller = controller;
      _progress = CurvedAnimation(parent: controller, curve: AppMotion.enter);
      controller.forward();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, child) {
        final t = _progress.value;
        final moving = t < 1 && !reduced;
        return ClipRect(
          clipBehavior: moving ? Clip.hardEdge : Clip.none,
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: moving ? t : 1,
            child: Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, moving ? 12 * (1 - t) : 0),
                child: child,
              ),
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Reports its child's size after layout (the floating composer's height,
/// which pads the thread and places the controls above it).
class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderMeasureSize(onChange);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasureSize renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    final measured = size;
    if (measured == _last) {
      return;
    }
    _last = measured;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(measured));
  }
}
