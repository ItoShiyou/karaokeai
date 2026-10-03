import 'dart:math' as math;

/// Estimates round-trip delay (seconds) between a played click [reference]
/// and what the mic [captured], via cross-correlation. Both are mono PCM at
/// [sampleRate]. Returns null if no clear peak (correlation too weak).
double? estimateLatencySeconds(
  List<double> reference,
  List<double> captured, {
  required int sampleRate,
  double maxSeconds = 1.0,
  double minPeakRatio = 3.0,
}) {
  final maxLag = math.min((maxSeconds * sampleRate).round(), captured.length - 1);
  var best = double.negativeInfinity;
  var bestLag = 0;
  var sumAbs = 0.0;
  for (var lag = 0; lag <= maxLag; lag++) {
    var s = 0.0;
    final n = math.min(reference.length, captured.length - lag);
    for (var i = 0; i < n; i++) {
      s += reference[i] * captured[i + lag];
    }
    sumAbs += s.abs();
    if (s > best) {
      best = s;
      bestLag = lag;
    }
  }
  final mean = sumAbs / (maxLag + 1);
  if (mean == 0 || best / mean < minPeakRatio) return null;
  return bestLag / sampleRate;
}

/// Per-output-device latency offsets (ms), e.g. car / home speaker / earphones.
abstract class LatencyStore {
  double? getMs(String outputId);
  void setMs(String outputId, double ms);
}

class InMemoryLatencyStore implements LatencyStore {
  final _m = <String, double>{};
  @override
  double? getMs(String outputId) => _m[outputId];
  @override
  void setMs(String outputId, double ms) => _m[outputId] = ms;
}

/// Effective latency = auto measurement + manual slider adjustment.
double effectiveLatencySeconds({required double autoMs, double manualMs = 0}) =>
    (autoMs + manualMs) / 1000;
