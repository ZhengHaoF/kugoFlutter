import 'package:dio/dio.dart';

Future<void> main() async {
  final dio = Dio(
    BaseOptions(
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36',
        'Referer': 'http://www.kugou.com/',
      },
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      validateStatus: (_) => true,
    ),
  );

  const hash = 'b3a52a7a958bf0aed0ebfba2e9a818b7';

  Future<void> probe(String name, String url, [Map<String, dynamic>? q]) async {
    try {
      final r = await dio.get<dynamic>(url, queryParameters: q);
      final s = r.data is String ? r.data as String : r.data.toString();
      final filtered = s.contains('URL过滤') || s.contains('Access Deny');
      print('[$name] ${r.statusCode} filtered=$filtered len=${s.length}');
      print(s.substring(0, s.length.clamp(0, 320)));
    } catch (e) {
      print('[$name] ERR ${e.toString().split('\n').first}');
    }
    print('---');
  }

  await probe(
    'tracker',
    'http://trackercdn.kugou.com/i/v2/',
    {
      'cmd': 23,
      'pid': 1,
      'behavior': 'play',
      'hash': hash,
      'album_id': 0,
    },
  );
  await probe(
    'tracker2',
    'http://tracker.kugou.com/v2/',
    {
      'cmd': 23,
      'pid': 1,
      'behavior': 'download',
      'hash': hash,
    },
  );
  await probe(
    'openapi',
    'http://openapi.kugou.com/openapi/v1/get_song_url',
    {'hash': hash},
  );
  await probe(
    'm3ws',
    'http://m3ws.kugou.com/api/v1/song/get_song_info',
    {'cmd': 'playInfo', 'hash': hash},
  );
  await probe(
    'mobileservice',
    'http://mobileservice.kugou.com/getSongInfo',
    {'cmd': 'playInfo', 'hash': hash},
  );
  await probe(
    'complexobj',
    'http://complexobjdn.kugou.com',
    {'cmd': 26, 'hash': hash},
  );
  await probe(
    'wwwapi-http-path',
    'http://wwwapi.kugou.com/yy/index.php',
    {
      'r': 'play/getdata',
      'hash': hash,
      'album_id': '',
      'mid': 'mid',
      'platid': 4,
    },
  );
  // another known mobile play path
  await probe(
    'trackercdn-https',
    'https://trackercdn.kugou.com/i/v2/',
    {
      'cmd': 23,
      'pid': 1,
      'behavior': 'play',
      'hash': hash,
    },
  );
}
