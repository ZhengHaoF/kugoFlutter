/// 封面大图查看器（`cover_viewer.dart`）：打开/关闭三条路径、大图 URL 请求。
///
/// CoverCache 的磁盘级用假 PathProvider 指到临时目录、网络级用脚本化 Dio
/// 回放——全程不打真 CDN（同 `cover_cache_test.dart` 的口径）。
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overtone/core/cache/cover_cache.dart';
import 'package:overtone/shared/widgets/cover_box.dart';
import 'package:overtone/shared/widgets/cover_viewer.dart';

import 'fakes/fake_kugo_client.dart';
import 'fakes/fake_path_provider.dart';

const _kugouCover =
    'https://imge.kugou.com/stdmusic/400/20230920/20230920142503632013.jpg';
const _kugouBig =
    'https://imge.kugou.com/stdmusic/1080/20230920/20230920142503632013.jpg';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late ScriptedAdapter adapter;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('kugo_viewer_test');
    installFakePathProvider(tmp);
  });

  tearDownAll(() {
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    adapter = ScriptedAdapter(const []);
    CoverCache.instance.dioForTesting = Dio(
      BaseOptions(
        responseType: ResponseType.bytes,
        validateStatus: (s) => s != null && s >= 200 && s < 300,
      ),
    )..httpClientAdapter = adapter;
  });

  Future<void> pumpHost(WidgetTester tester, {required String seed}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showCoverViewer(
                  context,
                  seed: seed,
                  tag: 'viewer-cover',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('mock 封面：占位渐变 + 点空白处关闭', (tester) async {
    await pumpHost(tester, seed: 'mock://a');
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CoverViewer), findsOneWidget);
    // 非网络 seed → CoverBox 占位（不发起任何图片解码）。
    expect(find.byType(CoverBox), findsOneWidget);

    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CoverViewer), findsNothing);
  });

  testWidgets('Esc 关闭', (tester) async {
    await pumpHost(tester, seed: 'mock://a');
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CoverViewer), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CoverViewer), findsNothing);
  });

  testWidgets('大图走 CoverCache 拉 1080 变体；拉不到保持占位', (tester) async {
    await pumpHost(tester, seed: _kugouCover);
    await tester.tap(find.text('open'));
    await tester.pump();
    expect(find.byType(CoverViewer), findsOneWidget);
    // CoverCache 的取数链（假 PathProvider → 真 IO → Dio）跨 fake/real 两个
    // 异步域：initState 里启动的 await 延续排在 fake 域微任务队列，只有
    // runAsync 与 pump 交替才能把整条链推到底。
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 10));
    }

    // 查看器自己拉的是大图 URL（不是原图重复下载）。
    final urls = adapter.requests.map((r) => r.uri.toString()).toList();
    expect(urls, contains(_kugouBig));
    // 另一个请求（若有）是 Hero 飞行 shuttle 为原图建的 CoverBox —— 真机上
    // 原图早已在 CoverCache 内存里，这里是内存命中、不发请求。

    // 大图没拉到 → 不渲染坏图，回落占位/原图。
    expect(find.byType(CoverBox), findsOneWidget);
  });
}
