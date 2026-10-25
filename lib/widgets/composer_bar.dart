import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../presence/presence_engine.dart';
import '../services/slash_commands.dart';
import '../theme/app_theme.dart';
import 'listening_stage.dart';
import 'slash_palette.dart';
import 'ui/frank_ui.dart';

/// Slide this far left while holding the mic to discard the recording.
const double kVoiceCancelDistance = 96;

/// Slide this far up while holding the mic to keep recording hands-free.
const double kVoiceLockDistance = 72;

/// A hold shorter than this is a tap: it starts hands-free recording instead
/// of sending an empty blip.
const Duration kVoiceTapThreshold = Duration(milliseconds: 600);

const _morphDuration = Duration(milliseconds: 160);

/// The thumb zone: a floating glass capsule with the message field and one
/// morphing action button (mic → send → stop).
///
/// The mic is Telegram-style: recording starts the moment it is touched.
/// Let go to send, slide left to cancel, slide up (or just tap) to keep
/// recording hands-free until Send or Cancel.
class ComposerBar extends StatefulWidget {
  const ComposerBar({
    super.key,
    required this.controller,
    required this.enabled,
    required this.recording,
    required this.sending,
    required this.showMic,
    required this.onSend,
    required this.onStop,
    required this.onRecordStart,
    required this.onRecordStop,
    this.onAttach,
    this.pendingImages = const [],
    this.onRemoveImage,
    this.onCancelRecording,
    this.level,
    this.transcript,
    this.onDeviceDictation = false,
    this.transcribing = false,
    this.capture,
    this.onCall,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool recording;
  final bool sending;
  final bool showMic;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onRecordStart;
  final VoidCallback onRecordStop;
  final VoidCallback? onAttach;
  final List<String> pendingImages;
  final ValueChanged<String>? onRemoveImage;

  /// Discard the recording without sending (slide-to-cancel, X).
  final VoidCallback? onCancelRecording;

  /// Smoothed mic level (0–1) for the live waveform.
  final ValueListenable<double>? level;

  /// Words heard so far during on-device dictation.
  final ValueListenable<String>? transcript;

  /// True when the mic uses on-device dictation (no server STT).
  final bool onDeviceDictation;

  /// True while Hermes turns the voice note into text.
  final bool transcribing;

  /// Receives how the mic is held, for [ListeningStage.capture].
  final ValueNotifier<VoiceCapture>? capture;

  /// Starts a live voice call. Its wave button sits beside the mic.
  final VoidCallback? onCall;

  @override
  State<ComposerBar> createState() => _ComposerBarState();
}

enum _Hold { none, holding, locked }

enum _Mode { compose, voice, transcribing }

enum _Action { mic, send, stop, voiceHold, voiceSend, transcribing }

class _ComposerBarState extends State<ComposerBar>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _focus = FocusNode(debugLabel: 'composer');
  final _actionKey = GlobalKey();
  final _drag = ValueNotifier<Offset>(Offset.zero);
  late final _VoiceMeter _meter = _VoiceMeter(this);

  _Hold _hold = _Hold.none;
  int? _pointer;
  Offset _downAt = Offset.zero;
  Duration _downStamp = Duration.zero;

  /// Between letting go of a voice note and Hermes starting to transcribe it
  /// (or the reply starting), keep showing the transcribing row instead of
  /// flashing the idle composer.
  bool _awaitingText = false;
  Timer? _awaitingTimeout;

  bool _hasText = false;
  bool _focused = false;
  bool _keyboardOpen = false;
  List<SlashCommandInfo> _matches = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focus.addListener(_onFocus);
    widget.controller.addListener(_onText);
    _readText();
    _syncMeter();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _keyboardOpen = _readKeyboard();
  }

  @override
  void didUpdateWidget(covariant ComposerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
      _readText();
    }
    if (oldWidget.recording && !widget.recording) {
      // Recording ended elsewhere (sent, failed, or dictation finished).
      _hold = _Hold.none;
      _drag.value = Offset.zero;
    }
    if (_awaitingText &&
        (widget.sending ||
            (!oldWidget.recording && widget.recording) ||
            (oldWidget.transcribing && !widget.transcribing))) {
      _stopAwaiting();
    }
    final startedElsewhere =
        !oldWidget.recording && widget.recording && _hold == _Hold.none;
    if (startedElsewhere || (!oldWidget.transcribing && widget.transcribing)) {
      // The field is hidden now; don't let the keyboard type into it.
      _focus.unfocus();
    }
    _syncMeter();
    _publishCapture();
  }

  @override
  void dispose() {
    _awaitingTimeout?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onText);
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    _meter.dispose();
    _drag.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (!mounted) {
      return;
    }
    final open = _readKeyboard();
    if (open != _keyboardOpen) {
      setState(() => _keyboardOpen = open);
    }
  }

  // The Scaffold strips view insets from its body, so ask the view directly.
  bool _readKeyboard() {
    final view = View.maybeOf(context);
    return view != null && view.viewInsets.bottom > 0;
  }

  void _onFocus() {
    if (_focus.hasFocus != _focused) {
      setState(() => _focused = _focus.hasFocus);
    }
  }

  void _onText() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    final matches = matchSlashCommands(widget.controller.text);
    if (hasText != _hasText || !listEquals(matches, _matches)) {
      setState(() {
        _hasText = hasText;
        _matches = matches;
      });
    }
  }

  void _readText() {
    _hasText = widget.controller.text.trim().isNotEmpty;
    _matches = matchSlashCommands(widget.controller.text);
  }

  // ---------------------------------------------------------------- state

  bool get _voice => widget.recording || _hold != _Hold.none;

  bool get _holding => _hold == _Hold.holding;

  bool get _canCancel => widget.onCancelRecording != null;

  bool get _hasContent {
    return widget.controller.text.trim().isNotEmpty ||
        widget.pendingImages.isNotEmpty;
  }

  bool get _transcribing => widget.transcribing || _awaitingText;

  bool get _canSend {
    return widget.enabled &&
        !widget.sending &&
        !_transcribing &&
        !_voice &&
        _hasContent;
  }

  _Mode get _mode {
    if (_voice) {
      return _Mode.voice;
    }
    return _transcribing ? _Mode.transcribing : _Mode.compose;
  }

  _Action get _action {
    if (_voice) {
      return _holding ? _Action.voiceHold : _Action.voiceSend;
    }
    if (_transcribing) {
      return _Action.transcribing;
    }
    if (widget.sending) {
      return _Action.stop;
    }
    if (widget.showMic && !_hasText && widget.pendingImages.isEmpty) {
      return _Action.mic;
    }
    return _Action.send;
  }

  bool get _calm {
    return AppMotion.reduced(context) ||
        (PresenceScope.maybeOf(context)?.settings?.reduceMotion ?? false);
  }

  void _syncMeter() {
    if (_voice) {
      _meter.start(widget.level);
    } else {
      _meter.stop();
    }
  }

  void _publishCapture() {
    final notifier = widget.capture;
    if (notifier == null) {
      return;
    }
    final next = _holding
        ? VoiceCapture.holding
        : _voice
        ? VoiceCapture.handsFree
        : VoiceCapture.none;
    if (notifier.value == next) {
      return;
    }
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      // Mid-build: the stage listening to it may already be built.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _publishCapture();
        }
      });
      return;
    }
    notifier.value = next;
  }

  void _setHold(_Hold hold) {
    setState(() => _hold = hold);
    _syncMeter();
    _publishCapture();
  }

  Offset? _actionCentre() {
    final box = _actionKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) {
      return null;
    }
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  void _beat(PresenceEvent event, [Offset? origin]) {
    PresenceScope.maybeOf(
      context,
    )?.event(event, origin: origin ?? _actionCentre());
  }

  void _haptic(Future<void> Function() feedback) {
    if (PresenceScope.maybeOf(context)?.settings?.haptics ?? false) {
      feedback();
    }
  }

  // --------------------------------------------------------------- voice

  void _beginVoice(_Hold hold) {
    // While a finger holds the mic the keyboard may stay; hands-free drops it.
    if (hold != _Hold.holding) {
      _focus.unfocus();
    }
    _drag.value = Offset.zero;
    _setHold(hold);
    // The bloom leaves from the mic: fire the beat before the controller
    // flips to listening, or the engine sees an already-lit mood and blooms
    // from its default origin instead.
    _beat(PresenceEvent.listenStart);
    widget.onRecordStart();
    // The controller flips `recording` synchronously, so by the end of the
    // next frame it is either on, or it failed and we drop the hold.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && _hold != _Hold.none && !widget.recording) {
        _setHold(_Hold.none);
      }
    });
  }

  void _lock({bool haptic = true}) {
    if (_hold == _Hold.locked) {
      return;
    }
    if (haptic) {
      _haptic(HapticFeedback.selectionClick);
    }
    _focus.unfocus();
    _drag.value = Offset.zero;
    _setHold(_Hold.locked);
  }

  void _sendVoice() {
    final origin = _actionCentre();
    _focus.unfocus();
    _drag.value = Offset.zero;
    // On-device dictation with no words yet ends in "No speech detected",
    // not a transcript, so there is nothing to wait for.
    final words = widget.transcript?.value.trim() ?? '';
    if (!widget.onDeviceDictation || words.isNotEmpty) {
      _awaitingText = true;
      _awaitingTimeout?.cancel();
      _awaitingTimeout = Timer(const Duration(milliseconds: 1500), () {
        if (mounted && _awaitingText && !widget.transcribing) {
          setState(_stopAwaiting);
        }
      });
    }
    _setHold(_Hold.none);
    widget.onRecordStop();
    _beat(PresenceEvent.listenSend, origin);
  }

  void _stopAwaiting() {
    _awaitingText = false;
    _awaitingTimeout?.cancel();
    _awaitingTimeout = null;
  }

  void _cancelVoice() {
    final origin = _actionCentre();
    _drag.value = Offset.zero;
    _setHold(_Hold.none);
    widget.onCancelRecording?.call();
    _beat(PresenceEvent.listenCancel, origin);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_pointer != null || !widget.enabled || _action != _Action.mic) {
      return;
    }
    _pointer = event.pointer;
    _downAt = event.position;
    _downStamp = event.timeStamp;
    _beginVoice(_Hold.holding);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || !_holding) {
      return;
    }
    final delta = event.position - _downAt;
    final left = math.max(0.0, -delta.dx);
    final up = math.max(0.0, -delta.dy);
    if (left >= up) {
      _drag.value = Offset(_canCancel ? -left : 0, 0);
      if (_canCancel && left >= kVoiceCancelDistance) {
        _cancelVoice();
      }
    } else {
      _drag.value = Offset(0, -up);
      if (up >= kVoiceLockDistance) {
        _lock();
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _pointer = null;
    if (!_holding) {
      return;
    }
    if (!widget.recording) {
      _setHold(_Hold.none);
    } else if (event.timeStamp - _downStamp < kVoiceTapThreshold) {
      _lock(haptic: false);
    } else {
      _sendVoice();
    }
    _drag.value = Offset.zero;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _pointer = null;
    if (_holding) {
      // Something took the touch (for example the mic permission dialog):
      // keep listening hands-free rather than lose or send the audio.
      if (widget.recording) {
        _lock(haptic: false);
      } else {
        _setHold(_Hold.none);
      }
    }
    _drag.value = Offset.zero;
  }

  // ---------------------------------------------------------------- text

  void _send() {
    if (!_canSend) {
      return;
    }
    final local =
        widget.pendingImages.isEmpty &&
        parseSlash(widget.controller.text) != null;
    if (!local) {
      _beat(PresenceEvent.send);
    }
    widget.onSend();
  }

  void _runCommand(SlashCommandInfo info) {
    final command = TextEditingValue(
      text: info.command,
      selection: TextSelection.collapsed(offset: info.command.length),
    );
    _haptic(HapticFeedback.selectionClick);
    if (widget.sending) {
      // Only /stop makes sense mid-reply; anything else waits in the field.
      if (info.command == '/stop') {
        widget.controller.clear();
        widget.onStop();
      } else {
        widget.controller.value = command;
      }
      return;
    }
    widget.controller.value = command;
    if (widget.enabled) {
      widget.onSend();
    }
  }

  String get _hint {
    if (!widget.enabled && !widget.sending) {
      return 'Connecting to Hermes…';
    }
    return widget.pendingImages.isEmpty ? 'Message Hermsy' : 'Add a caption';
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final calm = _calm;
    final mode = _mode;
    final voice = mode == _Mode.voice;
    // With photos attached a command would go to Frank as their caption,
    // so the palette only offers commands for a text-only draft.
    final palette =
        mode == _Mode.compose && widget.enabled && widget.pendingImages.isEmpty
        ? _matches
        : const <SlashCommandInfo>[];
    final lit =
        _focused || _hasText || voice || widget.pendingImages.isNotEmpty;
    final rim = _keyboardOpen && (widget.sending || _transcribing);
    final onDeviceWords = voice && widget.onDeviceDictation;

    final capsule = Stack(
      clipBehavior: Clip.none,
      children: [
        TweenAnimationBuilder<Color?>(
          tween: ColorTween(
            end: lit ? AppColors.strokeStrong : AppColors.hairline,
          ),
          duration: AppMotion.short,
          curve: AppMotion.standard,
          builder: (context, border, child) {
            return GlassPanel(
              radius: AppRadii.xl,
              borderColor: border,
              padding: const EdgeInsets.all(2),
              child: child!,
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PendingStrip(
                paths: widget.pendingImages,
                onRemove: widget.onRemoveImage,
              ),
              AnimatedSize(
                duration: AppMotion.quick,
                curve: AppMotion.standard,
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _leading(mode),
                      Expanded(child: _centre(mode, calm)),
                      _actionSlot(calm),
                      // Mic, then the call, as in other voice-first apps.
                      if (widget.onCall != null && _action == _Action.mic)
                        _GoldCircleButton(
                          tooltip: 'Voice call',
                          icon: Icons.graphic_eq_rounded,
                          onPressed: widget.enabled ? widget.onCall : null,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: -10,
          top: -10,
          right: -10,
          bottom: -10,
          child: _AuroraRim(active: rim, calm: calm),
        ),
        // Sits 8dp above the capsule at its own height, so large text grows
        // the chip upward instead of clipping it.
        Positioned(
          left: 0,
          right: 56,
          top: -8,
          child: FractionalTranslation(
            translation: const Offset(0, -1),
            child: _HintLane(
              text: _holding
                  ? (_canCancel
                        ? 'Slide left to cancel · up to lock'
                        : 'Slide up to lock')
                  : onDeviceWords
                  ? 'Listening on device'
                  : null,
              chevron: _holding && _canCancel,
              drag: _drag,
            ),
          ),
        ),
        Positioned(
          right: 6,
          top: -96,
          width: 40,
          height: 76,
          child: _LockPill(
            visible: _holding,
            locked: _hold == _Hold.locked,
            drag: _drag,
            calm: calm,
          ),
        ),
        Positioned(
          right: -6,
          bottom: -6,
          width: 64,
          height: 64,
          child: _HoldBubble(
            visible: _holding,
            drag: _drag,
            amp: _meter.amp,
            calm: calm,
          ),
        ),
      ],
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PaletteSlot(commands: palette, onSelect: _runCommand, calm: calm),
            capsule,
          ],
        ),
      ),
    );
  }

  Widget _leading(_Mode mode) {
    final Widget child;
    if (mode == _Mode.voice && _canCancel) {
      child = _CancelButton(
        key: const ValueKey('cancel'),
        drag: _drag,
        onPressed: _cancelVoice,
      );
    } else if (mode == _Mode.compose &&
        widget.onAttach != null &&
        !widget.sending) {
      child = FrankIconButton(
        key: const ValueKey('attach'),
        icon: Icons.add_rounded,
        tooltip: 'Attach photo',
        onPressed: widget.enabled ? widget.onAttach : null,
      );
    } else {
      child = const SizedBox(key: ValueKey('gap'), width: 12, height: 48);
    }
    return AnimatedSize(
      duration: AppMotion.short,
      curve: AppMotion.standard,
      alignment: Alignment.centerLeft,
      child: AnimatedSwitcher(
        duration: AppMotion.quick,
        layoutBuilder: _sizeToCurrent,
        child: child,
      ),
    );
  }

  Widget _centre(_Mode mode, bool calm) {
    final compose = mode == _Mode.compose;
    final Widget overlay = switch (mode) {
      _Mode.compose => const SizedBox.shrink(key: ValueKey('none')),
      _Mode.voice => _VoiceTrack(
        key: const ValueKey('voice'),
        meter: _meter,
        transcript: widget.onDeviceDictation ? widget.transcript : null,
        drag: _drag,
        holding: _holding,
      ),
      _Mode.transcribing => SizedBox(
        key: const ValueKey('transcribing'),
        height: 48,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 4),
            child: ShimmerText(
              'Transcribing',
              style: AppText.label.copyWith(color: AppColors.secondary),
              highlight: AppColors.whiteHot,
              enabled: !calm,
            ),
          ),
        ),
      ),
    };
    // The field stays mounted under the voice and transcribing rows, so a
    // hold that starts with the keyboard up does not drop it (and shift the
    // capsule away from the thumb).
    return ConstrainedBox(
      constraints: compose
          ? const BoxConstraints()
          : const BoxConstraints.tightFor(height: 48),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          IgnorePointer(
            ignoring: !compose,
            child: ExcludeSemantics(
              excluding: !compose,
              child: AnimatedOpacity(
                opacity: compose ? 1 : 0,
                duration: compose
                    ? AppMotion.short
                    : const Duration(milliseconds: 120),
                curve: compose
                    ? const Interval(0.35, 1, curve: AppMotion.standard)
                    : AppMotion.standard,
                child: _field(),
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: AppMotion.short,
              switchInCurve: const Interval(0.35, 1, curve: AppMotion.standard),
              switchOutCurve: const Interval(0.4, 1, curve: AppMotion.standard),
              layoutBuilder: (current, previous) {
                return Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, ?current],
                );
              },
              child: overlay,
            ),
          ),
        ],
      ),
    );
  }

  Widget _field() {
    return TextField(
      controller: widget.controller,
      focusNode: _focus,
      enabled: widget.enabled,
      minLines: 1,
      maxLines: 6,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.send,
      keyboardAppearance: Brightness.dark,
      onSubmitted: (_) => _send(),
      // Keep the keyboard up after sending so the next thought can follow.
      onEditingComplete: () {},
      style: _fieldStyle,
      strutStyle: _fieldStrut,
      cursorColor: AppColors.gold,
      cursorWidth: 2,
      cursorRadius: const Radius.circular(1),
      decoration: InputDecoration(
        hintText: _hint,
        hintStyle: _fieldStyle.copyWith(color: AppColors.hint),
        hintMaxLines: 1,
        isCollapsed: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        contentPadding: const EdgeInsets.fromLTRB(4, 12.8, 8, 12.8),
      ),
    );
  }

  Widget _actionSlot(bool calm) {
    final action = _action;
    final Widget glyph = switch (action) {
      _Action.mic => _MicGlyph(
        enabled: widget.enabled,
        onActivate: () {
          if (widget.enabled && _action == _Action.mic) {
            _beginVoice(_Hold.locked);
          }
        },
      ),
      _Action.send => _GoldCircleButton(
        tooltip: 'Send',
        icon: Icons.arrow_upward_rounded,
        onPressed: _canSend ? _send : null,
      ),
      _Action.stop => _RingButton(
        tooltip: 'Stop reply',
        onPressed: widget.onStop,
        calm: calm,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: AppColors.text,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
      // The hold bubble floats over this slot while the finger is down.
      _Action.voiceHold => const SizedBox.square(dimension: AppSpace.minTouch),
      _Action.voiceSend => _GoldCircleButton(
        tooltip: 'Send voice',
        icon: Icons.arrow_upward_rounded,
        onPressed: _sendVoice,
      ),
      _Action.transcribing => _RingButton(
        tooltip: 'Transcribing',
        calm: calm,
        child: Icon(
          Icons.graphic_eq_rounded,
          size: 18,
          color: AppColors.secondary,
        ),
      ),
    };
    return Listener(
      key: _actionKey,
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: AnimatedSwitcher(
            duration: _morphDuration,
            switchInCurve: AppMotion.standard,
            switchOutCurve: AppMotion.standard,
            transitionBuilder: calm ? _fade : _morph,
            child: KeyedSubtree(key: ValueKey(action), child: glyph),
          ),
        ),
      ),
    );
  }
}

TextStyle get _fieldStyle => TextStyle(
  color: AppColors.text,
  fontSize: 16,
  height: 1.4,
  letterSpacing: 0.05,
);

const _fieldStrut = StrutStyle(
  fontSize: 16,
  height: 1.4,
  forceStrutHeight: true,
);

Widget _sizeToCurrent(Widget? current, List<Widget> previous) {
  return Stack(
    clipBehavior: Clip.none,
    alignment: Alignment.centerLeft,
    children: [
      for (final child in previous)
        Positioned(left: 0, top: 0, bottom: 0, child: child),
      ?current,
    ],
  );
}

Widget _fade(Widget child, Animation<double> animation) {
  return FadeTransition(opacity: animation, child: child);
}

/// Mic → send → stop: a quarter turn and a scale up, 160ms.
Widget _morph(Widget child, Animation<double> animation) {
  return FadeTransition(
    opacity: animation,
    child: RotationTransition(
      turns: Tween<double>(begin: -0.25, end: 0).animate(animation),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.6, end: 1).animate(animation),
        child: child,
      ),
    ),
  );
}

// ------------------------------------------------------------------ meter

/// Samples the mic level into a scrolling 48-bar history and a smoothed
/// amplitude. Its ticker runs only while recording.
class _VoiceMeter extends ChangeNotifier {
  _VoiceMeter(TickerProvider vsync) {
    _ticker = vsync.createTicker(_tick);
  }

  static const bars = 48;
  static const _every = 0.04; // seconds per bar

  late final Ticker _ticker;
  final samples = Float32List(bars);

  /// Index of the newest committed sample in [samples].
  int head = 0;

  /// Peak of the bar still filling at the right edge.
  double live = 0;

  /// 0→1 progress towards the next bar; the history glides left with it.
  double phase = 0;

  /// The smoothed level (45ms attack, 140ms release).
  final amp = ValueNotifier<double>(0);

  /// Whole seconds since recording started.
  final seconds = ValueNotifier<int>(0);

  ValueListenable<double>? _level;
  Duration _last = Duration.zero;
  double _since = 0;
  double _amp = 0;

  void start(ValueListenable<double>? level) {
    _level = level;
    if (_ticker.isActive) {
      return;
    }
    samples.fillRange(0, bars, 0);
    head = 0;
    live = 0;
    phase = 0;
    _since = 0;
    _amp = 0;
    _last = Duration.zero;
    amp.value = 0;
    seconds.value = 0;
    _ticker.start();
  }

  void stop() {
    if (!_ticker.isActive) {
      return;
    }
    _ticker.stop();
    amp.value = 0;
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    final target = (_level?.value ?? 0).clamp(0.0, 1.0);
    final tau = target > _amp ? 0.045 : 0.14;
    _amp += (target - _amp) * (1 - math.exp(-dt / tau));
    live = math.max(live, _amp);
    _since += dt;
    while (_since >= _every) {
      head = (head + 1) % bars;
      samples[head] = live;
      live = _amp;
      _since -= _every;
    }
    phase = _since / _every;
    amp.value = _amp;
    seconds.value = elapsed.inSeconds;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    amp.dispose();
    seconds.dispose();
    super.dispose();
  }
}

// ------------------------------------------------------------ voice track

/// The centre of the recording capsule: the live waveform (or on-device
/// words) and the timer. It dims as the finger slides towards cancel.
class _VoiceTrack extends StatelessWidget {
  const _VoiceTrack({
    super.key,
    required this.meter,
    required this.transcript,
    required this.drag,
    required this.holding,
  });

  final _VoiceMeter meter;
  final ValueListenable<String>? transcript;
  final ValueListenable<Offset> drag;

  /// The hold bubble is wider than the button; keep the timer clear of it.
  final bool holding;

  @override
  Widget build(BuildContext context) {
    final Widget wave = RepaintBoundary(
      child: CustomPaint(
        painter: _WavePainter(meter),
        size: const Size(double.infinity, 48),
      ),
    );
    final words = transcript;
    return AnimatedBuilder(
      animation: drag,
      builder: (context, child) {
        final cancel = (-drag.value.dx / kVoiceCancelDistance).clamp(0.0, 1.0);
        return Opacity(opacity: 1 - 0.7 * cancel, child: child);
      },
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(
              child: words == null
                  ? wave
                  : ValueListenableBuilder<String>(
                      valueListenable: words,
                      builder: (context, value, _) {
                        final text = value.trim();
                        return AnimatedSwitcher(
                          duration: AppMotion.short,
                          child: text.isEmpty
                              ? KeyedSubtree(
                                  key: const ValueKey('wave'),
                                  child: wave,
                                )
                              : _TailText(key: const ValueKey('words'), text),
                        );
                      },
                    ),
            ),
            const SizedBox(width: 10),
            ValueListenableBuilder<int>(
              valueListenable: meter.seconds,
              builder: (context, value, _) {
                return Text(
                  formatVoiceClock(value),
                  style: AppText.tabular.copyWith(
                    color: AppColors.text,
                    fontSize: 14,
                  ),
                );
              },
            ),
            AnimatedContainer(
              duration: AppMotion.short,
              curve: AppMotion.standard,
              width: holding ? 20 : 6,
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of live words that keeps the newest ones in view, fading the
/// start once the line overflows.
class _TailText extends StatelessWidget {
  const _TailText(this.text, {super.key});

  final String text;

  static TextStyle get _style =>
      TextStyle(color: AppColors.secondary, fontSize: 15, height: 1.3);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: _style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final overflow = painter.width > constraints.maxWidth;
        painter.dispose();
        Widget line = ClipRect(
          child: OverflowBox(
            alignment: overflow ? Alignment.centerRight : Alignment.centerLeft,
            minWidth: 0,
            maxWidth: double.infinity,
            child: Text(text, maxLines: 1, softWrap: false, style: _style),
          ),
        );
        if (overflow) {
          line = ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) {
              return LinearGradient(
                colors: const [Color(0x00FFFFFF), Color(0xFFFFFFFF)],
                stops: [0, math.min(1, 32 / rect.width)],
              ).createShader(rect);
            },
            child: line,
          );
        }
        return line;
      },
    );
  }
}

/// 48 bars (2dp wide, 2dp apart, 4–28dp tall) scrolling right to left in
/// the listening spectrum, newest and brightest on the right.
class _WavePainter extends CustomPainter {
  _WavePainter(this.meter) : super(repaint: meter);

  final _VoiceMeter meter;

  static const _bar = 2.0;
  static const _slot = 4.0;
  static const _minHeight = 4.0;
  static const _maxHeight = 28.0;

  final _paint = Paint();
  Size? _shaderSize;
  bool? _shaderDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) {
      return;
    }
    if (_shaderSize != size || _shaderDark != AppColors.isDark) {
      _shaderSize = size;
      _shaderDark = AppColors.isDark;
      _paint.shader = ui.Gradient.linear(
        Offset.zero,
        Offset(size.width, 0),
        [AppColors.orchid, AppColors.iris, AppColors.azure, AppColors.ion],
        const [0, 0.35, 0.7, 1],
      );
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final mid = size.height / 2;
    final fadeWidth = size.width * 0.3;
    final count = math.min(_VoiceMeter.bars, (size.width / _slot).ceil() + 1);
    for (var k = 0; k < count; k++) {
      final level = k == 0
          ? meter.live
          : meter.samples[(meter.head - k + 1 + _VoiceMeter.bars) %
                _VoiceMeter.bars];
      final x = size.width - _bar - (k - 1 + meter.phase) * _slot;
      if (x < -_bar) {
        break;
      }
      final h =
          _minHeight +
          (_maxHeight - _minHeight) * math.pow(level, 0.8).toDouble();
      var alpha = (x / fadeWidth).clamp(0.12, 1.0);
      if (k == 0) {
        alpha *= meter.phase;
      }
      _paint.color = Color.fromRGBO(255, 255, 255, alpha);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, mid - h / 2, _bar, h),
          const Radius.circular(1),
        ),
        _paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    return !identical(oldDelegate.meter, meter);
  }
}

// ---------------------------------------------------------------- buttons

/// The idle mic. The composer's Listener owns the hold gesture; this claims
/// the pointer so nothing above (drawer, scroll) can steal the slide.
class _MicGlyph extends StatelessWidget {
  const _MicGlyph({required this.enabled, required this.onActivate});

  final bool enabled;

  /// Accessibility tap: start hands-free.
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final glyph = SizedBox.square(
      dimension: AppSpace.minTouch,
      child: Center(
        child: AnimatedOpacity(
          duration: AppMotion.short,
          opacity: enabled ? 1 : 0.4,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.veil(0x0F),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.mic_rounded,
              size: 22,
              color: AppColors.secondary,
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Voice input',
      hint: 'Hold to talk, or tap for hands-free',
      onTap: enabled ? onActivate : null,
      excludeSemantics: true,
      child: enabled
          ? RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              gestures: {
                EagerGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      EagerGestureRecognizer
                    >(EagerGestureRecognizer.new, (_) {}),
              },
              child: glyph,
            )
          : glyph,
    );
  }
}

/// Send (text or voice): Hermes gold with a soft glow.
class _GoldCircleButton extends StatelessWidget {
  const _GoldCircleButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Pressable(
        onTap: onPressed,
        pressedScale: 0.9,
        child: SizedBox.square(
          dimension: AppSpace.minTouch,
          child: Center(
            child: AnimatedContainer(
              duration: AppMotion.short,
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: enabled ? AppGradients.gold : null,
                color: enabled ? null : AppColors.veil(0x0F),
                shape: BoxShape.circle,
                boxShadow: enabled
                    ? [
                        BoxShadow(
                          color: AppColors.gold.withValues(alpha: 0.34),
                          blurRadius: 16,
                          spreadRadius: -3,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                icon,
                size: 22,
                color: enabled ? AppColors.onGold : AppColors.hint,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Stop and transcribing: a quiet disc with a turning aurora ring
/// (1 rev / 1.2s), still under reduced motion.
class _RingButton extends StatefulWidget {
  const _RingButton({
    required this.tooltip,
    required this.child,
    required this.calm,
    this.onPressed,
  });

  final String tooltip;
  final Widget child;
  final bool calm;
  final VoidCallback? onPressed;

  @override
  State<_RingButton> createState() => _RingButtonState();
}

class _RingButtonState extends State<_RingButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _RingButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.calm) {
      _spin.stop();
    } else if (!_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disc = SizedBox.square(
      dimension: AppSpace.minTouch,
      child: Center(
        child: SizedBox.square(
          dimension: 40,
          // The ring spins for the whole reply: keep its repaints local.
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _RingPainter(_spin, still: widget.calm),
              child: Center(
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.veil(0x14),
                    shape: BoxShape.circle,
                  ),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Tooltip(
      message: widget.tooltip,
      child: widget.onPressed == null
          ? disc
          : Pressable(onTap: widget.onPressed, pressedScale: 0.9, child: disc),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.spin, {required this.still}) : super(repaint: spin);

  final Animation<double> spin;
  final bool still;

  final _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round;
  Size? _shaderSize;
  bool? _shaderDark;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    if (_shaderSize != size || _shaderDark != AppColors.isDark) {
      _shaderSize = size;
      _shaderDark = AppColors.isDark;
      _paint.shader = ui.Gradient.sweep(
        centre,
        [
          const Color(0x003DF2E0),
          AppColors.ion,
          AppColors.azure,
          AppColors.iris,
          AppColors.orchid,
        ],
        const [0, 0.35, 0.6, 0.82, 1],
      );
    }
    _paint.color = Color.fromRGBO(255, 255, 255, still ? 0.7 : 1);
    canvas.save();
    // A circle is rotation-invariant, so turning the canvas turns only the
    // gradient: no new shader per frame.
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(spin.value * 2 * math.pi);
    canvas.translate(-centre.dx, -centre.dy);
    canvas.drawCircle(centre, size.shortestSide / 2 - 1, _paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.still != still || !identical(oldDelegate.spin, spin);
  }
}

/// The recording X. It warms towards danger as the finger slides to cancel.
class _CancelButton extends StatelessWidget {
  const _CancelButton({super.key, required this.drag, required this.onPressed});

  final ValueListenable<Offset> drag;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: drag,
      builder: (context, _) {
        final p = (-drag.value.dx / kVoiceCancelDistance).clamp(0.0, 1.0);
        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: 0.7 + 0.3 * p,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.signal.withValues(alpha: 0.18 * p),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            FrankIconButton(
              icon: Icons.close_rounded,
              tooltip: 'Cancel recording',
              color: Color.lerp(AppColors.secondary, AppColors.danger, p),
              onPressed: onPressed,
            ),
          ],
        );
      },
    );
  }
}

// --------------------------------------------------------- hold overlays

/// The gold bubble under the thumb while holding: it breathes with the
/// voice and follows the slide.
class _HoldBubble extends StatefulWidget {
  const _HoldBubble({
    required this.visible,
    required this.drag,
    required this.amp,
    required this.calm,
  });

  final bool visible;
  final ValueListenable<Offset> drag;
  final ValueListenable<double> amp;
  final bool calm;

  @override
  State<_HoldBubble> createState() => _HoldBubbleState();
}

class _HoldBubbleState extends State<_HoldBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _show = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    reverseDuration: AppMotion.quick,
    value: widget.visible ? 1 : 0,
  );
  late Listenable _motion = Listenable.merge([_show, widget.drag, widget.amp]);

  @override
  void didUpdateWidget(covariant _HoldBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.drag != widget.drag || oldWidget.amp != widget.amp) {
      _motion = Listenable.merge([_show, widget.drag, widget.amp]);
    }
    if (widget.visible != oldWidget.visible) {
      widget.visible ? _show.forward() : _show.reverse();
    }
  }

  @override
  void dispose() {
    _show.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _motion,
          builder: (context, child) {
            if (_show.isDismissed) {
              return const SizedBox.shrink();
            }
            final t = _show.value;
            final entry = widget.calm
                ? 1.0
                : _show.status == AnimationStatus.reverse
                ? 0.6 + 0.4 * t
                : Curves.easeOutBack.transform(t) * 0.4 + 0.6;
            final drag = widget.drag.value;
            final cancel = (-drag.dx / kVoiceCancelDistance).clamp(0.0, 1.0);
            final amp = widget.amp.value;
            final scale = entry * (1 + 0.12 * amp) * (1 - 0.18 * cancel);
            return Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(drag.dx, math.max(drag.dy * 0.5, -36)),
                child: CustomPaint(
                  painter: _HaloPainter(amp),
                  child: Transform.scale(scale: scale, child: child),
                ),
              ),
            );
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppGradients.gold,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(Icons.mic_rounded, size: 26, color: AppColors.onGold),
            ),
          ),
        ),
      ),
    );
  }
}

/// A soft gold halo around the hold bubble that swells with the voice.
class _HaloPainter extends CustomPainter {
  _HaloPainter(this.amp);

  final double amp;

  static final _paint = Paint()
    ..shader = ui.Gradient.radial(Offset.zero, 1, [
      AppColors.gold.withValues(alpha: 0.32),
      AppColors.gold.withValues(alpha: 0),
    ]);

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2 * (1.25 + 0.45 * amp);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(radius);
    canvas.drawCircle(Offset.zero, 1, _paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HaloPainter oldDelegate) {
    return oldDelegate.amp != amp;
  }
}

/// The lock target above the mic: the shackle closes as the finger rises.
class _LockPill extends StatefulWidget {
  const _LockPill({
    required this.visible,
    required this.locked,
    required this.drag,
    required this.calm,
  });

  final bool visible;
  final bool locked;
  final ValueListenable<Offset> drag;
  final bool calm;

  @override
  State<_LockPill> createState() => _LockPillState();
}

class _LockPillState extends State<_LockPill> with TickerProviderStateMixin {
  late final AnimationController _show = AnimationController(
    vsync: this,
    duration: AppMotion.short,
    reverseDuration: const Duration(milliseconds: 260),
    value: widget.visible ? 1 : 0,
  );
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    _syncBob();
  }

  @override
  void didUpdateWidget(covariant _LockPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      widget.visible ? _show.forward() : _show.reverse();
    }
    _syncBob();
  }

  void _syncBob() {
    final run = widget.visible && !widget.calm;
    if (run && !_bob.isAnimating) {
      _bob.repeat(reverse: true);
    } else if (!run && _bob.isAnimating) {
      _bob.stop();
    }
  }

  @override
  void dispose() {
    _show.dispose();
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([_show, widget.drag]),
          builder: (context, _) {
            if (_show.isDismissed) {
              return const SizedBox.shrink();
            }
            final t = AppMotion.standard.transform(_show.value);
            final p = widget.locked
                ? 1.0
                : (-widget.drag.value.dy / kVoiceLockDistance).clamp(0.0, 1.0);
            final tint = Color.lerp(AppColors.secondary, AppColors.gold, p)!;
            final rise = widget.calm ? 0.0 : (1 - t) * 12;
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, rise - 10 * p),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border: Border.all(
                      color: Color.lerp(
                        AppColors.strokeStrong,
                        AppColors.gold.withValues(alpha: 0.6),
                        p,
                      )!,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Transform.scale(
                        scale: 1 + 0.12 * p,
                        child: Icon(
                          p >= 1 ? Icons.lock_rounded : Icons.lock_open_rounded,
                          size: 18,
                          color: tint,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Opacity(
                        opacity: 1 - p,
                        child: AnimatedBuilder(
                          animation: _bob,
                          builder: (context, child) {
                            final y =
                                -3 * Curves.easeInOut.transform(_bob.value);
                            return Transform.translate(
                              offset: Offset(0, y),
                              child: child,
                            );
                          },
                          child: Icon(
                            Icons.keyboard_arrow_up_rounded,
                            size: 18,
                            color: AppColors.hint,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The one-line hint above the capsule ("Slide left to cancel · up to
/// lock"), which drifts with the finger and warms near the threshold.
class _HintLane extends StatelessWidget {
  const _HintLane({
    required this.text,
    required this.chevron,
    required this.drag,
  });

  final String? text;
  final bool chevron;
  final ValueListenable<Offset> drag;

  @override
  Widget build(BuildContext context) {
    final label = text;
    return IgnorePointer(
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: AnimatedSwitcher(
          duration: AppMotion.quick,
          child: label == null
              ? const SizedBox.shrink()
              : AnimatedBuilder(
                  key: ValueKey(label),
                  animation: drag,
                  builder: (context, child) {
                    final p = (-drag.value.dx / kVoiceCancelDistance).clamp(
                      0.0,
                      1.0,
                    );
                    final color = Color.lerp(
                      AppColors.secondary,
                      AppColors.danger,
                      ((p - 0.6) / 0.4).clamp(0.0, 1.0),
                    )!;
                    return Transform.translate(
                      offset: Offset(drag.value.dx * 0.4, 0),
                      child: Opacity(
                        opacity: 1 - 0.5 * p,
                        child: Center(
                          child: _HintChip(
                            label: label,
                            chevron: chevron,
                            color: color,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip({
    required this.label,
    required this.chevron,
    required this.color,
  });

  final String label;
  final bool chevron;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(chevron ? 6 : 12, 4, 12, 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (chevron) ...[
            Icon(Icons.chevron_left_rounded, size: 16, color: color),
            const SizedBox(width: 2),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// While Frank works with the keyboard up, the bottom edge glow is hidden
/// behind the IME, so the capsule carries a thin turning aurora rim.
class _AuroraRim extends StatefulWidget {
  const _AuroraRim({required this.active, required this.calm});

  final bool active;
  final bool calm;

  @override
  State<_AuroraRim> createState() => _AuroraRimState();
}

class _AuroraRimState extends State<_AuroraRim> with TickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: AppMotion.medium,
    reverseDuration: AppMotion.short,
    value: widget.active ? 1 : 0,
  )..addStatusListener(_onFade);
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );

  @override
  void initState() {
    super.initState();
    _syncSpin();
  }

  @override
  void didUpdateWidget(covariant _AuroraRim oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      widget.active ? _fade.forward() : _fade.reverse();
    }
    _syncSpin();
  }

  void _onFade(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      _syncSpin();
      setState(() {});
    }
  }

  void _syncSpin() {
    final run = !widget.calm && (widget.active || !_fade.isDismissed);
    if (run && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!run && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active && _fade.isDismissed) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _RimPainter(spin: _spin, fade: _fade),
        ),
      ),
    );
  }
}

class _RimPainter extends CustomPainter {
  _RimPainter({required this.spin, required this.fade})
    : super(repaint: Listenable.merge([spin, fade]));

  final Animation<double> spin;
  final Animation<double> fade;

  static const _inset = 10.0;
  static List<Color> get _colors => [
    AppColors.ion,
    AppColors.azure,
    AppColors.iris,
    AppColors.orchid,
    AppColors.ion,
  ];

  final _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  final _soft = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 6
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

  @override
  void paint(Canvas canvas, Size size) {
    final opacity = fade.value;
    if (opacity <= 0.002) {
      return;
    }
    final rect = (Offset.zero & size).deflate(_inset);
    final rrect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(AppRadii.xl),
    );
    final shader = SweepGradient(
      colors: _colors,
      transform: GradientRotation(spin.value * 2 * math.pi),
    ).createShader(rect);
    _soft
      ..shader = shader
      ..color = Color.fromRGBO(255, 255, 255, 0.55 * opacity);
    _line
      ..shader = shader
      ..color = Color.fromRGBO(255, 255, 255, 0.9 * opacity);
    canvas.drawRRect(rrect, _soft);
    canvas.drawRRect(rrect, _line);
  }

  @override
  bool shouldRepaint(covariant _RimPainter oldDelegate) {
    return !identical(oldDelegate.spin, spin) ||
        !identical(oldDelegate.fade, fade);
  }
}

// ------------------------------------------------------------- palette

/// Holds the slash palette above the capsule: fades and rises in over
/// 160ms, and gives its room back smoothly when it leaves.
class _PaletteSlot extends StatelessWidget {
  const _PaletteSlot({
    required this.commands,
    required this.onSelect,
    required this.calm,
  });

  final List<SlashCommandInfo> commands;
  final ValueChanged<SlashCommandInfo> onSelect;
  final bool calm;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: _morphDuration,
      curve: AppMotion.standard,
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none,
      child: AnimatedSwitcher(
        duration: _morphDuration,
        switchInCurve: AppMotion.enter,
        switchOutCurve: AppMotion.exit,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: calm
                ? child
                : AnimatedBuilder(
                    animation: animation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, (1 - animation.value) * 8),
                        child: child,
                      );
                    },
                    child: child,
                  ),
          );
        },
        child: commands.isEmpty
            ? const SizedBox(key: ValueKey('none'), width: double.infinity)
            : Padding(
                key: const ValueKey('palette'),
                padding: const EdgeInsets.only(bottom: 8),
                child: SlashPalette(commands: commands, onSelect: onSelect),
              ),
      ),
    );
  }
}

// ------------------------------------------------------- pending images

class _PendingStrip extends StatelessWidget {
  const _PendingStrip({required this.paths, required this.onRemove});

  final List<String> paths;
  final ValueChanged<String>? onRemove;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: AppMotion.short,
      curve: AppMotion.standard,
      alignment: Alignment.bottomCenter,
      child: paths.isEmpty
          ? const SizedBox(width: double.infinity)
          : SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                itemCount: paths.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final path = paths[index];
                  final remove = onRemove;
                  return _PendingImage(
                    path: path,
                    onRemove: remove == null ? null : () => remove(path),
                  );
                },
              ),
            ),
    );
  }
}

class _PendingImage extends StatelessWidget {
  const _PendingImage({required this.path, this.onRemove});

  final String path;
  final VoidCallback? onRemove;

  static const _size = 64.0;

  @override
  Widget build(BuildContext context) {
    final cache = (_size * MediaQuery.devicePixelRatioOf(context)).round();
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(path),
              width: _size,
              height: _size,
              cacheWidth: cache,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) {
                return ColoredBox(
                  color: AppColors.surfaceHigh,
                  child: SizedBox.expand(
                    child: Icon(
                      Icons.broken_image_rounded,
                      size: 20,
                      color: AppColors.hint,
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.hairline),
                ),
              ),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 0,
              right: 0,
              child: Tooltip(
                message: 'Remove photo',
                child: Semantics(
                  button: true,
                  label: 'Remove photo',
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onRemove,
                    child: Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.topRight,
                      padding: const EdgeInsets.all(4),
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: const Color(0xB3000000),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.strokeStrong),
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 13,
                          color: AppColors.text,
                        ),
                      ),
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
