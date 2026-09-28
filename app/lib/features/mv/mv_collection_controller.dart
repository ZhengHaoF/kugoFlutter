import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/mv_models.dart';
import '../../core/source/capabilities.dart';
import '../../core/source/music_platform.dart';
import '../../core/source/music_source.dart' show LoginRequired;
import '../../core/source/registry.dart';
import '../auth/auth_token_holder.dart';

/// MV 收藏状态（登录态 + 空 id 防护）。
///
/// id 必须是数字 video_id（[normalizeMvCollectId]）；hash / mixSongId 一律拒绝。
class MvCollectionState {
  const MvCollectionState({
    this.loaded = false,
    this.loading = false,
    this.collectedIds = const {},
    this.pendingIds = const {},
    this.error = '',
  });

  final bool loaded;
  final bool loading;
  final Set<String> collectedIds;
  final Set<String> pendingIds;
  final String error;

  bool isCollected(String rawId) {
    final id = normalizeMvCollectId(rawId);
    return id.isNotEmpty && collectedIds.contains(id);
  }

  bool isPending(String rawId) {
    final id = normalizeMvCollectId(rawId);
    return id.isNotEmpty && pendingIds.contains(id);
  }

  MvCollectionState copyWith({
    bool? loaded,
    bool? loading,
    Set<String>? collectedIds,
    Set<String>? pendingIds,
    String? error,
  }) {
    return MvCollectionState(
      loaded: loaded ?? this.loaded,
      loading: loading ?? this.loading,
      collectedIds: collectedIds ?? this.collectedIds,
      pendingIds: pendingIds ?? this.pendingIds,
      error: error ?? this.error,
    );
  }
}

class MvCollectionController extends Notifier<MvCollectionState> {
  @override
  MvCollectionState build() => const MvCollectionState();

  MvCollectSource? _src(MusicPlatform platform) =>
      requireMusicSourceRegistry.capability<MvCollectSource>(platform);

  /// 拉取收藏集合（幂等；已 loaded 则跳过）。未登录静默跳过。
  Future<void> ensureLoaded({
    MusicPlatform platform = MusicPlatform.kugou,
  }) async {
    if (state.loaded || state.loading) return;
    if (!AuthTokenHolder.instance.hasToken) return;
    final src = _src(platform);
    if (src == null) return;
    state = state.copyWith(loading: true, error: '');
    try {
      final ids = await src.fetchCollectedMvIds();
      state = state.copyWith(loaded: true, loading: false, collectedIds: ids);
    } on LoginRequired {
      state = state.copyWith(loading: false);
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: e.toString().split('\n').first,
      );
    }
  }

  /// 切换收藏。返回切换后的值；未登录 / 非法 id / 并发中返回 null。
  ///
  /// [state.error] 为 `LoginRequired.message` 时表示需要登录。
  Future<bool?> toggle(
    String rawId, {
    MusicPlatform platform = MusicPlatform.kugou,
  }) async {
    final id = normalizeMvCollectId(rawId);
    if (id.isEmpty || state.isPending(id)) return null;
    if (!AuthTokenHolder.instance.hasToken) {
      state = state.copyWith(error: '请先登录');
      return null;
    }
    final src = _src(platform);
    if (src == null) return null;
    await ensureLoaded(platform: platform);
    if (!state.loaded) return null;

    final next = !state.isCollected(id);
    final pending = {...state.pendingIds, id};
    state = state.copyWith(pendingIds: pending);
    try {
      await src.setMvCollected(id, collected: next);
      final ids = {...state.collectedIds};
      if (next) {
        ids.add(id);
      } else {
        ids.remove(id);
      }
      state = state.copyWith(collectedIds: ids, error: '');
      return next;
    } on LoginRequired catch (e) {
      state = state.copyWith(error: e.message);
      return null;
    } catch (e) {
      state = state.copyWith(error: e.toString().split('\n').first);
      return null;
    } finally {
      final rest = {...state.pendingIds}..remove(id);
      state = state.copyWith(pendingIds: rest);
    }
  }
}

final mvCollectionProvider =
    NotifierProvider<MvCollectionController, MvCollectionState>(
  MvCollectionController.new,
);
