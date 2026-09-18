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

  /// Playlist info + tracks (no auth, public lists).
  static const playlistInfo = '/api/v3/playlist/info';
  static const playlistSquare = '/api/v3/playlist/square';

  /// Album / singer (public mobile CDN).
  static const albumInfo = '/api/v3/album/info';
  static const albumSongs = '/api/v3/album/songs';
  static const singerInfo = '/api/v3/singer/info';
  static const singerSong = '/api/v3/singer/song';

  /// Rank / recommend (best-effort public).
  static const rankList = '/api/v3/rank/list';
  static const rankInfo = '/api/v3/rank/info';

  /// Personalized daily recommend (KuGouMusicApi everyday_recommend.js).
  /// POST gateway + header `x-router: everydayrec.service.kugou.com`.
  static const gateway = 'https://gateway.kugou.com';
  static const everydayRecommend = '/everyday_song_recommend';
  static const everydayRouter = 'everydayrec.service.kugou.com';

  /// Song play data (wwwapi).
  static const playData = '/yy/index.php';

  /// Tracker play url fallback.
  static const trackerPlay = '/i/v2/';

  /// Lyric search/download.
  static const lyricSearch = '/search';
  static const lyricDownload = '/download';
}
