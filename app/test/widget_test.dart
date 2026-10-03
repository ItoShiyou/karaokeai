import 'package:flutter_test/flutter_test.dart';
import 'package:karaokeai/main.dart';

void main() {
  testWidgets('home lists setlist and opens pocket mode', (tester) async {
    await tester.pumpWidget(const KaraokeApp());
    expect(find.text('デモ曲 1'), findsOneWidget);
    await tester.tap(find.text('ポケットモード開始'));
    await tester.pumpAndSettle();
    expect(find.text('デモ曲 1'), findsOneWidget);
  });
}
