import 'package:flutter/material.dart';
import 'package:karaokeai_core/karaokeai_core.dart';

/// Near-blank screen for in-pocket use. Touch input is ignored; control comes
/// from remote commands / voice (wired to AudioEngine.remoteCommands later).
class PocketScreen extends StatefulWidget {
  const PocketScreen({super.key, required this.setlist});

  final Setlist setlist;

  @override
  State<PocketScreen> createState() => _PocketScreenState();
}

class _PocketScreenState extends State<PocketScreen> {
  @override
  Widget build(BuildContext context) {
    final song = widget.setlist.current;
    return Scaffold(
      backgroundColor: Colors.black,
      body: AbsorbPointer(
        child: Center(
          child: Text(
            song == null ? 'おつかれさまでした' : song.title,
            style: const TextStyle(color: Colors.white24, fontSize: 20),
          ),
        ),
      ),
    );
  }
}
