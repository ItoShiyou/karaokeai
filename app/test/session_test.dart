import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:karaokeai/state/library.dart';
import 'package:karaokeai/state/session.dart';
import 'package:karaokeai_core/karaokeai_core.dart';

const sr = 16000;

Float64List _tone(double hz, double sec) => Float64List.fromList([
  for (var i = 0; i < sec * sr; i++) 0.4 * math.sin(2 * math.pi * hz * i / sr),
]);

class FakeEngine implements AudioEngine {
  FakeEngine(this.take);
  final List<double> take;
  final played = <String>[];
  @override
  String get currentOutputId => 'car';
  @override
  Stream<RemoteCommand> get remoteCommands => const Stream.empty();
  @override
  Future<RecordedTake> playAndRecord(String path) async {
    played.add(path);
    return RecordedTake(take, sr);
  }

  @override
  Future<void> stop() async {}
}

class FakeSpeaker implements Speaker {
  final said = <String>[];
  @override
  Future<void> speak(String t) async => said.add(t);
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('kai'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Library lib() => Library(
    headReader: (_) async => Uint8List(64),
    decoder: (_) async => PcmAudio(sr, [_tone(220, 2), _tone(220, 2)]),
    workDir: Directory('${tmp.path}/acc'),
  );

  test('sings in tune -> high score, spoken, setlist advances', () async {
    final l = lib();
    await l.importFile(const PickedFile('a.mp3', '/x/a.mp3'));
    final speaker = FakeSpeaker();
    final s = SingingSession(
      library: l,
      setlist: Setlist(l.songs),
      engine: FakeEngine(_tone(220, 2)),
      speaker: speaker,
      decoder: (_) async => PcmAudio(sr, [_tone(220, 2), _tone(220, 2)]),
    );
    await s.run();
    expect(s.results.single.score.total, greaterThan(90));
    expect(speaker.said.single, contains('点'));
    expect(s.setlist.isFinished, isTrue);
  });

  test('applies saved latency to scoring', () async {
    final l = lib();
    l.latency.setMs('car', 0);
    await l.importFile(const PickedFile('a.mp3', '/x/a.mp3'));
    final s = SingingSession(
      library: l,
      setlist: Setlist(l.songs),
      engine: FakeEngine(List.filled(2 * sr, 0.0)),
      speaker: FakeSpeaker(),
      decoder: (_) async => PcmAudio(sr, [_tone(220, 2), _tone(220, 2)]),
    );
    await s.run();
    expect(s.results.single.score.total, lessThan(10)); // silence
  });

  test('unprocessable song is announced and skipped', () async {
    final l = Library(
      headReader: (_) async => Uint8List(64),
      decoder: (_) async => throw const FormatException('x'),
      workDir: Directory('${tmp.path}/acc'),
    );
    await l.importFile(const PickedFile('a.mp3', '/x/a.mp3'));
    final speaker = FakeSpeaker();
    final s = SingingSession(
      library: l,
      setlist: Setlist(l.songs),
      engine: FakeEngine(const []),
      speaker: speaker,
      decoder: (_) async => throw const FormatException('x'),
    );
    await s.run();
    expect(s.results, isEmpty);
    expect(speaker.said.single, contains('処理できませんでした'));
    expect(s.setlist.isFinished, isTrue);
  });

  test('lyrics persist per song', () async {
    final tmp2 = File('${tmp.path}/l.json');
    final l = Library(
      headReader: (_) async => Uint8List(64),
      persistence: FilePersistence(tmp2),
    );
    await l.importFile(const PickedFile('a.mp3', '/x/a.mp3'));
    await l.setLyrics(l.songs.first, 'la la\nla');
    final l2 = Library(persistence: FilePersistence(tmp2));
    await l2.load();
    expect(l2.records.single.lyrics, 'la la\nla');
  });

  test('remote next skips without scoring; repeat sings again', () async {
    final l = lib();
    await l.importFile(const PickedFile('a.mp3', '/x/a.mp3'));
    final eng = ScriptedEngine(_tone(220, 2), [
      RemoteCommand.repeat,
      RemoteCommand.next,
    ]);
    final s = SingingSession(
      library: l,
      setlist: Setlist(l.songs),
      engine: eng,
      speaker: FakeSpeaker(),
      decoder: (_) async => PcmAudio(sr, [_tone(220, 2), _tone(220, 2)]),
    );
    await s.run();
    // play 1 interrupted by repeat -> same song again; play 2 interrupted
    // by next -> skipped without scoring.
    expect(eng.plays, 2);
    expect(s.results, isEmpty);
    expect(s.setlist.isFinished, isTrue);
  });
}

class ScriptedEngine extends FakeEngine {
  ScriptedEngine(super.take, this.script);
  final List<RemoteCommand> script;
  int plays = 0;
  final _c = StreamController<RemoteCommand>.broadcast();
  @override
  Stream<RemoteCommand> get remoteCommands => _c.stream;
  @override
  Future<RecordedTake> playAndRecord(String path) async {
    plays++;
    if (script.isNotEmpty) {
      // Simulate the user pressing a remote button mid-song.
      final cmd = script.removeAt(0);
      scheduleMicrotask(() => _c.add(cmd));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return super.playAndRecord(path);
  }
}
