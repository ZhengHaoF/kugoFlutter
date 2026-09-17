import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/shared/widgets/common.dart';
import 'package:kugo/shared/widgets/cover_box.dart';

void main() {
  testWidgets('TrackTile shows name and artist', (tester) async {
    const track = Track(
      id: 'x',
      name: '晴天',
      artist: '周杰伦',
      album: '',
      coverUrl: 'http://example.com/a.jpg',
      durationMs: 120000,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TrackTile(track: track)),
      ),
    );
    expect(find.text('晴天'), findsOneWidget);
    expect(find.text('周杰伦'), findsOneWidget);
  });

  testWidgets('CoverBox builds with seed', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CoverBox(seed: 'mock://t', size: 40)),
      ),
    );
    expect(find.byType(CoverBox), findsOneWidget);
  });

  testWidgets('QualityBadge VIP label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: QualityBadge(label: 'VIP', gradient: true)),
      ),
    );
    expect(find.text('VIP'), findsOneWidget);
  });
}
