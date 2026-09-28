/// 歌曲 → MV 的入口与共享数据面。
///
/// 对齐 EchoMusic 的展示口径：只要歌曲带**可寻址的专辑音频 id**（我们即
/// `Track.mixSongId`）且音源实现了 `MvSearchSource`，就露出 MV 入口，**不预检**；
/// 真有有没有 MV 由 `songMvs` 的返回决定（空 → 提示，不跳转）。
///
/// 拉取结果按 `platform:mixSongId` 内存缓存，播放栏 / 列表项 / 详情页共用，
/// 避免同一首歌反复打接口（`/mv` 播放页也复用同一缓存，见 `mv_controller`）。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/mv_models.dart';
import '../../core/models/track.dart';
import '../../core/source/capabilities.dart';
import '../../core/source/music_platform.dart';
import '../../core/source/registry.dart';
import '../../core/theme/kugo_theme.dart';

/// 已拉取的「歌曲 → MV 版本列表」。key = `musicIdentity(platform, mixSongId)`。
final Map<String, List<MvBrief>> _songMvCache = {};

/// 同 key 并发请求去重（列表里多行同曲时只发一次）。
final Map<String, Future<List<MvBrief>>> _songMvInflight = {};

/// 测试用：清空缓存。
void clearMvCache() {
  _songMvCache.clear();
  _songMvInflight.clear();
}

/// 缓存键：无 `mixSongId` 时返回 null（不可寻址）。
String? _cacheKeyOf(Track track) {
  final id = track.mixSongId.trim();
  if (id.isEmpty) return null;
  return musicIdentity(track.platform, id);
}

/// 这首歌是否**可能**有 MV：音源具备能力且带 [Track.mixSongId]。
///
/// 宽松判定（与 EchoMusic 的 `albumAudioId` 判据一致）——不发起网络请求。
/// 音频源（如网易）未实现 [MvSearchSource] 时自然为 false，入口自动隐藏。
bool canOpenMv(Track track) {
  if (_cacheKeyOf(track) == null) return false;
  return musicSourceRegistry?.capability<MvSearchSource>(track.platform) != null;
}

/// 拉取歌曲关联 MV（多版本），带内存缓存。
///
/// 无 `mixSongId` / 无能力 → 空列表且**不打网络**。解析失败原样抛出，由调用方
/// 决定是提示还是静默（`mv_controller` 的多版本增强即静默）。
Future<List<MvBrief>> loadSongMvs(Track track) async {
  final key = _cacheKeyOf(track);
  if (key == null) return const <MvBrief>[];

  final cached = _songMvCache[key];
  if (cached != null) return cached;

  final inflight = _songMvInflight[key];
  if (inflight != null) return inflight;

  final src = musicSourceRegistry?.capability<MvSearchSource>(track.platform);
  if (src == null) return const <MvBrief>[];

  final future = src.songMvs(track);
  _songMvInflight[key] = future;
  try {
    final list = await future;
    _songMvCache[key] = list;
    return list;
  } finally {
    _songMvInflight.remove(key);
  }
}

/// 打开某首歌的 MV：拉取 → 空则提示 → 否则跳 `/mv`（取第一个版本）。
Future<void> openMvForTrack(BuildContext context, Track track) async {
  List<MvBrief> list;
  try {
    list = await loadSongMvs(track);
  } catch (_) {
    if (context.mounted) _snack(context, 'MV 加载失败');
    return;
  }
  if (!context.mounted) return;
  if (list.isEmpty) {
    _snack(context, '这首歌暂无 MV');
    return;
  }

  final mv = list.first;
  context.push(
    Uri(
      path: '/mv',
      queryParameters: {
        'id': mv.id,
        'hash': mv.hash,
        'name': mv.name,
        'artist': mv.artist,
        'cover': mv.coverUrl,
        // MV 侧没带时退回歌曲的 mixSongId，供播放页拉同曲多版本。
        'mixSongId': mv.mixSongId.isEmpty ? track.mixSongId : mv.mixSongId,
      },
    ).toString(),
  );
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(milliseconds: 1600),
    ),
  );
}

/// 通用 MV 入口按钮。
///
/// [canOpenMv] 不满足时返回 `SizedBox.shrink()`，**不占位**，调用方无需再判空。
/// 悬停显隐由调用方（如 `TrackTile` 的行级 hover）负责，本组件只管图标/加载态。
class MvEntryButton extends StatefulWidget {
  const MvEntryButton({
    super.key,
    required this.track,
    this.size = 20,
    this.color,
    this.padding = EdgeInsets.zero,
    this.constraints,
  });

  final Track track;
  final double size;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final BoxConstraints? constraints;

  @override
  State<MvEntryButton> createState() => _MvEntryButtonState();
}

class _MvEntryButtonState extends State<MvEntryButton> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await openMvForTrack(context, widget.track);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!canOpenMv(widget.track)) return const SizedBox.shrink();

    final kugo = KugoTheme.of(context);
    return IconButton(
      tooltip: '播放 MV',
      padding: widget.padding,
      constraints:
          widget.constraints ??
          BoxConstraints(
            minWidth: widget.size + 20,
            minHeight: widget.size + 20,
          ),
      onPressed: _opening ? null : _open,
      icon: _opening
          ? SizedBox(
              width: widget.size,
              height: widget.size,
              child: const CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              Icons.videocam_outlined,
              size: widget.size,
              color: widget.color ?? kugo.textTertiary,
            ),
    );
  }
}