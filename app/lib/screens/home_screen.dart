import 'package:flutter/material.dart';
import 'package:karaokeai_core/karaokeai_core.dart';

import 'pocket_screen.dart';

/// Pre-departure screen: build the setlist, then start pocket mode.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // TODO: replace with imported + separated songs (file picker, StemSeparator).
  final List<Song> _songs = [
    const Song(id: 'demo1', title: 'デモ曲 1'),
    const Song(id: 'demo2', title: 'デモ曲 2'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('セットリスト')),
      body: ListView(
        children: [
          for (final s in _songs) ListTile(title: Text(s.title)),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('運転中は画面を見ない・操作しないでください。'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.directions_car),
        label: const Text('ポケットモード開始'),
        onPressed: _songs.isEmpty
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => PocketScreen(setlist: Setlist(_songs)),
                )),
      ),
    );
  }
}
