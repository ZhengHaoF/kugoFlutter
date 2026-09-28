import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:kugo/features/search/search_controller.dart';
import 'package:kugo/features/search/search_page.dart';

import 'fakes/fake_audio_player.dart';
import 'fakes/fake_music_source.dart';

/// Regression: the search controller used to outlive the page, so revisiting
/// Search showed an empty box on top of the previous results. A freshly-mounted
/// page (empty box) must drop those stale results.
void main() {
  testWidgets('revisiting Search clears results left from the last visit',
      (tester) async {
    bootstrapFakeMusicSources();
    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(path: '/search', builder: (_, __) => const SearchPage()),
        GoRoute(
          path: '/other',
          builder: (_, __) => const Scaffold(body: Text('other')),
        ),
      ],
    );
    addTearDown(router.dispose);

    final container = ProviderContainer(
      overrides: [
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: FakeAudioPlayer())),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    // Run a search (through the controller, so we don't fight the text field).
    await container.read(searchControllerProvider.notifier).submit('周杰伦');
    await tester.pumpAndSettle();
    expect(container.read(searchControllerProvider).searched, isTrue);

    // Leave the page (disposes its State), then come back fresh.
    router.go('/other');
    await tester.pumpAndSettle();
    router.go('/search');
    await tester.pumpAndSettle();

    // The new page mounts with an empty box — results must be gone too.
    expect(container.read(searchControllerProvider).searched, isFalse);
    expect(container.read(searchControllerProvider).activeTab.items, isEmpty);
    expect(find.text('热门搜索'), findsOneWidget);
  });
}