/// 网易云端点与请求常量（对齐 NeriPlayer `NeteaseClient`）。
abstract final class NeteaseEndpoints {
  static const mainHost = 'https://music.163.com';
  static const interfaceHost = 'https://interface.music.163.com';

  /// 一期业务口路径。
  ///
  /// 注意：`cloudsearch/get/web` 实测可能回 `50000005`；**可用**旧口
  /// `/weapi/search/get`（与 Neri 同源 weapi，参数更简单）。
  static const search = '/weapi/search/get';
  static const searchCloud = '/weapi/cloudsearch/get/web';
  static const songPlayUrlV1 = '/eapi/song/enhance/player/url/v1';
  static const songPlayUrlWeapi = '/weapi/song/enhance/player/url';
  static const songLyricV1 = '/eapi/song/lyric/v1';
  static const songLyricPlain = '/api/song/lyric';
  static const songDetail = '/weapi/v3/song/detail';

  static String weapiUrl(String path) {
    final p = path.startsWith('/') ? path : '/$path';
    return '$mainHost/weapi$p'.replaceFirst('/weapi/weapi', '/weapi');
  }

  static String eapiUrl(String path) {
    final p = path.startsWith('/') ? path : '/$path';
    if (p.startsWith('/eapi')) return '$interfaceHost$p';
    return '$interfaceHost/eapi$p';
  }

  static String plainUrl(String path) {
    final p = path.startsWith('/') ? path : '/$path';
    return '$mainHost$p';
  }
}
