import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/fm_mode.dart';
import '../../core/models/playback_source.dart';
import '../../core/theme/cover_palette.dart';
import '../../core/theme/hero_tags.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../core/theme/responsive.dart';
import '../fm/fm_controller.dart';
import '../fm/fm_radio_card.dart';
import '../player/player_controller.dart';

/// 发现页搜索框正下方的快捷入口：私人 FM 舞台（与 /fm 同构）+ 为你推荐入口卡。
///
/// 舞台直接复用 [FmStage] / [FmRadioCard] / [FmVinylCarousel]（桌面 272 / 手机 180），
/// 与独立私人 FM 页同一套「卡 + 黑胶一行」视觉；起播/切模式仍就地完成，不跳全屏播放页。
///
/// 独立成文件是为了可测试：[ExplorePage] 的 initState 会发起真实网络请求
/// （dio 的超时 Timer 在 FakeAsync 测试里永远挂起），入口本身无网络副作用，
/// 单独 pump 即可覆盖布局与导航。
class QuickEntries extends ConsumerStatefulWidget {
  const QuickEntries({super.key});

  @override
  ConsumerState<QuickEntries> createState() => _QuickEntriesState();
}

class _QuickEntriesState extends ConsumerState<QuickEntries>
    with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _bars;

  @override
  void initState() {
    super.initState();
    // 与 /fm 舞台一致的自旋 / 频谱时基；仅在播放时 repeat，空闲停表省电
    // 也让测试的 pumpAndSettle 能收敛。
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
    _bars = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void dispose() {
    _spin.dispose();
    _bars.dispose();
    super.dispose();
  }

  void _syncAnimations({required bool playing}) {
    if (playing) {
      if (!_spin.isAnimating) _spin.repeat();
      if (!_bars.isAnimating) _bars.repeat();
    } else {
      _spin.stop();
      _bars.stop();
    }
  }

  /// 与 /fm 一致：已激活则就地切换播放/暂停；未激活则按 pending 起播。
  Future<void> _startOrToggle() async {
    final player = ref.read(playerControllerProvider);
    final fm = ref.read(fmControllerProvider);
    final fmCtl = ref.read(fmControllerProvider.notifier);
    final playerCtl = ref.read(playerControllerProvider.notifier);
    final fmActive = fm.active || player.queueSource == PlaybackQueueSource.fm;
    if (fmActive && player.current != null) {
      playerCtl.togglePlay();
      return;
    }
    await fmCtl.start(mode: fm.pendingMode, pool: fm.pendingPool);
  }

  /// 模式切换（对齐 EchoMusic PersonalFm.vue 的 handleChangePersonalFmMode）：
  /// - FM 已激活 / 正在播放：立即以新模式重开会话；
  /// - 否则只改 pending，等起播时生效。
  void _handleModeChanged(FmMode newMode) {
    final fmState = ref.read(fmControllerProvider);
    if (fmState.loading) return;

    final player = ref.read(playerControllerProvider);
    final isFmActive = player.queueSource == PlaybackQueueSource.fm;

    if (isFmActive && newMode == fmState.mode) return;

    final fm = ref.read(fmControllerProvider.notifier);
    if (isFmActive || player.isPlaying) {
      unawaited(
        fm.start(mode: newMode, pool: fmState.pendingPool),
      );
    } else {
      fm.setPendingMode(newMode);
    }
  }

  void _like() {
    ref.read(fmControllerProvider.notifier).like();
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
    final playerCtl = ref.read(playerControllerProvider.notifier);
    final fmCtl = ref.read(fmControllerProvider.notifier);

    final desktop = isDesktopView(context);
    final fmActive = fm.active || player.queueSource == PlaybackQueueSource.fm;
    final current = player.current;
    final showPlaying = player.isPlaying && fmActive;
    _syncAnimations(playing: showPlaying);
    final accent = CoverPalette.accentFromSeed(
      current?.coverUrl ?? 'fm',
      kugo.palette,
    );

    final radioCard = FmRadioCard(
      kugo: kugo,
      accent: accent,
      mode: fm.pendingMode,
      pool: fm.pendingPool,
      onMode: _handleModeChanged,
      onPlay: _startOrToggle,
      onDislike: fmCtl.dislike,
      onLike: _like,
      isPlaying: showPlaying,
      bars: _bars,
      trackName: current?.name ?? '',
      artist: current?.artist ?? '',
      loading: fm.loading,
      actionsEnabled: current != null,
    );

    final carousel = FmVinylCarousel(
      kugo: kugo,
      accent: accent,
      spin: _spin,
      tracks: player.queue,
      currentIndex: player.currentIndex,
      fallbackCoverUrl: current?.coverUrl ?? 'fm',
      playing: showPlaying,
      onPlayIndex: (index) {
        if (index < 0 || index >= player.queue.length) return;
        if (index == player.currentIndex) return;
        playerCtl.playAtIndex(index);
      },
      onTapCurrent: _startOrToggle,
      discSize: FmStageMetrics.discSizeFor(desktop),
      sideGap: FmStageMetrics.sideGapFor(desktop),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FmStage(
          desktop: desktop,
          radioCard: radioCard,
          carousel: carousel,
        ),
        // 舞台阴影外溢略多，给下方入口留一点空气。
        const SizedBox(height: KugoSpacing.lg),
        // Android 无桌面侧栏：挂「为你推荐 + 探索」入口。窄屏纵向堆叠，
        // 半宽卡片里的副标题会把 68 高的卡挤爆。
        LayoutBuilder(
          builder: (context, constraints) {
            final sideBySide = constraints.maxWidth >= 520;
            final recommend = RecommendHubEntryCard(
              onTap: () => context.push('/recommend'),
            );
            final discovery = DiscoveryEntryCard(
              onTap: () => context.push('/discovery'),
            );
            if (!sideBySide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  recommend,
                  const SizedBox(height: 12),
                  discovery,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: recommend),
                const SizedBox(width: 12),
                Expanded(child: discovery),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// 发现页「探索」入口卡（对齐侧栏「探索」/ EchoMusic 探索发现）。
class DiscoveryEntryCard extends StatelessWidget {
  const DiscoveryEntryCard({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Material(
      key: const ValueKey('discovery_entry_card'),
      color: kugo.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kugo.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      kugo.secondary,
                      Color.lerp(kugo.secondary, kugo.primary, 0.40)!,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kugo.secondary.withValues(alpha: 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.explore_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '探索',
                      style: kugo.body.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '歌单 · 榜单 · 新碟 · 歌手',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kugo.caption.copyWith(
                        fontSize: 12,
                        color: kugo.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: kugo.secondary.withValues(alpha: 0.12),
                ),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: kugo.secondary,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 发现页「为你推荐」入口卡（EchoMusic Home feature-card 风格）。
///
/// 点击进入推荐聚合页 `/recommend`；每日推荐成为聚合页内子入口。
class RecommendHubEntryCard extends StatelessWidget {
  const RecommendHubEntryCard({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final dayStr = DateTime.now().day.toString();
    return Material(
      key: const ValueKey('recommend_hub_entry_card'),
      color: kugo.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kugo.divider),
          ),
          child: Row(
            children: [
              // EchoMusic: .feature-icon .gradient-primary（大号日历数字）
              Hero(
                tag: KugoHeroTags.dailyRecommendBadge,
                flightShuttleBuilder:
                    KugoHeroTags.dailyRecommendBadgeFlightShuttle,
                child: Material(
                  type: MaterialType.transparency,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          kugo.primary,
                          Color.lerp(kugo.primary, kugo.secondary, 0.35)!,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: kugo.primary.withValues(alpha: 0.30),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        dayStr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '为你推荐',
                      style: kugo.body.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '每日 · 风格 · 歌单精选',
                      style: kugo.caption.copyWith(
                        fontSize: 12,
                        color: kugo.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // EchoMusic: .feature-action 轻色块动作圆钮
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: kugo.primary.withValues(alpha: 0.12),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: kugo.primary,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
