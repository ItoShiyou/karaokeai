import 'dart:math' as math;

import 'package:karaokeai_core/karaokeai_core.dart';
import 'package:test/test.dart';

List<double> sine(double hz, double seconds, int sr, {double amp = 0.5}) => [
      for (var i = 0; i < seconds * sr; i++)
        amp * math.sin(2 * math.pi * hz * i / sr)
    ];

double medianVoiced(PitchTrack t) {
  final v = t.hz.where((h) => h > 0).toList()..sort();
  return v[v.length ~/ 2];
}

void main() {
  const sr = 16000;

  for (final f in [110.0, 220.0, 440.0, 880.0]) {
    test('detects $f Hz sine', () {
      final t = estimatePitchYin(sine(f, 1, sr), sr);
      expect(medianVoiced(t), closeTo(f, f * 0.01));
    });
  }

  test('detects harmonic-rich tone without octave error', () {
    const f = 196.0;
    final x = [
      for (var i = 0; i < sr; i++)
        0.4 * math.sin(2 * math.pi * f * i / sr) +
            0.3 * math.sin(2 * math.pi * 2 * f * i / sr) +
            0.2 * math.sin(2 * math.pi * 3 * f * i / sr)
    ];
    expect(medianVoiced(estimatePitchYin(x, sr)), closeTo(f, f * 0.01));
  });

  test('silence is unvoiced', () {
    final t = estimatePitchYin(List.filled(sr, 0.0), sr);
    expect(t.hz.every((h) => h == 0), isTrue);
  });

  test('white noise is mostly unvoiced', () {
    final r = math.Random(3);
    final t = estimatePitchYin(
        [for (var i = 0; i < sr; i++) r.nextDouble() - 0.5], sr);
    final voiced = t.hz.where((h) => h > 0).length;
    expect(voiced / t.length, lessThan(0.2));
  });

  test('tracks a pitch change', () {
    final x = [...sine(220, 0.5, sr), ...sine(330, 0.5, sr)];
    final t = estimatePitchYin(x, sr);
    expect(t.hz[20], closeTo(220, 4));
    expect(t.hz[80], closeTo(330, 6));
  });
}
