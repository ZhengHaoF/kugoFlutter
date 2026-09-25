import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/source/features.dart';
import 'package:kugo/core/source/music_platform.dart';
import 'package:kugo/data/sources/sources.dart';
import 'package:kugo/features/fm/fm_controller.dart';
import 'package:kugo/features/rank/rank_list_page.dart';
import 'package:kugo/features/search/search_controller.dart';
import 'package:kugo/features/settings/settings_controller.dart';
import 'package:kugo/features/settings/settings_page.dart';
import 'package:kugo/shared/widgets/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 两级开关要按「源 × 功能」判定能力，必须用真源（fake 源只有酷狗那套）。
  Future<ProviderContainer> restored(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    registerDefaultMusicSources();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.notifier).ensureRestored();
    return container;
  }

  AppSettings settingsOf(ProviderContainer c) =>
      c.read(settingsControllerProvider);
  SettingsController ctrl(ProviderContainer c) =>
      c.read(settingsControllerProvider.notifier);

  group('默认值与落盘', () {
    test('全新安装：所有「源 × 功能」子开关默认全开', () async {
      final c = await restored({});
      expect(settingsOf(c).disabledFeatures, isEmpty);
      for (final p in MusicPlatform.values) {
        for (final f in SourceFeature.values) {
          expect(settingsOf(c).isFeatureEnabled(p, f), isTrue,
              reason: '${p.wireName}:${f.id} 默认应为开');
        }
      }
    });

    test('落盘还原：只关掉 酷狗×私人FM', () async {
      final c = await restored({
        'settings.disabledFeatures': ['kugou:fm'],
      });
      expect(settingsOf(c).isFeatureOn(MusicPlatform.kugou, SourceFeature.personalFm),
          isFalse);
      // 同源其它功能、其它源的同一功能都不受影响。
      expect(
        settingsOf(c).isFeatureEnabled(MusicPlatform.kugou, SourceFeature.search),
        isTrue,
      );
      expect(
        settingsOf(c)
            .isFeatureEnabled(MusicPlatform.netease, SourceFeature.personalFm),
        isTrue,
      );
    });

    test('空列表是合法态（等于全开），不是非法值', () async {
      final c = await restored({'settings.disabledFeatures': <String>[]});
      expect(settingsOf(c).disabledFeatures, isEmpty);
      expect(
        settingsOf(c).isFeatureEnabled(MusicPlatform.kugou, SourceFeature.rank),
        isTrue,
      );
    });

    test('脏 token（源或功能已不存在）被丢弃', () async {
      final c = await restored({
        'settings.disabledFeatures': [
          'kugou:fm',
          'qqmusic:fm', // 未知源
          'kugou:sing', // 未知功能
          'kugou', // 不是 token 形状
        ],
      });
      expect(settingsOf(c).disabledFeatures, {'kugou:fm'});
    });

    test('setFeatureEnabled 落盘，且关→开可往返', () async {
      final c = await restored({});
      await ctrl(c).setFeatureEnabled(MusicPlatform.kugou, SourceFeature.rank, false);
      expect(
        settingsOf(c).isFeatureOn(MusicPlatform.kugou, SourceFeature.rank),
        isFalse,
      );
      var prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('settings.disabledFeatures'), ['kugou:rank']);

      await ctrl(c).setFeatureEnabled(MusicPlatform.kugou, SourceFeature.rank, true);
      expect(
        settingsOf(c).isFeatureOn(MusicPlatform.kugou, SourceFeature.rank),
        isTrue,
      );
      prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('settings.disabledFeatures'), isEmpty);
    });
  });

  group('两级 AND 语义', () {
    test('父开关关掉后功能不生效，但子开关的取值保留', () async {
      final c = await restored({});
      await ctrl(c)
          .setFeatureEnabled(MusicPlatform.kugou, SourceFeature.personalFm, false);

      // 停掉酷狗整源：子项取值不动（重新开启父开关要能恢复原配置）。
      await ctrl(c).setEnabledSources({MusicPlatform.netease});
      expect(
        settingsOf(c).isFeatureOn(MusicPlatform.kugou, SourceFeature.personalFm),
        isFalse,
        reason: '取值保留',
      );
      expect(
        settingsOf(c)
            .isFeatureEnabled(MusicPlatform.kugou, SourceFeature.personalFm),
        isFalse,
      );
      expect(
        settingsOf(c)
            .isFeatureEnabled(MusicPlatform.netease, SourceFeature.personalFm),
        isTrue,
      );

      // 重新开启父开关：仍是「关」（因为用户当初关过这一项）。
      await ctrl(c).setEnabledSources({
        MusicPlatform.kugou,
        MusicPlatform.netease,
      });
      expect(
        settingsOf(c)
            .isFeatureEnabled(MusicPlatform.kugou, SourceFeature.personalFm),
        isFalse,
      );
    });

    test('整源停用时，即使子开关是开也不生效', () async {
      final c = await restored({});
      await ctrl(c).setEnabledSources({MusicPlatform.netease});
      expect(
        settingsOf(c).isFeatureOn(MusicPlatform.kugou, SourceFeature.search),
        isTrue,
        reason: '没关过子开关',
      );
      expect(
        settingsOf(c)
            .isFeatureEnabled(MusicPlatform.kugou, SourceFeature.search),
        isFalse,
        reason: '父开关关着 → AND 结果必为假',
      );
    });

    test('空态归因：有源单独关掉该功能 → 归因功能；否则归因整源', () async {
      final c = await restored({});
      // 没人关过子开关 → 空态只可能是整源开关（或该源没这个能力）造成的。
      expect(settingsOf(c).featureSwitchCause(SourceFeature.rank), isNull);

      // 关掉酷狗榜单：酷狗仍启用，但这一项被单独关掉 → 归因功能。
      await ctrl(c).setFeatureEnabled(MusicPlatform.kugou, SourceFeature.rank, false);
      expect(
        settingsOf(c).featureSwitchCause(SourceFeature.rank),
        SourceFeature.rank,
        reason: '首选源仍启用 → 页面应该说「这一项功能被关了」',
      );

      // 再把酷狗整源停掉：启用中的网易并未关过榜单 → 归因整源。
      await ctrl(c).setEnabledSources({MusicPlatform.netease});
      expect(
        settingsOf(c).featureSwitchCause(SourceFeature.rank),
        isNull,
        reason: '启用集里没人关过该功能 → 页面应该说「音源已停用」',
      );
    });
  });

  group('消费点过滤', () {
    test('私人 FM：关掉酷狗的 FM 后可用源只剩网易云', () async {
      final c = await restored({});
      final fm = c.read(fmControllerProvider.notifier);
      expect(fm.availableSources(),
          [MusicPlatform.kugou, MusicPlatform.netease]);

      await ctrl(c)
          .setFeatureEnabled(MusicPlatform.kugou, SourceFeature.personalFm, false);
      expect(fm.availableSources(), [MusicPlatform.netease]);

      // 整源关掉网易云后一个都不剩 → 页面空态。
      await ctrl(c).setEnabledSources({MusicPlatform.kugou});
      expect(fm.availableSources(), isEmpty);
    });

    test('搜索：关掉网易云的搜索后筛选条只剩酷狗', () async {
      final c = await restored({});
      final search = c.read(searchControllerProvider.notifier);
      expect(search.availablePlatforms,
          [MusicPlatform.kugou, MusicPlatform.netease]);

      await ctrl(c)
          .setFeatureEnabled(MusicPlatform.netease, SourceFeature.search, false);
      expect(search.availablePlatforms, [MusicPlatform.kugou]);
    });

    testWidgets('榜单：关掉酷狗榜单后整页空态，且归因到功能而非整源',
        (tester) async {
      final c = await restored({});
      await ctrl(c).setEnabledSources({MusicPlatform.kugou});
      await ctrl(c).setFeatureEnabled(MusicPlatform.kugou, SourceFeature.rank, false);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: RankListPage()),
        ),
      );
      await tester.pump();

      expect(find.byType(SourceDisabledView), findsOneWidget);
      expect(find.text('酷狗的「排行榜」已关闭'), findsOneWidget);
    });

    testWidgets('设置页：子开关列全四个功能，父开关关闭时置灰但取值保留',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final c = await restored({});

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: SettingsPage()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // 两源都具备这四项能力 → 各 4 个子开关。
      for (final p in MusicPlatform.values) {
        for (final f in SourceFeature.values) {
          expect(
            find.byKey(ValueKey('feature_switch_${p.wireName}_${f.id}')),
            findsOneWidget,
            reason: '${p.wireName}:${f.id} 应出现',
          );
        }
      }

      SwitchListTile child(MusicPlatform p, SourceFeature f) =>
          tester.widget<SwitchListTile>(
            find.byKey(ValueKey('feature_switch_${p.wireName}_${f.id}')),
          );

      // 先关掉网易云的「私人 FM」子开关，再关掉网易云整源。
      expect(child(MusicPlatform.netease, SourceFeature.personalFm).value, isTrue);
      await tester.tap(
        find.byKey(const ValueKey('feature_switch_netease_fm')),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(child(MusicPlatform.netease, SourceFeature.personalFm).value, isFalse);

      await tester.tap(
        find.ancestor(
          of: find.text('启用网易云音源'),
          matching: find.byType(SwitchListTile),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      final tile = child(MusicPlatform.netease, SourceFeature.personalFm);
      expect(tile.value, isFalse, reason: '父开关关闭不重置子项取值');
      expect(tile.onChanged, isNull, reason: '父开关关闭时子项应置灰不可点');
      // 其它源的子开关不受影响。
      expect(child(MusicPlatform.kugou, SourceFeature.personalFm).onChanged,
          isNotNull);
    });
  });
}
