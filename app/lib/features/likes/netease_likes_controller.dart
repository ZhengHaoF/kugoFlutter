import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/track.dart';
import '../../core/source/capabilities.dart';
import '../../data/sources/netease/netease_source.dart';
import '../auth/netease_login_controller.dart';

/// 网易云云端「我喜欢」（F3 ids + A4 详情）的页面态。
///
/// 与酷狗侧 `userCollectionsProvider.cloudFavoriteTracks` 平行：两源各存一份，
/// 由「我喜欢」页的源筛选决定展示谁（见 多音源接入方案 §11）。
class NeteaseLikesState {
  const NeteaseLikesState({
    this.tracks = const [],
    this.loading = false,
    this.loaded = false,
    this.error = '',
  });

  final List<Track> tracks;
  final bool loading;
  final bool loaded;
  final String error;

  NeteaseLikesState copyWith({
    List<Track>? tracks,
    bool? loading,
    bool? loaded,
    String? error,
  }) {
    return NeteaseLikesState(
      tracks: tracks ?? this.tracks,
      loading: loading ?? this.loading,
      loaded: loaded ?? this.loaded,
      error: error ?? this.error,
    );
  }
}

class NeteaseLikesNotifier extends Notifier<NeteaseLikesState> {
  @override
  NeteaseLikesState build() {
    // 登录态是异步回填的（NeteaseLoginController 先 refreshAccount 再落状态），
    // 故这里既听转换、也在已登录时补一次，避免「先逛设置页再进我喜欢」漏加载。
    ref.listen<NeteaseLoginState>(neteaseLoginControllerProvider, (prev, next) {
      if (next.isLogged && !state.loaded) {
        load();
      } else if (!next.isLogged && state.loaded) {
        state = const NeteaseLikesState();
      }
    });
    if (ref.read(neteaseLoginControllerProvider).isLogged) {
      Future.microtask(load);
    }
    return const NeteaseLikesState();
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
      final tracks = await ref.read(neteaseLikesSourceProvider).likedTracks();
      state = NeteaseLikesState(tracks: tracks, loaded: true);
    } catch (e) {
      state = NeteaseLikesState(loaded: true, error: _msg(e));
    }
  }

  String _msg(Object e) {
    final s = e.toString().split('\n').first.trim();
    return s.isEmpty ? '网络异常' : s;
  }
}

/// 取「我喜欢」用的音源（默认全局网易源；测试覆盖成假源）。
final neteaseLikesSourceProvider = Provider<UserLibrarySource>(
  (ref) => neteaseSource,
);

final neteaseLikesProvider =
    NotifierProvider<NeteaseLikesNotifier, NeteaseLikesState>(
  NeteaseLikesNotifier.new,
);
