import '../models/track.dart';
import 'music_platform.dart';
import 'music_source.dart';

/// 音源注册表：按平台查找实现 + 能力探测。本身不含业务。
class MusicSourceRegistry {
  MusicSourceRegistry(List<MusicSource> sources)
      : _byPlatform = {for (final s in sources) s.platform: s};

  final Map<MusicPlatform, MusicSource> _byPlatform;

  MusicSource of(MusicPlatform p) =>
      _byPlatform[p] ?? (throw StateError('No MusicSource for $p'));

  MusicSource ofTrack(Track t) => of(t.platform);

  Iterable<MusicSource> get all => _byPlatform.values;

  Iterable<MusicPlatform> get platforms => _byPlatform.keys;

  bool supports(MusicPlatform p) => _byPlatform.containsKey(p);

  /// 单源入口显隐。
  T? capability<T>(MusicPlatform p) {
    final s = _byPlatform[p];
    return s is T ? s as T : null;
  }

  /// 任一源具备即显示入口（首页卡片等）。
  bool anyHas<T>() => _byPlatform.values.any((s) => s is T);
}

/// 全局注册表；`main` 启动时装配（见 `KugouSource.registerDefaultMusicSources`）。
MusicSourceRegistry? musicSourceRegistry;

MusicSourceRegistry get requireMusicSourceRegistry {
  final r = musicSourceRegistry;
  if (r == null) {
    throw StateError('MusicSourceRegistry not initialized');
  }
  return r;
}
