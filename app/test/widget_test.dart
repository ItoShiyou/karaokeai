import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:karaokeai/screens/home_screen.dart';
import 'package:karaokeai/state/library.dart';

Uint8List _mp4(String extra) => Uint8List.fromList(
  '${String.fromCharCodes([0, 0, 0, 20])}ftypM4A ${'\u0000' * 8}$extra'
      .codeUnits,
);

Widget _app(Library lib, PickedFile file) => MaterialApp(
  home: HomeScreen(library: lib, pickFile: () async => file),
);

void main() {
  testWidgets('imports a normal file, then opens pocket mode', (tester) async {
    final lib = Library(headReader: (_) async => _mp4('mp4a'));
    await tester.pumpWidget(_app(lib, const PickedFile('夜空.m4a', '/x/夜空.m4a')));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('夜空'), findsOneWidget);
    await tester.tap(find.text('ポケットモード開始'));
    await tester.pumpAndSettle();
    expect(find.text('夜空'), findsOneWidget);
  });

  testWidgets('rejects DRM-protected file', (tester) async {
    final lib = Library(headReader: (_) async => _mp4('drms'));
    await tester.pumpWidget(_app(lib, const PickedFile('a.m4a', '/x/a.m4a')));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('DRM保護された音源は読み込めません'), findsOneWidget);
    expect(lib.songs, isEmpty);
  });

  testWidgets('latency is stored per output', (tester) async {
    final lib = Library();
    await tester.pumpWidget(_app(lib, const PickedFile('a.mp3', '/x')));
    await tester.tap(find.byIcon(Icons.timer));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider), const Offset(100, 0));
    await tester.pump();
    expect(lib.latency.getMs('car'), isNotNull);
    expect(lib.latency.getMs('home'), isNull);
  });

  testWidgets('lyrics need stopped confirmation, then save', (tester) async {
    final lib = Library(headReader: (_) async => _mp4('mp4a'));
    await tester.pumpWidget(_app(lib, const PickedFile('a.m4a', '/x/a.m4a')));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.lyrics_outlined));
    await tester.pumpAndSettle();
    expect(find.text('停車中ですか？'), findsOneWidget);
    await tester.tap(find.text('停車中です'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'la la');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(lib.records.single.lyrics, 'la la');
  });
}
