import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/mv_models.dart';
import '../../core/source/capabilities.dart';
import '../../core/source/music_source.dart';
import '../../core/source/registry.dart';

/// MV 页加载状态。
enum MvLoadStatus { idle, loading, ready, error }

class MvPlayerState {
  const MvPlayerState({
    this.status = MvLoadStatus.idle,
    this.brief,
    this.detail,
    this.source,
    this.playUrl,
    this.error = '',
  });

  final MvLoadStatus status;
  final MvBrief? brief;
  final MvDetail? detail;

  /// 当前选中片源；null = 未选。
  final MvPlaySource? source;
  final MvPlayUrlResult? playUrl;
  final String error;

  bool get canPlay =>
      status == MvLoadStatus.ready && playUrl != null && playUrl!.url.isNotEmpty;

  MvPlayerState copyWith({
    MvLoadStatus? status,
    MvBrief? brief,
    MvDetail? detail,
    MvPlaySource? source,
    MvPlayUrlResult? playUrl,
    String? error,
    bool clearPlayUrl = false,
  }) {
    return MvPlayerState(
      status: status ?? this.status,
      brief: brief ?? this.brief,
      detail: detail ?? this.detail,
      source: source ?? this.source,
      playUrl: clearPlayUrl ? null : (playUrl ?? this.playUrl),
      error: error ?? this.error,
    );
  }
}

/// MV 详情 + 取流。与 [PlayerController]（音频）完全隔离。
///
/// 页面在 initState 调 [load]，dispose 时调 [disposePlayer] 由页面自管
/// `media_kit` 的 `Player`（避免 Riverpod 与 Widget 生命周期打架）。
class MvPlayerController extends Notifier<MvPlayerState> {
  @override
  MvPlayerState build() {
    return const MvPlayerState();
  }

  /// 加载详情并解析默认片源的播放地址。
  Future<void> load(MvBrief brief) async {
    state = state.copyWith(
      status: MvLoadStatus.loading,
      brief: brief,
      error: '',
      clearPlayUrl: true,
    );
    final registry = requireMusicSourceRegistry;
    final src = registry.capability<MvDetailSource>(brief.platform);
    if (src == null) {
      state = state.copyWith(
        status: MvLoadStatus.error,
        error: '当前音源不支持 MV',
      );
      return;
    }
    try {
      final detail = await src.fetchMvDetail(brief);
      final effective = detail ??
          MvDetail(brief: brief, sources: const []);
      final source = effective.defaultSource ??
          (brief.hash.isNotEmpty
              ? MvPlaySource(hash: brief.hash, label: '默认')
              : null);
      if (source == null) {
        state = state.copyWith(
          status: MvLoadStatus.error,
          detail: effective,
          error: '没有可用的视频片源',
        );
        return;
      }
      final playUrl = await src.resolveMvPlayUrl(source.hash);
      state = state.copyWith(
        status: MvLoadStatus.ready,
        brief: effective.brief,
        detail: effective,
        source: source,
        playUrl: playUrl,
      );
    } on SourceFailure catch (e) {
      state = state.copyWith(status: MvLoadStatus.error, error: e.message);
    } catch (e) {
      state = state.copyWith(
        status: MvLoadStatus.error,
        error: e.toString().split('\n').first,
      );
    }
  }

  /// 切换清晰度 / 编码档位。
  Future<void> selectSource(MvPlaySource source) async {
    if (state.source?.hash == source.hash && state.playUrl != null) return;
    final registry = requireMusicSourceRegistry;
    final brief = state.brief;
    if (brief == null) return;
    final src = registry.capability<MvDetailSource>(brief.platform);
    if (src == null) return;
    state = state.copyWith(source: source, clearPlayUrl: true);
    try {
      final playUrl = await src.resolveMvPlayUrl(source.hash);
      state = state.copyWith(playUrl: playUrl, status: MvLoadStatus.ready);
    } on SourceFailure catch (e) {
      state = state.copyWith(status: MvLoadStatus.error, error: e.message);
    } catch (e) {
      state = state.copyWith(
        status: MvLoadStatus.error,
        error: e.toString().split('\n').first,
      );
    }
  }
}

final mvPlayerProvider =
    NotifierProvider<MvPlayerController, MvPlayerState>(MvPlayerController.new);
