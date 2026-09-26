import 'package:kugo/core/api/kugo_sign.dart';
import 'package:kugo/core/models/comment.dart';
import 'package:kugo/data/repositories/comment_repository.dart';
import 'package:kugo/data/repositories/search_repository.dart';
import 'package:kugo/data/storage/device_identity.dart';
import 'package:kugo/features/auth/auth_token_holder.dart';

/// 手工探针：验证评论三类接口在本机网络下的行为（`flutter run -t tool/probe_comment.dart`）。
Future<void> main() async {
  final device = await DeviceIdentity.ensure();
  final auth = AuthTokenHolder.instance;
  print('device mid=${device.mid} dfid=${device.dfid}');
  print(
    'auth token=${auth.hasToken} userId=${auth.userId} holderMid=${auth.mid}',
  );

  const name = '甲乙丙丁';
  const artist = '李佳薇';
  final hits = await searchRepository.searchSongs('$name $artist', pageSize: 8);
  print('search hits=${hits.length}');
  for (final t in hits) {
    print(
      '  name=${t.name} artist=${t.artist} id=${t.id} mix=${t.mixSongId} hash=${t.hash}',
    );
  }

  final ids = <String>[if (hits.isNotEmpty) hits.first.mixSongId, '920474385'];
  final hash = hits.isNotEmpty ? hits.first.hash : '';
  for (final id in ids) {
    if (id.isEmpty) continue;
    final page = await commentRepository.fetchSongComments(mixSongId: id);
    print(
      'all mix=$id n=${page.items.length} total=${page.total} '
      'children=${page.childrenId} maxPage=${page.maxPage} err=${commentRepository.lastError}',
    );
    if (page.items.isNotEmpty) {
      final c = page.items.first;
      print(
        '  first=${c.user}(${c.likeCount}) ${c.content.substring(0, c.content.length.clamp(0, 40))}',
      );
    }

    final hottest = await commentRepository.fetchSongComments(
      mixSongId: id,
      sort: CommentSort.hottest,
    );
    print(
      'hot mix=$id n=${hottest.items.length} err=${commentRepository.lastError}',
    );

    if (page.childrenId.isNotEmpty && page.items.isNotEmpty) {
      final floors = await commentRepository.fetchFloorReplies(
        childrenId: page.childrenId,
        rootCommentId: page.items.first.id,
        mixSongId: id,
      );
      print('floor n=${floors.length} err=${commentRepository.lastError}');
    }
  }

  if (hash.isNotEmpty) {
    final count = await commentRepository.fetchCommentCount(hash: hash);
    print('count hash=$hash -> $count');
  }

  // Manual signature sanity for official params
  final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final params = <String, dynamic>{
    'dfid': device.dfid,
    'mid': device.mid,
    'uuid': '-',
    'appid': int.parse(KugoSign.appId),
    'clientver': int.parse(KugoSign.clientVer),
    'clienttime': clienttime,
    'mixsongid': 920474385,
    'need_show_image': 1,
    'p': 1,
    'pagesize': 20,
    'show_classify': 1,
    'show_hotword_list': 1,
    'extdata': '0',
    'code': 'fc4be23b4e972707f36b8a828a93ba8a',
  };
  params['signature'] = KugoSign.signatureAndroidParams(params);
  print('manual signature=${params['signature']} clienttime=$clienttime');
}
