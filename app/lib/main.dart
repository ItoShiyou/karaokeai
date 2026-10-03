import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'screens/home_screen.dart';
import 'state/library.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  final library = Library(
    persistence: FilePersistence(File('${dir.path}/library.json')),
    workDir: Directory('${dir.path}/accompaniment'),
  );
  await library.load();
  runApp(KaraokeApp(library: library));
}

class KaraokeApp extends StatelessWidget {
  const KaraokeApp({super.key, required this.library});
  final Library library;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KaraokeAI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: HomeScreen(library: library),
    );
  }
}
