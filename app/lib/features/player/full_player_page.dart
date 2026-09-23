import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/track.dart';
import '../../core/theme/cover_palette.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../features/likes/likes_controller.dart';
import '../../features/player/player_controller.dart';
import '../../features/settings/settings_controller.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/cover_box.dart';
import '../../shared/widgets/lyrics_view.dart';
import '../../core/models/playback_source.dart';
import '../fm/fm_controller.dart';
import 'fm_controls.dart';
import '../../shared/widgets/lyric_display_sheet.dart';
import '../../shared/widgets/quality_sheet.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/responsive.dart';
import '../../shared/widgets/smooth_scroll.dart';

class FullPlayerPage extends ConsumerWidget {
  const FullPlayerPage({super.key});

  static String format(int ms) {
    final safe = ms < 0 ? 0 : ms;
    final d = Duration(milliseconds: safe);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _openLyrics(BuildContext context) => context.push('/player/lyrics');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kugo = KugoTheme.of(context);
    final player = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final track = player.current;
    if (track == null) {
      return Scaffold(
        backgroundColor: kugo.bg,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '暂无播放内容\n去搜索或歌单里点一首歌',
                    textAlign: TextAlign.center,
                    style: kugo.caption,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    // 冷启动恢复 / 未起播时也可能停在本页：歌词与播放解耦，打开即 ensure。
    controller.ensureLyricsForCurrent(retryIfEmpty: true);

    final duration = player.durationMs == 0 ? 1 : player.durationMs;
    final isDesktop = isDesktopView(context);

    if (isDesktop) {
      return Scaffold(
        backgroundColor: kugo.bg,
        body: Container(
          decoration: BoxDecoration(
            gradient: CoverPalette.playerBackground(track.coverUrl, kugo.palette),
          ),
          child: SafeArea(
            child: Row(
              children: [
                // ---------------- 左栏：封面、歌曲信息、进度与播放控制 ----------------
                SizedBox(
                  width: 440,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 顶部导航：收起、标题、详情、队列
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => context.pop(),
                              tooltip: '收起播放页',
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 30,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('正在播放', style: kugo.section),
                            const Spacer(),
                            IconButton(
                              onPressed: () => _openSongDetail(context, track),
                              tooltip: '歌曲详情',
                              icon: const Icon(Icons.info_outline_rounded, size: 20),
                            ),
                            IconButton(
                              onPressed: () => _showQueueSheet(context, ref),
                              tooltip: '播放队列',
                              icon: const Icon(Icons.queue_music_rounded, size: 20),
                            ),
                          ],
                        ),

                        const Spacer(),

                        // 大封面（Hero 落地点：从桌面底栏封面飞入）
                        CoverHero(
                          tag: 'player-cover-${track.id}',
                          seed: track.coverUrl,
                          size: 260,
                          radius: 16,
                        ),

                        const SizedBox(height: 20),

                        // 歌曲名与歌手
                        Text(
                          track.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: kugo.title.copyWith(fontSize: 20, height: 1.2),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${track.artist} · ${track.album}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: kugo.caption.copyWith(fontSize: 13),
                        ),

                        const SizedBox(height: 10),
                        _PlayerQualityChip(track: track),

                        const Spacer(),

                        // 进度滑块 — only this block tracks the live cursor.
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: PlayerPositionBuilder(
                            builder: (context, positionMs) {
                              final progress =
                                  (positionMs / duration).clamp(0.0, 1.0);
                              return Column(
                                children: [
                                  SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 3,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                                    ),
                                    child: Slider(
                                      value: progress,
                                      onChanged: (v) =>
                                          controller.seekTo((v * duration).round()),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          FullPlayerPage.format(positionMs),
                                          style: kugo.caption.copyWith(fontSize: 11),
                                        ),
                                        Text(
                                          '-${FullPlayerPage.format(duration - positionMs)}',
                                          style: kugo.caption.copyWith(fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 12),

                        // 控制按钮栏
                        _ControlBar(
                          player: player,
                          controller: controller,
                          track: track,
                          compact: false,
                          height: 64,
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),

                // 分割线
                VerticalDivider(width: 1, color: kugo.divider.withValues(alpha: 0.5)),

                // ---------------- 右栏：完整平滑滚动歌词 ----------------
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '歌词',
                              style: kugo.section.copyWith(
                                color: kugo.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            if (ref.watch(fmControllerProvider).active)
                              const FmEntryPill(),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: PlayerPositionBuilder(
                            builder: (context, positionMs) => LyricsView(
                              lines: player.lyrics,
                              positionMs: positionMs,
                              status: player.lyricsStatus,
                              onTapLine: (ms) => controller.seekTo(ms),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      // Solid page bg avoids Material/Zoom settle flash-through.
      backgroundColor: kugo.bg,
      body: Container(
        decoration: BoxDecoration(
          gradient: CoverPalette.playerBackground(track.coverUrl, kugo.palette),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _TopBar(
                expanded: false,
                track: track,
                onCollapsePage: () => context.pop(),
                onCollapseLyrics: () => context.pop(),
                onSongDetail: () => _openSongDetail(context, track),
                onQueue: () => _showQueueSheet(context, ref),
              ),
              // FM 会话进行中：紧凑入口（原「私人 FM」页撤掉后的唯一常驻痕迹）。
              if (ref.watch(fmControllerProvider).active) const FmEntryPill(),
              Expanded(
                child: _CollapsedPlayerBody(
                  key: const ValueKey('player-collapsed'),
                  // Route Hero: large cover ↔ lyrics header / mini player.
                  useHero: true,
                  track: track,
                  player: player,
                  controller: controller,
                  duration: duration,
                  onExpandLyrics: () => _openLyrics(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSongDetail(BuildContext context, Track track) {
    final q = <String, String>{
      'id': track.id,
      'name': track.name,
      'artist': track.artist,
      'album': track.album,
      'cover': track.coverUrl,
      'hash': track.hash,
      'mixSongId': track.mixSongId,
      'duration': '${track.durationMs}',
    };
    final qs = q.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    context.push('/song?$qs');
  }

  void _showQueueSheet(BuildContext context, WidgetRef ref) {
    final kugo = KugoTheme.of(context);
    final player = ref.read(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    showKugoBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: kugo.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '播放队列 · ${player.queue.length} 首',
              style: kugo.section.copyWith(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SmoothListViewBuilder(
                shrinkWrap: true,
                itemCount: player.queue.length,
                itemBuilder: (context, index) {
                  final track = player.queue[index];
                  final isCurrent = index == player.currentIndex;
                  return ListTile(
                    title: Text(
                      track.name,
                      style: kugo.body.copyWith(
                        color: isCurrent
                            ? kugo.primary
                            : kugo.textPrimary,
                      ),
                    ),
                    subtitle:
                        Text(track.artist, style: kugo.caption),
                    trailing: isCurrent
                        ? Icon(
                            Icons.equalizer_rounded,
                            color: kugo.primary,
                            size: 18,
                          )
                        : null,
                    onTap: () {
                      controller.playQueue(player.queue, startIndex: index);
                      Navigator.of(sheetContext).pop();
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Full lyrics as its own route: Hero flies cover large → header, and the
/// page uses center scale + fade (see `/player/lyrics` in app.dart).
class PlayerLyricsPage extends ConsumerWidget {
  const PlayerLyricsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kugo = KugoTheme.of(context);
    final player = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final track = player.current;

    if (track == null) {
      return Scaffold(
        backgroundColor: kugo.bg,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '暂无播放内容',
                    style: kugo.caption,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    controller.ensureLyricsForCurrent(retryIfEmpty: true);

    final duration = player.durationMs == 0 ? 1 : player.durationMs;

    return Scaffold(
      backgroundColor: kugo.bg,
      body: Container(
        decoration: BoxDecoration(
          gradient: CoverPalette.playerBackground(track.coverUrl, kugo.palette),
        ),
        child: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onVerticalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v > 240 && context.canPop()) context.pop();
            },
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    KugoSpacing.sm,
                    KugoSpacing.sm,
                    KugoSpacing.xl,
                    4,
                  ),
                  child: SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => context.pop(),
                          tooltip: '收起歌词',
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 32,
                          ),
                        ),
                        // Hero destination: mini cover in lyrics header.
                        CoverHero(
                          tag: 'player-cover-${track.id}',
                          seed: track.coverUrl,
                          size: 44,
                          radius: 8,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: kugo.body.copyWith(
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                ),
                              ),
                              Text(
                                '${track.artist} · ${track.album}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: kugo.caption.copyWith(
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _PlayerQualityChip(track: track),
                      ],
                    ),
                  ),
                ),
                if (player.display == PlayerDisplayState.error)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      KugoSpacing.xl,
                      4,
                      KugoSpacing.xl,
                      0,
                    ),
                    child: Text(
                      player.errorCode.isEmpty
                          ? '播放失败，可点下一首重试'
                          : player.errorCode,
                      textAlign: TextAlign.center,
                      style: kugo.caption.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Expanded(
                  child: PlayerPositionBuilder(
                    builder: (context, positionMs) => LyricsView(
                      lines: player.lyrics,
                      positionMs: positionMs,
                      status: player.lyricsStatus,
                      onTapLine: (ms) => controller.seekTo(ms),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    KugoSpacing.lg,
                    4,
                    KugoSpacing.lg,
                    20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PlayerPositionBuilder(
                        builder: (context, positionMs) {
                          final progress =
                              (positionMs / duration).clamp(0.0, 1.0);
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                height: 48,
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 5,
                                    ),
                                    overlayShape: const RoundSliderOverlayShape(
                                      overlayRadius: 10,
                                    ),
                                  ),
                                  child: Slider(
                                    value: progress,
                                    onChanged: (v) => controller
                                        .seekTo((v * duration).round()),
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: 22,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        FullPlayerPage.format(positionMs),
                                        style: kugo.caption
                                            .copyWith(height: 1.2),
                                      ),
                                      Text(
                                        '-${FullPlayerPage.format((duration - positionMs).clamp(0, duration))}',
                                        style: kugo.caption
                                            .copyWith(height: 1.2),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      _ControlBar(
                        player: player,
                        controller: controller,
                        track: track,
                        compact: true,
                        height: 60,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.expanded,
    required this.track,
    required this.onCollapsePage,
    required this.onCollapseLyrics,
    required this.onSongDetail,
    required this.onQueue,
  });

  final bool expanded;
  final Track track;
  final VoidCallback onCollapsePage;
  final VoidCallback onCollapseLyrics;
  final VoidCallback onSongDetail;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final title = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: expanded
          ? Column(
              key: const ValueKey('expanded-title'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: kugo.section,
                ),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: kugo.caption,
                ),
              ],
            )
          : Text(
              key: const ValueKey('playing-title'),
              '正在播放',
              textAlign: TextAlign.center,
              style: kugo.section,
            ),
    );

    // Stack keeps the title on the true screen center: left has 1 action,
    // right has 2 — an Expanded between unequal side widths would shift left.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: SizedBox(
        height: 56,
        child: Stack(
          children: [
            Center(child: title),
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: expanded ? onCollapseLyrics : onCollapsePage,
                tooltip: expanded ? '收起歌词' : '返回',
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 32,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: onSongDetail,
                    tooltip: '歌曲详情',
                    icon: const Icon(Icons.info_outline_rounded),
                  ),
                  IconButton(
                    onPressed: onQueue,
                    icon: const Icon(Icons.queue_music_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerCoverSlot extends StatelessWidget {
  const _PlayerCoverSlot({
    required this.tag,
    required this.seed,
    required this.size,
    required this.radius,
    required this.useHero,
  });

  final String tag;
  final String seed;
  final double size;
  final double radius;

  /// Route Hero only on settled frames — avoids duplicate tags mid-FX.
  final bool useHero;

  @override
  Widget build(BuildContext context) {
    if (!useHero) {
      return CoverBox(seed: seed, size: size, radius: radius);
    }
    return CoverHero(
      tag: tag,
      seed: seed,
      size: size,
      radius: radius,
    );
  }
}

class _CollapsedPlayerBody extends StatelessWidget {
  const _CollapsedPlayerBody({
    super.key,
    required this.track,
    required this.player,
    required this.controller,
    required this.duration,
    required this.onExpandLyrics,
    this.useHero = true,
  });

  final Track track;
  final PlayerState player;
  final PlayerController controller;
  final int duration;
  final VoidCallback onExpandLyrics;
  final bool useHero;

  static String format(int ms) {
    final safe = ms < 0 ? 0 : ms;
    final d = Duration(milliseconds: safe);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final bodyH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        final showError = player.display == PlayerDisplayState.error;
        // Bottom chrome (meta / progress / controls) stays pinned.
        const metaH = 56.0;
        const sliderH = 48.0;
        const timeH = 22.0;
        const controlsH = 64.0;
        const padTop = KugoSpacing.sm;
        const padBottom = 20.0;
        final bottomH = padTop +
            metaH +
            (showError ? 56 : 0) +
            sliderH +
            timeH +
            controlsH +
            padBottom;
        final upperH = (bodyH - bottomH).clamp(120.0, bodyH);
        // Lyrics sit directly under the cover; split remaining upper space.
        final coverH = (upperH * 0.62).clamp(72.0, upperH - 48);
        final lyricsH = upperH - coverH;

        Widget lyrics() {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onExpandLyrics,
            onVerticalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -200) onExpandLyrics();
            },
            child: ClipRect(
              child: PlayerPositionBuilder(
                builder: (context, positionMs) => LyricsView(
                  compact: true,
                  lines: player.lyrics,
                  positionMs: positionMs,
                  status: player.lyricsStatus,
                ),
              ),
            ),
          );
        }

        return Column(
          children: [
            // 1) Album cover
            SizedBox(
              height: coverH,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(KugoRadius.card + 4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 28,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: _PlayerCoverSlot(
                        tag: 'player-cover-${track.id}',
                        seed: track.coverUrl,
                        size: 0,
                        radius: KugoRadius.card + 4,
                        useHero: useHero,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 2) Lyrics — right under the cover
            SizedBox(
              height: lyricsH,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: KugoSpacing.lg),
                child: lyrics(),
              ),
            ),
            // 3) Track meta + progress + controls
            SizedBox(
              height: bottomH,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  KugoSpacing.lg,
                  padTop,
                  KugoSpacing.lg,
                  padBottom,
                ),
                child: Column(
                  children: [
                    _TrackMetaRow(track: track, height: metaH),
                    if (showError)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: SizedBox(
                          height: 48,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.centerLeft,
                            child: Text(
                              player.errorCode.isEmpty
                                  ? '播放失败，可点下一首重试'
                                  : player.errorCode,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: kugo.caption.copyWith(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 12,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ),
                      ),
                    SizedBox(
                      height: sliderH + timeH,
                      child: PlayerPositionBuilder(
                        builder: (context, positionMs) {
                          final progress =
                              (positionMs / duration).clamp(0.0, 1.0);
                          return Column(
                            children: [
                              SizedBox(
                                height: sliderH,
                                child: Center(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 3,
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 6,
                                      ),
                                      overlayShape: const RoundSliderOverlayShape(
                                        overlayRadius: 10,
                                      ),
                                      trackShape: const RoundedRectSliderTrackShape(),
                                    ),
                                    child: Slider(
                                      value: progress,
                                      onChanged: (v) => controller
                                          .seekTo((v * duration).round()),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: timeH,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        format(positionMs),
                                        style: kugo.caption.copyWith(
                                          height: 1.2,
                                        ),
                                      ),
                                      Text(
                                        '-${format(duration - positionMs)}',
                                        style: kugo.caption.copyWith(
                                          height: 1.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    _ControlBar(
                      player: player,
                      controller: controller,
                      track: track,
                      compact: false,
                      height: controlsH,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TrackMetaRow extends StatelessWidget {
  const _TrackMetaRow({required this.track, required this.height});

  final Track track;
  final double height;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return SizedBox(
      height: height,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: child,
        ),
        child: SizedBox(
          key: ValueKey(track.id),
          height: height,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kugo.playerTitle.copyWith(
                        fontSize: 20,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${track.artist} · ${track.album}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kugo.caption.copyWith(height: 1.2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _PlayerQualityChip(track: track),
            ],
          ),
        ),
      ),
    );
  }
}

/// 播放页音质区域：VIP 与实际音质并排展示；音质 chip 可点切换。
class _PlayerQualityChip extends ConsumerWidget {
  const _PlayerQualityChip({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kugo = KugoTheme.of(context);
    final player = ref.watch(playerControllerProvider);
    final preferred = ref.watch(settingsControllerProvider).quality;
    final resolved = player.resolvedQuality;
    final quality = resolved ?? preferred;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (track.isVip) ...[
          const QualityBadge(label: 'VIP', gradient: true),
          const SizedBox(width: 4),
        ],
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => showQualitySheet(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                QualityBadge(
                  label: quality.badge,
                  gradient: quality == AppQuality.sq ||
                      quality == AppQuality.hiRes,
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.unfold_more_rounded,
                  size: 12,
                  color: kugo.textSecondary,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        const LyricDisplayButton(),
      ],
    );
  }
}

class _ControlBar extends ConsumerWidget {
  const _ControlBar({
    required this.player,
    required this.controller,
    required this.track,
    required this.compact,
    this.height,
  });

  final PlayerState player;
  final PlayerController controller;
  final Track track;
  final bool compact;
  final double? height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kugo = KugoTheme.of(context);
    // Always bind the live player state so the play/pause icon cannot go stale.
    final live = ref.watch(playerControllerProvider);
    final liked = ref.watch(likesProvider).any((t) => t.id == track.id);
    final barH = height ?? (compact ? 56.0 : 64.0);
    final playSize = compact ? 50.0 : 56.0;
    final isPlaying = live.isPlaying;
    final isLoading = live.isLoading;

    return SizedBox(
      height: barH,
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // FM 会话：循环/随机对"流"没有意义，这个位置换成 FM 原生的「不喜欢」。
            if (live.queueSource == PlaybackQueueSource.fm)
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                onPressed: () => ref.read(fmControllerProvider.notifier).dislike(),
                tooltip: '不喜欢，换下一首',
                icon: const Icon(
                  Icons.thumb_down_alt_rounded,
                  color: Color(0xFFE87A90),
                  size: 22,
                ),
              )
            else
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                onPressed: controller.cycleMode,
                tooltip: _modeLabel(live.mode),
                icon: Icon(
                  switch (live.mode) {
                    PlayerLoopMode.order => Icons.trending_flat_rounded,
                    PlayerLoopMode.listLoop => Icons.repeat_rounded,
                    PlayerLoopMode.shuffle => Icons.shuffle_rounded,
                    PlayerLoopMode.single => Icons.repeat_one_rounded,
                  },
                  color: kugo.textSecondary,
                  size: 22,
                ),
              ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              // FM 只能池内回退：退到会话第一首就禁用，绝不环绕到队列尾部。
              onPressed: live.canStepBack ? controller.previous : null,
              tooltip: live.canStepBack ? '上一首' : '已经是私人 FM 的第一首',
              icon: Icon(
                Icons.skip_previous_rounded,
                size: 32,
                color: live.canStepBack ? kugo.textPrimary : kugo.textTertiary,
              ),
            ),
            Container(
              width: playSize,
              height: playSize,
              decoration: BoxDecoration(
                gradient: kugo.accentGradient,
                shape: BoxShape.circle,
              ),
              child: isLoading
                  ? Padding(
                      padding: EdgeInsets.all(playSize * 0.28),
                      child: const CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: controller.togglePlay,
                      icon: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: compact ? 28 : 32,
                        color: Colors.white,
                      ),
                    ),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: controller.next,
              icon: Icon(
                Icons.skip_next_rounded,
                size: 32,
                color: kugo.textPrimary,
              ),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: () {
                ref.read(likesProvider.notifier).toggle(track);
              },
              icon: Icon(
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color:
                    liked ? const Color(0xFFE87A90) : kugo.textSecondary,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _modeLabel(PlayerLoopMode mode) => switch (mode) {
        PlayerLoopMode.order => '顺序播放',
        PlayerLoopMode.listLoop => '列表循环',
        PlayerLoopMode.shuffle => '随机播放',
        PlayerLoopMode.single => '单曲循环',
      };
}
