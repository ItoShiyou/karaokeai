import 'package:flutter/material.dart';
import 'package:karaokeai_core/karaokeai_core.dart';

import '../platform/native_audio.dart';
import '../state/library.dart';
import '../state/session.dart';
import 'result_screen.dart';

/// Near-blank screen for in-pocket use. Touch input is ignored; control
/// comes from remote commands (next / repeat) while the session runs.
class PocketScreen extends StatefulWidget {
  const PocketScreen({
    super.key,
    required this.setlist,
    this.library,
    this.engine,
    this.speaker,
  });

  final Setlist setlist;
  final Library? library;
  final PlatformAudioEngine? engine;
  final Speaker? speaker;

  @override
  State<PocketScreen> createState() => _PocketScreenState();
}

class _PocketScreenState extends State<PocketScreen> {
  SingingSession? _session;
  String? _error;

  @override
  void initState() {
    super.initState();
    final lib = widget.library,
        engine = widget.engine,
        speaker = widget.speaker;
    if (lib != null && engine != null && speaker != null) {
      _session = SingingSession(
        library: lib,
        setlist: widget.setlist,
        engine: engine,
        speaker: speaker,
        decoder: lib.decoder,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => _start(engine));
    }
  }

  Future<void> _start(PlatformAudioEngine engine) async {
    try {
      await engine.startSession();
      await _session!.run();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      try {
        await engine.endSession();
      } catch (_) {}
    }
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ResultScreen(results: _session!.results),
      ),
    );
  }

  @override
  void dispose() {
    _session?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.setlist.current;
    return Scaffold(
      backgroundColor: Colors.black,
      body: AbsorbPointer(
        child: Center(
          child: Text(
            _error ?? (song == null ? 'おつかれさまでした' : song.title),
            style: const TextStyle(color: Colors.white24, fontSize: 20),
          ),
        ),
      ),
    );
  }
}
