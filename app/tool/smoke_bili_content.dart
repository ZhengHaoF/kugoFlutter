import 'package:kugo/core/api/bili/bili_qr_login.dart';
import 'package:kugo/data/sources/bili/bili_source.dart';

/// 不持有账号凭据的公开内容冒烟：dart run tool/smoke_bili_content.dart。
/// 只打印摘要，不输出 Cookie、二维码 token 或音轨签名 URL。
Future<void> main() async {
  final source = BiliSource();
  final songs = await source.searchSongs('晴天');
  final track = songs.items.firstWhere((t) => t.artistId.isNotEmpty);
  final mid = track.artistId;
  print('搜索曲目=${track.id} mid=$mid');
  Future<void> check(String name, Future<void> Function() run) async {
    try {
      await run();
      print('$name: PASS');
    } catch (e) {
      print('$name: BLOCKED $e');
    }
  }

  await check('UP 主资料', () async {
    final artist = await source.fetchArtistDetail(mid);
    if (artist == null || artist.name.isEmpty) throw StateError('缺少资料');
    print('昵称=${artist.name}');
  });
  await check('UP 主投稿', () async {
    final videos = await source.fetchArtistSongsPage(mid);
    print('投稿=${videos.songs.length} total=${videos.total}');
    if (videos.songs.isEmpty) throw StateError('无投稿');
  });
  await check('合集/系列', () async {
    final page = await source.artistContents(mid);
    print('合集/系列=${page.items.length} total=${page.total}');
    if (page.items.isNotEmpty) {
      final detail = await source.fetchPlaylistDetail(
        page.items.first.id,
        briefHint: page.items.first,
      );
      print('首项=${page.items.first.id} tracks=${detail?.tracks.length}');
      if (detail == null) throw StateError('无详情');
    }
  });
  await check('视频分 P', () async {
    final detail = await source.fetchPlaylistDetail('video:${track.id}');
    if (detail == null || detail.tracks.isEmpty) throw StateError('无分 P');
    print('分 P=${detail.tracks.length}');
  });
  await check('扫码生成/等待状态（不登录）', () async {
    final qr = BiliQrLoginClient();
    final session = await qr.createSession();
    final poll = await qr.pollLogin(session);
    print('扫码状态=${poll.status.name}');
    if (poll.isConfirmed) throw StateError('意外的登录状态');
  });
}
