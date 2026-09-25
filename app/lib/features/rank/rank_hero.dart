import 'package:flutter/material.dart';

import '../../core/cache/cover_cache.dart';
import '../../core/models/track.dart';
import '../../core/source/music_platform.dart';
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
    this.dense = false,
  });

  final PlaylistBrief brief;
  final bool showTitle;

  /// Desktop grid: smaller overlay type so dense cards stay readable.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final inset = dense ? 8.0 : 12.0;
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
            left: inset,
            right: inset,
            bottom: inset,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showTitle) ...[
                  Text(
                    brief.name,
                    maxLines: dense ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: kugo.section.copyWith(
                      fontSize: dense ? 13 : 17,
                      color: kugo.onCover,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                if (brief.playCountLabel.isNotEmpty)
                  Text(
                    brief.playCountLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: kugo.caption.copyWith(
                      fontSize: dense ? 11 : null,
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
    this.platform = MusicPlatform.kugou,
  });

  final PlaylistBrief? brief;
  final int tracksCount;
  final String fallbackId;

  /// 头部信息行里追加「来源：X」，告诉用户这份歌单 / 榜单来自哪个音源。
  final MusicPlatform platform;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final b = brief;
    final cover = b?.coverUrl ?? '';
    final hasRealCover = cover.isNotEmpty &&
        !cover.contains('mock://') &&
        (cover.startsWith('http://') || cover.startsWith('https://'));
    final isLiked = b != null &&
        (b.name == '我喜欢' ||
            b.name.contains('喜欢') ||
            (b.isDefault && b.id == '2'));
    final isDefaultCollect = b != null &&
        (b.name == '默认收藏' || b.name.contains('收藏'));

    Widget bgWidget() {
      if (hasRealCover) {
        return CoverBox(
          seed: cover,
          size: 0,
          radius: 0,
        );
      }
      if (isLiked) {
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF8B1538), Color(0xFFD83A56), Color(0xFF1A1A24)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 28, right: 28),
              child: Icon(
                Icons.favorite_rounded,
                size: 110,
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
          ),
        );
      }
      if (isDefaultCollect) {
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2C3E50), Color(0xFF4A00E0), Color(0xFF1A1A24)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 28, right: 28),
              child: Icon(
                Icons.bookmark_rounded,
                size: 110,
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
          ),
        );
      }
      return CoverBox(
        seed: cover.isNotEmpty ? cover : fallbackId,
        size: 0,
        radius: 0,
      );
    }

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          bgWidget(),
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
                      : [
                          '$tracksCount 首',
                          if (b.playCountLabel.isNotEmpty) b.playCountLabel,
                          if (b.updateFrequency.isNotEmpty) b.updateFrequency,
                          '来源：${platform.label}',
                        ].join(' · '),
                  style: kugo.caption.copyWith(decoration: TextDecoration.none),
                ),
                if (b?.rankTypeName.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    b!.rankTypeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: kugo.caption.copyWith(
                      color: kugo.textSecondary.withValues(alpha: 0.85),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
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

  PlaylistBrief? brief;
  int tracksCount = 0;
  bool showTitle = false;
  bool dense = false;
  String fallbackId = '';
  MusicPlatform? platform;

  bool isRankCard = false;
  for (final ctx in [toHeroContext, fromHeroContext]) {
    final w = ctx.widget;
    if (w is Hero) {
      if (w.child is RankDetailHeaderSurface) {
        final surface = w.child as RankDetailHeaderSurface;
        brief ??= surface.brief;
        tracksCount = surface.tracksCount;
        fallbackId = surface.fallbackId;
        platform ??= surface.platform;
      } else if (w.child is RankCardSurface) {
        final surface = w.child as RankCardSurface;
        brief ??= surface.brief;
        showTitle = surface.showTitle;
        dense = surface.dense;
        isRankCard = true;
      } else if (w.child is CoverBox) {
        final box = w.child as CoverBox;
        if (fallbackId.isEmpty) fallbackId = box.seed;
      }
    }
  }

  final seed = brief?.coverUrl ?? fallbackId;
  final bytes = seed.isEmpty ? null : CoverCache.instance.peek(seed);

  final cardGrad = isRankCard
      ? rankCardGradient()
      : const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.transparent],
        );
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
      final progress = isPush ? rawValue : (1.0 - rawValue);
      final t = Curves.easeInOutCubic.transform(progress);
      final radius = fromRadius + (toRadius - fromRadius) * t;
      final currentGrad = LinearGradient.lerp(fromGrad, toGrad, t) ?? fromGrad;
      final sourceTextOpacity = (1.0 - progress * 2.5).clamp(0.0, 1.0);
      final destTextOpacity = ((progress - 0.4) / 0.6).clamp(0.0, 1.0);
      final cardTextOpacity = isPush ? sourceTextOpacity : destTextOpacity;
      final headerTextOpacity = isPush ? destTextOpacity : sourceTextOpacity;
      final inset = dense ? 8.0 : 12.0;

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
              coverImage,
              DecoratedBox(
                decoration: BoxDecoration(gradient: currentGrad),
              ),
              if (brief != null && cardTextOpacity > 0)
                Positioned(
                  left: inset,
                  right: inset,
                  bottom: inset,
                  child: Opacity(
                    opacity: cardTextOpacity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showTitle) ...[
                          Text(
                            brief.name,
                            maxLines: dense ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: kugo.section.copyWith(
                              fontSize: dense ? 13 : 17,
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
                              fontSize: dense ? 11 : null,
                              color: showTitle
                                  ? kugo.onCoverMuted
                                  : Colors.white70,
                              decoration: TextDecoration.none,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
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
                              : [
                                  '$tracksCount 首',
                                  if (brief.playCountLabel.isNotEmpty)
                                    brief.playCountLabel,
                                  if (brief.updateFrequency.isNotEmpty)
                                    brief.updateFrequency,
                                  if (platform != null)
                                    '来源：${platform.label}',
                                ].join(' · '),
                          style: kugo.caption
                              .copyWith(decoration: TextDecoration.none),
                        ),
                        if (brief?.rankTypeName.isNotEmpty == true) ...[
                          const SizedBox(height: 4),
                          Text(
                            brief!.rankTypeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: kugo.caption.copyWith(
                              color: kugo.textSecondary
                                  .withValues(alpha: 0.85),
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                        if (brief?.description.isNotEmpty == true) ...[
                          const SizedBox(height: 8),
                          Text(
                            brief!.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: kugo.caption.copyWith(
                              color:
                                  kugo.textSecondary.withValues(alpha: 0.8),
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
