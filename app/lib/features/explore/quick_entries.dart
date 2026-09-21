import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/fm_mode.dart';
import '../../core/models/playback_source.dart';
import '../../core/theme/hero_tags.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../shared/widgets/cover_box.dart';
import '../fm/fm_controller.dart';
import '../player/player_controller.dart';

/// 发现页搜索框正下方的快捷入口：私人 FM 舞台卡（前后层叠）+ 为你推荐入口卡。
///
/// 独立成文件是为了可测试：[ExplorePage] 的 initState 会发起真实网络请求
/// （dio 的超时 Timer 在 FakeAsync 测试里永远挂起），入口卡本身无状态/纯响应式，
/// 单独 pump 即可覆盖布局与导航。
class QuickEntries extends ConsumerWidget {
  const QuickEntries({super.key});

  /// 处理私人 FM 播放控制：
  /// - 若 FM 会话已激活且有当前曲目：就地切换播放/暂停，绝不跳页，也不重新拉新歌；
  /// - 若 FM 会话尚未激活：以当前选中的模式在原地启动 FM 会话并起播，不跳页。
  void _handlePlay(WidgetRef ref) {
    final player = ref.read(playerControllerProvider);
    final fm = ref.read(fmControllerProvider.notifier);
    final isFmActive = player.queueSource == PlaybackQueueSource.fm;

    if (isFmActive && player.current != null) {
      ref.read(playerControllerProvider.notifier).togglePlay();
    } else {
      final pendingMode = ref.read(fmControllerProvider).pendingMode;
      unawaited(fm.start(mode: pendingMode));
    }
  }

  /// 模式切换处理（对齐 EchoMusic PersonalFm.vue 中的 handleChangePersonalFmMode）：
  /// - 若正在播放或 FM 会话已激活：立即切换模式并拉取该模式的新歌切歌起播；
  /// - 若 FM 尚未开播：仅切换待生效模式，等用户点击播放时以此模式起播。
  void _handleModeChanged(FmMode newMode, WidgetRef ref) {
    final fmState = ref.read(fmControllerProvider);
    if (fmState.loading) return;

    final player = ref.read(playerControllerProvider);
    final isFmActive = player.queueSource == PlaybackQueueSource.fm;

    if (isFmActive && newMode == fmState.mode) return;

    final fm = ref.read(fmControllerProvider.notifier);
    if (isFmActive || player.isPlaying) {
      unawaited(fm.start(mode: newMode));
    } else {
      fm.setPendingMode(newMode);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FmHeroCard(
          onTap: () => _handlePlay(ref),
          onModeChanged: (mode) => _handleModeChanged(mode, ref),
        ),
        const SizedBox(height: 12),
        RecommendHubEntryCard(
          onTap: () => context.push('/recommend'),
        ),
      ],
    );
  }
}

/// 私人 FM Radio 舞台卡（复刻 EchoMusic `PersonalFm.vue` 的 Radio-Hero 舞台）。
///
/// 结构设计：
/// - **底层（右后侧）**：真实黑胶唱片（[FmVinyl]），从 Radio Card 右后侧向右自然探出，
///   展示黑胶细同心圆环纹与圆形专辑封面唱片芯；
/// - **表层（左前侧）**：EchoMusic 经典 Radio Card，带有 160° 深藏青混色渐变、
///   左上角径向高光、顶部档位胶囊切轴、电台名与动态曲名、底部 10 根律动条与播放圆钮。
class FmHeroCard extends ConsumerWidget {
  const FmHeroCard({
    super.key,
    required this.onTap,
    this.onModeChanged,
  });

  final VoidCallback onTap;
  final ValueChanged<FmMode>? onModeChanged;

  /// EchoMusic radio-card 的深藏青基色（#0B1620）。
  static const deep = Color(0xFF0B1620);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kugo = KugoTheme.of(context);
    final fmState = ref.watch(fmControllerProvider);
    final player = ref.watch(playerControllerProvider);
    final isFmActive = player.queueSource == PlaybackQueueSource.fm;
    final currentTrack = player.current;

    // 当 FM 激活时使用实播 mode，未激活时使用待生效的 pendingMode
    final mode = isFmActive ? fmState.mode : fmState.pendingMode;

    final isPlaying = isFmActive && player.isPlaying;
    // 关键修正：只有当前正在播放 FM 时才显示当前歌曲信息；
    // 未开启 FM 时显示通用的电台介绍，避免造成“显示的是A歌，点击却播B歌”的错觉。
    final subtitle = (isFmActive && currentTrack != null)
        ? '${currentTrack.name} · ${currentTrack.artist}'
        : '${mode.subtitle} · 动态歌池';
    final coverUrl = (isFmActive && currentTrack != null)
        ? currentTrack.coverUrl
        : 'personal-fm-vinyl';

    const stageHeight = 176.0;
    const vinylSize = 156.0;
    const rightMargin = 84.0;

    return SizedBox(
      key: const ValueKey('fm_hero_card'),
      height: stageHeight,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerLeft,
        children: [
          // 1. 底层（右后侧）：向右探出的黑胶唱片
          Positioned(
            right: 2,
            top: (stageHeight - vinylSize) / 2,
            child: FmVinyl(
              coverUrl: coverUrl,
              size: vinylSize,
            ),
          ),
          // 2. 表层（左前侧）：Radio Card 卡片主体
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            right: rightMargin,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  stops: const [0.0, 0.56, 1.0],
                  colors: [
                    Color.lerp(kugo.primary, deep, 0.30)!,
                    Color.lerp(kugo.primary, deep, 0.40)!,
                    deep,
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF050C14).withValues(alpha: 0.32),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: const Color(0xFF081826).withValues(alpha: 0.18),
                    blurRadius: 36,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: onTap,
                    child: Stack(
                    children: [
                      // 左上角径向高光（EchoMusic: radial at 16% 18%）
                      Positioned(
                        left: -40,
                        top: -50,
                        child: IgnorePointer(
                          child: Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  kugo.primary.withValues(alpha: 0.32),
                                  kugo.primary.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // 顶部：档位胶囊切轴（红心 / 小众 / 速览）
                            FmModeCapsule(
                              selected: mode,
                              onChanged: (newMode) {
                                if (onModeChanged != null) {
                                  onModeChanged!(newMode);
                                } else {
                                  ref
                                      .read(fmControllerProvider.notifier)
                                      .setPendingMode(newMode);
                                }
                              },
                            ),
                            // 中部：电台标题与副标题
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '私人 FM',
                                  style: kugo.section.copyWith(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.4,
                                    color: kugo.onCover,
                                    shadows: [
                                      Shadow(
                                        color: const Color(0xFF050C14)
                                            .withValues(alpha: 0.4),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: kugo.caption.copyWith(
                                    fontSize: 12,
                                    color: kugo.onCoverMuted,
                                  ),
                                ),
                              ],
                            ),
                            // 底部：律动条与播放圆钮
                            Row(
                              children: [
                                const FmEqualizer(),
                                const Spacer(),
                                FmPlayBadge(
                                  isPlaying: isPlaying,
                                  isLoading: fmState.loading,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
  }
}

/// 档位胶囊开关（EchoMusic .radio-mode-switch 风格）。
class FmModeCapsule extends StatelessWidget {
  const FmModeCapsule({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final FmMode selected;
  final ValueChanged<FmMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(KugoRadius.chip),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final mode in FmMode.values)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(mode),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: mode == selected
                      ? Colors.white.withValues(alpha: 0.22)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(KugoRadius.chip),
                  boxShadow: mode == selected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  mode.label,
                  style: TextStyle(
                    color: mode == selected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.70),
                    fontSize: 11,
                    fontWeight:
                        mode == selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 黑胶唱片：深色盘体 + 精密唱纹同心环 + 唱片芯封面（圆形）+ 中孔。
class FmVinyl extends StatelessWidget {
  const FmVinyl({
    super.key,
    this.coverUrl,
    this.size = 156,
  });

  final String? coverUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final labelSize = size * 0.52;
    return SizedBox(
      key: const ValueKey('fm_vinyl'),
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 黑胶盘体与外圈立体阴影
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Color(0xFF222834), Color(0xFF0A0D14)],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 22,
                  offset: const Offset(4, 8),
                ),
              ],
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1.5,
              ),
            ),
            child: const SizedBox.expand(),
          ),
          // 精密同心唱纹
          Positioned.fill(
            child: CustomPaint(
              painter: _GroovePainter(),
            ),
          ),
          // 唱片芯：展示专辑封面
          ClipOval(
            child: SizedBox(
              width: labelSize,
              height: labelSize,
              child: CoverBox(
                seed: coverUrl != null && coverUrl!.isNotEmpty
                    ? coverUrl!
                    : 'personal-fm-vinyl',
                size: labelSize,
                radius: 0,
              ),
            ),
          ),
          // 中孔
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0B1620),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 黑胶细密同心圆唱纹绘制器。
class _GroovePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (
      var r = size.shortestSide * 0.28;
      r < size.shortestSide * 0.48;
      r += 4
    ) {
      paint.color = Colors.white.withValues(alpha: 0.05);
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 10 根律动条（纯静态，避免无休止动画阻断测试）。
class FmEqualizer extends StatelessWidget {
  const FmEqualizer({super.key});

  static const _heights = <double>[11, 17, 8, 19, 13, 18, 9, 14, 8, 15];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < _heights.length; i++) ...[
          Container(
            width: 3,
            height: _heights[i],
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          if (i != _heights.length - 1) const SizedBox(width: 5),
        ],
      ],
    );
  }
}

/// Primary 播放圆钮。
class FmPlayBadge extends StatelessWidget {
  const FmPlayBadge({
    super.key,
    this.isPlaying = false,
    this.isLoading = false,
  });

  final bool isPlaying;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: kugo.primary,
        boxShadow: [
          BoxShadow(
            color: kugo.primary.withValues(alpha: 0.38),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 24,
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
