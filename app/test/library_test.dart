import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:karaokeai/state/library.dart';
import 'package:karaokeai_core/karaokeai_core.dart';

Uint8List _mp3() => Uint8List.fromList(List.filled(64, 1));

PcmAudio _stereo() {
  const sr = 8000;
  final v = Float64List.fromList(
      [for (var i = 0; i < sr; i++) 0.3 * math.sin(2 * math.pi * 440 * i / sr)]);
  return PcmAudio(sr, [v, Float64List.fromList(v)]);
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('kai'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Library make({Persistence? p}) => Library(
        headReader: (_) async => _mp3(),
        decoder: (_) async => _stereo(),
        persistence: p,
        workDir: Directory('${tmp.path}/acc'),
      );

  test('free tier allows 3 songs then blocks; purchase unlocks', () async {
    final lib = make();
    for (var i = 0; i < 4; i++) {
      await lib.importFile(PickedFile('s$i.mp3', '/x/s$i.mp3'));
    }
    final results = <ProcessResult>[];
    for (final s in lib.songs) {
      results.add(await lib.process(s));
    }
    expect(results, [
      ProcessResult.done,
      ProcessResult.done,
      ProcessResult.done,
      ProcessResult.limitReached,
    ]);
    lib.entitlement.purchased = true;
    expect(await lib.process(lib.songs.last), ProcessResult.done);
    expect(File(lib.records.last.accompanimentPath!).existsSync(), isTrue);
  });

  test('state survives restart', () async {
    final p = FilePersistence(File('${tmp.path}/lib.json'));
    final a = make(p: p);
    await a.importFile(const PickedFile('song.mp3', '/x/song.mp3'));
    await a.process(a.songs.first);
    a.latency.setMs('car', 210);
    await a.persist();

    final b = make(p: p);
    await b.load();
    expect(b.songs.single.title, 'song');
    expect(b.records.single.processed, isTrue);
    expect(b.latency.getMs('car'), 210);
    expect(b.entitlement.processed, 1);
  });

  test('decode failure reports failed and does not consume quota', () async {
    final lib = Library(
      headReader: (_) async => _mp3(),
      decoder: (_) async => throw const FormatException('x'),
      workDir: Directory('${tmp.path}/acc'),
    );
    await lib.importFile(const PickedFile('a.mp3', '/x/a.mp3'));
    expect(await lib.process(lib.songs.first), ProcessResult.failed);
    expect(lib.entitlement.processed, 0);
  });

  test('corrupt persistence file is ignored', () async {
    final f = File('${tmp.path}/bad.json')..writeAsStringSync('{not json');
    final lib = make(p: FilePersistence(f));
    await lib.load();
    expect(lib.songs, isEmpty);
  });
}
