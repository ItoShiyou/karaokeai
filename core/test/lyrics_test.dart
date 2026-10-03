import 'package:karaokeai_core/karaokeai_core.dart';
import 'package:test/test.dart';

void main() {
  test('parse drops blanks and trims', () {
    final l = Lyrics.parse(' a \r\n\r\n b\n');
    expect(l.lines, ['a', 'b']);
  });
  test('lineAt maps fraction to lines, clamps ends', () {
    final l = Lyrics.parse('1\n2\n3\n4');
    expect(l.lineAt(0), '1');
    expect(l.lineAt(0.5), '3');
    expect(l.lineAt(1.0), '4');
    expect(l.lineAt(-1), '1');
    expect(Lyrics.parse('').lineAt(0.5), isNull);
  });
  test('lyrics hidden while moving or when speed unknown', () {
    expect(lyricsVisible(0), isTrue);
    expect(lyricsVisible(2.9), isTrue);
    expect(lyricsVisible(30), isFalse);
    expect(lyricsVisible(null), isFalse);
  });
  test('resample keeps pitch at new hop', () {
    final t = PitchTrack(0.01, List.filled(100, 220.0));
    final r = t.resampled(0.0125);
    expect(r.hopSeconds, 0.0125);
    expect(r.hz.every((h) => h == 220), isTrue);
    expect(r.length, 80);
  });
}
