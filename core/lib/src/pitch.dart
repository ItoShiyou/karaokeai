import 'dart:math' as math;

/// A pitch track sampled at a fixed hop. `hz <= 0` or NaN means unvoiced.
class PitchTrack {
  PitchTrack(this.hopSeconds, List<double> hz) : hz = List.unmodifiable(hz);

  final double hopSeconds;
  final List<double> hz;

  int get length => hz.length;
  double get durationSeconds => length * hopSeconds;

  bool isVoicedAt(int i) => i >= 0 && i < length && hz[i] > 0 && !hz[i].isNaN;

  /// Cents relative to 440Hz; null when unvoiced.
  double? centsAt(int i) => isVoicedAt(i) ? hzToCents(hz[i]) : null;

  /// Returns a track delayed by [seconds] (positive) or advanced (negative),
  /// keeping length. Vacated frames are unvoiced.
  PitchTrack shifted(double seconds) {
    final n = (seconds / hopSeconds).round();
    final out = List<double>.filled(length, 0);
    for (var i = 0; i < length; i++) {
      final j = i - n;
      if (j >= 0 && j < length) out[i] = hz[j];
    }
    return PitchTrack(hopSeconds, out);
  }
}

double hzToCents(double hz) => 1200 * (math.log(hz / 440) / math.ln2);

/// Median filter over voiced frames only (window must be odd). Unvoiced
/// frames stay unvoiced; this suppresses short spikes such as cloth noise.
PitchTrack medianSmooth(PitchTrack t, {int window = 5}) {
  assert(window.isOdd);
  final r = window ~/ 2;
  final out = List<double>.filled(t.length, 0);
  for (var i = 0; i < t.length; i++) {
    if (!t.isVoicedAt(i)) continue;
    final vals = <double>[];
    for (var j = i - r; j <= i + r; j++) {
      if (t.isVoicedAt(j)) vals.add(t.hz[j]);
    }
    vals.sort();
    out[i] = vals[vals.length ~/ 2];
  }
  return PitchTrack(t.hopSeconds, out);
}

/// Drops frames outside the vocal band (default 80-1000Hz).
PitchTrack bandLimit(PitchTrack t, {double lo = 80, double hi = 1000}) {
  return PitchTrack(
    t.hopSeconds,
    [for (final h in t.hz) (h >= lo && h <= hi) ? h : 0.0],
  );
}
