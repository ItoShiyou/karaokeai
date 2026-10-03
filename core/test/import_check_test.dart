import 'dart:typed_data';

import 'package:karaokeai_core/karaokeai_core.dart';
import 'package:test/test.dart';

Uint8List mp4(List<String> extra) {
  final s = '${String.fromCharCodes([0, 0, 0, 20])}ftypM4A ${'\u0000' * 8}${extra.join('.')}';
  return Uint8List.fromList(s.codeUnits);
}

void main() {
  test('plain m4a is accepted', () {
    expect(checkImportable('a.m4a', mp4(['mp4a'])).ok, isTrue);
  });
  test('FairPlay m4a (drms) is rejected', () {
    final r = checkImportable('a.m4a', mp4(['drms']));
    expect(r.verdict, ImportVerdict.drmProtected);
  });
  test('.m4p is rejected', () {
    expect(checkImportable('a.m4p', mp4([])).verdict, ImportVerdict.drmProtected);
  });
  test('unknown extension is unsupported', () {
    expect(checkImportable('a.txt', Uint8List(64)).verdict, ImportVerdict.unsupported);
  });
  test('mp3 is accepted', () {
    expect(checkImportable('a.MP3', Uint8List(64)).ok, isTrue);
  });
}
