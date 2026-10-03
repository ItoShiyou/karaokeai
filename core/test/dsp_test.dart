import 'dart:math' as math;
import 'dart:typed_data';

import 'package:karaokeai_core/karaokeai_core.dart';
import 'package:test/test.dart';

double rms(Float64List x) =>
    math.sqrt(x.fold(0.0, (a, v) => a + v * v) / x.length);

void main() {
  const sr = 16000;
  Float64List tone(double hz, int n) => Float64List.fromList(
      [for (var i = 0; i < n; i++) 0.4 * math.sin(2 * math.pi * hz * i / sr)]);

  test('WAV round trip', () {
    final a = PcmAudio(sr, [tone(440, 1000), tone(220, 1000)]);
    final b = decodeWav(encodeWav(a));
    expect(b.sampleRate, sr);
    expect(b.channels.length, 2);
    expect(b.length, 1000);
    expect(b.channels[0][100], closeTo(a.channels[0][100], 1e-3));
  });

  test('rejects non-WAV', () {
    expect(() => decodeWav(Uint8List(100)), throwsFormatException);
  });

  test('centre-panned voice is removed, side instrument kept', () {
    final voice = tone(440, sr); // identical in L and R
    final guitar = tone(1500, sr); // only left
    final l = Float64List.fromList([for (var i = 0; i < sr; i++) voice[i] + guitar[i]]);
    final r = Float64List.fromList(voice);
    final acc = removeCenterVocals(PcmAudio(sr, [l, r]));
    // Correlate with each tone: |mean(x * sin)| measures that component.
    double corr(double hz) => (Iterable<int>.generate(sr)
            .fold(0.0, (a, i) => a + acc.channels[0][i] * math.sin(2 * math.pi * hz * i / sr)) /
        sr)
        .abs();
    final vocalLeft = corr(440);
    final guitarLeft = corr(1500);
    expect(guitarLeft, greaterThan(vocalLeft * 10));
  });

  test('mono input throws', () {
    expect(() => removeCenterVocals(PcmAudio(sr, [tone(440, 100)])),
        throwsFormatException);
  });

  test('entitlement: 3 free then locked, purchase unlocks', () {
    final e = Entitlement();
    expect([e.consume(), e.consume(), e.consume(), e.consume()],
        [true, true, true, false]);
    expect(e.freeRemaining, 0);
    e.purchased = true;
    expect(e.consume(), isTrue);
    final back = Entitlement.fromJson(e.toJson());
    expect(back.purchased, isTrue);
    expect(back.processed, e.processed);
  });
}
