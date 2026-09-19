import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../shared/widgets/cover_box.dart';

/// 发现页搜索框正下方的快捷入口：私人 FM hero 卡（独占一行）+ 每日推荐横排卡。
///
/// 独立成文件是为了可测试：[ExplorePage] 的 initState 会发起真实网络请求
/// （dio 的超时 Timer 在 FakeAsync 测试里永远挂起），入口卡本身无状态、
/// 无网络依赖，单独 pump 即可覆盖布局与导航。
class QuickEntries extends StatelessWidget {
  const QuickEntries({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dailyLabel = '${now.month}月${now.day}日 · 每日推荐';

    // 私人 FM 独占一行（EchoMusic 侧边栏一级入口的对应待遇），
    // 每日推荐降为全宽横排行卡，避免留下孤儿半宽卡。
    // stretch 让两张卡都吃满可用宽度 —— Column 默认居中会缩成内容宽。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FmHeroCard(onTap: () => context.push('/fm')),
        const SizedBox(height: 12),
        DailyEntryCard(
          icon: Icons.today_rounded,
          title: dailyLabel,
          subtitle: '按日轮换 · 点开即听',
          onTap: () => context.push('/daily'),
        ),
      ],
    );
  }
}

/// 私人 FM 独占一行的 hero 卡。
///
/// 样式复刻 EchoMusic `PersonalFm.vue` 的 radio-card：深色渐变方卡
/// （primary 混深藏青，**任何主题下都是深色**，是页面上的刻意对比色块，
/// 与排行榜卡的深色 scrim 同一逻辑）、白/40% 均衡器条、primary 播放圆钮、
/// 右缘出血的黑胶盘。刻意不放旋转动画 —— 发现页是常驻首屏，`repeat()`
/// 会让任何 `pumpAndSettle` 挂死（FM 页已踩过同样的坑）。
class FmHeroCard extends StatelessWidget {
  const FmHeroCard({super.key, required this.onTap});

  final VoidCallback onTap;

  /// EchoMusic radio-card 的深藏青基色（#0B1620）。
  static const deep = Color(0xFF0B1620);

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return ClipRRect(
      key: const ValueKey('fm_hero_card'),
      borderRadius: BorderRadius.circular(KugoRadius.card),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            // 160° 渐变：primary 混入深藏青 30% → 40% → 纯深藏青。
            borderRadius: BorderRadius.circular(KugoRadius.card),
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
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                // 左上角 radial 高光（EchoMusic: radial at 16% 18%）。
                Positioned(
                  left: -50,
                  top: -70,
                  child: Container(
                    width: 210,
                    height: 210,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          kugo.primary.withValues(alpha: 0.28),
                          kugo.primary.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                // 黑胶盘右上角出血（被 ClipRRect 裁出「盘压卡缘」的层次）。
                // 不放右下角 —— 底部行有播放圆钮，会撞在一起。
                const Positioned(right: -30, top: -34, child: FmVinyl()),
                Padding(
                  padding: const EdgeInsets.all(KugoSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '私人 FM',
                        style: kugo.section.copyWith(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: kugo.onCover,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '黑胶电台 · 动态歌池',
                        style: kugo.caption.copyWith(
                          fontSize: 13,
                          color: kugo.onCoverMuted,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Row(
                        children: [
                          FmEqualizer(),
                          Spacer(),
                          FmPlayBadge(),
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
    );
  }
}

/// 黑胶装饰盘：深色盘体 + 唱纹环 + 中央确定性渐变「唱片芯」 + 中孔。
/// 封面用 [CoverBox] 的 seed 渐变（本地绘制，零网络请求）。
class FmVinyl extends StatelessWidget {
  const FmVinyl({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('fm_vinyl'),
      width: 124,
      height: 124,
      child: Stack(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF232B38), Color(0xFF0C1017)],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(-4, 6),
                ),
              ],
            ),
            child: const SizedBox.expand(),
          ),
          // 唱纹：两道同心细环。
          Center(
            child: Container(
              width: 106,
              height: 106,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 94,
              height: 94,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
            ),
          ),
          // 唱片芯（EchoMusic 盘心放封面，这里用确定性渐变代替）。
          Center(
            child: ClipOval(
              child: SizedBox(
                width: 72,
                height: 72,
                child: CoverBox(seed: 'personal-fm-vinyl', size: 72, radius: 0),
              ),
            ),
          ),
          // 中孔。
          Center(
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: FmHeroCard.deep,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// EchoMusic radio-bars：10 根固定高度的装饰条。纯静态（无动画）。
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
          if (i != _heights.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

/// primary 播放圆钮（视觉元素；点击整卡即进入 FM 页，不设二级手势）。
class FmPlayBadge extends StatelessWidget {
  const FmPlayBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: kugo.primary,
        boxShadow: [
          BoxShadow(
            color: kugo.primary.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
    );
  }
}

/// 每日推荐 — FM 拿走独占行后的全宽横排行卡。
class DailyEntryCard extends StatelessWidget {
  const DailyEntryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Material(
      key: const ValueKey('daily_entry_card'),
      color: kugo.surface,
      borderRadius: BorderRadius.circular(KugoRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KugoRadius.card),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KugoSpacing.lg,
            vertical: 14,
          ),
          child: Row(
            children: [
              Icon(icon, color: kugo.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: kugo.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: kugo.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: kugo.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
