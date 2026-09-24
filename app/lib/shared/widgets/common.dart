import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/audio_quality.dart';
import '../../core/models/track.dart';
import '../../core/platform.dart';
import '../../core/source/music_platform.dart';
import '../../core/theme/hero_tags.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../core/theme/responsive.dart';
import 'cover_box.dart';

/// Builds an `onArtistTap` callback for a track row.
///
/// The artist-detail route needs a **numeric singer id**, not a name —
/// passing the name makes `singer/info` answer `参数错误` and the page shows
/// "加载失败". Payloads that only carry `filename` (e.g. `special/song`)
/// have no id, so this returns `null` and the row simply renders the artist
/// as plain, non-tappable text.
VoidCallback? artistTapFor(BuildContext context, Track track) {
  if (!track.hasArtistId) return null;
  return () => context.push('/artist/${track.artistId}');
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.showAccent = false,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool showAccent;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KugoSpacing.lg,
        KugoSpacing.xl,
        KugoSpacing.lg,
        KugoSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: kugo.section),
              if (showAccent) ...[
                const SizedBox(height: 6),
                Container(
                  width: 28,
                  height: 3,
                  decoration: BoxDecoration(
                    gradient: kugo.accentGradient,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ],
          ),
          const Spacer(),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel!,
                    style: kugo.caption.copyWith(fontSize: 13),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: kugo.textSecondary,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class QualityBadge extends StatelessWidget {
  const QualityBadge({super.key, required this.label, this.gradient = false});

  final String label;
  final bool gradient;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: gradient ? kugo.accentGradient : null,
        color: gradient ? null : kugo.surfaceElevated,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          // On the accent gradient the label must stay light in both themes.
          color: gradient ? kugo.onAccent : kugo.textPrimary,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// 来源角标：混排结果里标明这一行来自哪个音源。
///
/// 单源或已按音源筛选时不显示（见 `search_page.dart` 的 `showSource`）。
class SourceBadge extends StatelessWidget {
  const SourceBadge({super.key, required this.platform});

  final MusicPlatform platform;

  @override
  Widget build(BuildContext context) =>
      QualityBadge(label: platform.label);
}

/// 音源筛选条：全部 / 酷狗 / 网易云 …（只有一个源时不显示）。
///
/// 「切换音源」的轻量机制之一（见方案 §11 决策记录），不做全局音源切换。
/// 搜索页与「我喜欢」页共用。
class SourceFilterBar extends StatelessWidget {
  const SourceFilterBar({
    super.key,
    required this.platforms,
    required this.selected,
    required this.onSelect,
  });

  final List<MusicPlatform> platforms;

  /// `null` = 全部源（混排）。
  final MusicPlatform? selected;
  final ValueChanged<MusicPlatform?> onSelect;

  @override
  Widget build(BuildContext context) {
    if (platforms.length <= 1) return const SizedBox.shrink();
    final kugo = KugoTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: KugoSpacing.sm),
      child: SizedBox(
        height: 32,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: KugoSpacing.lg),
          children: [
            _SourceChip(
              label: '全部',
              selected: selected == null,
              onTap: () => onSelect(null),
              kugo: kugo,
            ),
            for (final p in platforms) ...[
              const SizedBox(width: KugoSpacing.sm),
              _SourceChip(
                label: p.label,
                selected: selected == p,
                onTap: () => onSelect(p),
                kugo: kugo,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.kugo,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final KugoTheme kugo;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: kugo.surface,
          borderRadius: BorderRadius.circular(KugoRadius.chip),
          border: Border.all(color: selected ? kugo.primary : kugo.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check_rounded, size: 13, color: kugo.primary),
              const SizedBox(width: 3),
            ],
            Text(
              label,
              style: kugo.caption.copyWith(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? kugo.primary : kugo.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    this.trailing,
    this.onTap,
    this.onArtistTap,
    this.isPlaying = false,
    this.index,
    this.showAlbum = false,
    this.showSource = false,
  });

  final Track track;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onArtistTap;
  final bool isPlaying;
  final int? index;

  /// 在时长前展示专辑名（歌手页等宽列表）。默认关闭，不影响其他页面。
  final bool showAlbum;

  /// 展示音源来源角标（多源混排搜索结果用）。
  final bool showSource;

  /// Catalog quality chip for lists: highest known tag, hide plain SD/SQ-default.
  static String? _listQualityBadge(Track track) {
    final available = track.availableQualities;
    if (available.isNotEmpty) {
      if (available.length == 1 && available.contains(AppQuality.standard)) {
        return null;
      }
      for (final q in const [
        AppQuality.hiRes,
        AppQuality.sq,
        AppQuality.hq,
      ]) {
        if (available.contains(q)) return q.badge;
      }
      return null;
    }
    final raw = track.quality.trim();
    if (raw.isEmpty || raw == 'SQ' || raw == 'SD') return null;
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final titleStyle = kugo.body.copyWith(
      color: isPlaying ? kugo.primary : kugo.textPrimary,
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KugoRadius.tile),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KugoSpacing.lg,
          vertical: 10,
        ),
        child: Row(
          children: [
            if (index != null)
              SizedBox(
                width: 28,
                child: Text(
                  '${index!}',
                  textAlign: TextAlign.center,
                  style: kugo.caption.copyWith(
                    color: isPlaying
                        ? kugo.primary
                        : kugo.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Stack(
              children: [
                CoverBox(seed: track.coverUrl, size: 52),
                if (isPlaying)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(KugoRadius.cover),
                      ),
                      child: Icon(
                        Icons.equalizer_rounded,
                        color: kugo.primary,
                        size: 22,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: KugoSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: GestureDetector(
                          onTap: onArtistTap,
                          child: Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: kugo.caption.copyWith(
                              color: onArtistTap == null
                                  ? kugo.textSecondary
                                  : kugo.primary,
                            ),
                          ),
                        ),
                      ),
                      if (track.isVip) ...[
                        const SizedBox(width: 6),
                        const QualityBadge(label: 'VIP', gradient: true),
                      ],
                      if (_listQualityBadge(track) != null) ...[
                        const SizedBox(width: 6),
                        QualityBadge(label: _listQualityBadge(track)!),
                      ],
                      if (showSource) ...[
                        const SizedBox(width: 6),
                        SourceBadge(platform: track.platform),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (showAlbum && track.album.isNotEmpty) ...[
              const SizedBox(width: KugoSpacing.md),
              SizedBox(
                width: 140,
                child: Text(
                  track.album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: kugo.caption.copyWith(color: kugo.textSecondary),
                ),
              ),
            ],
            if (trailing != null)
              trailing!
            else if (showAlbum) ...[
              const SizedBox(width: KugoSpacing.md),
              SizedBox(
                width: 48,
                child: Text(
                  track.durationLabel,
                  textAlign: TextAlign.right,
                  style: kugo.caption.copyWith(
                    color: kugo.textTertiary,
                  ),
                ),
              ),
            ] else
              Text(
                track.durationLabel,
                style: kugo.caption.copyWith(
                  color: kugo.textTertiary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class PlaylistCard extends StatelessWidget {
  const PlaylistCard({
    super.key,
    required this.playlist,
    this.width = 120,
    this.onTap,
  });

  final PlaylistBrief playlist;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (playlist.id.isNotEmpty)
                    CoverHero(
                      tag: playlist.isRank
                          ? KugoHeroTags.rankCover(playlist.id)
                          : KugoHeroTags.playlistCover(playlist.id),
                      seed: playlist.coverUrl,
                      size: width,
                      radius: KugoRadius.card,
                    )
                  else
                    CoverBox(
                      seed: playlist.coverUrl,
                      size: width,
                      radius: KugoRadius.card,
                    ),
                  if (playlist.playCountLabel.isNotEmpty &&
                      !playlist.playCountLabel.contains('/'))
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(KugoRadius.chip),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.play_arrow_rounded,
                              size: 12,
                              color: Colors.white,
                            ),
                            Text(
                              playlist.playCountLabel,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              playlist.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: kugo.body.copyWith(fontSize: 13, height: 1.3),
            ),
            if (playlist.description.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                playlist.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: kugo.caption,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Horizontal result row used by the playlist / album / artist search tabs.
///
/// The three differ only in their subtitle and the detail route they open, so
/// they share one layout instead of three near-identical widgets.
class SearchResultRow extends StatelessWidget {
  const SearchResultRow({
    super.key,
    required this.imageSeed,
    required this.title,
    this.subtitle = '',
    this.trailingLabel = '',
    this.round = false,
    this.heroTag,
    this.onTap,
    this.platform,
  });

  /// Cover URL (or color seed). Empty renders the gradient placeholder.
  final String imageSeed;
  final String title;
  final String subtitle;

  /// Small text on the right — track count, etc. Hidden when empty.
  final String trailingLabel;

  /// Circular art, for artists.
  final bool round;

  /// Optional Hero tag for seamless route transition.
  final String? heroTag;

  final VoidCallback? onTap;

  /// 非空时在右侧展示来源角标（多源混排搜索结果用）。
  final MusicPlatform? platform;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final radius = round ? 26.0 : KugoRadius.cover;
    final cover = CoverBox(
      seed: imageSeed,
      size: 52,
      radius: radius,
      child: round && imageSeed.trim().isEmpty
          ? Icon(
              Icons.person_rounded,
              size: 24,
              color: kugo.onAccent.withValues(alpha: 0.85),
            )
          : null,
    );
    final coverWidget = (heroTag != null && heroTag!.isNotEmpty)
        ? Hero(
            tag: heroTag!,
            flightShuttleBuilder: coverHeroFlightShuttle,
            child: cover,
          )
        : cover;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KugoRadius.tile),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KugoSpacing.lg,
          vertical: 10,
        ),
        child: Row(
          children: [
            coverWidget,
            const SizedBox(width: KugoSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: kugo.body,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kugo.caption,
                    ),
                  ],
                ],
              ),
            ),
            if (trailingLabel.isNotEmpty) ...[
              const SizedBox(width: KugoSpacing.sm),
              Text(
                trailingLabel,
                style: kugo.caption.copyWith(color: kugo.textTertiary),
              ),
            ],
            if (platform != null) ...[
              const SizedBox(width: 6),
              SourceBadge(platform: platform!),
            ],
          ],
        ),
      ),
    );
  }
}

class GlassSurface extends StatelessWidget {  const GlassSurface({
    super.key,
    required this.child,
    this.radius = KugoRadius.card,
    this.padding = const EdgeInsets.all(KugoSpacing.md),
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    // Material (not a bare Container) so ListTile ink splashes inside the card
    // paint on this surface instead of reaching for a distant ancestor —
    // otherwise Flutter asserts and the ripples are invisible.
    return Material(
      color: kugo.surface,
      elevation: kugo.palette.isLight ? 1 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: kugo.divider),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Themed bottom sheet chrome — background follows the **current** palette
/// (never pass a hardcoded color into showModalBottomSheet.backgroundColor).
class KugoSheetChrome extends StatelessWidget {
  const KugoSheetChrome({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    // Material (not a bare Container) so ListTile ink splashes inside sheets
    // have a surface to paint on.
    return Material(
      color: kugo.surfaceElevated,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: kugo.divider),
      ),
      child: child,
    );
  }
}

/// Themed desktop side sheet chrome — docked to the right edge with desktop elevation,
/// border-left divider, and comfortable width (~400px).
class KugoDesktopSideSheetChrome extends StatelessWidget {
  const KugoDesktopSideSheetChrome({
    super.key,
    required this.child,
    this.width = 400,
  });

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: kugo.surfaceElevated,
        elevation: 16,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        shape: Border(
          left: BorderSide(color: kugo.divider, width: 1),
        ),
        child: SizedBox(
          width: width,
          height: double.infinity,
          child: Stack(
            children: [
              Positioned.fill(
                child: SafeArea(
                  child: child,
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: '关闭',
                  splashRadius: 18,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<T?> showKugoBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
}) {
  if (isDesktopPlatform && isDesktopView(context)) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, _, _) {
        return KugoDesktopSideSheetChrome(
          child: builder(dialogContext),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
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

  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    isScrollControlled: isScrollControlled,
    builder: (sheetContext) => KugoSheetChrome(
      child: SafeArea(child: builder(sheetContext)),
    ),
  );
}
