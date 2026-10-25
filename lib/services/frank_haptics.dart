import 'package:flutter/services.dart';

import 'app_settings.dart';

/// Frank's haptic vocabulary, gated by the Haptics setting.
class FrankHaptics {
  FrankHaptics(this.settings, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final AppSettings settings;
  final DateTime Function() _clock;

  /// True while the mic is open. Ambient taps (a tool starting, a reply
  /// finishing) stay quiet so they never buzz into a recording.
  bool muted = false;

  /// Tool taps come at most this often, so a burst of tools reads as one
  /// beat instead of a rattle.
  static const toolSpacing = Duration(milliseconds: 600);

  DateTime? _lastTool;

  void send() => _run(HapticFeedback.lightImpact);

  /// A tool started. Muted while recording, and at most one per
  /// [toolSpacing].
  void tool() {
    if (muted) {
      return;
    }
    final now = _clock();
    final last = _lastTool;
    if (last != null && now.difference(last) < toolSpacing) {
      return;
    }
    _lastTool = now;
    _run(HapticFeedback.selectionClick);
  }

  /// A reply finished. Muted while recording.
  void done() {
    if (muted) {
      return;
    }
    _run(HapticFeedback.mediumImpact);
  }

  void tap() => _run(HapticFeedback.selectionClick);
  void lock() => _run(HapticFeedback.lightImpact);

  /// The mic opened.
  void listenStart() => _run(HapticFeedback.mediumImpact);

  /// Voice was discarded, or a hold-to-talk threshold was crossed.
  void listenCancel() => _run(HapticFeedback.selectionClick);

  /// Voice was sent for transcription.
  void listenSend() => _run(HapticFeedback.lightImpact);

  /// Something failed: two light knocks.
  void error() {
    if (!settings.haptics) {
      // No second knock to schedule (and no timer left pending).
      return;
    }
    _run(HapticFeedback.lightImpact);
    Future<void>.delayed(
      const Duration(milliseconds: 90),
      () => _run(HapticFeedback.lightImpact),
    );
  }

  /// The app unlocked.
  void unlock() => _run(HapticFeedback.lightImpact);

  /// A wrong PIN.
  void pinWrong() => _run(HapticFeedback.heavyImpact);

  void _run(Future<void> Function() feedback) {
    if (!settings.haptics) {
      return;
    }
    feedback();
  }
}
