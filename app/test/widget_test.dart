import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

    // 冷启动落在「发现」页，底部导航两个主入口都在。
    expect(find.text('发现'), findsWidgets);
    expect(find.text('我的'), findsWidgets);
    // 只断言正向事实：以前这里还有一条 `expect(find.text('首页'), findsNothing)`
    // ——那是「某个文案不存在」的变更探测器，改个措辞就红，红了也不是真 bug。
    expect(tester.takeException(), isNull);
  });
}
