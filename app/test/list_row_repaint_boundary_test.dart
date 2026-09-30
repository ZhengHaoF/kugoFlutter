import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/source/music_platform.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/features/settings/settings_controller.dart';
import 'package:kugo/shared/widgets/common.dart';

/// 长列表（发现页歌曲列表、搜索结果列表）里的行原先没有任何重绘边界：
/// 桌面端鼠标扫过时每行的 hover setState 与 140ms 的 AnimatedOpacity 会把
/// 重绘范围扩散到整段列表。这里把「行自带 RepaintBoundary」定为约定。
Track _track() => const Track(
      id: 'a1',
      platform: MusicPlatform.kugou,
      name: '测试歌曲',
      artist: '测试歌手',
      album: '测试专辑',
      coverUrl: 'mock://a',
      durationMs: 200000,
      hash: 'h1',
    );

Widget _harness(Widget child) => ProviderScope(
      overrides: [
        settingsControllerProvider.overrideWith(_FixedSettings.new),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

class _FixedSettings extends SettingsController {
  @override
  AppSettings build() => const AppSettings();
}

void main() {
  testWidgets('TrackTile wraps its row in a repaint boundary', (tester) async {
    await tester.pumpWidget(
      _harness(TrackTile(track: _track(), onTap: () {})),
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(TrackTile),
        matching: find.byType(RepaintBoundary),
      ),
      findsAtLeastNWidgets(1),
    );
  });

  testWidgets('SearchResultRow wraps its row in a repaint boundary',
      (tester) async {
    await tester.pumpWidget(
      _harness(const SearchResultRow(imageSeed: 'mock://a', title: '结果')),
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(SearchResultRow),
        matching: find.byType(RepaintBoundary),
      ),
      findsAtLeastNWidgets(1),
    );
  });
}
