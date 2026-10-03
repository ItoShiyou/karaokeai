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
  final side = Float64List(n);
  final mid = Float64List(n);
  for (var i = 0; i < n; i++) {
    side[i] = (l[i] - r[i]) / 2;
    mid[i] = (l[i] + r[i]) / 2;
  }
  // 4 cascaded one-pole low-passes (~24dB/oct) keep bass/kick but not
  // vocal fundamentals.
  final dt = 1 / src.sampleRate;
  final rc = 1 / (2 * 3.141592653589793 * bassKeepHz);
  final a = dt / (rc + dt);
  var bass = mid;
  for (var stage = 0; stage < 4; stage++) {
    final o = Float64List(n);
    var y = 0.0;
    for (var i = 0; i < n; i++) {
      y += a * (bass[i] - y);
      o[i] = y;
    }
    bass = o;
  }
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = side[i] + bass[i];
  }
  // Normalize to avoid clipping.
  var peak = 0.0;
  for (final v in out) {
    if (v.abs() > peak) peak = v.abs();
  }
  if (peak > 0.99) {
    for (var i = 0; i < n; i++) {
      out[i] = out[i] / peak * 0.99;
    }
  }
  return PcmAudio(src.sampleRate, [out, Float64List.fromList(out)]);
}

/// Estimated "vocal" signal (centre component) for reference pitch.
PcmAudio extractCenter(PcmAudio src) {
  final n = src.length;
  final l = src.channels[0], r = src.channels[src.channels.length > 1 ? 1 : 0];
  final mid = Float64List(n);
  for (var i = 0; i < n; i++) {
    mid[i] = (l[i] + r[i]) / 2;
  }
  return PcmAudio(src.sampleRate, [mid]);
}
