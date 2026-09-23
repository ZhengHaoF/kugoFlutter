import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/fm_mode.dart';
import '../../core/models/playback_source.dart';
import '../../core/models/track.dart';
import '../../core/platform.dart';
import '../../core/theme/cover_palette.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../core/theme/responsive.dart';
import '../../shared/widgets/cover_box.dart';
import '../player/player_controller.dart';
import 'fm_controller.dart';
import 'fm_radio_card.dart';
import '../../shared/widgets/smooth_scroll.dart';

/// Windows / wide desktop: dedicated Personal FM page.
///
/// Presentation-only shell over [FmController] + [PlayerController] —
/// never owns a second song pool. Narrow screens still get a single-column
/// fallback if the route is opened, but Android entry points keep
/// start-session → player (not this route).
///
/// 版式对齐 EchoMusic `views/PersonalFm.vue`：抬头（标题 + 右上角歌池轴）→
/// 舞台（深底电台卡 + 横向可滑盘阵，滑到吸附位起播）→ 「当前播放」面板 → 「接下来」。
/// 底色是纯色：颜色只由电台卡、黑胶和主色按钮提供，整页不再铺渐变。
class FmPage extends ConsumerStatefulWidget {
  const FmPage({super.key});

  @override
  ConsumerState<FmPage> createState() => _FmPageState();
}

class _FmPageState extends ConsumerState<FmPage>
    with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _bars;

  /// 「接下来」最多列几条：全列会把面板撑成列表页，预览由盘阵轮播 + 前几条负责。
  static const int _maxUpcoming = 8;

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

  Future<void> _startOrToggle({
    required FmSession fm,
    required PlayerState player,
  }) async {
    final fmCtl = ref.read(fmControllerProvider.notifier);
    final playerCtl = ref.read(playerControllerProvider.notifier);
    final fmActive = fm.active || player.queueSource == PlaybackQueueSource.fm;
    if (fmActive && player.current != null) {
      playerCtl.togglePlay();
      return;
    }
    await fmCtl.start(mode: fm.pendingMode, pool: fm.pendingPool);
  }

  void _like(FmController fmCtl) {
    fmCtl.like();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已加入我喜欢'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final fm = ref.watch(fmControllerProvider);
    final player = ref.watch(playerControllerProvider);
    final fmCtl = ref.read(fmControllerProvider.notifier);
    final playerCtl = ref.read(playerControllerProvider.notifier);
    final current = player.current;
    final desktop = isDesktopView(context);
    final fmActive = fm.active || player.queueSource == PlaybackQueueSource.fm;
    final accent = CoverPalette.accentFromSeed(
      current?.coverUrl ?? 'fm',
      kugo.palette,
    );
    final message = fm.gatewayError.isNotEmpty ? fm.gatewayError : fm.error;

    final radioCard = FmRadioCard(
      kugo: kugo,
      accent: accent,
      mode: fm.pendingMode,
      pool: fm.pendingPool,
      onMode: fmCtl.setPendingMode,
      onPlay: () => _startOrToggle(fm: fm, player: player),
      onDislike: fmCtl.dislike,
      onLike: () => _like(fmCtl),
      isPlaying: player.isPlaying && fmActive,
      bars: _bars,
      trackName: current?.name ?? '',
      artist: current?.artist ?? '',
      loading: fm.loading,
      actionsEnabled: current != null,
    );

    // 歌池轴：抬抬头右上角（EchoMusic 的 radio-strategy-switch 位置）。
    final poolSwitch = FmCapsuleSwitch<FmSongPool>(
      kugo: kugo,
      values: FmSongPool.values,
      labelOf: (p) => p.label,
      selected: fm.pendingPool,
      onChanged: fmCtl.setPendingPool,
      compact: !desktop,
    );

    // 盘阵 = 整条播放器队列的横向轮播（方案 A）：滑到左缘吸附位起播。
    // 数据与「接下来」同源；不再按 maxSideDiscs 截成 3 张。
    Widget buildCarousel({
      double discSize = FmStageMetrics.discSize,
      double sideGap = FmStageMetrics.sideGap,
    }) {
      return FmVinylCarousel(
        kugo: kugo,
        accent: accent,
        spin: _spin,
        tracks: player.queue,
        currentIndex: player.currentIndex,
        fallbackCoverUrl: current?.coverUrl ?? 'fm',
        playing: player.isPlaying && fmActive,
        onPlayIndex: (index) {
          if (index < 0 || index >= player.queue.length) return;
          // 同下标不重入（settle 与点击都可能到达）。
          if (index == player.currentIndex) return;
          playerCtl.playAtIndex(index);
        },
        onTapCurrent: () => _startOrToggle(fm: fm, player: player),
        discSize: discSize,
        sideGap: sideGap,
      );
    }

    // 轮播 viewport 左缘 = `cardWidth - overlap`，吸附位即「半截进卡」。
    // 桌面 / 窄屏同一行构图，只换 mobile 档尺度。
    final stage = FmStage(
      desktop: desktop,
      radioCard: radioCard,
      carousel: buildCarousel(
        discSize: FmStageMetrics.discSizeFor(desktop),
        sideGap: FmStageMetrics.sideGapFor(desktop),
      ),
    );

    final startCta = FilledButton.icon(
      key: const ValueKey('fm_start_cta'),
      onPressed: fm.loading
          ? null
          : () => _startOrToggle(fm: fm, player: player),
      icon: fm.loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.play_arrow_rounded),
      label: const Text('开始电台'),
    );

    final pendingBar = !fm.hasPendingChange
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: KugoSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '已切到 ${fm.pendingMode.label} · ${fm.pendingPool.label}，下一首生效',
                    style: kugo.caption.copyWith(
                      color: kugo.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: fmCtl.applyPendingNow,
                  child: const Text('立即生效'),
                ),
              ],
            ),
          );

    final errorBanner = message.isEmpty
        ? const SizedBox.shrink()
        : Container(
            margin: const EdgeInsets.only(bottom: KugoSpacing.md),
            padding: const EdgeInsets.symmetric(
              horizontal: KugoSpacing.md,
              vertical: KugoSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              color: kugo.surface,
              borderRadius: BorderRadius.circular(KugoRadius.tile),
              border: Border.all(color: kugo.divider),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: kugo.textSecondary,
                ),
                const SizedBox(width: KugoSpacing.sm),
                Expanded(
                  child: Text(
                    message,
                    style: kugo.caption.copyWith(color: kugo.textSecondary),
                  ),
                ),
              ],
            ),
          );

    final nowPanel = _FmPanel(
      kugo: kugo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('当前播放', style: kugo.section.copyWith(fontSize: 15)),
              const Spacer(),
              // 未起播时这里留一个明确入口；起播后操作都收在电台卡 footer 里。
              if (!fmActive) startCta,
            ],
          ),
          const SizedBox(height: KugoSpacing.lg),
          if (current != null)
            _NowPlayingBody(
              kugo: kugo,
              track: current,
              desktop: desktop,
              // 来源标注只在「这是 FM 队列」时有意义。
              // 空闲页若播放器里是搜索/歌单的歌，不能写成「关键词检索」。
              sourceBadge: (fmActive ||
                      player.queueSource == PlaybackQueueSource.fm)
                  ? FmSourceBadge(
                      kugo: kugo,
                      fromServer: fm.fromServer,
                      gatewayError: fm.gatewayError,
                      pool: fm.pool,
                      mode: fm.mode,
                      textAlign: desktop ? TextAlign.left : TextAlign.center,
                    )
                  : const SizedBox.shrink(),
            )
          else
            _FmIdleBody(kugo: kugo, mode: fm.pendingMode, pool: fm.pendingPool),
        ],
      ),
    );

    final upcomingPanel = _UpcomingPanel(
      kugo: kugo,
      player: player,
      maxItems: _maxUpcoming,
      appending: fm.appending,
      onTap: (index) => playerCtl.playAtIndex(index),
    );

    // 没起播就没有队列，此时「接下来」面板只会显示一句令人误会的空文案，直接不渲染。
    final showUpcoming = fmActive || player.queue.isNotEmpty;

    return Scaffold(
      backgroundColor: kugo.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KugoSpacing.sm,
                KugoSpacing.sm,
                KugoSpacing.lg,
                4,
              ),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    // Prefer Navigator pop so the page works in tests without
                    // a GoRouter in the tree; desktop shell still pops routes.
                    if (ModalRoute.of(context)?.canPop ?? false)
                      IconButton(
                        tooltip: '返回',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      )
                    else
                      const SizedBox(width: 12),
                    const SizedBox(width: KugoSpacing.xs),
                    Flexible(
                      child: Text(
                        '私人 FM',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kugo.section.copyWith(fontSize: 19),
                      ),
                    ),
                    if (fmActive) ...[
                      const SizedBox(width: KugoSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: kugo.primary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'LIVE',
                          style: TextStyle(
                            color: kugo.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    poolSwitch,
                  ],
                ),
              ),
            ),
            Expanded(
              child: SmoothSingleChildScrollView(
                // 浏览型页面：内容铺满侧栏之外的全部宽度（与发现页 /「我的」「历史」一致），
                // 不再做居中限宽——最大化窗口时两侧不会再留大片空白。
                padding: EdgeInsets.fromLTRB(
                  KugoSpacing.lg,
                  KugoSpacing.sm,
                  KugoSpacing.lg,
                  isDesktopPlatform ? KugoSpacing.lg : 100,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    errorBanner,
                    stage,
                    pendingBar,
                    const SizedBox(height: KugoSpacing.xxl),
                    nowPanel,
                    if (showUpcoming) ...[
                      const SizedBox(height: KugoSpacing.xl),
                      upcomingPanel,
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 面板容器：surface 底 + 细边 + 轻阴影（EchoMusic `fm-panel`）。
class _FmPanel extends StatelessWidget {
  const _FmPanel({required this.kugo, required this.child});

  final KugoTheme kugo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: kugo.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kugo.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: kugo.isLight ? 0.05 : 0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// 「当前播放」主体：左封面 + 右信息列（歌名 / 歌手 / 专辑 / 推荐理由 / chips / 来源）。
class _NowPlayingBody extends StatelessWidget {
  const _NowPlayingBody({
    required this.kugo,
    required this.track,
    required this.desktop,
    required this.sourceBadge,
  });

  final KugoTheme kugo;
  final Track track;
  final bool desktop;
  final Widget sourceBadge;

  @override
  Widget build(BuildContext context) {
    final coverSize = desktop ? 180.0 : 150.0;
    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        width: coverSize,
        height: coverSize,
        child: CoverBox(
          seed: track.coverUrl,
          size: coverSize,
          radius: 20,
        ),
      ),
    );
    final info = Column(
      crossAxisAlignment: desktop
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          track.name,
          textAlign: desktop ? TextAlign.left : TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: kugo.title.copyWith(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          track.artist,
          textAlign: desktop ? TextAlign.left : TextAlign.center,
          style: kugo.body.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: kugo.textSecondary,
          ),
        ),
        if (track.album.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            track.album,
            textAlign: desktop ? TextAlign.left : TextAlign.center,
            style: kugo.caption.copyWith(color: kugo.textTertiary),
          ),
        ],
        if (track.recDesc.isNotEmpty) ...[
          const SizedBox(height: KugoSpacing.sm),
          Text(
            track.recDesc,
            textAlign: desktop ? TextAlign.left : TextAlign.center,
            style: kugo.caption.copyWith(
              color: kugo.primary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: KugoSpacing.md),
        FmInfoChips(
          kugo: kugo,
          track: track,
          center: !desktop,
        ),
        const SizedBox(height: KugoSpacing.md),
        sourceBadge,
      ],
    );

    if (!desktop) {
      return Column(
        children: [Center(child: cover), const SizedBox(height: KugoSpacing.lg), info],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        cover,
        const SizedBox(width: 28),
        Expanded(child: info),
      ],
    );
  }
}

/// 未起播时的占位：一张主题封面 + 一句话，告诉用户点哪里开始。
class _FmIdleBody extends StatelessWidget {
  const _FmIdleBody({
    required this.kugo,
    required this.mode,
    required this.pool,
  });

  final KugoTheme kugo;
  final FmMode mode;
  final FmSongPool pool;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CoverBox(
          seed: 'fm',
          size: 96,
          radius: 20,
          child: const Icon(
            Icons.radio_rounded,
            size: 36,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: KugoSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '尚未开始电台',
                style: kugo.body.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${mode.stationTitle} · ${mode.subtitle} · ${pool.label}，'
                '点击「开始电台」即可收流',
                style: kugo.caption.copyWith(color: kugo.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 「接下来」面板：待播队列预览，行样式而不是密集小列表。
class _UpcomingPanel extends StatelessWidget {
  const _UpcomingPanel({
    required this.kugo,
    required this.player,
    required this.maxItems,
    required this.appending,
    required this.onTap,
  });

  final KugoTheme kugo;
  final PlayerState player;
  final int maxItems;
  final bool appending;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final from = player.currentIndex + 1;
    final upcoming = player.queue.length > from
        ? player.queue.sublist(from, math.min(from + maxItems, player.queue.length))
        : const <Track>[];
    final left = player.queue.isEmpty
        ? 0
        : player.queue.length - player.currentIndex - 1;

    return _FmPanel(
      kugo: kugo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('接下来', style: kugo.section.copyWith(fontSize: 15)),
              const SizedBox(width: KugoSpacing.sm),
              Expanded(
                child: Text(
                  appending ? '正在续接歌池…' : '$left 首待播',
                  style: kugo.caption,
                ),
              ),
            ],
          ),
          const SizedBox(height: KugoSpacing.sm),
          if (upcoming.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: KugoSpacing.lg),
              child: Text(
                appending ? '歌池正在续接…' : '歌池见底了，换个模式或歌池试试',
                style: kugo.caption.copyWith(color: kugo.textTertiary),
              ),
            )
          else
            for (var i = 0; i < upcoming.length; i++) ...[
              if (i > 0) Divider(color: kugo.divider, height: 1),
              _UpcomingRow(
                kugo: kugo,
                index: from + i,
                track: upcoming[i],
                onTap: () => onTap(from + i),
              ),
            ],
        ],
      ),
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({
    required this.kugo,
    required this.index,
    required this.track,
    required this.onTap,
  });

  final KugoTheme kugo;
  final int index;
  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(KugoRadius.tile),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${index + 1}',
                textAlign: TextAlign.center,
                style: kugo.caption.copyWith(color: kugo.textTertiary),
              ),
            ),
            const SizedBox(width: KugoSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 44,
                height: 44,
                child: CoverBox(seed: track.coverUrl, size: 44, radius: 10),
              ),
            ),
            const SizedBox(width: KugoSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: kugo.body.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: kugo.caption.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: KugoSpacing.sm),
            if (track.durationMs > 0)
              Text(track.durationLabel, style: kugo.caption),
          ],
        ),
      ),
    );
  }
}
