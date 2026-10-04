import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:karaokeai_core/karaokeai_core.dart';

import '../state/session.dart';

const kAudioChannel = MethodChannel('app.karaokeai/audio');
const kRemoteChannel = EventChannel('app.karaokeai/remote');
const kTtsChannel = MethodChannel('app.karaokeai/tts');

/// Maps the OS audio route to the key used for latency settings.
/// Bluetooth is assumed to be the car; the user can still tune per output.
String outputIdForRoute(String route) => switch (route) {
  'bluetooth' => 'car',
  'usb' => 'car',
  'wired' => 'earphones',
  _ => 'home',
};

RemoteCommand? parseRemoteCommand(Object? v) => switch (v) {
  'next' => RemoteCommand.next,
  'previous' => RemoteCommand.previous,
  'playPause' => RemoteCommand.playPause,
  'repeat' => RemoteCommand.repeat,
  _ => null,
};

/// [AudioEngine] backed by native code (Android: AudioTrack/AudioRecord,
/// iOS: AVAudioEngine). Input is the built-in mic; output follows the route.
class PlatformAudioEngine implements AudioEngine {
  PlatformAudioEngine({MethodChannel? channel, EventChannel? remote})
    : _ch = channel ?? kAudioChannel,
      _remote = remote ?? kRemoteChannel;

  static const recordRate = 16000;

  final MethodChannel _ch;
  final EventChannel _remote;
  String _outputId = 'home';

  @override
  String get currentOutputId => _outputId;

  Future<void> _refreshRoute() async {
    final r = await _ch.invokeMethod<String>('currentRoute');
    _outputId = outputIdForRoute(r ?? 'speaker');
  }

  /// Returns false if the user denied microphone permission.
  Future<bool> requestMicPermission() async =>
      (await _ch.invokeMethod<bool>('requestMicPermission')) ?? false;

  /// Starts keep-alive for locked-screen use (Android foreground service /
  /// iOS audio session). Call before the first song, [endSession] after.
  Future<void> startSession() async {
    // Android 14+ requires the mic permission before a microphone-type
    // foreground service may start.
    if (!await requestMicPermission()) {
      throw StateError('microphone permission denied');
    }
    await _ch.invokeMethod<void>('startSession');
  }
  Future<void> endSession() => _ch.invokeMethod<void>('endSession');

  @override
  Future<RecordedTake> playAndRecord(String accompanimentPath) async {
    if (!await requestMicPermission()) {
      throw StateError('microphone permission denied');
    }
    await _refreshRoute();
    return _playAndRecord(accompanimentPath);
  }

  Future<RecordedTake> _playAndRecord(String path) async {
    final res = await _ch.invokeMapMethod<String, Object?>('playAndRecord', {
      'path': path,
      'recordRate': recordRate,
    });
    return RecordedTake(
      pcm16ToDoubles(res!['pcm'] as Uint8List),
      (res['sampleRate'] as int?) ?? recordRate,
    );
  }

  @override
  Future<void> stop() => _ch.invokeMethod<void>('stop');

  @override
  Stream<RemoteCommand> get remoteCommands => _remote
      .receiveBroadcastStream()
      .map(parseRemoteCommand)
      .where((c) => c != null)
      .cast<RemoteCommand>();

  /// Plays a short click through the current output while recording the mic,
  /// and returns the round-trip delay in ms (null if not detected).
  Future<double?> measureLatencyMs({Directory? tmp}) async {
    if (!await requestMicPermission()) return null;
    await _refreshRoute();
    final click = makeClickTrack();
    final dir = tmp ?? Directory.systemTemp;
    final f = File('${dir.path}/latency_click.wav');
    await f.writeAsBytes(encodeWav(PcmAudio(recordRate, [click])));
    try {
      final take = await _playAndRecord(f.path);
      final s = estimateLatencySeconds(
        click,
        take.samples,
        sampleRate: take.sampleRate,
        maxSeconds: 1.0,
      );
      return s == null ? null : s * 1000;
    } finally {
      try {
        await f.delete();
      } catch (_) {}
    }
  }
}

/// 1.5s of silence with a short decaying noise burst at 0.2s.
Float64List makeClickTrack({int sampleRate = PlatformAudioEngine.recordRate}) {
  final out = Float64List((sampleRate * 1.5).round());
  final rnd = math.Random(7);
  final start = (sampleRate * 0.2).round();
  final len = (sampleRate * 0.01).round();
  for (var i = 0; i < len; i++) {
    out[start + i] = (rnd.nextDouble() * 2 - 1) * (1 - i / len) * 0.9;
  }
  return out;
}

/// Excludes [dir] (accompaniment files) from OS backups so separated audio
/// never leaves the device. Must be called after the directory exists.
Future<void> excludeFromBackup(Directory dir, {MethodChannel? channel}) async {
  await dir.create(recursive: true);
  await (channel ?? kAudioChannel)
      .invokeMethod<void>('excludeFromBackup', {'path': dir.path});
}

Float64List pcm16ToDoubles(Uint8List bytes) {
  final bd = ByteData.sublistView(bytes);
  final n = bytes.length ~/ 2;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = bd.getInt16(i * 2, Endian.little) / 32768;
  }
  return out;
}

/// Decodes any OS-supported format (mp3/m4a/aac/flac/...) to PCM through
/// the platform decoder (iOS AVAudioFile / Android MediaCodec).
Future<PcmAudio> nativeDecode(
  String path, {
  MethodChannel? channel,
  Directory? tmp,
}) async {
  final ch = channel ?? kAudioChannel;
  final dir = tmp ?? Directory.systemTemp;
  final dst = '${dir.path}/dec_${DateTime.now().microsecondsSinceEpoch}.wav';
  try {
    await ch.invokeMethod<void>('decodeToWav', {'src': path, 'dst': dst});
    return decodeWav(await File(dst).readAsBytes());
  } on PlatformException catch (e) {
    throw FormatException('decode failed: ${e.message}');
  } finally {
    try {
      await File(dst).delete();
    } catch (_) {}
  }
}

class PlatformSpeaker implements Speaker {
  PlatformSpeaker({MethodChannel? channel}) : _ch = channel ?? kTtsChannel;
  final MethodChannel _ch;

  /// Completes when the utterance has finished.
  @override
  Future<void> speak(String text) =>
      _ch.invokeMethod<void>('speak', {'text': text});
}
