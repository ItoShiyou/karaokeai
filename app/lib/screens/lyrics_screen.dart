import 'package:flutter/material.dart';
import 'package:karaokeai_core/karaokeai_core.dart';

import '../state/library.dart';

/// Paste/edit lyrics (user-supplied only) and preview. Display is blocked
/// unless the vehicle is stopped.
class LyricsScreen extends StatefulWidget {
  const LyricsScreen({
    super.key,
    required this.library,
    required this.song,
    this.speedKmh,
  });

  final Library library;
  final Song song;

  /// Current speed from the location layer; null = unknown (hidden).
  final double? speedKmh;

  @override
  State<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    final rec =
        widget.library.records.firstWhere((r) => r.song.id == widget.song.id);
    _c = TextEditingController(text: rec.lyrics);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = lyricsVisible(widget.speedKmh);
    return Scaffold(
      appBar: AppBar(title: Text('歌詞: ${widget.song.title}')),
      body: !visible
          ? const Center(child: Text('走行中は歌詞を表示できません'))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Expanded(
                  child: TextField(
                    controller: _c,
                    maxLines: null,
                    expands: true,
                    decoration: const InputDecoration(
                        hintText: 'ご自身で用意した歌詞を貼り付けてください'),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () async {
                    await widget.library.setLyrics(widget.song, _c.text);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text('保存'),
                ),
              ]),
            ),
    );
  }
}
