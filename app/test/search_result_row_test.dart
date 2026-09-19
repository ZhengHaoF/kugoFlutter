import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/shared/widgets/common.dart';

void main() {
  group('SearchResultRow', () {
    testWidgets('renders title, subtitle and trailing count', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchResultRow(
              imageSeed: '',
              title: '范特西',
              subtitle: '周杰伦',
              trailingLabel: '10首',
            ),
          ),
        ),
      );

      expect(find.text('范特西'), findsOneWidget);
      expect(find.text('周杰伦'), findsOneWidget);
      expect(find.text('10首'), findsOneWidget);
    });

    testWidgets('hides the trailing label when empty', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: const SearchResultRow(
              imageSeed: '',
              title: '周杰伦',
            ),
          ),
        ),
      );

      expect(find.text('周杰伦'), findsOneWidget);
      // Only the title should be present — no empty subtitle / count slots.
      expect(find.byType(Text), findsOneWidget);
    });

    testWidgets('fires onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchResultRow(
              imageSeed: '',
              title: '晴天',
              onTap: () => taps++,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(SearchResultRow));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('round mode draws the person fallback for artists',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: const SearchResultRow(
              imageSeed: '',
              title: '林俊杰',
              round: true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    });

    testWidgets('a disabled row (null onTap) does not crash on tap',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: const SearchResultRow(
              imageSeed: '',
              title: '无 id 歌手',
            ),
          ),
        ),
      );

      await tester.tap(find.byType(SearchResultRow));
      await tester.pump();
      expect(find.text('无 id 歌手'), findsOneWidget);
    });
  });
}
