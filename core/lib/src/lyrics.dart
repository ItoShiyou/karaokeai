/// Lyrics pasted by the user. Never bundled or distributed by the app.
class Lyrics {
  Lyrics._(this.lines);

  factory Lyrics.parse(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return Lyrics._(lines);
  }

  final List<String> lines;
  bool get isEmpty => lines.isEmpty;

  /// Line shown at [fraction] (0..1) of the song: coarse linear sync, used
  /// until speech-recognition sync exists.
  String? lineAt(double fraction) {
    if (lines.isEmpty) return null;
    final i = (fraction.clamp(0.0, 0.999999) * lines.length).floor();
    return lines[i];
  }
}

/// Lyrics are shown only when the vehicle is (nearly) stopped.
/// Unknown speed (null) hides them: fail safe.
bool lyricsVisible(double? speedKmh, {double maxKmh = 3}) =>
    speedKmh != null && speedKmh <= maxKmh;
