import 'package:dio/dio.dart';

Future<void> main() async {
  final dio = Dio(
    BaseOptions(
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36',
        'Referer': 'http://www.kugou.com/',
      },
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
    ),
  );

  Future<void> probe(String name, String url, [Map<String, dynamic>? q]) async {
    try {
      final r = await dio.get<dynamic>(url, queryParameters: q);
      final s = r.data is String ? r.data as String : r.data.toString();
      final ok = s.contains('{') || s.contains('[');
      print('[$name] ${r.statusCode} json=$ok len=${s.length}');
      print(s.substring(0, s.length.clamp(0, 280)));
    } catch (e) {
      print('[$name] ERR ${e.toString().split('\n').first}');
    }
    print('---');
  }

  await probe(
    'http-search',
    'http://mobilecdn.kugou.com/api/v3/search/song',
    {
      'format': 'json',
      'keyword': '晴天',
      'page': 1,
      'pagesize': 2,
      'showtype': 1,
    },
  );
  await probe(
    'https-search',
    'https://mobilecdn.kugou.com/api/v3/search/song',
    {
      'format': 'json',
      'keyword': '晴天',
      'page': 1,
      'pagesize': 1,
      'showtype': 1,
    },
  );
  await probe(
    'http-play',
    'http://wwwapi.kugou.com/yy/index.php',
    {
      'r': 'play/getdata',
      'hash': 'b3a52a7a958bf0aed0ebfba2e9a818b7',
      'mid': 'kugo_mid',
      'guid': 'kugo_guid',
      'platid': 4,
      'appid': 1014,
    },
  );
  await probe(
    'http-lyric',
    'http://lyrics.kugou.com/search',
    {
      'ver': 1,
      'man': 'yes',
      'client': 'pc',
      'keyword': '周杰伦 晴天',
      'hash': 'b3a52a7a958bf0aed0ebfba2e9a818b7',
      'timelength': 269000,
    },
  );
  await probe(
    'http-playlist',
    'http://mobilecdn.kugou.com/api/v3/playlist/info',
    {'specialid': 262040, 'page': 1, 'pagesize': 5, 'format': 'json'},
  );
}
