import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/netease/netease_mappers.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/capabilities.dart';
import 'package:kugo/core/source/music_platform.dart';
import 'package:kugo/core/source/music_source.dart';
import 'package:kugo/features/auth/netease_login_controller.dart';
import 'package:kugo/features/likes/netease_likes_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_device_login_source.dart';

/// 测试用假「我喜欢」源：不碰网络，可注入错误。
class FakeUserLibrarySource implements UserLibrarySource {
  List<Track> tracks = const [];
  Object? error;
  int calls = 0;

  @override
  Future<List<Track>> likedTracks() async {
    calls++;
    final e = error;
    if (e != null) throw e;
    return tracks;
  }
}

const _track = Track(
  id: '65536',
  name: '爱情转移',
  artist: '陈奕迅',
  album: '认了吧',
  coverUrl: 'https://p/a.jpg',
  durationMs: 246000,
  platform: MusicPlatform.netease,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('mapNeteaseLikedSongIds', () {
    test('顶层 ids → int 列表', () {
      expect(
        mapNeteaseLikedSongIds('{"code":200,"ids":[1,2,3]}'),
        [1, 2, 3],
      );
    });

    test('非数字 / 非正数 id 丢弃', () {
      expect(
        mapNeteaseLikedSongIds('{"code":200,"ids":[1,"x",null,0,-2,3]}'),
        [1, 3],
      );
    });

    test('ids 缺失返回空（不抛）', () {
      expect(mapNeteaseLikedSongIds('{"code":200}'), isEmpty);
      expect(mapNeteaseLikedSongIds('{"code":200,"ids":"x"}'), isEmpty);
    });

    test('业务码非 200 抛 SourceFailure', () {
      expect(
        () => mapNeteaseLikedSongIds('{"code":301}'),
        throwsA(isA<SourceFailure>()),
      );
    });
  });

  group('mapNeteaseSongDetails', () {
    test('新结构：ar / al.picUrl / dt', () {
      const raw = '{"code":200,"songs":[{"id":65536,"name":"爱情转移",'
          '"ar":[{"id":2116,"name":"陈奕迅"}],'
          '"al":{"id":1,"name":"认了吧","picUrl":"http://p/a.jpg"},'
          '"dt":246000,"fee":0}]}';
      final tracks = mapNeteaseSongDetails(raw);
      expect(tracks, hasLength(1));
      final t = tracks.single;
      expect(t.id, '65536');
      expect(t.name, '爱情转移');
      expect(t.artist, '陈奕迅');
      expect(t.artistId, '2116');
      expect(t.album, '认了吧');
      // http → https（与 _pic 同口径）
      expect(t.coverUrl, 'https://p/a.jpg');
      expect(t.durationMs, 246000);
      expect(t.platform, MusicPlatform.netease);
    });

    test('id 非数字的节点被跳过', () {
      expect(
        mapNeteaseSongDetails('{"code":200,"songs":[{"name":"x"}]}'),
        isEmpty,
      );
    });

    test('业务码非 200 抛 SourceFailure', () {
      expect(
        () => mapNeteaseSongDetails('{"code":500}'),
        throwsA(isA<SourceFailure>()),
      );
    });
  });

  group('NeteaseLikesNotifier', () {
    ProviderContainer makeContainer(
      FakeUserLibrarySource likes,
      FakeDeviceLoginSource login,
    ) {
      final container = ProviderContainer(
        overrides: [
          neteaseLikesSourceProvider.overrideWithValue(likes),
          neteaseLoginSourceProvider.overrideWithValue(login),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Future<void> waitFor(bool Function() test) async {
      for (var i = 0; i < 100 && !test(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    test('未登录不发请求，只给「需登录」提示', () async {
      final likes = FakeUserLibrarySource()..tracks = [_track];
      final c = makeContainer(likes, FakeDeviceLoginSource());

      await c.read(neteaseLikesProvider.notifier).load();

      expect(likes.calls, 0);
      expect(c.read(neteaseLikesProvider).error, '需登录后查看');
      expect(c.read(neteaseLikesProvider).tracks, isEmpty);
    });

    test('登录态回填后自动拉取我喜欢', () async {
      final likes = FakeUserLibrarySource()..tracks = [_track];
      final login = FakeDeviceLoginSource()
        ..account = const LoginAccount(userId: '42', nickname: '小明');
      final c = makeContainer(likes, login);

      // 页面先 watch（此时登录态还没回填），再等 login controller 落状态。
      c.listen(neteaseLikesProvider, (_, _) {});
      await c.read(neteaseLoginControllerProvider.notifier).refreshAccount();
      await waitFor(() => c.read(neteaseLikesProvider).loaded);

      final s = c.read(neteaseLikesProvider);
      expect(likes.calls, 1);
      expect(s.tracks, hasLength(1));
      expect(s.tracks.single.id, '65536');
      expect(s.error, isEmpty);
    });

    test('已登录时 build 即拉取（不依赖登录态变化）', () async {
      final likes = FakeUserLibrarySource()..tracks = [_track];
      final login = FakeDeviceLoginSource()
        ..account = const LoginAccount(userId: '42', nickname: '小明');
      final c = makeContainer(likes, login);

      await c.read(neteaseLoginControllerProvider.notifier).refreshAccount();
      c.read(neteaseLikesProvider);
      await waitFor(() => c.read(neteaseLikesProvider).loaded);

      expect(likes.calls, 1);
      expect(c.read(neteaseLikesProvider).tracks, hasLength(1));
    });

    test('失败时保留错误文案且不抛', () async {
      final likes = FakeUserLibrarySource()..error = const NotFound('取我喜欢失败');
      final login = FakeDeviceLoginSource()
        ..account = const LoginAccount(userId: '42', nickname: '小明');
      final c = makeContainer(likes, login);

      await c.read(neteaseLoginControllerProvider.notifier).refreshAccount();
      await c.read(neteaseLikesProvider.notifier).load();

      final s = c.read(neteaseLikesProvider);
      expect(s.loaded, isTrue);
      expect(s.error, contains('取我喜欢失败'));
      expect(s.tracks, isEmpty);
    });

    test('登出清空已加载的列表', () async {
      final likes = FakeUserLibrarySource()..tracks = [_track];
      final login = FakeDeviceLoginSource()
        ..account = const LoginAccount(userId: '42', nickname: '小明');
      final c = makeContainer(likes, login);

      await c.read(neteaseLoginControllerProvider.notifier).refreshAccount();
      await c.read(neteaseLikesProvider.notifier).load();
      expect(c.read(neteaseLikesProvider).tracks, hasLength(1));

      await c.read(neteaseLoginControllerProvider.notifier).logout();

      expect(c.read(neteaseLikesProvider).tracks, isEmpty);
      expect(c.read(neteaseLikesProvider).loaded, isFalse);
    });
  });
}
