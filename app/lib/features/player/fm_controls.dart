import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/fm_mode.dart';
import '../../core/models/track.dart';
import '../../core/platform.dart';
import '../../core/theme/cover_palette.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../core/theme/responsive.dart';
import '../../shared/widgets/cover_box.dart';
import '../fm/fm_controller.dart';
import '../fm/fm_radio_card.dart';
import '../player/player_controller.dart';

/// 播放页上的 FM 紧凑入口：一行药丸，点开 [showFmSheet]。
///
/// 它是「入口」而不是「卡片本身」：卡片在面板里（见 [_FmSheet]），
/// 药丸只负责在播放页留一个不挡歌词、不抢封面的痕迹（高约 36px）。
class FmEntryPill extends ConsumerWidget {
  const FmEntryPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kugo = KugoTheme.of(context);
    final fm = ref.watch(fmControllerProvider);
    final player = ref.watch(playerControllerProvider);
    final accent = CoverPalette.accentFromSeed(
      player.current?.coverUrl ?? 'fm',
      kugo.palette,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KugoSpacing.lg,
        0,
        KugoSpacing.lg,
        KugoSpacing.sm,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          button: true,
          label: '私人 FM 电台：${fm.pendingMode.stationTitle} · ${fm.pendingPool.label}',
          child: InkWell(
            borderRadius: BorderRadius.circular(KugoRadius.chip),
            onTap: () => showFmSheet(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: kugo.surface.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(KugoRadius.chip),
                border: Border.all(color: accent.withValues(alpha: 0.45)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.radio_rounded, size: 14, color: accent),
                  const SizedBox(width: 6),
                  Text(
                    '${fm.pendingMode.stationTitle} · ${fm.pendingPool.label}',
                    style: kugo.caption.copyWith(
                      color: kugo.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  // 有待生效的轴时给个小圆点，否则用户不知道切了没生效。
                  if (fm.hasPendingChange) ...[
                    const SizedBox(width: 6),
                    Container(
                      key: const ValueKey('fm_pending_dot'),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 16,
                    color: kugo.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// FM 控制面板：自定义转场（上滑 + 淡入）+ 可拖拽展开。
///
/// 用 `showGeneralDialog` 而不是 `showModalBottomSheet`，才能自己控制转场曲线；
/// 里面套 `DraggableScrollableSheet`，可以下拉收回、上拉接近全屏。
///
/// 面板内容就是原来 FM 页的那一套视觉：渐变底 + 电台卡（档位胶囊 / 台名 /
/// 频谱 / 播放键）+ 黑胶台 + 信息行 + 三个圆钮，歌池轴回到右上角胶囊。
Future<void> showFmSheet(BuildContext context) {
  final isDesktop = isDesktopPlatform && isDesktopView(context);
  if (isDesktop) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭私人 FM 面板',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => const _FmSheet(isDesktop: true),
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭私人 FM 面板',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, _, _) => const _FmSheet(),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.12),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _FmSheet extends ConsumerStatefulWidget {
  const _FmSheet({this.isDesktop = false});

  final bool isDesktop;

  @override
  ConsumerState<_FmSheet> createState() => _FmSheetState();
}

class _FmSheetState extends ConsumerState<_FmSheet>
    with TickerProviderStateMixin {
  /// 黑胶转速（18s 一圈，与 FM 页一致）。
  late final AnimationController _spin;
  /// 10 根频谱条的跳动源（1100ms 一轮）。
  late final AnimationController _bars;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
    _bars = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    _bars.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final fm = ref.watch(fmControllerProvider);
    final player = ref.watch(playerControllerProvider);
    final fmCtl = ref.read(fmControllerProvider.notifier);
    final playerCtl = ref.read(playerControllerProvider.notifier);
    final current = player.current;
    final accent = CoverPalette.accentFromSeed(
      current?.coverUrl ?? 'fm',
      kugo.palette,
    );

    final slivers = [
      if (!widget.isDesktop) SliverToBoxAdapter(child: _grabber(kugo)),
      if (widget.isDesktop) const SliverToBoxAdapter(child: SizedBox(height: 16)),
      SliverToBoxAdapter(child: _header(context, kugo, fm, fmCtl)),
      if (fm.hasPendingChange)
        SliverToBoxAdapter(child: _pendingBar(kugo, fm, fmCtl)),
      SliverToBoxAdapter(
        child: FmRadioCard(
          kugo: kugo,
          accent: accent,
          mode: fm.pendingMode,
          pool: fm.pendingPool,
          onMode: fmCtl.setPendingMode,
          onPlay: playerCtl.togglePlay,
          isPlaying: player.isPlaying,
          bars: _bars,
          trackName: current?.name ?? '',
          artist: current?.artist ?? '',
          loading: fm.loading,
        ),
      ),
      const SliverToBoxAdapter(
        child: SizedBox(height: KugoSpacing.lg),
      ),
      SliverToBoxAdapter(
        child: FmVinylStage(
          kugo: kugo,
          accent: accent,
          spin: _spin,
          coverUrl: current?.coverUrl ?? 'fm',
          playing: player.isPlaying,
          upcoming: _sideDiscs(player),
          onPick: (t) {
            final i = player.queue.indexWhere((e) => e.id == t.id);
            if (i >= 0) playerCtl.playAtIndex(i);
          },
          onTapCurrent: playerCtl.togglePlay,
        ),
      ),
      SliverToBoxAdapter(
        child: _nowPlaying(kugo, current),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KugoSpacing.lg,
          ),
          child: FmSourceBadge(
            kugo: kugo,
            fromServer: fm.fromServer,
            gatewayError: fm.gatewayError,
            pool: fm.pool,
            mode: fm.mode,
          ),
        ),
      ),
      const SliverToBoxAdapter(
        child: SizedBox(height: KugoSpacing.lg),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KugoSpacing.lg,
          ),
          child: FmActionRow(
            kugo: kugo,
            accent: accent,
            isPlaying: player.isPlaying,
            onDislike: fmCtl.dislike,
            onToggle: playerCtl.togglePlay,
            onLike: () async {
              await fmCtl.like();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已加入我喜欢'),
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
          ),
        ),
      ),
      const SliverToBoxAdapter(
        child: SizedBox(height: KugoSpacing.md),
      ),
      SliverToBoxAdapter(child: _upcomingHeader(kugo, fm, player)),
      _upcomingList(kugo, player, playerCtl),
      const SliverToBoxAdapter(
        child: SizedBox(height: KugoSpacing.xxl),
      ),
    ];

    if (widget.isDesktop) {
      return Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: Colors.transparent,
          elevation: 16,
          shape: Border(left: BorderSide(color: kugo.divider, width: 1)),
          child: SizedBox(
            width: 440,
            height: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: CoverPalette.playerBackground(
                  current?.coverUrl ?? 'fm',
                  kugo.palette,
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: SafeArea(
                      child: CustomScrollView(
                        slivers: slivers,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20, color: Colors.white70),
                      tooltip: '关闭',
                      splashRadius: 18,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: DraggableScrollableSheet(
        initialChildSize: 0.82,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          // 面板底色交给 Material 而不是 Container 的 decoration：
          // 里面是 ListTile，中间夹一层带背景的 DecoratedBox 会让它
          // 自己的背景和水波纹被盖住（框架会直接断言报错）。
          return Material(
            clipBehavior: Clip.antiAlias,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: CoverPalette.playerBackground(
                  current?.coverUrl ?? 'fm',
                  kugo.palette,
                ),
              ),
              child: CustomScrollView(
                controller: scrollController,
                slivers: slivers,
              ),
            ),
          );
        },
      ),
    );
  }

  /// 黑胶台两侧最多 3 张待播盘（原来 FM 页的唱片堆）。
  List<Track> _sideDiscs(PlayerState player) {
    final from = player.currentIndex + 1;
    if (player.queue.length <= from) return const [];
    final to = math.min(from + 3, player.queue.length);
    return player.queue.sublist(from, to);
  }

  Widget _grabber(KugoTheme kugo) => Center(
        child: Container(
          margin: const EdgeInsets.only(
            top: KugoSpacing.sm,
            bottom: KugoSpacing.xs,
          ),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: kugo.textTertiary.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  /// 面板抬头：标题居中 + 右上角歌池轴胶囊（与原 FM 页位置一致）+ 关闭。
  Widget _header(
    BuildContext context,
    KugoTheme kugo,
    FmSession fm,
    FmController fmCtl,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KugoSpacing.sm),
      child: Row(
        children: [
          IconButton(
            tooltip: '收起',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
          ),
          Expanded(
            child: Text(
              '私人 FM',
              textAlign: TextAlign.center,
              style: kugo.section,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: KugoSpacing.xs),
            child: FmCapsuleSwitch<FmSongPool>(
              kugo: kugo,
              values: FmSongPool.values,
              labelOf: (p) => p.label,
              selected: fm.pendingPool,
              onChanged: fmCtl.setPendingPool,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }

  /// 曲名 / 歌手（黑胶下方，与 FM 页一致）。
  Widget _nowPlaying(KugoTheme kugo, Track? track) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KugoSpacing.xxl),
      child: Column(
        children: [
          Text(
            track?.name ?? '',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: kugo.playerTitle,
          ),
          const SizedBox(height: 6),
          Text(track?.artist ?? '', style: kugo.caption),
          const SizedBox(height: KugoSpacing.md),
          FmInfoChips(kugo: kugo, track: track),
        ],
      ),
    );
  }

  /// 轴切了但还没生效时的提示条：说清「下一首生效」并给一键立即生效。
  Widget _pendingBar(KugoTheme kugo, FmSession fm, FmController fmCtl) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KugoSpacing.lg,
        KugoSpacing.sm,
        KugoSpacing.lg,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '已切到 ${fm.pendingMode.label} · ${fm.pendingPool.label}，下一首生效',
              style: kugo.caption.copyWith(color: kugo.primary, fontSize: 11),
            ),
          ),
          TextButton(
            onPressed: fmCtl.applyPendingNow,
            child: const Text('立即生效'),
          ),
        ],
      ),
    );
  }

  Widget _upcomingHeader(KugoTheme kugo, FmSession fm, PlayerState player) {
    final left = player.queue.isEmpty
        ? 0
        : player.queue.length - player.currentIndex - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KugoSpacing.lg,
        KugoSpacing.sm,
        KugoSpacing.lg,
        KugoSpacing.xs,
      ),
      child: Row(
        children: [
          Text('接下来', style: kugo.section),
          const SizedBox(width: KugoSpacing.sm),
          Expanded(
            child: Text(
              fm.appending ? '正在续接歌池…' : '$left 首待播',
              style: kugo.caption,
            ),
          ),
        ],
      ),
    );
  }

  Widget _upcomingList(
    KugoTheme kugo,
    PlayerState player,
    PlayerController playerCtl,
  ) {
    final from = player.currentIndex + 1;
    final upcoming = player.queue.length > from
        ? player.queue.sublist(from, math.min(from + 20, player.queue.length))
        : const <Track>[];
    if (upcoming.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(KugoSpacing.lg),
          child: Text('歌池正在续接…', style: kugo.caption),
        ),
      );
    }
    return SliverList.separated(
      itemCount: upcoming.length,
      separatorBuilder: (_, _) => Divider(color: kugo.divider, height: 1),
      itemBuilder: (context, i) {
        final t = upcoming[i];
        return ListTile(
          dense: true,
          leading: ClipOval(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CoverBox(seed: t.coverUrl, size: 36, radius: 999),
            ),
          ),
          title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(t.artist, maxLines: 1),
          trailing: t.durationMs > 0
              ? Text(t.durationLabel, style: kugo.caption)
              : null,
          onTap: () {
            // 直接跳到待播列表里的某一首（原先侧立唱片堆的能力）。
            playerCtl.playAtIndex(from + i);
          },
        );
      },
    );
  }
}
