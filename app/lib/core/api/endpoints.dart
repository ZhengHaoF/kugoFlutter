/// Kugou public mobile endpoints used for research/learning client.
/// These endpoints can change without notice; keep isolated here.
///
/// Network note (2026-09): this LAN blocks HTTPS to kugou and most
/// play/stream hosts, but HTTP `mobilecdn` search + `lyrics` work.
abstract final class KugoEndpoints {
  static const mobileCdn = 'http://mobilecdn.kugou.com';
  static const wwwApi = 'http://wwwapi.kugou.com';
  static const tracker = 'http://trackercdn.kugou.com';
  static const lyrics = 'http://lyrics.kugou.com';

  /// Search songs (no auth).
  static const searchSong = '/api/v3/search/song';
  static const searchHot = '/api/v3/search/hot';
  static const searchSuggest = '/api/v3/search/suggest';
  static const searchLyric = '/api/v3/search/lyric';

  /// Multi-type search. These are distinct endpoints — `showtype` on
  /// [searchSong] is a spelling-correction toggle, not a type switch.
  static const searchSpecial = '/api/v3/search/special';
  static const searchAlbum = '/api/v3/search/album';
  static const searchSinger = '/api/v3/search/singer';
  static const searchMv = '/api/v3/search/mv';

  // ── MV / 视频（见 docs/api-notes.md「MV / 视频」节 + tool/probe_mv.dart） ──

  /// MV 富搜索（gateway complexsearch，字段比 [searchMv] 全）。
  /// GET gateway + `x-router: complexsearch.kugou.com`。
  static const searchMvRich = '/v1/search/mv';
  static const complexSearchRouter = 'complexsearch.kugou.com';

  /// 歌曲关联 MV。POST gateway + `x-router: openapi.kugou.com` + `kg-tid: 38`。
  /// body `{data:[{album_audio_id: MixSongID}], fields}` —— **id 必须是 MixSongID**。
  static const kmrAudioMv = '/kmr/v1/audio/mv';
  static const openApiRouter = 'openapi.kugou.com';

  /// MV 详情。POST gateway + `x-router: kmr.service.kugou.com`；鉴权在 body。
  static const videoDetail = '/v1/video';
  static const kmrServiceRouter = 'kmr.service.kugou.com';

  /// MV 特权/清晰度。POST gateway + `x-router: media.store.kugou.com`。
  static const videoPrivilege = '/v1/get_video_privilege';
  static const mediaStoreRouter = 'media.store.kugou.com';

  /// **MV 播放地址**。GET gateway + `x-router: trackermv.kugou.com`；
  /// `key=signKey(hash,mid)` + android signature。响应 `data[hash].downurl`。
  static const videoUrl = '/v2/interface/index';
  static const trackerMvRouter = 'trackermv.kugou.com';

  /// 歌手 MV 列表。GET `openapicdn.kugou.com/kmr/v1/author/videos`。
  static const openApiCdn = 'https://openapicdn.kugou.com';
  static const artistVideos = '/kmr/v1/author/videos';

  /// MV 收藏（KuGouMusicApi `mv_collect.js` / `mv_collect_del.js` /
  /// `user_video_collect.js`）。ctype=2；obj_id = **video_id**（数字）。
  static const collectService = 'https://collectservice.kugou.com';
  static const mvCollect = '/v1/collect';
  static const mvCollectDel = '/v1/cancel_collect';

  /// 已收藏 MV 列表。POST gateway + path（encryptType=android）。
  static const userVideoCollect = '/collectservice/v2/collect_list_mixvideo';

  /// Playlist info + tracks (no auth, public lists).
  ///
  /// Network note (2026-09): `playlist/info` and `playlist/songs` return
  /// `Access Deny ! No Actions !` on every host reachable from here
  /// (mobilecdn / mobiles / wwwapi / trackercdn / msearchcdn). The `special`
  /// family serves the same data and is reachable, so use that instead.
  static const playlistInfo = '/api/v3/special/info';
  static const playlistSongs = '/api/v3/special/song';
  static const playlistSquare = '/api/v3/playlist/square';

  /// Album / singer (public mobile CDN).
  ///
  /// Network note (2026-09): the plural `album/songs` is Access-Denied from
  /// this network; the singular `album/song` works and returns the same shape.
  static const albumInfo = '/api/v3/album/info';
  static const albumSongs = '/api/v3/album/song';
  static const singerInfo = '/api/v3/singer/info';
  static const singerSong = '/api/v3/singer/song';

  /// Rank / recommend (best-effort public).
  /// Rank tracks legacy public slice: `rank/song?rankid=` — NOT `specialid`.
  /// Often returns only a few rows for large boards; prefer [rankAudio].
  static const rankList = '/api/v3/rank/list';
  static const rankInfo = '/api/v3/rank/info';
  static const rankSong = '/api/v3/rank/song';

  /// Full rank tracks (KuGouMusicApi `module/rank_audio.js`, EchoMusic `/rank/audio`).
  /// POST `https://gateway.kugou.com/openapi/kmr/v2/rank/audio`
  /// body `{rank_id, rank_cid, page, pagesize, type:1, area_code:1, ...}`
  /// encryptType=android + header `kg-tid: 369` → `data.songlist[]` + `data.total`.
  static const rankAudio = '/openapi/kmr/v2/rank/audio';

  /// Personalized daily recommend (KuGouMusicApi everyday_recommend.js).
  /// POST gateway + header `x-router: everydayrec.service.kugou.com`.
  static const gateway = 'https://gateway.kugou.com';
  static const everydayRecommend = '/everyday_song_recommend';
  static const everydayRouter = 'everydayrec.service.kugou.com';

  /// Style recommend songs (KuGouMusicApi everyday_style_recommend.js).
  ///
  /// Upstream uses the **service-prefixed path on gateway**, no x-router:
  /// POST `https://gateway.kugou.com/everydayrec.service/everyday_style_recommend`
  /// body `{}` (signature data = `'{}'`), query `tagids`.
  static const everydayStyleRecommendPrefixed =
      '/everydayrec.service/everyday_style_recommend';

  /// Category playlists (KuGouMusicApi top_playlist.js → specialrec).
  static const specialRecommend = '/v2/special_recommend';
  static const specialRecommendRouter = 'specialrec.service.kugou.com';

  /// Editorial picks (KuGouMusicApi top_ip.js).
  static const musicAdService = 'http://musicadservice.kugou.com';
  static const topIp = '/v1/daily_recommend';

  /// Discovery tabs (KuGouMusicApi top_song / top_album / artist_lists / playlist_tags).
  ///
  /// New songs / new albums live on musicadservice (same host as [topIp]).
  /// Artist list + playlist tags go through the signed gateway.
  static const newSongPublish = '/container/v1/newsong_publish';
  static const mobileNewAlbum = '/v1/mobile_newalbum_sp';
  static const singerList = '/ocean/v6/singer/list';
  static const playlistTags = '/pubsongs/v1/get_tags_by_type';

  /// Real personal FM (KuGouMusicApi personal_fm.js → upstream).
  static const personalRecommend = '/v2/personal_recommend';
  static const personalFmRouter = 'persnfm.service.kugou.com';

  /// Song play data (wwwapi).
  static const playData = '/yy/index.php';

  /// Tracker play url fallback.
  static const trackerPlay = '/i/v2/';

  /// Lyric search/download.
  static const lyricSearch = '/search';
  static const lyricDownload = '/download';

  /// Account profile (KuGouMusicApi user_info / user_detail / user_vip_detail /
  /// user_grade_info → EchoMusic `/user/detail` `/user/vip/detail` `/user/grade/info`).
  static const userInfoRelation = 'http://relation.user.kugou.com';
  static const getMyUserInfo = '/v1/get_my_userinfo';
  static const getMyInfo = '/v3/get_my_info';
  static const usercenterRouter = 'usercenter.kugou.com';
  static const kugouVip = 'https://kugouvip.kugou.com';
  static const getUnionVip = '/v1/get_union_vip';
  static const userInfoService = 'http://userinfo.user.kugou.com';
  static const getGradeInfo = '/v2/get_grade_info';

  // ── 音乐云盘（KuGouMusicApi `user_cloud*.js`，见 docs/api-notes.md） ──

  /// 云盘业务宿主（列表 / 删除 / 写入；AES+RSA 信封）。
  static const mcloudService = 'https://mcloudservice.kugou.com';

  /// 云盘列表。POST + AES body + RSA `p`。
  static const cloudGetList = '/v1/get_list';

  /// 云盘删除。POST + AES body + RSA `p`。
  static const cloudDelFiles = '/v1/del_files';

  /// 云盘写入（上传最后一步）。POST + AES body + RSA `p`。
  static const cloudAddFiles = '/v1/add_files';

  /// 云盘播放地址。GET gateway + android signature。
  static const cloudMusicUrl = '/bsstrackercdngz/v2/query_musicclound_url';

  /// 云盘资源 pid（播放地址固定值）。
  static const cloudPid = 20026;

  /// 云盘上传授权。GET gateway + android signature。
  static const cloudUploadAuth = '/bsstrackercdngz/v1/upload/auth';

  /// 分片上传初始化 / 上传 / 完成（host 见 `bssulbig` / `external_host`）。
  static const bssulbig = 'http://bssulbig.kugou.com';
  static const cloudMultipartInit = '/v2/multipart/initiate/music';
  static const cloudMultipartUpload = '/v3/multipart/upload';
  static const cloudMultipartComplete = '/v3/multipart/complete';

  /// 曲库按 hash 匹配（上传前关联 audio_id / album_audio_id）。
  static const kmrService = 'http://kmr.service.kugou.com';
  static const albumAudioLookup = '/v2/album_audio/audio';

  /// 云盘 bucket 名。
  static const cloudBucket = 'musicclound';
}
