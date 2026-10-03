import 'package:flutter/material.dart';

import '../state/session.dart';

/// Post-drive summary (parked use).
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.results});
  final List<SongResult> results;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('結果')),
      body: ListView(children: [
        if (results.isEmpty) const ListTile(title: Text('採点した曲はありません')),
        for (final r in results)
          ListTile(
            title: Text(r.song.title),
            subtitle: Text('音程 ${r.score.pitch.round()} / リズム ${r.score.rhythm.round()}'),
            trailing: Text('${r.score.total.round()}点',
                style: Theme.of(context).textTheme.titleLarge),
          ),
      ]),
    );
  }
}
