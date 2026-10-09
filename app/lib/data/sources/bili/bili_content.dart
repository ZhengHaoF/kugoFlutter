import '../../../core/api/bili/bili_client.dart';
import '../../../core/models/catalog_models.dart';
import '../../../core/models/search_result.dart';
import '../../../core/models/track.dart';
import '../../../core/source/capabilities.dart';
import '../../../core/source/music_platform.dart';
import '../../../core/source/music_source.dart';

/// B 站内容 ID 显式携带类型；season/series 必须包含 UP 主 mid。
/// `fav:<id>` / `season:<mid>:<id>` / `series:<mid>:<id>` / `video:<bvid>`。
class BiliContent {
  BiliContent(this.client);
  final BiliClient client;

  static int number(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  static String text(Object? value) => value is String ? value : '';
  static String cover(Object? value) {
    final url = text(value);
    return url.startsWith('//') ? 'https:$url' : url;
  }

  static List<Map<String, dynamic>> rows(Object? value) =>
      value is List ? value.whereType<Map<String, dynamic>>().toList() : [];

  static Track? track(Map<String, dynamic> row, {String mid = ''}) {
    final bvid = text(row['bvid'] ?? row['bv_id']);
    if (bvid.isEmpty || number(row['attr']) & 9 == 9) return null;
    final owner = row['owner'] ?? row['upper'];
    final info = owner is Map ? owner : const {};
    final cid = number(row['cid']);
    final rawDuration = row['duration'] ?? row['length'];
    final duration = rawDuration is String && rawDuration.contains(':')
        ? biliParseDurationSeconds(rawDuration)
        : number(rawDuration);
    return Track(
      platform: MusicPlatform.bili,
      id: cid > 0 ? '$bvid:$cid' : bvid,
      name: biliStripHtml(text(row['title'])),
      artist: text(info['name']).isNotEmpty
          ? text(info['name'])
          : text(row['author']),
      artistId: number(info['mid']) > 0 ? '${info['mid']}' : mid,
      coverUrl: cover(row['pic'] ?? row['cover']),
      durationMs: duration * 1000,
      album: '',
      quality: '',
    );
  }

  static PlaylistBrief folder(
    Map<String, dynamic> row, {
    bool collected = false,
  }) {
    final upper = row['upper'];
    final mid = number(row['mid']) > 0
        ? number(row['mid'])
        : upper is Map
        ? number(upper['mid'])
        : 0;
    final seasonId = number(row['season_id']);
    final id = number(row['id']) > 0 ? number(row['id']) : seasonId;
    return PlaylistBrief(
      platform: MusicPlatform.bili,
      id: collected && (number(row['type']) == 21 || seasonId > 0)
          ? 'season:$mid:$id'
          : 'fav:$id',
      name: text(row['title']),
      coverUrl: cover(row['cover']),
      description: text(row['intro']),
      creator: upper is Map ? text(upper['name']) : '',
      trackCount: number(row['media_count']),
      type: collected ? 1 : 0,
    );
  }

  Future<UserPlaylistsPage> folders(
    String mid, {
    int offset = 0,
    int limit = 20,
  }) async {
    // 自建口一次返回全量，收藏口分页；offset 在源内部转换成页码。
    final size = limit.clamp(1, 20);
    final created = await client.content('/x/v3/fav/folder/created/list-all', {
      'up_mid': mid,
    });
    final own = rows(created['list']).map(folder).toList();
    if (offset == 0 && number(created['count']) > own.length) {
      final seen = own.map((p) => p.id).toSet();
      for (var pn = 1; own.length < number(created['count']); pn++) {
        final data = await client.content('/x/v3/fav/folder/created/list', {
          'up_mid': mid,
          'pn': '$pn',
          'ps': '20',
          'web_location': '333.1387',
        });
        final fresh = rows(
          data['list'],
        ).map(folder).where((p) => seen.add(p.id)).toList();
        if (fresh.isEmpty || pn >= 1000) {
          throw const UpstreamChanged('自建收藏夹列表不完整，请重试');
        }
        own.addAll(fresh);
      }
    }
    final collected = await client.content('/x/v3/fav/folder/collected/list', {
      'up_mid': mid,
      'pn': '${offset ~/ size + 1}',
      'ps': '$size',
      'platform': 'web',
    });
    return UserPlaylistsPage(
      created: offset == 0 ? own : [],
      collected: rows(collected['list'])
          .where((r) => number(r['id'] ?? r['season_id']) > 0)
          .map((r) => folder(r, collected: true))
          .toList(),
      more:
          collected['has_more'] == true ||
          rows(collected['list']).isNotEmpty &&
              offset + rows(collected['list']).length <
                  number(collected['count']),
    );
  }

  Future<({PlaylistBrief brief, List<Track> tracks})> detail(
    String id, {
    PlaylistBrief? hint,
  }) async {
    final parts = id.split(':');
    if (parts.length == 2 && parts.first == 'video' && parts.last.isNotEmpty) {
      final info = await client.videoBasicInfo(parts.last);
      final base = track({...info, 'bvid': parts.last});
      if (base == null) throw const NotFound('视频不存在');
      final pages = await client.pages(parts.last);
      return (
        brief: PlaylistBrief(
          id: id,
          platform: MusicPlatform.bili,
          name: base.name,
          coverUrl: base.coverUrl,
          creator: base.artist,
          trackCount: pages.length,
        ),
        tracks: [
          for (final p in pages)
            base.copyWith(
              id: '${parts.last}:${p.cid}',
              name: p.part,
              durationMs: p.durationSec * 1000,
            ),
        ],
      );
    }
    final kind = parts.first;
    final valid = kind == 'fav'
        ? parts.length == 2 && number(parts.last) > 0
        : (kind == 'season' || kind == 'series') &&
              parts.length == 3 &&
              number(parts[1]) > 0 &&
              number(parts[2]) > 0;
    if (!valid) throw const NotFound('无效的 B 站内容 ID');
    final tracks = <Track>[];
    PlaylistBrief? brief = hint;
    final seen = <String>{};
    for (var page = 1; ; page++) {
      final data = await client.content(
        switch (kind) {
          'fav' => '/x/v3/fav/resource/list',
          'season' => '/x/polymer/web-space/seasons_archives_list',
          _ => '/x/series/archives',
        },
        {
          if (kind == 'fav') 'media_id': parts.last,
          if (kind != 'fav') 'mid': parts[1],
          if (kind == 'season') 'season_id': parts.last,
          if (kind == 'series') 'series_id': parts.last,
          if (kind == 'season') ...{
            'page_num': '$page',
            'page_size': '30',
          } else ...{
            'pn': '$page',
            'ps': '30',
          },
          if (kind == 'fav') ...{
            'order': 'mtime',
            'type': '0',
            'tid': '0',
            'platform': 'web',
          },
          if (kind == 'season') ...{
            'sort_reverse': 'false',
            'web_location': '333.999',
          },
          if (kind == 'series') ...{'only_normal': 'true', 'sort': 'desc'},
        },
        signed: kind == 'season',
      );
      final info = data['info'] ?? data['meta'];
      if (page == 1 && info is Map<String, dynamic>) {
        final previous = brief;
        brief = PlaylistBrief(
          id: id,
          platform: MusicPlatform.bili,
          name: text(info['title'] ?? info['name']),
          coverUrl: cover(info['cover']),
          description: text(info['intro'] ?? info['description']),
          trackCount: number(info['media_count'] ?? info['total']),
          creator: info['upper'] is Map
              ? text((info['upper'] as Map)['name'])
              : previous?.creator ?? '',
          type: previous?.type ?? 0,
        );
      }
      final items = rows(data[kind == 'fav' ? 'medias' : 'archives']);
      var added = 0;
      for (final item in items) {
        final t = track(item, mid: kind == 'fav' ? '' : parts[1]);
        if (t != null && seen.add(t.identityKey)) {
          tracks.add(t);
          added++;
        }
      }
      final pagination = data['page'];
      final total = pagination is Map ? number(pagination['total']) : 0;
      final more = kind == 'fav'
          ? data['has_more'] == true
          : total > 0
          ? page * 30 < total
          : items.length == 30;
      if (!more || items.isEmpty) break;
      if (added == 0 || page >= 1000) {
        throw const UpstreamChanged('B 站列表分页异常，未返回完整内容');
      }
    }
    // series 的档案接口不带元数据，单独取标题，不能伪装成专辑。
    if (brief == null && kind == 'series') {
      final meta = await client.content('/x/series/series', {
        'series_id': parts.last,
      });
      final info = meta['meta'];
      if (info is Map) {
        brief = PlaylistBrief(
          id: id,
          platform: MusicPlatform.bili,
          name: text(info['name']),
          coverUrl: cover(info['cover']),
          description: text(info['description']),
          trackCount: tracks.length,
        );
      }
    }
    return (
      brief:
          brief ??
          PlaylistBrief(
            id: id,
            platform: MusicPlatform.bili,
            name: 'B 站内容',
            coverUrl: '',
            trackCount: tracks.length,
          ),
      tracks: tracks,
    );
  }

  Future<ArtistDetail> artist(String mid) async {
    if (number(mid) <= 0) throw const NotFound('无效的 UP 主 ID');
    final data = await client.content('/x/space/wbi/acc/info', {
      'mid': mid,
      'platform': 'web',
      'web_location': '1550101',
    }, signed: true);
    return ArtistDetail(
      id: mid,
      name: text(data['name']),
      avatarUrl: cover(data['face']),
      intro: text(data['sign']),
    );
  }

  Future<SearchPageResult<PlaylistBrief>> contents(
    String mid, {
    int page = 1,
  }) async {
    if (number(mid) <= 0) throw const NotFound('无效的 UP 主 ID');
    final data = await client.content(
      '/x/polymer/web-space/seasons_series_list',
      {
        'mid': mid,
        'page_num': '$page',
        'page_size': '20',
        'web_location': '333.999',
      },
      signed: true,
    );
    final lists = data['items_lists'];
    final items = <PlaylistBrief>[];
    if (lists is Map) {
      for (final kind in ['season', 'series']) {
        for (final entry in rows(
          lists[kind == 'season' ? 'seasons_list' : 'series_list'],
        )) {
          final raw = entry['meta'];
          if (raw is! Map) continue;
          final id = number(raw['${kind}_id']);
          if (id <= 0) continue;
          items.add(
            PlaylistBrief(
              platform: MusicPlatform.bili,
              id: '$kind:$mid:$id',
              name: text(raw['name']),
              coverUrl: cover(raw['cover']),
              description: text(raw['description']),
              trackCount: number(raw['total']),
            ),
          );
        }
      }
    }
    final pagination = lists is Map ? lists['page'] : null;
    return SearchPageResult(
      items: items,
      total: pagination is Map ? number(pagination['total']) : null,
    );
  }

  Future<ArtistSongsPage> videos(
    String mid, {
    int page = 1,
    int pageSize = 30,
    ArtistSongSort sort = ArtistSongSort.hot,
  }) async {
    if (number(mid) <= 0) throw const NotFound('无效的 UP 主 ID');
    final size = pageSize.clamp(1, 50);
    final data = await client.content('/x/space/wbi/arc/search', {
      'mid': mid,
      'pn': '$page',
      'ps': '$size',
      'order': sort == ArtistSongSort.hot ? 'click' : 'pubdate',
    }, signed: true);
    final list = data['list'];
    final pagination = data['page'];
    final total = pagination is Map ? number(pagination['count']) : 0;
    final items = list is Map ? rows(list['vlist']) : <Map<String, dynamic>>[];
    return ArtistSongsPage(
      songs: [
        for (final r in items)
          if (track(r, mid: mid) case final Track t) t,
      ],
      total: total,
      hasMore: page * size < total,
    );
  }
}
