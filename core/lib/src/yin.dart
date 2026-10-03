import 'dart:math' as math;

import 'pitch.dart';

/// YIN pitch estimator (de Cheveigné & Kawahara, 2002), pure Dart.
///
/// [samples] mono PCM. Returns a track with one value per [hopSeconds];
/// unvoiced frames are 0. Frequencies outside [minHz]..[maxHz] are dropped.
PitchTrack estimatePitchYin(
  List<double> samples,
  int sampleRate, {
  double hopSeconds = 0.01,
  double frameSeconds = 0.04,
  double minHz = 80,
  double maxHz = 1000,
  double threshold = 0.15,
  double minRms = 0.01,
}) {
  final hop = (hopSeconds * sampleRate).round();
  final frame = (frameSeconds * sampleRate).round();
  final tauMin = (sampleRate / maxHz).floor();
  final tauMax = math.min((sampleRate / minHz).ceil(), frame ~/ 2 - 1);
  final out = <double>[];

  for (var start = 0; start + frame <= samples.length; start += hop) {
    out.add(_yinFrame(samples, start, frame, sampleRate, tauMin, tauMax,
        threshold, minRms));
  }
  return PitchTrack(hop / sampleRate, out);
}

double _yinFrame(List<double> x, int s, int frame, int sr, int tauMin,
    int tauMax, double threshold, double minRms) {
  final w = frame ~/ 2;
  var energy = 0.0;
  for (var i = 0; i < frame; i++) {
    energy += x[s + i] * x[s + i];
  }
  if (math.sqrt(energy / frame) < minRms) return 0;

  // Difference function.
  final d = List<double>.filled(tauMax + 1, 0);
  for (var tau = 1; tau <= tauMax; tau++) {
    var sum = 0.0;
    for (var i = 0; i < w; i++) {
      final diff = x[s + i] - x[s + i + tau];
      sum += diff * diff;
    }
    d[tau] = sum;
  }
  // Cumulative mean normalized difference.
  final cm = List<double>.filled(tauMax + 1, 1);
  var running = 0.0;
  for (var tau = 1; tau <= tauMax; tau++) {
    running += d[tau];
    cm[tau] = running == 0 ? 1 : d[tau] * tau / running;
  }
  // First dip below threshold (then walk to the local minimum).
  var tau = math.max(tauMin, 2);
  var found = -1;
  while (tau <= tauMax) {
    if (cm[tau] < threshold) {
      while (tau + 1 <= tauMax && cm[tau + 1] < cm[tau]) {
        tau++;
      }
      found = tau;
      break;
    }
    tau++;
  }
  if (found < 0) return 0;

  // Parabolic interpolation.
  var better = found.toDouble();
  if (found > 1 && found < tauMax) {
    final a = cm[found - 1], b = cm[found], c = cm[found + 1];
    final denom = a - 2 * b + c;
    if (denom != 0) better = found + (a - c) / (2 * denom);
  }
  return sr / better;
}
