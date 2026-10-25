import 'dart:async';

/// Gathers what you say in a call into one turn. A stretch of speech ends
/// at a short silence; the turn ends only when you stay quiet for [pause]
/// after it. Talk again in time and it all goes as one.
class TurnHold {
  TurnHold({required this.pause, required this.onTurn});

  final Duration pause;

  /// Called with the whole turn once you have paused long enough.
  final void Function(String text) onTurn;

  final _parts = <String>[];
  Timer? _timer;

  /// What you have said so far this turn.
  String get text => _parts.join(' ');

  /// Talking again: hold off.
  void speechStarted() => _timer?.cancel();

  /// Quiet again. Waits for more if anything was said (a noise that
  /// started the detector but said nothing must not hold the turn open).
  void speechEnded() {
    if (_parts.isNotEmpty) {
      _wait();
    }
  }

  /// A stretch of speech, transcribed.
  void heard(String words) {
    final said = words.trim();
    if (said.isNotEmpty) {
      _parts.add(said);
    }
    if (_parts.isNotEmpty) {
      _wait();
    }
  }

  /// Drops what was held (hang-up).
  void clear() {
    _timer?.cancel();
    _parts.clear();
  }

  void _wait() {
    _timer?.cancel();
    _timer = Timer(pause, () {
      final turn = text;
      _parts.clear();
      if (turn.isNotEmpty) {
        onTurn(turn);
      }
    });
  }
}
