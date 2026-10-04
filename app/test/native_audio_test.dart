import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaokeai/platform/native_audio.dart';
import 'package:karaokeai_core/karaokeai_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ch = MethodChannel('test/audio');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(ch, null));

  test('route mapping', () {
    expect(outputIdForRoute('bluetooth'), 'car');
    expect(outputIdForRoute('wired'), 'earphones');
    expect(outputIdForRoute('speaker'), 'home');
  });

  test('remote command parsing', () {
    expect(parseRemoteCommand('next'), RemoteCommand.next);
    expect(parseRemoteCommand('nope'), isNull);
  });

  test('pcm16 decoding', () {
    final b = ByteData(4)
      ..setInt16(0, 16384, Endian.little)
      ..setInt16(2, -32768, Endian.little);
    final d = pcm16ToDoubles(b.buffer.asUint8List());
    expect(d[0], closeTo(0.5, 1e-9));
    expect(d[1], -1.0);
  });

  test('engine: permission denied throws', () async {
    messenger.setMockMethodCallHandler(
      ch,
      (c) async => c.method == 'requestMicPermission' ? false : null,
    );
    final e = PlatformAudioEngine(channel: ch);
    expect(() => e.playAndRecord('/x.wav'), throwsStateError);
  });

  test('engine: records and maps route', () async {
    messenger.setMockMethodCallHandler(ch, (c) async {
      switch (c.method) {
        case 'requestMicPermission':
          return true;
        case 'currentRoute':
          return 'bluetooth';
        case 'playAndRecord':
          expect((c.arguments as Map)['recordRate'], 16000);
          return {
            'pcm': Uint8List.fromList([0, 0x40, 0, 0xC0]),
            'sampleRate': 16000,
          };
      }
      return null;
    });
    final e = PlatformAudioEngine(channel: ch);
    final take = await e.playAndRecord('/a.wav');
    expect(take.samples.length, 2);
    expect(take.sampleRate, 16000);
    expect(e.currentOutputId, 'car');
  });

  test('latency measurement recovers simulated 180ms delay', () async {
    final click = makeClickTrack();
    const delay = 2880; // 180ms @16k
    messenger.setMockMethodCallHandler(ch, (c) async {
      switch (c.method) {
        case 'requestMicPermission':
          return true;
        case 'currentRoute':
          return 'bluetooth';
        case 'playAndRecord':
          final cap = Float64List(click.length + delay);
          for (var i = 0; i < click.length; i++) {
            cap[i + delay] = click[i] * 0.3;
          }
          final bd = ByteData(cap.length * 2);
          for (var i = 0; i < cap.length; i++) {
            bd.setInt16(i * 2, (cap[i] * 32767).round(), Endian.little);
          }
          return {'pcm': bd.buffer.asUint8List(), 'sampleRate': 16000};
      }
      return null;
    });
    final ms = await PlatformAudioEngine(channel: ch)
        .measureLatencyMs(tmp: Directory.systemTemp);
    expect(ms, closeTo(180, 2));
  });

  test('nativeDecode reads the WAV the platform wrote', () async {
    final tmp = Directory.systemTemp.createTempSync('dec');
    addTearDown(() => tmp.deleteSync(recursive: true));
    messenger.setMockMethodCallHandler(ch, (c) async {
      final dst = (c.arguments as Map)['dst'] as String;
      File(dst).writeAsBytesSync(
        encodeWav(PcmAudio(8000, [Float64List(100), Float64List(100)])),
      );
      return null;
    });
    final pcm = await nativeDecode('/x.mp3', channel: ch, tmp: tmp);
    expect(pcm.channels.length, 2);
    expect(pcm.sampleRate, 8000);
    expect(tmp.listSync(), isEmpty); // temp file cleaned
  });

  test('nativeDecode maps platform failure to FormatException', () async {
    messenger.setMockMethodCallHandler(
      ch,
      (c) async => throw PlatformException(code: 'x', message: 'bad'),
    );
    expect(() => nativeDecode('/x.mp3', channel: ch), throwsFormatException);
  });
}
