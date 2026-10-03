import 'dart:typed_data';

/// Decoded PCM audio: [channels] lists of samples in -1..1.
class PcmAudio {
  PcmAudio(this.sampleRate, this.channels);
  final int sampleRate;
  final List<Float64List> channels;
  int get length => channels.isEmpty ? 0 : channels.first.length;
  double get seconds => length / sampleRate;
}

/// Parses 16-bit PCM RIFF/WAVE. Throws [FormatException] otherwise.
PcmAudio decodeWav(Uint8List bytes) {
  final bd = ByteData.sublistView(bytes);
  String tag(int o) => String.fromCharCodes(bytes.sublist(o, o + 4));
  if (bytes.length < 44 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
    throw const FormatException('not a WAV file');
  }
  int? ch, sr, bits, dataOff, dataLen;
  var o = 12;
  while (o + 8 <= bytes.length) {
    final id = tag(o);
    final size = bd.getUint32(o + 4, Endian.little);
    if (id == 'fmt ') {
      final fmt = bd.getUint16(o + 8, Endian.little);
      if (fmt != 1) throw const FormatException('only PCM WAV supported');
      ch = bd.getUint16(o + 10, Endian.little);
      sr = bd.getUint32(o + 12, Endian.little);
      bits = bd.getUint16(o + 22, Endian.little);
    } else if (id == 'data') {
      dataOff = o + 8;
      dataLen = (o + 8 + size > bytes.length) ? bytes.length - dataOff : size;
      break;
    }
    o += 8 + size + (size & 1);
  }
  if (ch == null || sr == null || bits != 16 || dataOff == null) {
    throw const FormatException('unsupported WAV (need 16-bit PCM)');
  }
  final frames = dataLen! ~/ (2 * ch);
  final out = List.generate(ch, (_) => Float64List(frames));
  for (var i = 0; i < frames; i++) {
    for (var c = 0; c < ch; c++) {
      out[c][i] = bd.getInt16(dataOff + (i * ch + c) * 2, Endian.little) / 32768;
    }
  }
  return PcmAudio(sr, out);
}

Uint8List encodeWav(PcmAudio a) {
  final ch = a.channels.length;
  final dataLen = a.length * ch * 2;
  final b = BytesBuilder();
  final h = ByteData(44);
  void tag(int o, String s) {
    for (var i = 0; i < 4; i++) {
      h.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  h.setUint32(4, 36 + dataLen, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  h.setUint32(16, 16, Endian.little);
  h.setUint16(20, 1, Endian.little);
  h.setUint16(22, ch, Endian.little);
  h.setUint32(24, a.sampleRate, Endian.little);
  h.setUint32(28, a.sampleRate * ch * 2, Endian.little);
  h.setUint16(32, ch * 2, Endian.little);
  h.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  h.setUint32(40, dataLen, Endian.little);
  b.add(h.buffer.asUint8List());
  final d = ByteData(dataLen);
  for (var i = 0; i < a.length; i++) {
    for (var c = 0; c < ch; c++) {
      final v = (a.channels[c][i].clamp(-1.0, 1.0) * 32767).round();
      d.setInt16((i * ch + c) * 2, v, Endian.little);
    }
  }
  b.add(d.buffer.asUint8List());
  return b.toBytes();
}
