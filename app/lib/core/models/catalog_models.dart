import 'track.dart';

/// 专辑详情（酷狗 `album/info` / 网易 `v1/album/{id}` 通用展示模型）。
class AlbumDetail {
  const AlbumDetail({
    required this.id,
    required this.name,
    required this.coverUrl,
    this.artist = '',
    this.publishTime = '',
    this.intro = '',
    this.songs = const [],
  });

  final String id;
  final String name;
  final String coverUrl;
  final String artist;
  final String publishTime;
  final String intro;
  final List<Track> songs;
}

/// 歌曲排序：接口侧 `sort=hot|new`（网易侧映射 `order=hot|new`）。
enum ArtistSongSort {
  hot('hot', '热门'),
  newest('new', '最新');

  const ArtistSongSort(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

/// 歌手详情头部（酷狗 `singer/info` / 网易 `artist/head/info/get`）。
class ArtistDetail {
  const ArtistDetail({
    required this.id,
    required this.name,
    required this.avatarUrl,
    this.intro = '',
    this.fansLabel = '',
    this.birthday = '',
    this.songCount = 0,
    this.albumCount = 0,
    this.mvCount = 0,
    this.songs = const [],
  });

  final String id;
  final String name;
  final String avatarUrl;
  final String intro;
  final String fansLabel;
  final String birthday;
  final int songCount;
  final int albumCount;
  final int mvCount;
  final List<Track> songs;
}

/// 歌单分类标签**组**（探索发现「歌单」Tab）。
///
/// 各源层级不同：酷狗 `playlist/tags` 是二级 group（`tag_name` + `son[]`），
/// 网易只有一级扁平标签 —— 统一收口为「组 → 子标签」，网易侧拍成单组，
/// UI 只渲染同一行 chips。
class PlaylistTagGroup {
  const PlaylistTagGroup({required this.name, required this.child});

  final String name;
  final List<PlaylistTag> child;
}

/// 单个分类标签。
///
/// [id] 是**该源分类接口要传的值**（酷狗 `categoryid` / 网易 `cat` 标签名），
/// UI 不解读、原样回传给 `categoryPlaylists`。
class PlaylistTag {
  const PlaylistTag({required this.id, required this.name, this.group = ''});

  final String id;
  final String name;

  /// 所属组名（酷狗分组回填；网易扁平无组时为空）。
  final String group;
}

/// 歌手歌曲分页结果。
class ArtistSongsPage {
  const ArtistSongsPage({
    this.songs = const [],
    this.total = 0,
    this.hasMore = false,
  });

  final List<Track> songs;
  final int total;
  final bool hasMore;
}
