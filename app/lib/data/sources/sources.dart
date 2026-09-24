import '../../core/source/registry.dart';
import 'kugou/kugou_source.dart';
import 'netease/netease_source.dart';

/// 启动装配：注册全部内置音源（编译期组合，不做运行时热加载）。
///
/// 列表顺序即 `registry.all` 的默认展示顺序（酷狗在前、网易云在后）。
void registerDefaultMusicSources() {
  musicSourceRegistry = MusicSourceRegistry([kugouSource, neteaseSource]);
}
