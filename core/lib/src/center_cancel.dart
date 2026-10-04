import 'dart:typed_data';

import 'wav.dart';

/// Model-free vocal reduction: removes the phantom-centre component
/// (L-R). No learned weights, so no model-licence concerns. Quality is
/// lower than ML separation: bass/kick panned centre are also reduced,
/// and mono sources can't be processed.
///
/// Returns a stereo accompaniment (same signal on both channels, with a
/// low-pass-preserved centre bass to limit thinning).
PcmAudio removeCenterVocals(PcmAudio src, {double bassKeepHz = 100}) {
  if (src.channels.length < 2) {
    throw const FormatException('stereo audio required for centre cancellation');
  }
  final l = src.channels[0], r = src.channels[1];
  final n = src.length;

  // 4 cascaded one-pole low-passes (~24dB/oct) on the centre keep bass/kick
  // but not vocal fundamentals. Single pass, no intermediate arrays.
  final dt = 1 / src.sampleRate;
  final rc = 1 / (2 * 3.141592653589793 * bassKeepHz);
  final a = dt / (rc + dt);
  var y1 = 0.0, y2 = 0.0, y3 = 0.0, y4 = 0.0;
  final out = Float32List(n);
  var peak = 0.0;
  for (var i = 0; i < n; i++) {
    final mid = (l[i] + r[i]) / 2;
    y1 += a * (mid - y1);
    y2 += a * (y1 - y2);
    y3 += a * (y2 - y3);
    y4 += a * (y3 - y4);
    final v = (l[i] - r[i]) / 2 + y4;
    out[i] = v;
    if (v.abs() > peak) peak = v.abs();
  }
  if (peak > 0.99) {
    final g = 0.99 / peak;
    for (var i = 0; i < n; i++) {
      out[i] = out[i] * g;
    }
  }
  // Same signal on both channels (shared buffer; no second copy).
  return PcmAudio(src.sampleRate, [out, out]);
}

/// Estimated "vocal" signal (centre component) for reference pitch.
PcmAudio extractCenter(PcmAudio src) {
  final n = src.length;
  final l = src.channels[0], r = src.channels[src.channels.length > 1 ? 1 : 0];
  final mid = Float32List(n);
  for (var i = 0; i < n; i++) {
    mid[i] = (l[i] + r[i]) / 2;
  }
  return PcmAudio(src.sampleRate, [mid]);
}
