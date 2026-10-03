import 'dart:math' as math;

import 'pitch.dart';

class ScoreResult {
  const ScoreResult({
    required this.total,
    required this.pitch,
    required this.rhythm,
    required this.sections,
    required this.keyOffsetCents,
  });

  /// 0-100.
  final double total;
  final double pitch;
  final double rhythm;
  final List<double> sections;

  /// Median singer-vs-reference offset; a consistent offset is treated as a
  /// different key, not as an error (relative pitch).
  final double keyOffsetCents;
}

/// Compares the singer's pitch to the reference track.
///
/// [latencySeconds] shifts the *reference* (never the backing playback).
/// Pitch is relative: the median offset is removed and octave jumps folded.
ScoreResult scoreSinging({
  required PitchTrack reference,
  required PitchTrack singer,
  double latencySeconds = 0,
  double toleranceCents = 100,
  double sectionSeconds = 8,
}) {
  assert((reference.hopSeconds - singer.hopSeconds).abs() < 1e-9);
  final ref = reference.shifted(latencySeconds);
  final n = math.min(ref.length, singer.length);

  // Octave-folded pitch differences on frames where both are voiced.
  final diffs = <int, double>{};
  for (var i = 0; i < n; i++) {
    final a = ref.centsAt(i), b = singer.centsAt(i);
    if (a == null || b == null) continue;
    diffs[i] = _foldOctave(b - a);
  }
  if (diffs.isEmpty) {
    return const ScoreResult(
        total: 0, pitch: 0, rhythm: 0, sections: [], keyOffsetCents: 0);
  }
  final sorted = diffs.values.toList()..sort();
  final offset = sorted[sorted.length ~/ 2];

  double frameScore(double d) {
    final err = (_foldOctave(d - offset)).abs();
    return (1 - err / toleranceCents).clamp(0.0, 1.0);
  }

  // Rhythm: voiced/unvoiced agreement over frames where the reference sings.
  var refVoiced = 0, agree = 0;
  for (var i = 0; i < n; i++) {
    if (ref.isVoicedAt(i)) {
      refVoiced++;
      if (singer.isVoicedAt(i)) agree++;
    }
  }
  final rhythm = refVoiced == 0 ? 0.0 : agree / refVoiced;

  // Pitch: mean over reference-voiced frames (missed frames count as 0).
  var pitchSum = 0.0;
  for (final e in diffs.entries) {
    pitchSum += frameScore(e.value);
  }
  final pitch = refVoiced == 0 ? 0.0 : pitchSum / refVoiced;

  // Sections: trend per window so brief glitches don't dominate.
  final secFrames = math.max(1, (sectionSeconds / ref.hopSeconds).round());
  final sections = <double>[];
  for (var s = 0; s < n; s += secFrames) {
    var cnt = 0;
    var sum = 0.0;
    for (var i = s; i < math.min(n, s + secFrames); i++) {
      if (!ref.isVoicedAt(i)) continue;
      cnt++;
      final d = diffs[i];
      if (d != null) sum += frameScore(d);
    }
    if (cnt > 0) sections.add(100 * sum / cnt);
  }

  final total = 100 * (0.7 * pitch + 0.3 * rhythm);
  return ScoreResult(
    total: total,
    pitch: 100 * pitch,
    rhythm: 100 * rhythm,
    sections: sections,
    keyOffsetCents: offset,
  );
}

double _foldOctave(double cents) {
  var c = cents % 1200;
  if (c > 600) c -= 1200;
  if (c < -600) c += 1200;
  return c;
}

/// Spoken result text for the end of a song (read out via TTS).
String spokenSummary(ScoreResult r) {
  final t = r.total.round();
  final comment = t >= 90
      ? '素晴らしい'
      : t >= 75
          ? 'とても良い'
          : t >= 60
              ? '良い調子'
              : 'もう少し';
  return '$t点。$comment。';
}
