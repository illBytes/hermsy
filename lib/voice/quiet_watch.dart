import 'dart:async';

/// Notices a call left alone. Counting only while Hermsy is listening, it
/// checks in after [checkIn] of quiet, and gives up after [giveUp] more with
/// no answer. Thinking and speaking never count: a slow reply is not you
/// being gone.
class QuietWatch {
  QuietWatch({
    required this.checkIn,
    required this.giveUp,
    required this.onCheckIn,
    required this.onGiveUp,
  });

  final Duration checkIn;
  final Duration giveUp;

  /// Quiet for [checkIn]: ask whether you are still there.
  final void Function() onCheckIn;

  /// Still quiet [giveUp] after asking: hang up.
  final void Function() onGiveUp;

  Timer? _timer;

  /// Hermsy asked and has not heard from you since.
  bool get asked => _asked;
  var _asked = false;

  /// Listening again: count the quiet from now.
  void listening() {
    _timer?.cancel();
    _timer = Timer(_asked ? giveUp : checkIn, () {
      _timer = null;
      if (_asked) {
        onGiveUp();
      } else {
        _asked = true;
        onCheckIn();
      }
    });
  }

  /// You spoke or tapped: you are there. Counting starts again at the next
  /// [listening].
  void heardYou() {
    _asked = false;
    _timer?.cancel();
  }

  /// Thinking, speaking or hung up: stop counting.
  void pause() => _timer?.cancel();
}
