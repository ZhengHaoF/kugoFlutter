import 'package:flutter/material.dart';

import '../../core/cache/cover_cache.dart';
import '../../core/models/track.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../shared/widgets/cover_box.dart';

/// Tag helper for rank cover hero transition.
String rankCoverHeroTag(String rankId) => 'rank-cover-$rankId';

/// Gradient used on the rank grid card.
LinearGradient rankCardGradient() => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.black.withValues(alpha: 0.02),
        Colors.black.withValues(alpha: 0.55),
      ],
    );

/// Gradient used on the playlist/rank detail header.
LinearGradient rankDetailHeaderGradient(Color bgColor) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.black.withValues(alpha: 0.15),
        bgColor.withValues(alpha: 0.92),
      ],
    );

/// Visual surface of a rank card on the rank list / explore page.
class RankCardSurface extends StatelessWidget {
  const RankCardSurface({
    super.key,
    required this.brief,
    this.showTitle = false,
  });

  final PlaylistBrief brief;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CoverBox(
            seed: brief.coverUrl,
            size: 0,
            radius: KugoRadius.card,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: rankCardGradient(),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showTitle) ...[
                  Text(
                    brief.name,
                    style: kugo.section.copyWith(
                      fontSize: 17,
                      color: kugo.onCover,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                if (brief.playCountLabel.isNotEmpty)
                  Text(
                    brief.playCountLabel,
                    style: kugo.caption.copyWith(
                      color: showTitle ? kugo.onCoverMuted : Colors.white70,
                      decoration: TextDecoration.none,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Visual surface of the playlist/rank detail header.
class RankDetailHeaderSurface extends StatelessWidget {
  const RankDetailHeaderSurface({
    super.key,
    required this.brief,
    required this.tracksCount,
    required this.fallbackId,
  });

  final PlaylistBrief? brief;
  final int tracksCount;
  final String fallbackId;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final b = brief;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CoverBox(
            seed: b?.coverUrl ?? fallbackId,
            size: 0,
            radius: 0,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: rankDetailHeaderGradient(kugo.bg),
            ),
          ),
          Positioned(
            left: KugoSpacing.lg,
            right: KugoSpacing.lg,
            bottom: KugoSpacing.lg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b?.name ?? '歌单',
                  style: kugo.title.copyWith(decoration: TextDecoration.none),
                ),
                const SizedBox(height: 6),
                Text(
                  b == null
                      ? '在线加载'
                      : '$tracksCount 首'
                          '${b.playCountLabel.isNotEmpty ? ' · ${b.playCountLabel}' : ''}',
                  style: kugo.caption.copyWith(decoration: TextDecoration.none),
                ),
                if (b?.description.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    b!.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: kugo.caption.copyWith(
                      color: kugo.textSecondary.withValues(alpha: 0.8),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Unified flight shuttle that morphs the card surface (cover + mask + text)
/// smoothly into the detail header surface (cover + header mask + title/count).
Widget rankHeroFlightShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection flightDirection,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final kugo = KugoTheme.of(flightContext);

  // Extract brief from to or from context
  PlaylistBrief? brief;
  int tracksCount = 0;
  bool showTitle = false;
  String fallbackId = '';

  for (final ctx in [toHeroContext, fromHeroContext]) {
    final w = ctx.widget;
    if (w is Hero) {
      if (w.child is RankDetailHeaderSurface) {
        final surface = w.child as RankDetailHeaderSurface;
        brief ??= surface.brief;
        tracksCount = surface.tracksCount;
        fallbackId = surface.fallbackId;
      } else if (w.child is RankCardSurface) {
        final surface = w.child as RankCardSurface;
        brief ??= surface.brief;
        showTitle = surface.showTitle;
      } else if (w.child is CoverBox) {
        final box = w.child as CoverBox;
        if (fallbackId.isEmpty) fallbackId = box.seed;
      }
    }
  }

  final seed = brief?.coverUrl ?? fallbackId;
  final bytes = seed.isEmpty ? null : CoverCache.instance.peek(seed);

  final cardGrad = rankCardGradient();
  final headerGrad = rankDetailHeaderGradient(kugo.bg);

  final isPush = flightDirection == HeroFlightDirection.push;
  final fromGrad = isPush ? cardGrad : headerGrad;
  final toGrad = isPush ? headerGrad : cardGrad;
  final fromRadius = isPush ? KugoRadius.card : 0.0;
  final toRadius = isPush ? 0.0 : KugoRadius.card;

  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final rawValue = animation.value;
      // In Flutter, Pop animation runs in reverse: animation.value goes from 1.0 down to 0.0.
      // Normalize progress to always run 0.0 (flight start) -> 1.0 (flight end).
      final progress = isPush ? rawValue : (1.0 - rawValue);
      if (progress == 0.0 || progress == 1.0 || (progress > 0.49 && progress < 0.52)) {
        debugPrint('[RANK_HERO_SHUTTLE] isPush=$isPush rawValue=$rawValue progress=$progress seed=$seed tag=${brief?.id}');
      }
      final t = Curves.easeInOutCubic.transform(progress);

      // Smooth radius transition
      final radius = fromRadius + (toRadius - fromRadius) * t;

      // Smooth gradient morphing
      final currentGrad = LinearGradient.lerp(fromGrad, toGrad, t) ?? fromGrad;

      // The source widget's text fades out in the first 40% of the flight
      final sourceTextOpacity = (1.0 - progress * 2.5).clamp(0.0, 1.0);
      // The destination widget's text fades in during the last 60% of the flight
      final destTextOpacity = ((progress - 0.4) / 0.6).clamp(0.0, 1.0);

      final cardTextOpacity = isPush ? sourceTextOpacity : destTextOpacity;
      final headerTextOpacity = isPush ? destTextOpacity : sourceTextOpacity;

      final Widget coverImage;
      if (bytes != null) {
        coverImage = Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          width: double.infinity,
          height: double.infinity,
        );
      } else {
        coverImage = CoverBox(seed: seed, size: 0, radius: radius);
      }

      return Material(
        type: MaterialType.transparency,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Cover image
              coverImage,

              // 2. Continuous, morphing dark gradient overlay
              DecoratedBox(
                decoration: BoxDecoration(gradient: currentGrad),
              ),

              // 3. Card text (fades out on push, fades in on pop)
              if (brief != null && cardTextOpacity > 0)
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Opacity(
                    opacity: cardTextOpacity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showTitle) ...[
                          Text(
                            brief.name,
                            style: kugo.section.copyWith(
                              fontSize: 17,
                              color: kugo.onCover,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const SizedBox(height: 2),
                        ],
                        if (brief.playCountLabel.isNotEmpty)
                          Text(
                            brief.playCountLabel,
                            style: kugo.caption.copyWith(
                              color:
                                  showTitle ? kugo.onCoverMuted : Colors.white70,
                              decoration: TextDecoration.none,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

              // 4. Header title and info (fades in on push, fades out on pop)
              if (headerTextOpacity > 0)
                Positioned(
                  left: KugoSpacing.lg,
                  right: KugoSpacing.lg,
                  bottom: KugoSpacing.lg,
                  child: Opacity(
                    opacity: headerTextOpacity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          brief?.name ?? '歌单',
                          style: kugo.title
                              .copyWith(decoration: TextDecoration.none),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          brief == null
                              ? '在线加载'
                              : '$tracksCount 首'
                                  '${brief.playCountLabel.isNotEmpty ? ' · ${brief.playCountLabel}' : ''}',
                          style: kugo.caption
                              .copyWith(decoration: TextDecoration.none),
                        ),
                        if (brief?.description.isNotEmpty == true) ...[
                          const SizedBox(height: 8),
                          Text(
                            brief!.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: kugo.caption.copyWith(
                              color: kugo.textSecondary.withValues(alpha: 0.8),
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
