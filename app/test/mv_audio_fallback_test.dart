import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overtone/core/models/mv_models.dart';
import 'package:overtone/core/models/search_result.dart';
import 'package:overtone/core/models/track.dart';
import 'package:overtone/core/source/capabilities.dart';
import 'package:overtone/core/source/music_platform.dart';
import 'package:overtone/core/source/music_source.dart';
import 'package:overtone/core/source/registry.dart';
import 'package:overtone/features/mv/mv_entry.dart';
import 'package:overtone/features/player/mv_audio_fallback.dart';
import 'package:overtone/features/player/player_controller.dart';
import 'package:overtone/features/settings/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player.dart';
import 'fakes/fake_music_source.dart';

const _kMvAudioEnabled = 'settings.mvAudioFallbackEnabled';

/// MV 源：可控返回 + 记录取流请求。
/// （[FakeMusicSource] 本身不实现 MV 能力，保持它作为「无 MV 音源」的语义。）
class _MvFakeSource extends FakeMusicSource
    implements MvSearchSource, MvDetailSource {
  /// `songMvs` 返回的版本列表。
  List<MvBrief> songMvVersions = const [];

  /// 非空时 `songMvs` 抛出该错误。
  Object? songMvsError;

  /// `resolveMvPlayUrl` 的返回（可带备用地址与防盗链头）。
  MvPlayUrlResult mvPlayUrl = const MvPlayUrlResult(
    url: 'https://example.com/mv.mp4',
    headers: {'Referer': 'https://example.com'},
  );

  /// 非空时 `resolveMvPlayUrl` 抛出该错误。
  Object? mvPlayUrlError;

  /// 被请求过的 MV hash（用来断言选中了哪一版、以及是否只试了一次）。
  final List<String> requestedMvHashes = [];

  @override
  Future<List<MvBrief>> songMvs(Track track) async {
    final e = songMvsError;
    if (e != null) throw e;
    return songMvVersions;
  }

  @override
  Future<MvPlayUrlResult> resolveMvPlayUrl(String hash) async {
    requestedMvHashes.add(hash);
    final e = mvPlayUrlError;
    if (e != null) throw e;
    return mvPlayUrl;
  }

  @override
  Future<SearchPageResult<MvBrief>> searchMvs(
    String keyword, {
    int page = 1,
    int pageSize = 20,
  }) async => const SearchPageResult<MvBrief>.empty();

  @override
  Future<SearchPageResult<MvBrief>> fetchArtistMvs(
    String authorId, {
    int page = 1,
    int pageSize = 30,
    String tag = '',
  }) async => const SearchPageResult<MvBrief>.empty();

  @override
  Future<MvDetail?> fetchMvDetail(MvBrief brief) async => null;
}

Track _track(String id, {String mixSongId = '123456'}) => Track(
  id: id,
  name: id,
  artist: 'fixture',
  album: 'fixture',
  coverUrl: 'https://example.invalid/$id.jpg',
  durationMs: 180000,
  hash: 'hash-$id',
  mixSongId: mixSongId,
  platform: MusicPlatform.kugou,
);

/// 一条默认「合格」的曲库 MV；各字段可单独改坏以覆盖过滤规则。
MvBrief _mv({
  String id = '1',
  String hash = 'mv-hash',
  int? isPublish = 1,
  int? isUgc = 0,
  int? isShort = 0,
  int? isOther = 0,
  bool recommend = false,
  int durationMs = 180000,
}) => MvBrief(
  id: id,
  hash: hash,
  name: 'mv-$id',
  coverUrl: '',
  durationMs: durationMs,
  isRecommend: recommend,
  isPublish: isPublish,
  isUgc: isUgc,
  isShort: isShort,
  isOther: isOther,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    musicSourceRegistry = null;
    clearMvCache();
  });

  tearDown(() {
    musicSourceRegistry = null;
    clearMvCache();
  });

  group('pickCatalogMv 过滤规则', () {
    test('只收官方发布 + 非 UGC + 非短视频 + 非其他', () {
      expect(pickCatalogMv([_mv(id: 'ok')])?.id, 'ok');
    });

    test('任一标记为 null 时一律不收（字段缺失不等于 0）', () {
      expect(pickCatalogMv([_mv(isUgc: null)]), isNull);
      expect(pickCatalogMv([_mv(isShort: null)]), isNull);
      expect(pickCatalogMv([_mv(isOther: null)]), isNull);
      expect(pickCatalogMv([_mv(isPublish: null)]), isNull);
    });

    test('UGC / 短视频 / 其他版本 / 未发布 都被排除', () {
      expect(pickCatalogMv([_mv(isUgc: 1)]), isNull);
      expect(pickCatalogMv([_mv(isShort: 1)]), isNull);
      expect(pickCatalogMv([_mv(isOther: 1)]), isNull);
      expect(pickCatalogMv([_mv(isPublish: 0)]), isNull);
    });

    test('时长为 0 或 hash 为空不参与兜底', () {
      expect(pickCatalogMv([_mv(durationMs: 0)]), isNull);
      expect(pickCatalogMv([_mv(hash: '')]), isNull);
    });

    test('优先官方推荐位；并列时保持上游顺序', () {
      expect(
        pickCatalogMv([
          _mv(id: 'a'),
          _mv(id: 'b', recommend: true),
          _mv(id: 'c'),
        ])?.id,
        'b',
      );
      expect(pickCatalogMv([_mv(id: 'a'), _mv(id: 'b')])?.id, 'a');
    });
  });

  group('resolveMvAudioFallback', () {
    late _MvFakeSource source;

    setUp(() {
      source = _MvFakeSource();
      musicSourceRegistry = MusicSourceRegistry([source]);
    });

    test('缺少可寻址 mixSongId 不查询', () async {
      final reasons = <MvAudioUnavailableReason>[];
      final result = await resolveMvAudioFallback(
        _track('A', mixSongId: ''),
        isCurrent: () => true,
        onUnavailable: reasons.add,
      );
      expect(result, isNull);
      expect(reasons, [MvAudioUnavailableReason.noMixSongId]);
    });

    test('音源注册表缺失 → 无能力', () async {
      musicSourceRegistry = null;
      final reasons = <MvAudioUnavailableReason>[];
      expect(
        await resolveMvAudioFallback(
          _track('A'),
          isCurrent: () => true,
          onUnavailable: reasons.add,
        ),
        isNull,
      );
      expect(reasons, [MvAudioUnavailableReason.noCapability]);
    });

    test('没有合格版本 → noCatalogMv', () async {
      source.songMvVersions = [_mv(isUgc: 1)];
      final reasons = <MvAudioUnavailableReason>[];
      expect(
        await resolveMvAudioFallback(
          _track('A'),
          isCurrent: () => true,
          onUnavailable: reasons.add,
        ),
        isNull,
      );
      expect(reasons, [MvAudioUnavailableReason.noCatalogMv]);
    });

    test('全是平台短视频 → allShortVideos', () async {
      source.songMvVersions = [_mv(isShort: 1)];
      final reasons = <MvAudioUnavailableReason>[];
      expect(
        await resolveMvAudioFallback(
          _track('A'),
          isCurrent: () => true,
          onUnavailable: reasons.add,
        ),
        isNull,
      );
      expect(reasons, [MvAudioUnavailableReason.allShortVideos]);
    });

    test('命中曲库 MV → 交出地址与防盗链头', () async {
      source.songMvVersions = [
        _mv(id: 'a', hash: 'aaa'),
        _mv(id: 'b', hash: 'bbb', recommend: true),
      ];
      source.mvPlayUrl = const MvPlayUrlResult(
        url: 'https://example.com/main.mp4',
        backupUrls: ['https://example.com/backup.mp4'],
        headers: {'Referer': 'https://example.com'},
      );

      final result = await resolveMvAudioFallback(
        _track('A'),
        isCurrent: () => true,
      );

      expect(result, isNotNull);
      expect(result!.mv.id, 'b');
      expect(result.urls, [
        'https://example.com/main.mp4',
        'https://example.com/backup.mp4',
      ]);
      expect(result.headers['Referer'], 'https://example.com');
      expect(source.requestedMvHashes, ['bbb']);
    });

    test('版本列表查询失败 → queryFailed', () async {
      source.songMvsError = const UpstreamChanged('boom');
      final reasons = <MvAudioUnavailableReason>[];
      expect(
        await resolveMvAudioFallback(
          _track('A'),
          isCurrent: () => true,
          onUnavailable: reasons.add,
        ),
        isNull,
      );
      expect(reasons, [MvAudioUnavailableReason.queryFailed]);
    });

    test('取流失败 → queryFailed', () async {
      source.songMvVersions = [_mv()];
      source.mvPlayUrlError = const UpstreamChanged('no url');
      final reasons = <MvAudioUnavailableReason>[];
      expect(
        await resolveMvAudioFallback(
          _track('A'),
          isCurrent: () => true,
          onUnavailable: reasons.add,
        ),
        isNull,
      );
      expect(reasons, [MvAudioUnavailableReason.queryFailed]);
    });

    test('取流途中切歌（isCurrent 变 false）→ 丢弃结果', () async {
      source.songMvVersions = [_mv()];
      var current = true;

      final future = resolveMvAudioFallback(
        _track('A'),
        isCurrent: () => current,
      );
      current = false;
      expect(await future, isNull);
    });
  });

  group('播放控制器接入', () {
    late FakeMusicSource playback;
    late _MvFakeSource mvSource;

    setUp(() {
      playback = FakeMusicSource();
      mvSource = _MvFakeSource();
    });

    ProviderContainer container(FakeAudioPlayer engine) {
      musicSourceRegistry = MusicSourceRegistry([mvSource]);
      addTearDown(() => musicSourceRegistry = null);
      final c = ProviderContainer(
        overrides: [
          playerControllerProvider.overrideWith(
            () => PlayerController(engine: engine, source: playback),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<void> play(
      WidgetTester tester,
      ProviderContainer c,
      String id,
    ) async {
      final p = c.read(playerControllerProvider.notifier);
      await tester.runAsync(() => p.playQueue([_track(id)]));
      await tester.pump();
    }

    testWidgets('开关默认关闭：VIP 解析失败不触发兜底', (tester) async {
      final engine = FakeAudioPlayer();
      playback.playError = const NoPermission('VIP 歌曲');
      mvSource.songMvVersions = [_mv()];
      final c = container(engine);

      await play(tester, c, 'A');

      final state = c.read(playerControllerProvider);
      expect(state.display, PlayerDisplayState.error);
      expect(state.playingMvAudio, isFalse);
      expect(engine.lastUrl, isNull);
      expect(mvSource.requestedMvHashes, isEmpty);
    });

    testWidgets('开启后：解析失败改为播放 MV 音轨并打标', (tester) async {
      SharedPreferences.setMockInitialValues({_kMvAudioEnabled: true});
      final engine = FakeAudioPlayer();
      playback.playError = const NoPermission('VIP 歌曲');
      mvSource.songMvVersions = [_mv(hash: 'mv-hash')];
      final c = container(engine);
      await c.read(settingsControllerProvider.notifier).ensureRestored();

      await play(tester, c, 'A');

      final state = c.read(playerControllerProvider);
      expect(state.display, PlayerDisplayState.playing);
      expect(state.playingMvAudio, isTrue);
      expect(state.resolvedQuality, isNull);
      expect(engine.lastUrl, 'https://example.com/mv.mp4');
      expect(mvSource.requestedMvHashes, ['mv-hash']);
    });

    testWidgets('网络类失败不兜底（不额外打 MV 接口）', (tester) async {
      SharedPreferences.setMockInitialValues({_kMvAudioEnabled: true});
      final engine = FakeAudioPlayer();
      playback.playError = const NetworkFailure('offline');
      mvSource.songMvVersions = [_mv()];
      final c = container(engine);
      await c.read(settingsControllerProvider.notifier).ensureRestored();

      await play(tester, c, 'A');

      final state = c.read(playerControllerProvider);
      expect(state.display, PlayerDisplayState.error);
      expect(state.playingMvAudio, isFalse);
      expect(mvSource.requestedMvHashes, isEmpty);
    });

    testWidgets('兜底自身失败时只尝试一次，并保留原始失败信息', (tester) async {
      SharedPreferences.setMockInitialValues({_kMvAudioEnabled: true});
      final engine = FakeAudioPlayer();
      playback.playError = const NoPermission('VIP 歌曲');
      mvSource.songMvVersions = [_mv()];
      mvSource.mvPlayUrlError = const UpstreamChanged('mv url fail');
      final c = container(engine);
      await c.read(settingsControllerProvider.notifier).ensureRestored();

      await play(tester, c, 'A');

      final state = c.read(playerControllerProvider);
      expect(state.display, PlayerDisplayState.error);
      expect(state.errorCode, contains('VIP 歌曲'));
      expect(mvSource.requestedMvHashes, hasLength(1));
      expect(state.playingMvAudio, isFalse);
    });

    testWidgets('切歌后 MV 标记复位', (tester) async {
      SharedPreferences.setMockInitialValues({_kMvAudioEnabled: true});
      final engine = FakeAudioPlayer();
      playback.playError = const NoPermission('VIP 歌曲');
      mvSource.songMvVersions = [_mv()];
      final c = container(engine);
      await c.read(settingsControllerProvider.notifier).ensureRestored();

      await play(tester, c, 'A');
      expect(c.read(playerControllerProvider).playingMvAudio, isTrue);

      // 下一首能正常解析：兜底标记必须清掉，且不再走 MV。
      playback.playError = null;
      playback.nextPlayUrl = const PlayUrlResult(
        url: 'https://example.com/b.mp3',
      );
      await play(tester, c, 'B');

      final state = c.read(playerControllerProvider);
      expect(state.playingMvAudio, isFalse);
      expect(engine.lastUrl, 'https://example.com/b.mp3');
    });
  });
}
