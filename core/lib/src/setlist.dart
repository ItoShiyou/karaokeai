class Song {
  const Song({required this.id, required this.title});
  final String id;
  final String title;
}

/// Setlist that advances automatically after each song (pocket mode).
class Setlist {
  Setlist(List<Song> songs) : _songs = List.of(songs);

  final List<Song> _songs;
  int _index = 0;

  List<Song> get songs => List.unmodifiable(_songs);
  Song? get current => _index < _songs.length ? _songs[_index] : null;
  bool get isFinished => _index >= _songs.length;

  /// Advances; returns the next song or null when the list is done.
  Song? advance() {
    if (_index < _songs.length) _index++;
    return current;
  }

  void skip() => advance();

  void restart() => _index = 0;
}
