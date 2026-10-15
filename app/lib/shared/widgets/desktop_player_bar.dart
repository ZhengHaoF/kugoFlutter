import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/playback_source.dart';
import '../../core/platform.dart';
import '../../core/theme/overtone_theme.dart';
import '../../features/desktop_lyric/desktop_lyric_bridge.dart';
import '../../features/fm/fm_controller.dart';
import '../../features/likes/likes_controller.dart';
import '../../features/mv/mv_entry.dart';
import '../../features/player/player_controller.dart';
import '../../features/settings/settings_controller.dart';
import 'common.dart';
import 'cover_box.dart';
import 'player_icon_buttons.dart';
import 'quality_sheet.dart';
import 'queue_sheet.dart';

/// Desktop bottom playback bar: persistent, full-featured player controls
/// suited for wide screens (Spotify / NetEase Cloud Music desktop style).
class DesktopPlayerBar extends ConsumerStatefulWidget {
  const DesktopPlayerBar({super.key});

  @override
  ConsumerState<DesktopPlayerBar> createState() => _DesktopPlayerBarState();
}

class _DesktopPlayerBarState extends ConsumerState<DesktopPlayerBar> {
  bool _isDraggingProgress = false;
  double _dragProgress = 0.0;
  double _lastVolume = 0.8;

  /// Local volume value while the slider is being dragged. Writing each
  /// `onChanged` straight to the controller rebuilt the whole player bar.
  double? _volumeDraft;

  /// 封面「展开播放器」提示的 hover 态：罩层 + 图标一起淡入淡出。
  ///
  /// 静息时封面保持全彩，不再常驻压暗 —— 与 `TrackTile` 行级 hover 显隐
  /// （`common.dart`）同一套口径。本组件只挂桌面分支（`root_shell.dart`），
  /// 触屏走 MiniPlayerBar，不存在「无 hover 设备看不到入口」的问题。
  bool _coverHovered = false;

  // Stable tear-offs so MouseRegion doesn't see new closures every rebuild.
  void _handleCoverEnter(PointerEnterEvent _) {
    if (_coverHovered) return;
    setState(() => _coverHovered = true);
  }

  void _handleCoverExit(PointerExitEvent _) {
    if (!_coverHovered || !mounted) return;
    setState(() => _coverHovered = false);
  }

  static String _formatDuration(int ms) {
    if (ms <= 0) return '00:00';
    final safe = ms < 0 ? 0 : ms;
    final d = Duration(milliseconds: safe);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = OvertoneTheme.of(context);
    final player = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final track = player.current;

    final duration = player.durationMs <= 0 ? 1 : player.durationMs;

    final isLiked =
        track != null && ref.watch(likesProvider).any((t) => t.id == track.id);

    return Container(
      height: 76,
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border(
          top: BorderSide(color: theme.divider, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            offset: const Offset(0, -3),
            blurRadius: 10,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // ---------------- 左侧：歌曲信息 ----------------
          SizedBox(
            width: 220,
            child: track == null
                ? Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: theme.surfaceElevated,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.music_note_rounded,
                          color: theme.textTertiary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('暂无播放音乐', style: theme.caption),
                    ],
                  )
                : Row(
                    children: [
                      // 封面（点击进播放器；展开提示仅 hover 浮现）
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: _handleCoverEnter,
                        onExit: _handleCoverExit,
                        child: GestureDetector(
                          onTap: () => context.push('/player'),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CoverHero(
                                tag: 'player-cover-${track.id}',
                                seed: track.coverUrl,
                                size: 50,
                                radius: 8,
                              ),
                              // 罩层 + 图标整体淡入：静息态封面全彩，
                              // 不再常驻压暗（对齐 TrackTile 行级 hover）。
                              AnimatedOpacity(
                                opacity: _coverHovered ? 1 : 0,
                                duration: const Duration(milliseconds: 140),
                                child: Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: Colors.black.withValues(
                                      alpha: 0.25,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.open_in_full_rounded,
                                    size: 16,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 歌名与歌手
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () => context.push('/player'),
                                child: Text(
                                  track.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.body.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            MouseRegion(
                              cursor: track.hasArtistId
                                  ? SystemMouseCursors.click
                                  : SystemMouseCursors.basic,
                              child: GestureDetector(
                                onTap: artistTapFor(context, track),
                                child: Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.caption.copyWith(
                                    fontSize: 12,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 播放 MV（这首歌有 MV 时露出）
                      MvEntryButton(track: track, size: 20),
                      const SizedBox(width: 8),
                      // 喜欢按钮
                      LikeButton(
                        liked: isLiked,
                        onToggle: () =>
                            ref.read(likesProvider.notifier).toggle(track),
                        size: 20,
                        activeColor: Colors.redAccent,
                        inactiveColor: theme.textTertiary,
                      ),
                    ],
                  ),
          ),

          // ---------------- 中间：控制按钮 + 进度条 ----------------
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 控制按钮栏
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 循环模式
                        _buildLoopModeButton(player, controller, theme),
                        const SizedBox(width: 8),

                        // 上一首
                        IconButton(
                          tooltip: '上一首',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed:
                              player.canStepBack ? () => controller.previous() : null,
                          icon: const Icon(Icons.skip_previous_rounded, size: 24),
                          color: player.canStepBack
                              ? theme.textPrimary
                              : theme.textTertiary,
                        ),
                        const SizedBox(width: 8),

                        // 播放 / 暂停
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.primary,
                          ),
                          child: IconButton(
                            tooltip: player.isPlaying ? '暂停' : '播放',
                            padding: EdgeInsets.zero,
                            onPressed: () => controller.togglePlay(),
                            icon: PlayPauseIcon(
                              playing: player.isPlaying,
                              size: 22,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // 下一首
                        IconButton(
                          tooltip: '下一首',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: () => controller.next(),
                          icon: const Icon(Icons.skip_next_rounded, size: 24),
                          color: theme.textPrimary,
                        ),
                        const SizedBox(width: 8),

                        // FM 不喜欢按钮（仅在 FM 播放时显示）
                        if (player.queueSource == PlaybackQueueSource.fm) ...[
                          IconButton(
                            tooltip: '不喜欢并跳过',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            onPressed: () => ref
                                .read(fmControllerProvider.notifier)
                                .dislike(),
                            icon: const Icon(Icons.thumb_down_outlined, size: 18),
                            color: theme.textSecondary,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // 进度条 — only this row tracks the live cursor.
                  SizedBox(
                    height: 18,
                    child: PlayerPositionBuilder(
                      builder: (context, positionMs) {
                        final currentPos = _isDraggingProgress
                            ? (_dragProgress * duration).round()
                            : positionMs.clamp(0, duration);
                        final progress =
                            (currentPos / duration).clamp(0.0, 1.0);
                        return Row(
                          children: [
                            Text(
                              _formatDuration(currentPos),
                              style: theme.caption.copyWith(fontSize: 11),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 5,
                                  ),
                                  overlayShape:
                                      const RoundSliderOverlayShape(
                                    overlayRadius: 10,
                                  ),
                                  activeTrackColor: theme.primary,
                                  inactiveTrackColor: theme.divider,
                                  thumbColor: theme.primary,
                                ),
                                child: Slider(
                                  value: progress,
                                  onChanged: (v) {
                                    setState(() {
                                      _isDraggingProgress = true;
                                      _dragProgress = v;
                                    });
                                  },
                                  onChangeEnd: (v) {
                                    controller.seekTo((v * duration).round());
                                    setState(() {
                                      _isDraggingProgress = false;
                                    });
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '-${_formatDuration((duration - currentPos).clamp(0, duration))}',
                              style: theme.caption.copyWith(fontSize: 11),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ---------------- 右侧：音质、音量、桌面歌词、播放列表 ----------------
          SizedBox(
            width: 260,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                // 音质标识（点击可调音质）
                if (track != null)
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => showQualitySheet(context, ref),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: QualityBadge(
                          label: player.resolvedQuality?.label ?? '标准',
                          gradient:
                              player.resolvedQuality == AppQuality.sq ||
                              player.resolvedQuality == AppQuality.hiRes,
                        ),
                      ),
                    ),
                  ),

                const SizedBox(width: 8),

                // 音量控制（含鼠标滚轮监听）
                Listener(
                  onPointerSignal: (pointerSignal) {
                    if (pointerSignal is PointerScrollEvent) {
                      final delta = pointerSignal.scrollDelta.dy;
                      final newVol =
                          (player.volume - delta * 0.0008).clamp(0.0, 1.0);
                      controller.setVolume(newVol);
                    }
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: player.volume == 0 ? '恢复音量' : '静音',
                        icon: Icon(
                          player.volume == 0
                              ? Icons.volume_off_rounded
                              : player.volume < 0.5
                                  ? Icons.volume_down_rounded
                                  : Icons.volume_up_rounded,
                          size: 20,
                          color: theme.textSecondary,
                        ),
                        onPressed: () {
                          if (player.volume > 0) {
                            _lastVolume = player.volume;
                            controller.setVolume(0);
                          } else {
                            controller.setVolume(
                                _lastVolume > 0 ? _lastVolume : 0.7);
                          }
                        },
                      ),
                      SizedBox(
                        width: 76,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 4,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 8,
                            ),
                            activeTrackColor: theme.textSecondary,
                            inactiveTrackColor: theme.divider,
                            thumbColor: theme.textPrimary,
                          ),
                          child: Slider(
                            value: _volumeDraft ?? player.volume.clamp(0.0, 1.0),
                            // Only commit on release: `onChanged` fires on every
                            // mouse move, and `setVolume` writes global state,
                            // which rebuilt the whole bar mid-drag.
                            onChanged: (v) => setState(() => _volumeDraft = v),
                            onChangeEnd: (v) {
                              setState(() => _volumeDraft = null);
                              controller.setVolume(v);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 4),

                // 桌面歌词开关（与设置页 / 托盘 / 标题栏同一状态）
                if (isDesktopPlatform)
                  _DesktopLyricToggle(theme: theme),

                const SizedBox(width: 4),

                // 播放列表
                IconButton(
                  tooltip: '播放队列',
                  onPressed: () => showQueueSheet(context, ref),
                  icon: Icon(
                    Icons.queue_music_rounded,
                    size: 22,
                    color: theme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        ],
      ),
    );
  }

  Widget _buildLoopModeButton(
    PlayerState player,
    PlayerController controller,
    OvertoneTheme theme,
  ) {
    final (icon, tip) = switch (player.mode) {
      PlayerLoopMode.listLoop => (Icons.repeat_rounded, '列表循环'),
      PlayerLoopMode.single => (Icons.repeat_one_rounded, '单曲循环'),
      PlayerLoopMode.shuffle => (Icons.shuffle_rounded, '随机播放'),
      PlayerLoopMode.order => (Icons.arrow_right_alt_rounded, '顺序播放'),
    };
    return IconButton(
      tooltip: tip,
      onPressed: () => controller.cycleMode(),
      icon: Icon(icon, size: 20, color: theme.textSecondary),
    );
  }
}

/// 底栏「桌面歌词」开关：图标高亮表示已开启，与托盘/设置/标题栏同状态。
class _DesktopLyricToggle extends ConsumerWidget {
  const _DesktopLyricToggle({required this.theme});

  final OvertoneTheme theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(
      settingsControllerProvider.select((s) => s.desktopLyricEnabled),
    );
    return IconButton(
      tooltip: enabled ? '关闭桌面歌词' : '开启桌面歌词',
      onPressed: () => DesktopLyricBridge.instance?.toggle(),
      icon: Icon(
        Icons.lyrics_outlined,
        size: 22,
        color: enabled ? theme.primary : theme.textSecondary,
      ),
    );
  }
}
