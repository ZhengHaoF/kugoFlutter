import 'package:dio/dio.dart';

Future<void> main() async {
  final dio = Dio(
    BaseOptions(
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120',
        'Referer': 'http://www.kugou.com/',
      },
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
      responseType: ResponseType.plain,
    ),
  );

  final r = await dio.get<dynamic>(
    'http://mobilecdn.kugou.com/api/v3/search/song',
    queryParameters: {
      'format': 'json',
      'keyword': '晴天',
      'page': 1,
      'pagesize': 2,
      'showtype': 1,
    },
  );
  final s = r.data is String ? r.data as String : r.data.toString();
  print('len=${s.length}');
  print(s.substring(0, s.length.clamp(0, 4000)));
  print('---KEYS---');
  final keys = <String>{};
  final re = RegExp(r'"([A-Za-z0-9_]+)"\s*:');
  for (final m in re.allMatches(s)) {
    keys.add(m.group(1)!);
  }
  final sorted = keys.toList()..sort();
  print(sorted.join(', '));
}
