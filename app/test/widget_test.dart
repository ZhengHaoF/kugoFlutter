import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kugo/app.dart';

void main() {
  testWidgets('app boots into explore shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: KugoApp()));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('发现'), findsWidgets);
    expect(find.text('我的'), findsWidgets);
    expect(find.text('首页'), findsNothing);
  });
}
