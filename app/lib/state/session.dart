import 'package:karaokeai_core/karaokeai_core.dart';

import 'library.dart';

/// Text-to-speech (AVSpeechSynthesizer / Android TextToSpeech).
abstract class Speaker {
  Future<void> speak(String text);
}

class SongResult {
  const SongResult(this.song, this.score);
  final Song song;
  final ScoreResult score;
}

/// Runs the setlist hands-free: sing → score → read result aloud → next.
class SingingSession {
  SingingSession({
    required this.library,
    required this.setlist,
    required this.engine,
    required this.speaker,
    Decoder? decoder,
  }) : _decoder = decoder ?? decodeWavFile;

  final Library library;
  final Setlist setlist;
  final AudioEngine engine;
  final Speaker speaker;
  final Decoder _decoder;

  final List<SongResult> results = [];
  bool _stopped = false;

  Future<void> stop() async {
    _stopped = true;
    await engine.stop();
  }

  /// Plays through the whole setlist. Songs that can't be prepared are
  /// announced and skipped so the drive is never blocked on a screen.
  Future<void> run() async {
    while (!_stopped && !setlist.isFinished) {
      final song = setlist.current!;
      final r = await library.process(song);
      if (r != ProcessResult.done) {
        await speaker.speak(r == ProcessResult.limitReached
            ? '無料枠を使い切りました。次の曲へ進みます。'
            : '${song.title}は処理できませんでした。次の曲へ進みます。');
        setlist.advance();
        continue;
      }
      final rec = library.records.firstWhere((x) => x.song.id == song.id);
      final take = await engine.playAndRecord(rec.accompanimentPath!);
      if (_stopped) break;
      final score = await _score(rec, take);
      results.add(SongResult(song, score));
      await speaker.speak(spokenSummary(score));
      setlist.advance();
    }
  }

  Future<ScoreResult> _score(SongRecord rec, RecordedTake take) async {
    final singer = medianSmooth(bandLimit(
        estimatePitchYin(take.samples, take.sampleRate)));
    final src = await _decoder(rec.sourcePath);
    final ref = medianSmooth(bandLimit(
            estimatePitchYin(extractCenter(src).channels[0], src.sampleRate)))
        .resampled(singer.hopSeconds);
    final ms = library.latency.getMs(engine.currentOutputId) ?? 0;
    return scoreSinging(
      reference: ref,
      singer: singer,
      latencySeconds: ms / 1000,
    );
  }
}
