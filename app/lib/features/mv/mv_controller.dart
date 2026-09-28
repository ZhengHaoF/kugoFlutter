import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/mv_models.dart';
import '../../core/models/track.dart';
import '../../core/source/capabilities.dart';
import '../../core/source/music_source.dart';
import '../../core/source/registry.dart';
import 'mv_entry.dart';

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
    this.versions = const [],
    this.versionIndex = 0,
  });

  final MvLoadStatus status;
  final MvBrief? brief;
  final MvDetail? detail;

  /// 当前选中片源；null = 未选。
  final MvPlaySource? source;
  final MvPlayUrlResult? playUrl;
  final String error;

  /// 同一歌曲的多版本 MV（官方 / 现场 / 饭制…），来自 `songMvs`。
  /// 空 = 未拉到或单版本。
  final List<MvBrief> versions;

  /// 当前版本在 [versions] 中的下标；单版本时恒为 0。
  final int versionIndex;

  bool get canPlay =>
      status == MvLoadStatus.ready && playUrl != null && playUrl!.url.isNotEmpty;

  bool get hasPrevVersion => versionIndex > 0;
  bool get hasNextVersion =>
      versions.isNotEmpty && versionIndex < versions.length - 1;

  MvPlayerState copyWith({
    MvLoadStatus? status,
    MvBrief? brief,
    MvDetail? detail,
    MvPlaySource? source,
    MvPlayUrlResult? playUrl,
    String? error,
    List<MvBrief>? versions,
    int? versionIndex,
    bool clearPlayUrl = false,
  }) {
    return MvPlayerState(
      status: status ?? this.status,
      brief: brief ?? this.brief,
      detail: detail ?? this.detail,
      source: source ?? this.source,
      playUrl: clearPlayUrl ? null : (playUrl ?? this.playUrl),
      error: error ?? this.error,
      versions: versions ?? this.versions,
      versionIndex: versionIndex ?? this.versionIndex,
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
  ///
  /// [brief.mixSongId] 非空时并行拉同曲多版本列表（失败不挡主流程）。
  Future<void> load(MvBrief brief) async {
    state = state.copyWith(
      status: MvLoadStatus.loading,
      brief: brief,
      error: '',
      versions: const [],
      versionIndex: 0,
      clearPlayUrl: true,
    );
    unawaited(_loadVersions(brief));
    await _loadDetailAndPlay(brief);
  }

  /// 拉同曲多版本；把当前 brief 对齐到列表下标。
  Future<void> _loadVersions(MvBrief brief) async {
    final mixSongId = brief.mixSongId.trim();
    if (mixSongId.isEmpty) return;
    try {
      // 与列表 / 播放栏入口共用 [`loadSongMvs`] 的内存缓存，
      // 从入口点进来时不再重复打 `/kmr/v1/audio/mv`。
      final list = await loadSongMvs(
        Track(
          id: mixSongId,
          name: brief.name,
          artist: brief.artist,
          album: '',
          coverUrl: brief.coverUrl,
          durationMs: brief.durationMs,
          mixSongId: mixSongId,
          platform: brief.platform,
        ),
      );
      if (list.isEmpty) return;
      // 若主流程已换歌，丢弃本次结果。
      final current = state.brief;
      if (current == null ||
          (current.id != brief.id && current.hash != brief.hash)) {
        return;
      }
      var idx = list.indexWhere((v) =>
          (brief.id.isNotEmpty && v.id == brief.id) ||
          (brief.hash.isNotEmpty && v.hash == brief.hash));
      if (idx < 0) idx = 0;
      state = state.copyWith(versions: list, versionIndex: idx);
    } catch (_) {
      // 多版本是增强能力，失败静默。
    }
  }

  /// 详情 + 默认片源取流。不清 versions。
  Future<void> _loadDetailAndPlay(MvBrief brief) async {
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
      final effective = detail ?? MvDetail(brief: brief, sources: const []);
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

  /// 切到同曲的另一版本（官方 / 现场 / 饭制…）。
  Future<void> selectVersion(int index) async {
    final versions = state.versions;
    if (index < 0 || index >= versions.length) return;
    if (index == state.versionIndex && state.canPlay) return;
    final next = versions[index];
    state = state.copyWith(
      status: MvLoadStatus.loading,
      brief: next,
      versionIndex: index,
      error: '',
      clearPlayUrl: true,
    );
    await _loadDetailAndPlay(next);
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
