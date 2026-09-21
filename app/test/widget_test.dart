import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kugo/app.dart';
import 'package:kugo/features/player/player_controller.dart';

import 'fakes/fake_audio_player.dart';

void main() {
  testWidgets('app boots into explore shell', (tester) async {
    // 必须注入假引擎：`createAudioEngine()` 在 Windows 宿主上会选 media_kit，
    // 而 libmpv 只在真实应用里由 `main()` 初始化过。
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerControllerProvider
              .overrideWith(() => PlayerController(engine: FakeAudioPlayer())),
        ],
        child: const KugoApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('发现'), findsWidgets);
    expect(find.text('我的'), findsWidgets);
    expect(find.text('首页'), findsNothing);
  });
}
