import 'package:kugo/core/api/kugo_sign.dart';
import 'package:kugo/data/repositories/search_repository.dart';
import 'package:kugo/data/repositories/song_detail_repository.dart';
import 'package:kugo/data/storage/device_identity.dart';
import 'package:kugo/features/auth/auth_token_holder.dart';

Future<void> main() async {
  final device = await DeviceIdentity.ensure();
  final auth = AuthTokenHolder.instance;
  print('device mid=${device.mid} dfid=${device.dfid}');
  print('auth token=${auth.hasToken} userId=${auth.userId} holderMid=${auth.mid}');

  const name = '甲乙丙丁';
  const artist = '李佳薇';
  final hits = await searchRepository.searchSongs('$name $artist', pageSize: 8);
  print('search hits=${hits.length}');
  for (final t in hits) {
    print('  name=${t.name} artist=${t.artist} id=${t.id} mix=${t.mixSongId} hash=${t.hash}');
  }

  final ids = <String>[
    if (hits.isNotEmpty) hits.first.mixSongId,
    '920474385',
  ];
  for (final id in ids) {
    if (id.isEmpty) continue;
    final list = await songDetailRepository.fetchComments(mixSongId: id);
    print('fetch mix=$id count=${list.length} err=${songDetailRepository.lastError}');
    if (list.isNotEmpty) {
      print('  first=${list.first.user}: ${list.first.content.substring(0, list.first.content.length.clamp(0, 40))}');
    }
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
