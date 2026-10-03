import 'package:flutter/material.dart';

import '../state/library.dart';

/// Manual latency adjustment per output (car / home speaker / earphones).
class LatencyScreen extends StatefulWidget {
  const LatencyScreen({super.key, required this.library});
  final Library library;

  @override
  State<LatencyScreen> createState() => _LatencyScreenState();
}

class _LatencyScreenState extends State<LatencyScreen> {
  static const outputs = {'car': '車', 'home': '自宅スピーカー', 'earphones': 'イヤホン'};
  String _output = 'car';

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
            ),
            const Text('確認用ビートに合わせて声や手拍子で調整します。'
                '（自動測定は録音エンジン実装後に接続）'),
          ],
        ),
      ),
    );
  }
}
