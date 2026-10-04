import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'platform/native_audio.dart';
import 'screens/home_screen.dart';
import 'state/library.dart';
import 'state/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  final engine = PlatformAudioEngine();
  final speaker = PlatformSpeaker();
  final library = Library(
    decoder: nativeDecode,
    persistence: FilePersistence(File('${dir.path}/library.json')),
    workDir: Directory('${dir.path}/accompaniment'),
  );
  await excludeFromBackup(Directory('${dir.path}/accompaniment'));
  await library.load();
  runApp(KaraokeApp(library: library, engine: engine, speaker: speaker));
}

class KaraokeApp extends StatelessWidget {
  const KaraokeApp({
    super.key,
    required this.library,
    this.engine,
    this.speaker,
  });
  final Library library;
  final PlatformAudioEngine? engine;
  final Speaker? speaker;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KaraokeAI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: HomeScreen(library: library, engine: engine, speaker: speaker),
    );
  }
}
