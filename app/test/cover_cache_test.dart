import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/cache/cover_cache.dart';

import 'fakes/fake_kugo_client.dart';
import 'fakes/fake_path_provider.dart';

/// 封面缓存：防盗链 Referer 按 CDN 域名下发 + 内存/磁盘/网络三级。
///
/// `headersFor` 踩过坑：网易系画布要 `music.163.com` 的 Referer，酷狗系要
/// `kugou.com`，发错就是一张张裂图。磁盘那级用假 PathProvider 指到临时目录，
/// 网络那级用注入的假 Dio——**全程不打真 CDN**（原来这两级一碰就真发请求，
/// 测试环境里是 HandshakeException，又慢又不可靠）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late CoverCache cache;
  late Dio dio;

  /// 按 CoverCache 的口径（sha1(url)）预置一份磁盘缓存。
  void seedDisk(String url, List<int> bytes) {
    final key = sha1.convert(utf8.encode(url)).toString();
    final dir = Directory('${tmp.path}${Platform.pathSeparator}cover_cache');
    dir.createSync(recursive: true);
    File('${dir.path}${Platform.pathSeparator}$key').writeAsBytesSync(bytes);
  }

  String diskPathOf(String url) {
    final key = sha1.convert(utf8.encode(url)).toString();
    return '${tmp.path}${Platform.pathSeparator}cover_cache'
        '${Platform.pathSeparator}$key';
  }

  /// 装一个按 FIFO 回放的假 Dio。
  ///
  /// BaseOptions 必须和 CoverCache 里那个一致：`responseType: bytes` 决定
  /// `resp.data` 是字节数组（否则 dio 会按 content-type 解成 String，
  /// `Uint8List.fromList` 直接类型转换失败）。
  void stubNetwork(List<(int, String, String)> responses) {
    dio = Dio(
      BaseOptions(
        responseType: ResponseType.bytes,
        validateStatus: (s) => s != null && s >= 200 && s < 300,
      ),
    )..httpClientAdapter = ScriptedAdapter(responses);
    cache.dioForTesting = dio;
  }

  // 整个文件共用一个临时目录：CoverCache._dir 会缓存目录句柄，
  // 每个用例换目录会让后面的用例读到已删除的旧路径。
  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('kugo_cover_test');
    installFakePathProvider(tmp);
  });

  tearDownAll(() {
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    cache = CoverCache.instance;
    stubNetwork(const []);
  });

  group('headersFor — 防盗链按域名下发', () {
    test('网易系域名带 music.163.com Referer', () {
      for (final url in const [
        'https://p1.music.126.net/abc.jpg',
        'http://music.163.com/x.png',
        'https://img.126.net/y.webp',
      ]) {
        expect(
          CoverCache.headersFor(url)['Referer'],
          'https://music.163.com',
          reason: url,
        );
      }
    });

    test('酷狗系 / 其他域名带 kugou.com Referer', () {
      for (final url in const [
        'https://imge.kugou.com/a.jpg',
        'http://imgcdn.kugou.com/b.png',
        'https://example.com/whatever.jpg',
      ]) {
        expect(
          CoverCache.headersFor(url)['Referer'],
          'http://www.kugou.com/',
          reason: url,
        );
      }
    });

    test('域名匹配大小写不敏感', () {
      expect(
        CoverCache.headersFor('https://P1.MUSIC.126.NET/a.jpg')['Referer'],
        'https://music.163.com',
      );
      expect(
        CoverCache.headersFor('https://IMGE.KUGOU.COM/a.jpg')['Referer'],
        'http://www.kugou.com/',
      );
    });

    test('两种域名共用同一个移动端 User-Agent', () {
      final a = CoverCache.headersFor('https://p1.music.126.net/a.jpg');
      final b = CoverCache.headersFor('https://imge.kugou.com/a.jpg');
      expect(a['User-Agent'], isNotEmpty);
      expect(a['User-Agent'], b['User-Agent']);
      expect(a['User-Agent'], contains('Android'));
    });
  });

  group('get — 非网络 URL 直接放弃', () {
    test('空串 / 空白 / mock:// / 相对路径都返回 null', () async {
      expect(await cache.get(''), isNull);
      expect(await cache.get('   '), isNull);
      expect(await cache.get('mock://cover1'), isNull);
      expect(await cache.get('/local/path.jpg'), isNull);
      expect(await cache.get('cover.jpg'), isNull);
    });

    test('http:// 前缀（不只是 https）也放行', () async {
      // 用磁盘命中证明它没被前置规则拦掉。
      const url = 'http://imge.kugou.com/plain-http.jpg';
      seedDisk(url, [7, 7]);
      expect(await cache.get(url), [7, 7]);
    });
  });

  group('磁盘命中', () {
    test('peek 在未加载前是 null（首帧不同步读盘）', () {
      const url = 'https://imge.kugou.com/not-loaded.jpg';
      expect(cache.peek(url), isNull);
    });

    test('磁盘命中 → get 返回字节，并把内存也填上', () async {
      const url = 'https://imge.kugou.com/disk-hit.jpg';
      seedDisk(url, [1, 2, 3, 4]);

      expect(cache.peek(url), isNull);
      expect(await cache.get(url), [1, 2, 3, 4]);
      // 内存已回填：Hero 落地时不会闪一下渐变占位。
      expect(cache.peek(url), [1, 2, 3, 4]);
    });

    test('peek 会裁掉首尾空白再查', () async {
      const url = 'https://imge.kugou.com/trim.jpg';
      seedDisk(url, [5]);
      expect(await cache.get(url), [5]);
      expect(cache.peek('  $url  '), [5]);
    });

    test('磁盘上的空文件被当作未命中，转而走网络', () async {
      const url = 'https://imge.kugou.com/empty-file.jpg';
      seedDisk(url, []);
      // 网络也拿不到非空内容 → 最终 null。
      stubNetwork([ScriptedAdapter.text('')]);

      expect(cache.peek(url), isNull);
      expect(await cache.get(url), isNull);
    });
  });

  group('网络下载', () {
    test('下载成功 → 返回字节、写盘、填内存', () async {
      const url = 'https://imge.kugou.com/fresh.jpg';
      stubNetwork([ScriptedAdapter.text('PNGDATA')]);

      expect(await cache.get(url), isNotNull);
      expect(cache.peek(url), isNotNull);

      // 落盘了（异步写，给几轮事件循环）。
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(File(diskPathOf(url)).existsSync(), isTrue);
    });

    test('下载失败（非 2xx）→ null，不抛', () async {
      const url = 'https://imge.kugou.com/boom.jpg';
      stubNetwork([ScriptedAdapter.raw(500, 'server error')]);
      expect(await cache.get(url), isNull);
    });

    test('空响应体 → null', () async {
      const url = 'https://imge.kugou.com/empty-body.jpg';
      stubNetwork([ScriptedAdapter.text('')]);
      expect(await cache.get(url), isNull);
    });

    test('请求头带上该域名的防盗链 Referer', () async {
      const url = 'https://p1.music.126.net/n.jpg';
      final adapter = ScriptedAdapter([ScriptedAdapter.text('x')]);
      dio = Dio(
        BaseOptions(
          responseType: ResponseType.bytes,
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ),
      )..httpClientAdapter = adapter;
      cache.dioForTesting = dio;

      await cache.get(url);
      final sent = adapter.requests.single;
      expect(sent.headers['Referer'], 'https://music.163.com');
      expect(sent.headers['User-Agent'], isNotEmpty);
    });
  });

  group('clear', () {
    test('清掉内存与磁盘', () async {
      const url = 'https://imge.kugou.com/to-clear.jpg';
      seedDisk(url, [9, 9]);
      expect(await cache.get(url), [9, 9]);
      expect(cache.peek(url), isNotNull);

      await cache.clear();
      expect(cache.peek(url), isNull);
      expect(File(diskPathOf(url)).existsSync(), isFalse);
    });

    test('没有缓存目录时 clear 不抛', () async {
      // 指向一个全新的临时目录（下面没有 cover_cache）。
      final empty = Directory.systemTemp.createTempSync('kugo_cover_empty');
      installFakePathProvider(empty);
      await cache.clear();
      try {
        empty.deleteSync(recursive: true);
      } catch (_) {}
    });
  });
}
