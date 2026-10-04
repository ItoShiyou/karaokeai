import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:karaokeai_core/karaokeai_core.dart';

/// A file chosen by the user (name + path), abstracted for testing.
class PickedFile {
  const PickedFile(this.name, this.path);
  final String name;
  final String path;
}

typedef FilePickerFn = Future<PickedFile?> Function();
typedef HeadReader = Future<Uint8List> Function(String path);

/// Decodes a source file to PCM. Default handles WAV only; compressed
/// formats (mp3/m4a/...) need a native decoder (AVAudioFile / MediaCodec).
typedef Decoder = Future<PcmAudio> Function(String path);

Future<PcmAudio> decodeWavFile(String path) async =>
    decodeWav(await File(path).readAsBytes());

Future<Uint8List> readHead(String path, {int bytes = 512 * 1024}) async {
  final f = await File(path).open();
  try {
    return await f.read(bytes);
  } finally {
    await f.close();
  }
}

/// Key-value JSON persistence (app-private file).
abstract class Persistence {
  Future<Map<String, Object?>?> load();
  Future<void> save(Map<String, Object?> json);
}

class FilePersistence implements Persistence {
  FilePersistence(this.file);
  final File file;

  @override
  Future<Map<String, Object?>?> load() async {
    if (!await file.exists()) return null;
    try {
      return (jsonDecode(await file.readAsString()) as Map)
          .cast<String, Object?>();
    } catch (_) {
      return null; // corrupt file: start fresh rather than crash
    }
  }

  @override
  Future<void> save(Map<String, Object?> json) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(json));
  }
}

class SongRecord {
  SongRecord({
    required this.song,
    required this.sourcePath,
    this.accompanimentPath,
    this.lyrics = '',
  });
  final Song song;
  final String sourcePath;
  String? accompanimentPath;
  String lyrics;

  bool get processed => accompanimentPath != null;
}

enum ProcessResult { done, limitReached, failed }

/// Imported songs, per-output latency, entitlement.
class Library extends ChangeNotifier {
  Library({
    HeadReader? headReader,
    LatencyStore? latency,
    this._persistence,
    Decoder? decoder,
    this.workDir,
    Entitlement? entitlement,
  }) : _readHead = headReader ?? readHead,
       latency = latency ?? InMemoryLatencyStore(),
       _decoder = decoder ?? decodeWavFile,
       entitlement = entitlement ?? Entitlement();

  final HeadReader _readHead;
  final Persistence? _persistence;
  final Decoder _decoder;
  Decoder get decoder => _decoder;
  final LatencyStore latency;
  final Entitlement entitlement;

  /// Directory for generated accompaniment files (app-private, excluded
  /// from backup by the platform layer).
  final Directory? workDir;

  final List<SongRecord> records = [];
  List<Song> get songs => [for (final r in records) r.song];
  String? pathOf(String songId) => _find(songId)?.sourcePath;

  static const _outputs = ['car', 'home', 'earphones'];

  SongRecord? _find(String id) {
    for (final r in records) {
      if (r.song.id == id) return r;
    }
    return null;
  }

  Future<void> load() async {
    final j = await _persistence?.load();
    if (j == null) return;
    records.clear();
    for (final e in (j['songs'] as List? ?? const [])) {
      final m = (e as Map).cast<String, Object?>();
      records.add(
        SongRecord(
          song: Song(id: m['id'] as String, title: m['title'] as String),
          sourcePath: m['source'] as String,
          accompanimentPath: m['accompaniment'] as String?,
          lyrics: (m['lyrics'] as String?) ?? '',
        ),
      );
    }
    final lat = (j['latency'] as Map?)?.cast<String, Object?>() ?? const {};
    for (final k in _outputs) {
      final v = lat[k];
      if (v is num) latency.setMs(k, v.toDouble());
    }
    final ent = j['entitlement'];
    if (ent is Map) {
      final e = Entitlement.fromJson(ent.cast<String, Object?>());
      entitlement.purchased = e.purchased;
      entitlement.processed = e.processed;
    }
    notifyListeners();
  }

  Future<void> _save() async {
    await _persistence?.save({
      'songs': [
        for (final r in records)
          {
            'id': r.song.id,
            'title': r.song.title,
            'source': r.sourcePath,
            'accompaniment': r.accompanimentPath,
            'lyrics': r.lyrics,
          },
      ],
      'latency': {
        for (final k in _outputs)
          if (latency.getMs(k) != null) k: latency.getMs(k),
      },
      'entitlement': entitlement.toJson(),
    });
  }

  Future<void> setLyrics(Song s, String text) async {
    final r = _find(s.id);
    if (r == null) return;
    r.lyrics = text;
    notifyListeners();
    await _save();
  }

  /// Call after changing latency or purchase state.
  Future<void> persist() => _save();

  /// Returns null on success, or a user-facing rejection reason.
  Future<String?> importFile(PickedFile file) async {
    final head = await _readHead(file.path);
    final check = checkImportable(file.name, head);
    if (!check.ok) return check.reason;
    final id = '${DateTime.now().microsecondsSinceEpoch}-${records.length}';
    final dot = file.name.lastIndexOf('.');
    final title = dot > 0 ? file.name.substring(0, dot) : file.name;
    records.add(
      SongRecord(
        song: Song(id: id, title: title),
        sourcePath: file.path,
      ),
    );
    notifyListeners();
    await _save();
    return null;
  }

  Future<void> remove(Song s) async {
    final r = _find(s.id);
    if (r?.accompanimentPath != null) {
      try {
        await File(r!.accompanimentPath!).delete();
      } catch (_) {}
    }
    records.removeWhere((x) => x.song.id == s.id);
    notifyListeners();
    await _save();
  }

  /// Separates the song (centre cancellation) and stores the accompaniment
  /// in app-private storage. Counts against the free tier.
  Future<ProcessResult> process(Song s) async {
    final r = _find(s.id);
    if (r == null) return ProcessResult.failed;
    if (r.processed) return ProcessResult.done;
    if (!entitlement.canProcessMore) return ProcessResult.limitReached;
    try {
      final pcm = await _decoder(r.sourcePath);
      final acc = removeCenterVocals(pcm);
      final dir = workDir ?? Directory.systemTemp;
      await dir.create(recursive: true);
      final out = File('${dir.path}/${s.id}_acc.wav');
      await out.writeAsBytes(encodeWav(acc));
      r.accompanimentPath = out.path;
      entitlement.consume();
      notifyListeners();
      await _save();
      return ProcessResult.done;
    } on FormatException {
      return ProcessResult.failed;
    } on FileSystemException {
      return ProcessResult.failed;
    }
  }
}
