import 'dart:math' as math;

import 'package:karaokeai_core/karaokeai_core.dart';
import 'package:test/test.dart';

PitchTrack melody({double shiftCents = 0, int octave = 0}) {
  final hz = <double>[];
  const notes = [220.0, 246.9, 277.2, 329.6];
  for (var i = 0; i < 400; i++) {
    if (i % 100 >= 90) {
      hz.add(0); // rest
    } else {
      final base = notes[(i ~/ 100) % notes.length];
      hz.add(base * math.pow(2, shiftCents / 1200) * math.pow(2, octave));
    }
  }
  return PitchTrack(0.02, hz);
}

void main() {
  test('perfect singing scores high', () {
    final r = scoreSinging(reference: melody(), singer: melody());
    expect(r.total, greaterThan(98));
  });

  test('different key (transposed) is not penalized', () {
    final r = scoreSinging(reference: melody(), singer: melody(shiftCents: 300));
    expect(r.total, greaterThan(95));
    expect(r.keyOffsetCents, closeTo(300, 1));
  });

  test('octave-lower singing is not penalized', () {
    final r = scoreSinging(reference: melody(), singer: melody(octave: -1));
    expect(r.total, greaterThan(95));
  });

  test('random pitches score low', () {
    final rnd = math.Random(1);
    final singer = PitchTrack(0.02, [
      for (var i = 0; i < 400; i++) 150 + rnd.nextDouble() * 400,
    ]);
    final r = scoreSinging(reference: melody(), singer: singer);
    expect(r.total, lessThan(60));
  });

  test('latency compensation recovers score', () {
    final ref = melody();
    final late = ref.shifted(0.2); // singer heard late by 200ms
    final bad = scoreSinging(reference: ref, singer: late);
    final good = scoreSinging(reference: ref, singer: late, latencySeconds: 0.2);
    expect(good.total, greaterThan(bad.total));
    expect(good.total, greaterThan(90));
  });

  test('silence scores zero', () {
    final silent = PitchTrack(0.02, List.filled(400, 0));
    expect(scoreSinging(reference: melody(), singer: silent).total, 0);
  });

  test('median filter removes short spikes', () {
    final t = PitchTrack(0.02, [200, 200, 900, 200, 200, 200, 200]);
    final s = medianSmooth(t, window: 5);
    expect(s.hz[2], 200);
  });

  test('latency estimation finds click delay', () {
    const sr = 8000;
    final ref = List<double>.filled(200, 0)..[0] = 1;
    final cap = List<double>.filled(4000, 0);
    const delay = 1200; // 150ms
    for (var i = 0; i < ref.length; i++) {
      cap[delay + i] = ref[i];
    }
    final est = estimateLatencySeconds(ref, cap, sampleRate: sr);
    expect(est, closeTo(0.15, 1e-6));
  });

  test('latency estimation returns null on silence', () {
    final est = estimateLatencySeconds([1, 0, 0], List.filled(1000, 0),
        sampleRate: 8000);
    expect(est, isNull);
  });

  test('setlist auto-advances and finishes', () {
    final s = Setlist([const Song(id: 'a', title: 'A'), const Song(id: 'b', title: 'B')]);
    expect(s.current!.id, 'a');
    expect(s.advance()!.id, 'b');
    expect(s.advance(), isNull);
    expect(s.isFinished, isTrue);
  });
}
