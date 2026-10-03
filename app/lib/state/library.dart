import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:karaokeai_core/karaokeai_core.dart';

/// A file chosen by the user (name + path), abstracted for testing.
class PickedFile {
  const PickedFile(this.name, this.path);
  final String name;
  final String path;
}

typedef FilePickerFn = Future<PickedFile?> Function();
typedef HeadReader = Future<Uint8List> Function(String path);

Future<Uint8List> readHead(String path, {int bytes = 512 * 1024}) async {
  final f = await File(path).open();
  try {
    return await f.read(bytes);
  } finally {
    await f.close();
  }
}

/// Imported songs plus per-output latency settings.
class Library extends ChangeNotifier {
  Library({HeadReader? headReader, LatencyStore? latency})
      : _readHead = headReader ?? readHead,
        latency = latency ?? InMemoryLatencyStore();

  final HeadReader _readHead;
  final LatencyStore latency;
  final List<Song> songs = [];
  final Map<String, String> _paths = {};

  String? pathOf(String songId) => _paths[songId];

  /// Returns null on success, or a user-facing rejection reason.
  Future<String?> importFile(PickedFile file) async {
    final head = await _readHead(file.path);
    final check = checkImportable(file.name, head);
    if (!check.ok) return check.reason;
    final id = '${DateTime.now().microsecondsSinceEpoch}-${songs.length}';
    final dot = file.name.lastIndexOf('.');
    final title = dot > 0 ? file.name.substring(0, dot) : file.name;
    songs.add(Song(id: id, title: title));
    _paths[id] = file.path;
    notifyListeners();
    return null;
  }

  void remove(Song s) {
    songs.removeWhere((x) => x.id == s.id);
    _paths.remove(s.id);
    notifyListeners();
  }
}
