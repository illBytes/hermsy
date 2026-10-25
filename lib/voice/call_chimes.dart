import 'dart:math' as math;
import 'dart:typed_data';

/// Sample rate of the chimes.
const chimeSampleRate = 24000;

/// "Velvet": a low major chord (D4, F#4, A4) rolled softly upwards. Frank
/// is listening, you can talk.
final readyChime = _velvet(
  const [(293.66, 0.9), (369.99, 0.8), (440.0, 0.75)],
  gap: 0.07,
  decay: 0.30,
  length: 1.1,
);

/// The same chord rolled downwards: the call has ended.
final endChime = _velvet(
  const [(440.0, 0.75), (369.99, 0.8), (293.66, 0.9)],
  gap: 0.08,
  decay: 0.34,
  length: 1.2,
);

/// How long [chime] plays, its quiet room tail included.
Duration chimeLength(Float32List chime) =>
    Duration(microseconds: chime.length * 1000000 ~/ chimeSampleRate);

/// How long [chime] is clearly heard: until it falls under a twentieth of
/// its peak. Frank starts listening, or lets go of the audio, after this;
/// the tail that follows is too quiet to matter.
Duration chimeHeard(Float32List chime) {
  var peak = 0.0;
  for (final sample in chime) {
    peak = math.max(peak, sample.abs());
  }
  var last = 0;
  for (var i = 0; i < chime.length; i++) {
    if (chime[i].abs() > peak / 20) {
      last = i;
    }
  }
  return Duration(microseconds: last * 1000000 ~/ chimeSampleRate);
}

/// Warm notes [gap] seconds apart, each two slightly detuned sines with a
/// smooth swell and a slow fade (no bright overtones), in a soft room.
Float32List _velvet(
  List<(double, double)> notes, {
  required double gap,
  required double decay,
  required double length,
  double attack = 0.03,
  double detune = 0.0025,
  double volume = 0.30,
}) {
  final n = (length * chimeSampleRate).round();
  final dry = Float64List(n);
  for (var k = 0; k < notes.length; k++) {
    final (frequency, level) = notes[k];
    final start = (k * gap * chimeSampleRate).round();
    for (var i = 0; start + i < n; i++) {
      final t = i / chimeSampleRate;
      final rise = 0.5 - 0.5 * math.cos(math.pi * math.min(1.0, t / attack));
      final envelope = rise * math.exp(-math.max(0.0, t - attack) / decay);
      final a = math.sin(2 * math.pi * frequency * t);
      final b = math.sin(2 * math.pi * frequency * (1 + detune) * t);
      dry[start + i] += level * envelope * 0.5 * (a + b);
    }
  }
  // A few quiet echoes, so it sits in a room rather than at your ear.
  const taps = [(0.031, 0.32), (0.047, 0.24), (0.071, 0.16), (0.113, 0.10)];
  final wet = Float64List(n + (0.5 * chimeSampleRate).round());
  for (var i = 0; i < n; i++) {
    wet[i] += dry[i];
  }
  for (final (delay, level) in taps) {
    final d = (delay * chimeSampleRate).round();
    for (var i = 0; i < n; i++) {
      wet[i + d] += dry[i] * level;
    }
  }
  var peak = 0.0;
  for (final sample in wet) {
    peak = math.max(peak, sample.abs());
  }
  final out = Float32List(wet.length);
  for (var i = 0; i < wet.length; i++) {
    out[i] = wet[i] * volume / peak;
  }
  // Fade the last few milliseconds so the clip never ends on a click.
  final tail = (0.01 * chimeSampleRate).round();
  for (var i = 0; i < tail; i++) {
    out[out.length - 1 - i] *= i / tail;
  }
  return out;
}
