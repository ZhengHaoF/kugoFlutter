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
}
