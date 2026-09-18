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
import '../../shared/widgets/quality_sheet.dart';

class FullPlayerPage extends ConsumerStatefulWidget {
  const FullPlayerPage({super.key});

  @override
  ConsumerState<FullPlayerPage> createState() => _FullPlayerPageState();
}

class _FullPlayerPageState extends ConsumerState<FullPlayerPage>
    with SingleTickerProviderStateMixin {
  bool _lyricsExpanded = false;
  late final AnimationController _fx;

  @override
  void initState() {
    super.initState();
    _fx = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      reverseDuration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _fx.dispose();
    super.dispose();
  }

  void _expandLyrics() {
    if (_lyricsExpanded) return;
    setState(() => _lyricsExpanded = true);
    _fx.forward(from: 0);
  }

  void _collapseLyrics() {
    if (!_lyricsExpanded) return;
    setState(() => _lyricsExpanded = false);
    _fx.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final track = player.current;
    if (track == null) {
      return Scaffold(
        backgroundColor: KugoColors.bg,
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
                    style: KugoTypography.caption,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final duration = player.durationMs == 0 ? 1 : player.durationMs;
    final progress = (player.positionMs / duration).clamp(0.0, 1.0);
    final expanded = _lyricsExpanded;
    final palette = CoverPalette.fromSeed(track.coverUrl);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: CoverPalette.playerBackground(track.coverUrl),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _TopBar(
                expanded: expanded,
                track: track,
                onCollapsePage: () => context.pop(),
                onCollapseLyrics: _collapseLyrics,
                onSongDetail: () => _openSongDetail(context, track),
                onQueue: () => _showQueueSheet(context, ref),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, bodyConstraints) {
                    final rawH = bodyConstraints.maxHeight;
                    final rawW = bodyConstraints.maxWidth;
                    final bodyH =
                        rawH.isFinite && rawH > 0 ? rawH : double.nan;
                    final bodyW =
                        rawW.isFinite && rawW > 0 ? rawW : double.nan;

                    return AnimatedBuilder(
                      animation: _fx,
                      builder: (context, _) {
                        final t = _fx.value;
                        // Settled states: paint the plain body only — no
                        // ImageFiltered/BackdropFilter (those can gray-out
                        // the whole player on some devices/release builds).
                        if (t < 0.02) {
                          return _CollapsedPlayerBody(
                            key: const ValueKey('player-collapsed'),
                            track: track,
                            player: player,
                            controller: controller,
                            progress: progress,
                            duration: duration,
                            onExpandLyrics: _expandLyrics,
                          );
                        }
                        if (t > 0.98 && _lyricsExpanded) {
                          return _ExpandedLyricsBody(
                            key: const ValueKey('lyrics-expanded'),
                            track: track,
                            player: player,
                            controller: controller,
                            progress: progress,
                            duration: duration,
                            onSwipeDown: _collapseLyrics,
                          );
                        }

                        // Mid-transition FX only.
                        final ease = Curves.easeOutCubic.transform(t);
                        final collapsedOpacity =
                            (1.0 - t * 1.45).clamp(0.0, 1.0);
                        final h = bodyH.isNaN ? 640.0 : bodyH;
                        final w = bodyW.isNaN ? 360.0 : bodyW;
                        final revealH = h * (0.22 + 0.78 * ease);
                        final expandedOpacity =
                            (0.25 + 0.75 * ease).clamp(0.0, 1.0);
                        final blurT = t < 0.5
                            ? Curves.easeOut.transform(t / 0.5)
                            : (1.0 - (t - 0.5) / 0.5).clamp(0.0, 1.0);

                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            if (collapsedOpacity > 0.02)
                              Opacity(
                                opacity: collapsedOpacity,
                                child: Transform.scale(
                                  scale: 1.0 - 0.35 * ease,
                                  alignment: Alignment.topCenter,
                                  child: Transform.translate(
                                    offset: Offset(0, -h * 0.1 * ease),
                                    child: _CollapsedPlayerBody(
                                      key: const ValueKey(
                                        'player-collapsed',
                                      ),
                                      track: track,
                                      player: player,
                                      controller: controller,
                                      progress: progress,
                                      duration: duration,
                                      onExpandLyrics: _expandLyrics,
                                    ),
                                  ),
                                ),
                              ),
                            if (expandedOpacity > 0.02)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                height: revealH,
                                child: Opacity(
                                  opacity: expandedOpacity,
                                  child: ClipRect(
                                    child: OverflowBox(
                                      alignment: Alignment.bottomCenter,
                                      minWidth: w,
                                      maxWidth: w,
                                      minHeight: h,
                                      maxHeight: h,
                                      child: SizedBox(
                                        width: w,
                                        height: h,
                                        child: Transform.translate(
                                          offset: Offset(0, 12 * (1 - ease)),
                                          child: _ExpandedLyricsBody(
                                            key: const ValueKey(
                                              'lyrics-expanded',
                                            ),
                                            track: track,
                                            player: player,
                                            controller: controller,
                                            progress: progress,
                                            duration: duration,
                                            onSwipeDown: _collapseLyrics,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (blurT > 0.05)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          palette[0].withValues(
                                            alpha: 0.12 * blurT,
                                          ),
                                          Colors.black.withValues(
                                            alpha: 0.18 * blurT,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
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
                color: KugoColors.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '播放队列 · ${player.queue.length} 首',
              style: KugoTypography.section.copyWith(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: player.queue.length,
                itemBuilder: (context, index) {
                  final track = player.queue[index];
                  final isCurrent = index == player.currentIndex;
                  return ListTile(
                    title: Text(
                      track.name,
                      style: KugoTypography.body.copyWith(
                        color: isCurrent
                            ? KugoColors.primary
                            : KugoColors.textPrimary,
                      ),
                    ),
                    subtitle:
                        Text(track.artist, style: KugoTypography.caption),
                    trailing: isCurrent
                        ? Icon(
                            Icons.equalizer_rounded,
                            color: KugoColors.primary,
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
                  style: KugoTypography.section,
                ),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: KugoTypography.caption,
                ),
              ],
            )
          : Text(
              key: const ValueKey('playing-title'),
              '正在播放',
              textAlign: TextAlign.center,
              style: KugoTypography.section,
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

class _CollapsedPlayerBody extends StatelessWidget {
  const _CollapsedPlayerBody({
    super.key,
    required this.track,
    required this.player,
    required this.controller,
    required this.progress,
    required this.duration,
    required this.onExpandLyrics,
  });

  final Track track;
  final PlayerState player;
  final PlayerController controller;
  final double progress;
  final int duration;
  final VoidCallback onExpandLyrics;

  static String format(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
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
              child: LyricsView(
                compact: true,
                lines: player.lyrics,
                positionMs: player.positionMs,
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
                      child: Hero(
                        tag: 'player-cover-${track.id}',
                        child: CoverBox(
                          seed: track.coverUrl,
                          size: 0,
                          radius: KugoRadius.card + 4,
                        ),
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
                              style: KugoTypography.caption.copyWith(
                                color: const Color(0xFFFF8A9A),
                                fontSize: 12,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ),
                      ),
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
                            onChanged: (v) =>
                                controller.seekTo((v * duration).round()),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: timeH,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              format(player.positionMs),
                              style: KugoTypography.caption.copyWith(
                                height: 1.2,
                              ),
                            ),
                            Text(
                              '-${format(duration - player.positionMs)}',
                              style: KugoTypography.caption.copyWith(
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
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
                      style: KugoTypography.playerTitle.copyWith(
                        fontSize: 20,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${track.artist} · ${track.album}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KugoTypography.caption.copyWith(height: 1.2),
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

/// 播放页可点音质徽章：显示实际解析音质，点击打开切换 sheet。
class _PlayerQualityChip extends ConsumerWidget {
  const _PlayerQualityChip({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerControllerProvider);
    final preferred = ref.watch(settingsControllerProvider).quality;
    final resolved = player.resolvedQuality;
    final display =
        track.isVip ? 'VIP' : (resolved ?? preferred).badge;

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => showQualitySheet(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            QualityBadge(
              label: display,
              gradient: track.isVip,
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.unfold_more_rounded,
              size: 12,
              color: KugoColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpandedLyricsBody extends ConsumerWidget {
  const _ExpandedLyricsBody({
    super.key,
    required this.track,
    required this.player,
    required this.controller,
    required this.progress,
    required this.duration,
    required this.onSwipeDown,
  });

  final Track track;
  final PlayerState player;
  final PlayerController controller;
  final double progress;
  final int duration;
  final VoidCallback onSwipeDown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onVerticalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v > 240) onSwipeDown();
      },
      child: Column(
        children: [
          // Compact header: small cover + quality
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KugoSpacing.xl,
              KugoSpacing.sm,
              KugoSpacing.xl,
              4,
            ),
            child: SizedBox(
              height: 48,
              child: Row(
                children: [
                  Hero(
                    tag: 'player-cover-${track.id}',
                    child: CoverBox(
                      seed: track.coverUrl,
                      size: 44,
                      radius: 8,
                    ),
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
                          style: KugoTypography.body.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                        Text(
                          '${track.artist} · ${track.album}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: KugoTypography.caption.copyWith(height: 1.2),
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: KugoTypography.caption.copyWith(
                  color: const Color(0xFFFF8A9A),
                ),
              ),
            ),
          // Full lyrics
          Expanded(
            child: LyricsView(
              lines: player.lyrics,
              positionMs: player.positionMs,
              onTapLine: (ms) => controller.seekTo(ms),
            ),
          ),
          // Mini transport
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
                      onChanged: (v) =>
                          controller.seekTo((v * duration).round()),
                    ),
                  ),
                ),
                SizedBox(
                  height: 22,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _CollapsedPlayerBody.format(player.positionMs),
                          style: KugoTypography.caption.copyWith(height: 1.2),
                        ),
                        Text(
                          '-${_CollapsedPlayerBody.format(duration - player.positionMs)}',
                          style: KugoTypography.caption.copyWith(height: 1.2),
                        ),
                      ],
                    ),
                  ),
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
                color: KugoColors.textSecondary,
                size: 22,
              ),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: controller.previous,
              icon: Icon(
                Icons.skip_previous_rounded,
                size: 32,
                color: KugoColors.textPrimary,
              ),
            ),
            Container(
              width: playSize,
              height: playSize,
              decoration: BoxDecoration(
                gradient: KugoColors.accentGradient,
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
                color: KugoColors.textPrimary,
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
                    liked ? const Color(0xFFE87A90) : KugoColors.textSecondary,
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
