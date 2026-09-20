import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/models/fm_mode.dart';
import '../../core/models/track.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../shared/widgets/cover_box.dart';

/// 私人 FM 的「电台卡」及其配套视觉件，从原 FM 页面原样搬出。
///
/// 这些不是新画的：`FmRadioCard`（渐变底 + 档位胶囊 + 台名 + 10 根频谱 + 播放键）、
/// `FmVinylStage`（自绘黑胶 + 侧立待播盘）、`FmInfoChips`、`FmSourceBadge`、
/// `FmActionRow`、`FmCapsuleSwitch` 都是原先 `personal_fm_page.dart` 的实现。
/// 页面撤掉时把它们抽到这里，播放页的控制面板再复用 —— 样式与原来完全一致。

/// EchoMusic `radio-card` 的等价物：模式轴 + 电台名 + 频谱 + 播放。
class FmRadioCard extends StatelessWidget {
  const FmRadioCard({
    super.key,
    required this.kugo,
    required this.accent,
    required this.mode,
    required this.pool,
    required this.onMode,
    required this.onPlay,
    required this.isPlaying,
    required this.bars,
    required this.trackName,
    required this.artist,
    required this.loading,
  });

  final KugoTheme kugo;
  final Color accent;
  final FmMode mode;
  final FmSongPool pool;
  final ValueChanged<FmMode> onMode;
  final VoidCallback onPlay;
  final bool isPlaying;
  final AnimationController bars;
  final String trackName;
  final String artist;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KugoSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(KugoSpacing.lg),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: 0.42),
              accent.withValues(alpha: 0.20),
              kugo.bg.withValues(alpha: 0.92),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 模式轴：红心 / 小众 / 速览。
            FmCapsuleSwitch<FmMode>(
              kugo: kugo,
              values: FmMode.values,
              labelOf: (m) => m.label,
              selected: mode,
              onChanged: onMode,
              onLightSurface: true,
            ),
            const SizedBox(height: KugoSpacing.md),
            Text(
              mode.stationTitle,
              style: kugo.greeting.copyWith(color: kugo.onCover, fontSize: 26),
            ),
            const SizedBox(height: 4),
            Text(
              artist.isEmpty ? '${mode.subtitle} · ${pool.label}' : artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: kugo.caption.copyWith(color: kugo.onCoverMuted),
            ),
            const SizedBox(height: KugoSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _Spectrum(bars: bars, active: isPlaying),
                ),
                const SizedBox(width: KugoSpacing.md),
                _CircleIconButton(
                  icon: loading
                      ? Icons.hourglass_empty_rounded
                      : (isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded),
                  size: 52,
                  background: Colors.white.withValues(alpha: 0.18),
                  iconColor: kugo.onAccent,
                  onTap: loading ? null : onPlay,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 唱片区：当前盘 + 最多 3 张侧立的后续盘（可点击直接播放）。
class FmVinylStage extends StatelessWidget {
  const FmVinylStage({
    super.key,
    required this.kugo,
    required this.accent,
    required this.spin,
    required this.coverUrl,
    required this.playing,
    required this.upcoming,
    required this.onPick,
    required this.onTapCurrent,
  });

  final KugoTheme kugo;
  final Color accent;
  final AnimationController spin;
  final String coverUrl;
  final bool playing;
  final List<Track> upcoming;
  final ValueChanged<Track> onPick;
  final VoidCallback onTapCurrent;

  @override
  Widget build(BuildContext context) {
    const currentSize = 176.0;
    return SizedBox(
      height: 210,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 侧盘从远到近绘制，越近越亮、越大。
          for (var i = upcoming.length - 1; i >= 0; i--)
            _OffsetDisc(
              spin: spin,
              spinning: playing,
              coverUrl: upcoming[i].coverUrl,
              size: currentSize,
              dx: 34 + i * 30,
              scale: 0.80 - i * 0.09,
              opacity: 0.55 - i * 0.13,
              onTap: () => onPick(upcoming[i]),
            ),
          AnimatedBuilder(
            animation: spin,
            builder: (context, child) {
              final angle = playing ? spin.value * 2 * pi : 0.0;
              return Transform.rotate(angle: angle, child: child);
            },
            child: _Vinyl(
              coverUrl: coverUrl,
              size: currentSize,
              accent: accent,
              kugo: kugo,
              onTap: onTapCurrent,
            ),
          ),
        ],
      ),
    );
  }
}

class _OffsetDisc extends StatelessWidget {
  const _OffsetDisc({
    required this.spin,
    required this.spinning,
    required this.coverUrl,
    required this.size,
    required this.dx,
    required this.scale,
    required this.opacity,
    required this.onTap,
  });

  final AnimationController spin;
  final bool spinning;
  final String coverUrl;
  final double size;
  final double dx;
  final double scale;
  final double opacity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Transform.translate(
        offset: Offset(dx, 0),
        child: Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: AnimatedBuilder(
              animation: spin,
              builder: (context, child) {
                final angle = spinning ? spin.value * 2 * pi : 0.0;
                return Transform.rotate(angle: angle, child: child);
              },
              child: _Vinyl(
                coverUrl: coverUrl,
                size: size,
                accent: Colors.transparent,
                kugo: null,
                onTap: onTap,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 自绘黑胶：沟槽 + 封面标签 + 中心孔。
class _Vinyl extends StatelessWidget {
  const _Vinyl({
    required this.coverUrl,
    required this.size,
    required this.accent,
    required this.kugo,
    required this.onTap,
  });

  final String coverUrl;
  final double size;
  final Color accent;
  final KugoTheme? kugo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = kugo ?? KugoTheme.of(context);
    final labelSize = size * 0.60;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            colors: [Color(0xFF1A1A1E), Color(0xFF05050A)],
          ),
          border: Border.all(color: theme.divider, width: 2),
          boxShadow: [
            BoxShadow(
              color: accent == Colors.transparent
                  ? Colors.black.withValues(alpha: 0.3)
                  : accent.withValues(alpha: 0.35),
              blurRadius: 34,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _GroovePainter()),
              ),
            ),
            ClipOval(
              child: SizedBox(
                width: labelSize,
                height: labelSize,
                child: CoverBox(seed: coverUrl, size: labelSize, radius: 999),
              ),
            ),
            Container(
              width: size * 0.06,
              height: size * 0.06,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.bg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroovePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (
      var r = size.shortestSide * 0.30;
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

/// 10 根跳动频谱条（EchoMusic `radio-bars`）。
class _Spectrum extends StatelessWidget {
  const _Spectrum({required this.bars, required this.active});

  final AnimationController bars;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: bars,
      builder: (context, _) {
        return SizedBox(
          height: 26,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 10; i++)
                Container(
                  width: 3,
                  margin: const EdgeInsets.only(right: 3),
                  height: active
                      ? 6 + 18 * (0.5 + 0.5 * sin((bars.value * 2 * pi) + i))
                      : 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: active ? 0.75 : 0.30),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 信息 chip：时长 / 音质。
class FmInfoChips extends StatelessWidget {
  const FmInfoChips({super.key, required this.kugo, this.track});

  final KugoTheme kugo;
  final Track? track;

  @override
  Widget build(BuildContext context) {
    final t = track;
    if (t == null) return const SizedBox.shrink();
    final items = <String>[
      if (t.durationMs > 0) t.durationLabel,
      if (t.quality.isNotEmpty) t.quality,
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: KugoSpacing.sm,
      runSpacing: KugoSpacing.xs,
      children: [
        for (final item in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: kugo.surface.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(KugoRadius.chip),
              border: Border.all(color: kugo.divider),
            ),
            child: Text(item, style: kugo.caption),
          ),
      ],
    );
  }
}

/// 数据来源标注 —— 兜底模式必须让人看出来不是个性化推荐。
class FmSourceBadge extends StatelessWidget {
  const FmSourceBadge({
    super.key,
    required this.kugo,
    required this.fromServer,
    required this.gatewayError,
    required this.pool,
    required this.mode,
  });

  final KugoTheme kugo;
  final bool fromServer;
  final String gatewayError;
  final FmSongPool pool;
  final FmMode mode;

  @override
  Widget build(BuildContext context) {
    final semantic = pool.semantic.isEmpty ? '' : ' · ${pool.semantic}';
    final text = fromServer
        ? '来源：酷狗私人 FM · ${pool.label}$semantic'
        : (gatewayError.isEmpty
              ? '来源：关键词检索（${pool.reasonLabel}，非个性化）'
              : '来源：关键词检索 · ${pool.reasonLabel}');
    return Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 2,
      style: kugo.caption.copyWith(color: kugo.textTertiary, fontSize: 11),
    );
  }
}

class FmActionRow extends StatelessWidget {
  const FmActionRow({
    super.key,
    required this.kugo,
    required this.accent,
    required this.isPlaying,
    required this.onDislike,
    required this.onToggle,
    required this.onLike,
  });

  final KugoTheme kugo;
  final Color accent;
  final bool isPlaying;
  final VoidCallback onDislike;
  final VoidCallback onToggle;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CircleAction(
          icon: Icons.thumb_down_alt_rounded,
          label: '不喜欢',
          onTap: onDislike,
        ),
        _CircleAction(
          large: true,
          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          onTap: onToggle,
          accent: accent,
        ),
        _CircleAction(
          icon: Icons.thumb_up_alt_rounded,
          label: '红心',
          onTap: onLike,
        ),
      ],
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.onTap,
    this.label,
    this.large = false,
    this.accent,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  final bool large;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final size = large ? 72.0 : 52.0;
    final tone = accent ?? kugo.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The label is part of the tap target — tapping the word should work
        // just as well as tapping the circle.
        InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: large
                      ? LinearGradient(
                          colors: [tone, tone.withValues(alpha: 0.7)],
                        )
                      : null,
                  color: large ? null : kugo.surface.withValues(alpha: 0.75),
                ),
                child: Icon(
                  icon,
                  size: large ? 36 : 24,
                  color: large ? kugo.onAccent : kugo.textPrimary,
                ),
              ),
              if (label != null) ...[
                const SizedBox(height: 6),
                Text(label!, style: kugo.caption),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.size,
    required this.background,
    required this.iconColor,
    this.onTap,
  });

  final IconData icon;
  final double size;
  final Color background;
  final Color iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: background),
        child: Icon(icon, color: iconColor, size: size * 0.5),
      ),
    );
  }
}

/// 胶囊分段开关：顶部歌池轴 / 电台卡模式轴共用。
class FmCapsuleSwitch<T> extends StatelessWidget {
  const FmCapsuleSwitch({
    super.key,
    required this.kugo,
    required this.values,
    required this.labelOf,
    required this.selected,
    required this.onChanged,
    this.compact = false,
    this.onLightSurface = false,
  });

  final KugoTheme kugo;
  final List<T> values;
  final String Function(T) labelOf;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool compact;
  final bool onLightSurface;

  @override
  Widget build(BuildContext context) {
    final background = onLightSurface
        ? Colors.white.withValues(alpha: 0.16)
        : kugo.surface.withValues(alpha: 0.55);
    final foreground = onLightSurface ? kugo.onCoverMuted : kugo.textSecondary;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(KugoRadius.chip),
        border: Border.all(color: kugo.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final value in values)
            GestureDetector(
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 10 : 14,
                  vertical: compact ? 5 : 7,
                ),
                decoration: BoxDecoration(
                  color: value == selected
                      ? (onLightSurface
                            ? Colors.white.withValues(alpha: 0.22)
                            : kugo.primary.withValues(alpha: 0.30))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(KugoRadius.chip),
                ),
                child: Text(
                  labelOf(value),
                  style: kugo.caption.copyWith(
                    color: value == selected
                        ? (onLightSurface ? kugo.onAccent : kugo.textPrimary)
                        : foreground,
                    fontWeight: value == selected
                        ? FontWeight.w700
                        : FontWeight.w500,
                    fontSize: compact ? 11 : 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
