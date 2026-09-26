/// 网易云端点与请求常量（对齐 NeriPlayer `NeteaseClient`）。
abstract final class NeteaseEndpoints {
  static const mainHost = 'https://music.163.com';
  static const interfaceHost = 'https://interface.music.163.com';
  static const interface3Host = 'https://interface3.music.163.com';

  /// 一期：搜索/播放/歌词/单曲详情
  ///
  /// 注意：`cloudsearch/get/web` 实测可能回 `50000005`；**可用**旧口
  /// `/weapi/search/get`。
  static const search = '/weapi/search/get';
  static const searchCloud = '/weapi/cloudsearch/get/web';
  static const songPlayUrlV1 = '/eapi/song/enhance/player/url/v1';
  static const songPlayUrlWeapi = '/weapi/song/enhance/player/url';
  static const songLyricV1 = '/eapi/song/lyric/v1';
  static const songLyricPlain = '/api/song/lyric';
  static const songDetail = '/weapi/v3/song/detail';

  /// 登录 / 账号
  static const account = '/weapi/w/nuser/account/get';
  static const qrUnikey = '/weapi/login/qrcode/unikey';
  static const qrCheck = '/weapi/login/qrcode/client/login';
  static const loginCellphone = '/w/login/cellphone';
  static const smsSend = '/weapi/sms/captcha/sent';
  static const smsVerify = '/weapi/sms/captcha/verify';

  /// 我喜欢 / 用户歌单
  static const userPlaylist = '/weapi/user/playlist';
  static const songLikeGet = '/weapi/song/like/get';
  static const songLike = '/song/like';
  static const playlistManipulateTracks = '/playlist/manipulate/tracks';
  static const userAlbums = '/eapi/mine/rn/resource/list';

  /// 详情（歌单 / 专辑 / 歌人）
  static const playlistDetail = '/api/v6/playlist/detail';
  static const albumDetail = '/weapi/v1/album/';
  static const artistHeadInfo = '/api/artist/head/info/get';
  static const artistDynamic = '/api/artist/detail/dynamic';
  static const artistSongs = '/api/v1/artist/songs';
  static const artistAlbums = '/api/artist/albums/';

  /// 推荐 / 发现（G 组）
  static const personalizedPlaylist = '/weapi/personalized/playlist';
  static const dailyRecommendResource = '/v1/discovery/recommend/resource';
  static const dailyRecommendSongs = '/v3/discovery/recommend/songs';
  static const personalFm = '/v1/radio/get';
  static const personalizedNewSong = '/personalized/newsong';
  static const topPlaylists = '/playlist/list';
  static const highQualityList = '/playlist/highquality/list';
  static const highQualityTags = '/api/playlist/highquality/tags';
  static const radarPlaylistMeta = '/api/playlist/detail';

  /// G11 榜单列表：全部官方榜的**元数据**（id / name / coverImgUrl /
  /// trackCount / updateFrequency），与 G10 的「按 id 取曲目」互补。
  /// 免登录 PLAIN API，形态与 `playlistDetail` 同族。
  static const toplistDetail = '/api/toplist/detail';

  /// G12 新碟上架：`area`（ALL / ZH / EA / KR / JP）+ `limit` / `offset` / `total`。
  ///
  /// 2026-09-26 实测**明文即通**（5 区全 `code=200`、`total=500`、`area` 真生效）——
  /// 参考实现（NeteaseCloudMusicApi `module/album_new.js`）用 weapi，但网易这口双认，
  /// 故留明文以免每次预热。
  static const albumNew = '/api/album/new';

  /// G13 歌手列表：`type`（-1 全部 / 1 男 / 2 女 / 3 乐队）+ `area`
  /// （-1 全部 / 7 华语 / 96 欧美 / 8 日本 / 16 韩国 / 0 其他）+ `initial`
  /// + `limit` / `offset` / `total`。
  ///
  /// **路径必须带 `v1`**（2026-09-26 实测）：`/api/artist/list`（无 `v1`）是**旧路由**，
  /// 只认 `limit`，`type`/`area`/`initial` 全被忽略（换参数响应逐字节相同）；
  /// 参照 NeteaseCloudMusicApi `module/artist_list.js` 打 `/api/v1/artist/list`。
  /// 另注意 `initial` 需转**大写 ASCII 码**（`a` → `65`），见 `NeteaseClient._artistInitialCode`。
  static const artistList = '/api/v1/artist/list';

  static String weapiUrl(String path, {String host = mainHost}) {
    final p = path.startsWith('/') ? path : '/$path';
    return '$host/weapi$p'.replaceFirst('/weapi/weapi', '/weapi');
  }

  static String eapiUrl(String path, {String host = interfaceHost}) {
    final p = path.startsWith('/') ? path : '/$path';
    if (p.startsWith('/eapi')) return '$host$p';
    return '$host/eapi$p';
  }

  static String plainUrl(String path, {String host = mainHost}) {
    final p = path.startsWith('/') ? path : '/$path';
    return '$host$p';
  }
}
