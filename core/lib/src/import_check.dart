import 'dart:typed_data';

enum ImportVerdict { ok, drmProtected, unsupported }

class ImportCheck {
  const ImportCheck(this.verdict, this.reason);
  final ImportVerdict verdict;
  final String reason;
  bool get ok => verdict == ImportVerdict.ok;
}

const _audioExt = {'mp3', 'm4a', 'aac', 'wav', 'aiff', 'aif', 'flac', 'ogg', 'opus', 'mp4', 'mov'};

/// Decides whether a file may be imported. Only DRM-free local audio is
/// accepted; protected files are rejected, never circumvented.
///
/// [head] is the first bytes of the file (a few hundred KB is plenty; MP4
/// atoms like `drms` may sit in the sample description inside `moov`).
ImportCheck checkImportable(String fileName, Uint8List head) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();

  if (ext == 'm4p' || (ext == 'm4b' && _containsAscii(head, 'drms'))) {
    return const ImportCheck(
        ImportVerdict.drmProtected, 'DRM保護された音源は読み込めません');
  }
  if (!_audioExt.contains(ext)) {
    return ImportCheck(ImportVerdict.unsupported, '非対応の形式です: .$ext');
  }
  if (_isMp4(head)) {
    // FairPlay-protected MP4 audio uses 'drms'/'drmi' sample entries and 'sinf'/'schm' scheme boxes.
    if (_containsAscii(head, 'drms') ||
        _containsAscii(head, 'drmi') ||
        (_containsAscii(head, 'sinf') && _containsAscii(head, 'itun'))) {
      return const ImportCheck(
          ImportVerdict.drmProtected, 'DRM保護された音源は読み込めません');
    }
  }
  if (head.length < 12) {
    return const ImportCheck(ImportVerdict.unsupported, 'ファイルが小さすぎます');
  }
  return const ImportCheck(ImportVerdict.ok, '');
}

bool _isMp4(Uint8List b) => b.length >= 8 && _asciiAt(b, 4, 'ftyp');

bool _asciiAt(Uint8List b, int off, String s) {
  if (off + s.length > b.length) return false;
  for (var i = 0; i < s.length; i++) {
    if (b[off + i] != s.codeUnitAt(i)) return false;
  }
  return true;
}

bool _containsAscii(Uint8List b, String s) {
  for (var i = 0; i + s.length <= b.length; i++) {
    if (_asciiAt(b, i, s)) return true;
  }
  return false;
}
