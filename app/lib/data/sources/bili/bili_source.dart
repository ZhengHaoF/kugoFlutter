import '../../../core/api/bili/bili_client.dart';
import '../../../core/api/bili/bili_endpoints.dart';
import '../../../core/api/bili/bili_mappers.dart';
import '../../../core/models/audio_quality.dart';
import '../../../core/models/search_result.dart';
import '../../../core/models/track.dart';
import '../../../core/source/music_source.dart';
import '../../../core/source/music_platform.dart';

/// B 站音源适配器（B2：搜索 + 取流）。
///
/// 范围对齐方案 §8 B2：`searchSongs` + `resolvePlayUrl`（音轨降级 + cid 懒取）
/// + 音质映射 + 分 P 展开的 id 兼容。歌单 / 歌手 / 收藏夹 / 账号等能力接口
/// 属 B3/B4，本类先只 implements [MusicSource]——**禁止空实现冒充**
/// （多音源方案 §3.2：谁有谁 implements）。
class BiliSource implements MusicSource {
  BiliSource({BiliClient? client}) : _client = client ?? BiliClient();

  final BiliClient _client;

  @override
  MusicPlatform get platform => MusicPlatform.bili;

  // ── 搜索 ──────────────────────────────────────────────────

  @override
  Future<SearchPageResult<Track>> searchSongs(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async {
    final result = await _client.searchVideos(keyword, page: page);
    return BiliMappers.mapSearchPage(result);
  }

  /// B 站无独立歌单搜索口；合集/收藏夹代偿属 B4 内容面，先返空态。
  @override
  Future<SearchPageResult<PlaylistBrief>> searchPlaylists(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async =>
      const SearchPageResult.empty();

  /// B 站无专辑概念（方案 §5.3 #2：合集 ≠ 专辑）。
  @override
  Future<SearchPageResult<AlbumBrief>> searchAlbums(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async =>
      const SearchPageResult.empty();

  /// `search_type=bili_user` 搜 UP 主一期不做（方案 §4.1）。
  @override
  Future<SearchPageResult<ArtistBrief>> searchArtists(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async =>
      const SearchPageResult.empty();

  // ── 播放 ──────────────────────────────────────────────────

  @override
  Future<PlayUrlResult> resolvePlayUrl(
    Track track, {
    AppQuality? preferred,
  }) async {
    final locator = await _locateCid(track.id);
    var info = await _playUrlWithRetry(
      bvid: locator.bvid,
      cid: locator.cid,
    );
    var pick = selectAudio(info, preferred);

    // DASH 音轨持续为空 → html5/mp4 渐进流兜底（整段音视频，
    // 播放端只解音轨即可；方案 §3.5）。
    if (pick == null && info.durlUrls.isEmpty) {
      info = await _client.playUrl(
        bvid: locator.bvid,
        cid: locator.cid,
        platform: 'html5',
      );
      pick = selectAudio(info, preferred);
    }
    if (pick == null || pick.track.baseUrl.isEmpty) {
      throw const NotFound('B 站：该视频无可用音轨');
    }

    return PlayUrlResult(
      url: pick.track.baseUrl,
      backupUrls: pick.track.backupUrls,
      // 防盗链头由 Source 下发，播放器不写死（方案 §3.4）。
      headers: _streamHeaders,
      grantedQuality: pick.quality,
      // B 站无「试听片段」概念（§5.3 #4）。
      isPreviewClip: false,
    );
  }

  @override
  Future<LyricPayload> fetchLyric(Track track) async => LyricPayload.empty;

  // ── 内部 ──────────────────────────────────────────────────

  static const _streamHeaders = {
    'Referer': BiliEndpoints.referer,
    'User-Agent': BiliEndpoints.webUA,
  };

  /// Track.id → (bvid, cid)。**两种形态都认**（方案 §5.3 #5）：
  /// - `bvid:cid`（内容态，B4 列表口产出）→ 直接用；
  /// - 裸 `bvid`（搜索态）→ `pagelist` 取 P1 的 cid（每次播放多 1 次请求）。
  Future<({String bvid, int cid})> _locateCid(String id) async {
    final sep = id.indexOf(':');
    if (sep > 0) {
      final cid = int.tryParse(id.substring(sep + 1));
      if (cid != null && cid > 0) {
        return (bvid: id.substring(0, sep), cid: cid);
      }
    }
    final bvid = sep > 0 ? id.substring(0, sep) : id;
    if (bvid.isEmpty) {
      throw const NotFound('B 站：曲目 id 为空');
    }
    final pages = await _client.pages(bvid);
    if (pages.isEmpty) {
      throw NotFound('B 站：$bvid 无分 P');
    }
    return (bvid: bvid, cid: pages.first.cid);
  }

  /// DASH 空音轨重试一次（对齐 NeriPlayer「DASH 音频重试」）。
  Future<BiliPlayInfo> _playUrlWithRetry({
    required String bvid,
    required int cid,
  }) async {
    var info = await _client.playUrl(bvid: bvid, cid: cid);
    if (_hasAnyAudio(info)) return info;
    info = await _client.playUrl(bvid: bvid, cid: cid);
    return info;
  }

  static bool _hasAnyAudio(BiliPlayInfo info) =>
      info.audio.isNotEmpty ||
      info.dolby.isNotEmpty ||
      info.flac.isNotEmpty;

  // ── 选轨（纯函数，单测覆盖）────────────────────────────────

  /// 带宽 → 抽象档。**按带宽判、禁硬编码 audio id**（方案 §3.5 / §8.1）：
  /// 实测 30216≈64k / 30232≈80~115k / 30280≈177~216k，同一 id 带宽还随
  /// 视频变，只能按带宽分档。
  static AppQuality qualityOfBandwidth(int bandwidth) {
    if (bandwidth >= 150000) return AppQuality.sq;
    if (bandwidth >= 70000) return AppQuality.hq;
    return AppQuality.standard;
  }

  /// 一次选轨结果。[quality] 为实际档位（mp4 兜底时未知 = null）。
  static BiliAudioPick? selectAudio(BiliPlayInfo info, AppQuality? preferred) {
    final candidates = <BiliAudioPick>[
      for (final t in info.flac)
        BiliAudioPick(track: t, quality: AppQuality.hiRes, group: 'flac'),
      for (final t in info.dolby)
        BiliAudioPick(track: t, quality: AppQuality.sq, group: 'dolby'),
      for (final t in info.audio)
        BiliAudioPick(
            track: t, quality: qualityOfBandwidth(t.bandwidth), group: 'audio'),
    ];

    if (candidates.isNotEmpty) {
      // 偏好档从高到低找（hiRes 未指定时默认从最高往下走）。
      for (final q in (preferred ?? AppQuality.hiRes).candidatesDownward) {
        final matches = candidates.where((c) => c.quality == q).toList()
          ..sort(_comparePick);
        if (matches.isNotEmpty) return matches.first;
      }
      // 有轨但偏好档全部落空（如偏好 standard 而该视频最低只有 115k）
      // → 取**最低可用档**。这不是「无音轨」，绝不走 mp4 兜底。
      return candidates.reduce((a, b) {
        final byTier = a.quality!.index.compareTo(b.quality!.index);
        if (byTier != 0) return byTier < 0 ? a : b;
        return a.track.bandwidth <= b.track.bandwidth ? a : b;
      });
    }

    // DASH 全空 → durl（MP4 整段）兜底；码率未知，grantedQuality 留空。
    if (info.durlUrls.isNotEmpty) {
      return BiliAudioPick(
        track: BiliAudioTrack(
          id: 0,
          qualityTag: null,
          bandwidth: 0,
          mimeType: 'video/mp4',
          codecs: '',
          baseUrl: info.durlUrls.first,
          backupUrls: info.durlUrls.skip(1).toList(),
        ),
        quality: null,
        group: 'durl',
      );
    }
    return null;
  }

  /// 同档内排序：特殊组（flac > dolby）优先于普通 audio（方案 §3.5 把
  /// sq 映射到 dolby，不能因为普通轨带宽数字大就把 dolby 挤掉），
  /// 同组内带宽高的优先。
  static int _comparePick(BiliAudioPick a, BiliAudioPick b) {
    final byGroup = _groupRank(b.group).compareTo(_groupRank(a.group));
    if (byGroup != 0) return byGroup;
    return b.track.bandwidth.compareTo(a.track.bandwidth);
  }

  static int _groupRank(String group) => switch (group) {
        'flac' => 2,
        'dolby' => 1,
        _ => 0,
      };
}

/// [BiliSource.selectAudio] 的选出项。
class BiliAudioPick {
  const BiliAudioPick({
    required this.track,
    required this.quality,
    this.group = 'audio',
  });

  final BiliAudioTrack track;

  /// 实际下发档；null = 未知（仅 mp4 兜底）。
  final AppQuality? quality;

  /// 来源组：`flac` / `dolby` / `audio` / `durl`。
  final String group;
}
