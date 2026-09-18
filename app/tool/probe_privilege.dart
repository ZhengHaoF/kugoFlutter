import 'package:dio/dio.dart';

Future<void> probe(Dio dio, String name, String url,
    [Map<String, dynamic>? q]) async {
  try {
    final r = await dio.get<dynamic>(url, queryParameters: q);
    final s = r.data is String ? r.data as String : r.data.toString();
    print('[$name] ${r.statusCode} len=${s.length}');
    print(s.substring(0, s.length.clamp(0, 800)));
  } catch (e) {
    print('[$name] ERR ${e.toString().split('\n').first}');
  }
  print('---');
}

Future<void> main() async {
  final dio = Dio(
    BaseOptions(
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120',
        'Referer': 'http://www.kugou.com/',
      },
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      responseType: ResponseType.plain,
      validateStatus: (c) => c != null && c > 0,
    ),
  );

  const hash = 'b3a52a7a958bf0aed0ebfba2e9a818b7';
  const albumId = '966846';

  await probe(dio, 'privilege-lite-gw', 'https://gateway.kugou.com/privilege/lite', {
    'hash': hash,
    'album_id': albumId,
  });
  await probe(dio, 'privilege-v2', 'https://gateway.kugou.com/v2/privilege/lite', {
    'hash': hash,
    'album_id': albumId,
  });
  await probe(dio, 'song-info', 'http://mobilecdn.kugou.com/api/v3/song/info', {
    'hash': hash,
    'album_id': albumId,
    'format': 'json',
  });
  await probe(dio, 'song-singer', 'http://mobilecdn.kugou.com/api/v3/song/singer', {
    'hash': hash,
    'format': 'json',
  });
  await probe(dio, 'priv-www', 'http://wwwapi.kugou.com/yy/index.php', {
    'r': 'privilege/lite',
    'hash': hash,
    'album_id': albumId,
  });
  await probe(dio, 'priv-open', 'https://openapi.kugou.com/vipmusic/privilege/v1/get_privilege', {
    'hash': hash,
  });
}
