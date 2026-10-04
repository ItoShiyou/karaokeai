import 'package:flutter/material.dart';

import '../platform/native_audio.dart';
import '../state/library.dart';

/// Manual latency adjustment per output (car / home speaker / earphones).
class LatencyScreen extends StatefulWidget {
  const LatencyScreen({super.key, required this.library, this.engine});
  final Library library;
  final PlatformAudioEngine? engine;

  @override
  State<LatencyScreen> createState() => _LatencyScreenState();
}

class _LatencyScreenState extends State<LatencyScreen> {
  static const outputs = {'car': '車', 'home': '自宅スピーカー', 'earphones': 'イヤホン'};
  String _output = 'car';
  String? _status;

  Future<void> _measure() async {
    setState(() => _status = '測定中…');
    try {
      final ms = await widget.engine!.measureLatencyMs();
      if (!mounted) return;
      if (ms == null) {
        setState(() => _status = '検出できませんでした。音量を上げて静かな場所で再実行してください。');
        return;
      }
      // Store under the output the OS is actually routing to.
      final id = widget.engine!.currentOutputId;
      widget.library.latency.setMs(id, ms);
      await widget.library.persist();
      if (!mounted) return;
      setState(() {
        _output = id;
        _status = '${ms.round()} ms を保存しました（${outputs[id] ?? id}）';
      });
    } catch (e) {
      if (mounted) setState(() => _status = '測定に失敗しました: $e');
    }
  }

  double get _ms => widget.library.latency.getMs(_output) ?? 150;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('遅延補正')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<String>(
              segments: [
                for (final e in outputs.entries)
                  ButtonSegment(value: e.key, label: Text(e.value)),
              ],
              selected: {_output},
              onSelectionChanged: (s) => setState(() => _output = s.first),
            ),
            const SizedBox(height: 24),
            Text('${_ms.round()} ms'),
            Slider(
              min: 0,
              max: 500,
              divisions: 100,
              value: _ms.clamp(0, 500),
              onChanged: (v) =>
                  setState(() => widget.library.latency.setMs(_output, v)),
              onChangeEnd: (_) => widget.library.persist(),
            ),
            if (widget.engine != null)
              FilledButton.icon(
                icon: const Icon(Icons.graphic_eq),
                label: const Text('自動測定（クリック音を再生して録音）'),
                onPressed: _measure,
              ),
            if (_status != null) Text(_status!),
            const SizedBox(height: 8),
            const Text(
              '自動測定は静かな場所で、実際に使う出力（車のスピーカー等）につないで行ってください。'
              '結果は手動スライダーで微調整できます。',
            ),
          ],
        ),
      ),
    );
  }
}
