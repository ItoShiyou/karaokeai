import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:karaokeai_core/karaokeai_core.dart';

import '../state/library.dart';
import 'latency_screen.dart';
import 'pocket_screen.dart';

/// Pre-departure screen: import songs, build the setlist, start pocket mode.
class HomeScreen extends StatefulWidget {
  HomeScreen({super.key, Library? library, FilePickerFn? pickFile})
      : library = library ?? Library(),
        pickFile = pickFile ?? _defaultPick;

  final Library library;
  final FilePickerFn pickFile;

  static Future<PickedFile?> _defaultPick() async {
    final r = await FilePicker.pickFiles(type: FileType.audio);
    if (r.isEmpty) return null;
    final f = r.first;
    if (f.path == null) return null;
    return PickedFile(f.name, f.path!);
  }

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _import() async {
    final file = await widget.pickFile();
    if (file == null) return;
    final error = await widget.library.importFile(file);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _process(Song s) async {
    final r = await widget.library.process(s);
    if (!mounted) return;
    final msg = switch (r) {
      ProcessResult.done => null,
      ProcessResult.limitReached => '無料枠（3曲）を使い切りました。買い切りで解除できます。',
      ProcessResult.failed => 'この形式はまだ処理できません（現在はステレオWAVのみ）。',
    };
    if (msg != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = widget.library;
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('セットリスト'),
          actions: [
            IconButton(
              tooltip: '遅延補正',
              icon: const Icon(Icons.timer),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => LatencyScreen(library: lib))),
            ),
            IconButton(
              tooltip: '曲を追加',
              icon: const Icon(Icons.add),
              onPressed: _import,
            ),
          ],
        ),
        body: ListView(
          children: [
            if (lib.songs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('「＋」でお持ちの音源（DRMなし）を追加してください。'),
              ),
            for (final s in lib.songs)
              ListTile(
                title: Text(s.title),
                subtitle: Text(lib.records
                        .firstWhere((r) => r.song.id == s.id)
                        .processed
                    ? '声除去済み'
                    : '未処理'),
                onTap: () => _process(s),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => lib.remove(s),
                ),
              ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('運転中は画面を見ない・操作しないでください。'),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.directions_car),
          label: const Text('ポケットモード開始'),
          onPressed: lib.songs.isEmpty
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => PocketScreen(setlist: Setlist(lib.songs)),
                  )),
        ),
      ),
    );
  }
}
