import 'package:flutter_test/flutter_test.dart';

import 'package:kugo/core/models/audio_quality.dart';
import 'package:kugo/core/source/capabilities.dart';
import 'package:kugo/core/source/music_platform.dart';
import 'package:kugo/core/source/music_source.dart';
import 'package:kugo/core/source/quality_map.dart';
import 'package:kugo/core/source/registry.dart';
import 'package:kugo/data/sources/bili/bili_source.dart';
import 'package:kugo/data/sources/sources.dart';
import 'package:kugo/features/profile/source_account.dart';

import 'fakes/fake_music_source.dart';

/// B5 装配回归：registry 注册 / 能力诚实性 / 登录入口门控 / 选档阈值。
///
/// UI 层的 B 站游客态（我的页 / 个人中心 / 我喜欢空态）在
/// `account_source_dispatch_test.dart` 的「B 站账号源」组。
/// 封面防盗链 Referer 在 `cover_cache_test.dart`；默认音源集在
/// `settings_enabled_sources_test.dart`。

/// 带 [DeviceLoginSource] 的假源。真 `neteaseSource` 也能过 `is T` 判定，
/// 但构造它要拉一串依赖；假源零成本，且 `canLoginSource` 只做能力判定。
class _LoginCapableSource extends FakeMusicSource
    implements DeviceLoginSource {
  _LoginCapableSource() : super(platform: MusicPlatform.netease);

  @override
  Future<LoginQrSession> createLoginQr() async =>
      const LoginQrSession(id: 'k', qrContent: 'https://qr');

  @override
  Future<LoginQrPoll> pollLoginQr(LoginQrSession session) async =>
      const LoginQrPoll(status: LoginQrStatus.waiting);

  @override
  Future<LoginAccount?> currentAccount() async => null;

  @override
  Future<void> logout() async {}
}

void main() {
  setUp(() {
    // registry 是全局可变状态：每个用例自备，避免相互污染。
    musicSourceRegistry = null;
  });

  group('registry 装配', () {
    test('registerDefaultMusicSources 注册三源，B 站排最后', () {
      registerDefaultMusicSources();

      expect(
        musicSourceRegistry!.platforms,
        [MusicPlatform.kugou, MusicPlatform.netease, MusicPlatform.bili],
      );
      expect(musicSourceRegistry!.supports(MusicPlatform.bili), isTrue);
    });

    test('biliSource 单例：基类契约在，账号/内容能力不冒充', () {
      final registry = MusicSourceRegistry([biliSource]);

      expect(biliSource.platform, MusicPlatform.bili);
      // 基类六件套在（搜索 + 取流 + 恒空歌词，B2 已落地）。
      expect(registry.capability<MusicSource>(MusicPlatform.bili), isNotNull);
      // B3/B4 实现只读内容和登录；云端我喜欢依然不实现。
      expect(
        registry.capability<DeviceLoginSource>(MusicPlatform.bili),
        isNotNull,
      );
      expect(
        registry.capability<UserLibrarySource>(MusicPlatform.bili),
        isNull,
      );
      expect(
        registry.capability<UserPlaylistReadSource>(MusicPlatform.bili),
        isNotNull,
      );
    });
  });

  group('登录入口门控（canLoginSource）', () {
    test('酷狗恒真（独立 auth 链路，不经 DeviceLoginSource）', () {
      musicSourceRegistry = MusicSourceRegistry([biliSource]);
      expect(canLoginSource(MusicPlatform.kugou), isTrue);
    });

    test('B 站 B3 落地后有登录入口', () {
      musicSourceRegistry = MusicSourceRegistry([biliSource]);
      expect(canLoginSource(MusicPlatform.bili), isTrue);
    });

    test('有 DeviceLoginSource 的源为 true', () {
      musicSourceRegistry = MusicSourceRegistry([_LoginCapableSource()]);
      expect(canLoginSource(MusicPlatform.netease), isTrue);
    });

    test('registry 未装配时不崩（非酷狗按没有登录入口处理）', () {
      musicSourceRegistry = null;
      expect(canLoginSource(MusicPlatform.kugou), isTrue);
      expect(canLoginSource(MusicPlatform.netease), isFalse);
      expect(canLoginSource(MusicPlatform.bili), isFalse);
    });
  });

  group('B 站选档阈值（quality_map ↔ BiliSource 一口径）', () {
    test('带宽下限：sq=150k / hq=70k / standard=0', () {
      expect(SourceQualityMap.biliBandwidthFloor(AppQuality.sq), 150000);
      expect(SourceQualityMap.biliBandwidthFloor(AppQuality.hq), 70000);
      expect(SourceQualityMap.biliBandwidthFloor(AppQuality.standard), 0);
    });

    test('qualityOfBandwidth 按同一阈值分档（B1 实测口径）', () {
      // 30216≈64k → standard；30232≈80~115k → hq；30280≈177~216k → sq。
      expect(BiliSource.qualityOfBandwidth(64000), AppQuality.standard);
      expect(BiliSource.qualityOfBandwidth(69999), AppQuality.standard);
      expect(BiliSource.qualityOfBandwidth(70000), AppQuality.hq);
      expect(BiliSource.qualityOfBandwidth(115000), AppQuality.hq);
      expect(BiliSource.qualityOfBandwidth(149999), AppQuality.hq);
      expect(BiliSource.qualityOfBandwidth(150000), AppQuality.sq);
      expect(BiliSource.qualityOfBandwidth(216000), AppQuality.sq);
    });
  });
}
