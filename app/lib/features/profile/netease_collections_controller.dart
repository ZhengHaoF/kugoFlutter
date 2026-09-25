import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/track.dart' show PlaylistBrief;
import '../../core/source/capabilities.dart';
import '../../data/sources/netease/netease_source.dart';
import '../auth/netease_login_controller.dart';

/// 网易云云端歌单（自建 / 收藏）的页面态。
///
/// 与酷狗侧 `userCollectionsProvider` 平行：两源各存一份（见
/// 多音源接入方案 §11），由「我的」页的账号源决定展示谁。
class NeteaseCollectionsState {
  const NeteaseCollectionsState({
    this.created = const [],
    this.collected = const [],
    this.loading = false,
    this.loaded = false,
    this.error = '',
  });

  final List<PlaylistBrief> created;
  final List<PlaylistBrief> collected;
  final bool loading;
  final bool loaded;
  final String error;

  int get totalPlaylistsCount => created.length + collected.length;

  /// 云端「我喜欢的音乐」（`specialType == 5`，mapper 已打 `isDefault`）。
  PlaylistBrief? get likedPlaylist {
    for (final p in [...created, ...collected]) {
      if (p.isDefault) return p;
    }
    return null;
  }

  NeteaseCollectionsState copyWith({
    List<PlaylistBrief>? created,
    List<PlaylistBrief>? collected,
    bool? loading,
    bool? loaded,
    String? error,
  }) {
    return NeteaseCollectionsState(
      created: created ?? this.created,
      collected: collected ?? this.collected,
      loading: loading ?? this.loading,
      loaded: loaded ?? this.loaded,
      error: error ?? this.error,
    );
  }
}

class NeteaseCollectionsNotifier extends Notifier<NeteaseCollectionsState> {
  @override
  NeteaseCollectionsState build() {
    // 登录态是异步回填的，故既听转换、也在已登录时补一次（与 likes 同构）。
    ref.listen<NeteaseLoginState>(neteaseLoginControllerProvider, (prev, next) {
      if (next.isLogged && !state.loaded) {
        load();
      } else if (!next.isLogged && state.loaded) {
        state = const NeteaseCollectionsState();
      }
    });
    if (ref.read(neteaseLoginControllerProvider).isLogged) {
      Future.microtask(load);
    }
    return const NeteaseCollectionsState();
  }

  Future<void> load({bool force = false}) async {
    if (state.loading) return;
    if (!force && state.loaded) return;
    if (!ref.read(neteaseLoginControllerProvider).isLogged) {
      state = state.copyWith(loading: false, error: '需登录后查看');
      return;
    }
    state = state.copyWith(loading: true, error: '');
    try {
      final page =
          await ref.read(neteaseCollectionsSourceProvider).userPlaylists();
      state = NeteaseCollectionsState(
        created: page.created,
        collected: page.collected,
        loaded: true,
      );
    } catch (e) {
      state = NeteaseCollectionsState(loaded: true, error: _msg(e));
    }
  }

  String _msg(Object e) {
    final s = e.toString().split('\n').first.trim();
    return s.isEmpty ? '网络异常' : s;
  }
}

/// 取用户歌单用的音源（默认全局网易源；测试覆盖成假源）。
final neteaseCollectionsSourceProvider = Provider<UserPlaylistReadSource>(
  (ref) => neteaseSource,
);

final neteaseCollectionsProvider =
    NotifierProvider<NeteaseCollectionsNotifier, NeteaseCollectionsState>(
  NeteaseCollectionsNotifier.new,
);
