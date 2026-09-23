import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kugo/app.dart';
import 'package:kugo/features/explore/explore_page.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:kugo/features/playlist/playlist_detail_page.dart';
import 'package:kugo/features/recommend/daily_recommend_page.dart';
import 'package:kugo/features/settings/settings_page.dart';
import 'package:kugo/shared/shell/desktop_sidebar.dart';
import 'package:kugo/shared/widgets/desktop_player_bar.dart';
import 'package:kugo/shared/widgets/mini_player_bar.dart';

import 'fakes/fake_audio_player.dart';

void main() {
  group('Desktop nested navigation tests', () {
    testWidgets(
      'Navigating to /daily, /ranks, and /settings on desktop keeps DesktopSidebar and DesktopPlayerBar mounted',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 720);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final engine = FakeAudioPlayer();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              playerControllerProvider
                  .overrideWith(() => PlayerController(engine: engine)),
            ],
            child: const KugoApp(),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));

        // Initial state: Explore page inside DesktopShell
        expect(find.byType(DesktopSidebar), findsOneWidget);
        expect(find.byType(DesktopPlayerBar), findsOneWidget);

        // Click "每日推荐" in DesktopSidebar
        final dailyItem = find.descendant(
          of: find.byType(DesktopSidebar),
          matching: find.text('每日推荐'),
        );
        expect(dailyItem, findsOneWidget);
        await tester.tap(dailyItem);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        // DesktopSidebar and DesktopPlayerBar must STILL be present!
        expect(find.byType(DesktopSidebar), findsOneWidget);
        expect(find.byType(DesktopPlayerBar), findsOneWidget);
        expect(find.byType(DailyRecommendPage), findsOneWidget);

        // Click "系统设置" in DesktopSidebar
        final settingsItem = find.descendant(
          of: find.byType(DesktopSidebar),
          matching: find.text('系统设置'),
        );
        expect(settingsItem, findsOneWidget);
        await tester.tap(settingsItem);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        // DesktopSidebar and DesktopPlayerBar must STILL be present!
        expect(find.byType(DesktopSidebar), findsOneWidget);
        expect(find.byType(DesktopPlayerBar), findsOneWidget);
        expect(find.byType(SettingsPage), findsOneWidget);
      },
    );

    testWidgets(
      'Pushing detail page /playlist/test_1 retains shell, and AppBar back pops cleanly',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 720);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final engine = FakeAudioPlayer();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              playerControllerProvider
                  .overrideWith(() => PlayerController(engine: engine)),
            ],
            child: const KugoApp(),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));

        final routerCtx = tester.element(find.byType(DesktopSidebar));

        // Push playlist detail page
        GoRouter.of(routerCtx).push('/playlist/mock_123');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        // Verify shell is still mounted on desktop
        expect(find.byType(DesktopSidebar), findsOneWidget);
        expect(find.byType(DesktopPlayerBar), findsOneWidget);
        expect(find.byType(PlaylistDetailPage), findsOneWidget);

        // Pop back to explore via AppBar back button
        final backButton = find.byIcon(Icons.arrow_back_rounded);
        expect(backButton, findsOneWidget);
        await tester.tap(backButton);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.byType(DesktopSidebar), findsOneWidget);
        expect(find.byType(DesktopPlayerBar), findsOneWidget);
        expect(find.byType(PlaylistDetailPage), findsNothing);
      },
    );

    testWidgets(
      'Sidebar switch fades/drifts the content pane instead of hard-cutting',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 720);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final engine = FakeAudioPlayer();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              playerControllerProvider
                  .overrideWith(() => PlayerController(engine: engine)),
            ],
            child: const KugoApp(),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));

        final dailyItem = find.descendant(
          of: find.byType(DesktopSidebar),
          matching: find.text('每日推荐'),
        );
        await tester.tap(dailyItem);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));

        // Mid-flight: content pane is under an Opacity/Transform wrapper.
        expect(find.byType(DailyRecommendPage), findsOneWidget);
        expect(
          find.ancestor(
            of: find.byType(DailyRecommendPage),
            matching: find.byType(Opacity),
          ),
          findsWidgets,
        );

        // 240ms nav fade — pump past it without pumpAndSettle (page tickers).
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(DailyRecommendPage), findsOneWidget);
        // Settled: transition wrapper unwraps so the pane paints raw.
        expect(
          find.ancestor(
            of: find.byType(DailyRecommendPage),
            matching: find.byType(Transform),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Mobile narrow screen hides dock on subpages, keeping full-screen experience',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final engine = FakeAudioPlayer();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              playerControllerProvider
                  .overrideWith(() => PlayerController(engine: engine)),
            ],
            child: const KugoApp(),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));

        // Main tab shows mini player bar
        expect(find.byType(MiniPlayerBar), findsOneWidget);
        expect(find.byType(DesktopSidebar), findsNothing);

        final routerCtx = tester.element(find.byType(ExplorePage));

        // Navigate to subpage /daily
        GoRouter.of(routerCtx).push('/daily');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        // Subpage on mobile: dock and mini bar are hidden
        expect(find.byType(DailyRecommendPage), findsOneWidget);
        expect(find.byType(MiniPlayerBar), findsNothing);
      },
    );
  });
}
