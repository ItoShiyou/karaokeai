import 'pitch.dart';

/// Native low-latency audio (Oboe on Android, AVAudioEngine on iOS).
/// Input is always the built-in mic; output may be Bluetooth/AUX/USB.
abstract class AudioEngine {
  /// Plays [accompanimentPath] while recording the mic. Completes with the
  /// recorded mono PCM (float, [sampleRate]) when playback ends.
  Future<RecordedTake> playAndRecord(String accompanimentPath);
  Future<void> stop();
  Stream<RemoteCommand> get remoteCommands;
  String get currentOutputId;
}

class RecordedTake {
  const RecordedTake(this.samples, this.sampleRate);
  final List<double> samples;
  final int sampleRate;
}

enum RemoteCommand { next, previous, playPause, repeat }

/// On-device source separation (Demucs via ONNX Runtime). Chunked internally.
abstract class StemSeparator {
  /// Returns paths of (accompaniment, vocals) files stored in app-private
  /// storage, excluded from backups.
  Future<SeparatedSong> separate(String sourcePath,
      {void Function(double progress)? onProgress});
}

class SeparatedSong {
  const SeparatedSong(this.accompanimentPath, this.vocalsPath);
  final String accompanimentPath;
  final String vocalsPath;
}

/// Pitch estimation (CREPE/YIN) producing fixed-hop tracks.
abstract class PitchEstimator {
  Future<PitchTrack> estimate(String audioPath);
  PitchTrack estimateSamples(List<double> samples, int sampleRate);
}
