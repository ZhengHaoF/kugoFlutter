import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/audio_quality.dart';
import '../../core/models/track.dart';
import '../../core/platform.dart';
import '../../core/source/features.dart';
import '../../core/source/music_platform.dart';
import '../../core/theme/hero_tags.dart';
import '../../core/theme/overtone_theme.dart';
import '../../core/theme/overtone_tokens.dart';
import '../../core/theme/responsive.dart';
import '../../features/mv/mv_entry.dart';
import 'overtone_clickable.dart';
import 'cover_box.dart';
import 'overtone_h_scroll.dart';

/// Builds an `onArtistTap` callback for a track row.
///
/// The artist-detail route needs a **numeric singer id**, not a name —
/// passing the name makes `singer/info` answer `参数错误` and the page shows
/// "加载失败". Payloads that only carry `filename` (e.g. `special/song`)
/// have no id, so this returns `null` and the row simply renders the artist
/// as plain, non-tappable text.
VoidCallback? artistTapFor(BuildContext context, Track track) {
  if (!track.hasArtistId) return null;
  // 非酷狗曲目的 artistId 是对应源的歌手 id，必须带 src 让详情页按源取数。
  final src = track.platform == MusicPlatform.kugou
      ? ''
      : '?src=${track.platform.wireName}';
  return () => context.push('/artist/${track.artistId}$src');
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
    final theme = OvertoneTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OvertoneSpacing.lg,
        OvertoneSpacing.xl,
        OvertoneSpacing.lg,
        OvertoneSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.section),
              if (showAccent) ...[
                const SizedBox(height: 6),
                Container(
                  width: 28,
                  height: 3,
                  decoration: BoxDecoration(
                    gradient: theme.accentGradient,
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
                    style: theme.caption.copyWith(fontSize: 13),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: theme.textSecondary,
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
    final theme = OvertoneTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: gradient ? theme.accentGradient : null,
        color: gradient ? null : theme.surfaceElevated,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          // On the accent gradient the label must stay light in both themes.
          color: gradient ? theme.onAccent : theme.textPrimary,
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

/// 当前音源只读小字：`来源：酷狗`。
///
/// 与 [SourceBadge]（行内角标）区分：用于「整页 / 整块内容来自哪个源」的
/// 场景——播放器、详情页头部、发现页头。多源场景下
/// 优先用可切换的 `SourceFilterBar` chips，这里只做只读陈述，不承载切换。
class SourceLabel extends StatelessWidget {
  const SourceLabel({
    super.key,
    required this.platform,
    this.prefix = '来源：',
    this.compact = false,
  });

  final MusicPlatform platform;

  /// 前缀文案。按场景可覆盖为「当前音源：」等更明确的说法。
  final String prefix;

  /// 紧凑模式：去掉图标，只留文字（用于空间受限处，如迷你播放条）。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = OvertoneTheme.of(context);
    final style = theme.caption.copyWith(
      fontSize: compact ? 10 : 11,
      color: theme.textTertiary,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!compact) ...[
          Icon(Icons.source_rounded, size: 12, color: theme.textTertiary),
          const SizedBox(width: 4),
        ],
        Text('$prefix${platform.label}', style: style),
      ],
    );
  }
}

/// 「音源已停用」空态：整源开关关掉某源后，只依赖该源的页面（FM /
/// 榜单 / 每日推荐 / 发现）用它代替内容区，避免空白或一串请求报错。
///
/// 只拦「新内容入口」：正在播放 / 已入队的曲目不受影响（见方案 §11）。
class SourceDisabledView extends StatelessWidget {
  const SourceDisabledView({super.key, required this.platform, this.feature});

  final MusicPlatform platform;

  /// 非 null 表示归因到**功能**（源还启用着，只是这项被单独关了），
  /// 文案与「整个源被停用」区分开——不然用户会去开整源开关却发现本来就开着。
  final SourceFeature? feature;

  @override
  Widget build(BuildContext context) {
    final theme = OvertoneTheme.of(context);
    final f = feature;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(OvertoneSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.power_settings_new, size: 44, color: theme.textTertiary),
            const SizedBox(height: OvertoneSpacing.lg),
            Text(
              f == null
                  ? '${platform.label}音源已停用'
                  : '${platform.label}的「${f.label}」已关闭',
              style: theme.section,
            ),
            const SizedBox(height: OvertoneSpacing.sm),
            Text(
              f == null
                  ? '本页内容依赖${platform.label}。已停用期间不再请求该音源；'
                      '已在播放队列中的歌曲不受影响。'
                  : '${platform.label}音源仍启用，只是这一项功能被单独关掉了；'
                      '开启后本页即可用。已在播放队列中的歌曲不受影响。',
              textAlign: TextAlign.center,
              style: theme.caption.copyWith(color: theme.textTertiary),
            ),
            const SizedBox(height: OvertoneSpacing.lg),
            FilledButton.tonal(
              onPressed: () => context.push('/settings'),
              child: const Text('去设置开启'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 音源筛选条：全部 / 酷狗 / 网易云 …（只有一个源时不显示）。
///
/// 「切换音源」的轻量机制之一（见方案 §11 决策记录），不做全局音源切换。
/// 搜索页与「我喜欢」页共用。
///
/// 本组件**只负责展示与回调**，不写任何全局状态；「切源后同步全局默认源
/// （`settings.defaultSource`）」由各调用点的 `onSelect` 自行处理，保持
/// `shared/` 不反向依赖 `features/`。
class SourceFilterBar extends StatelessWidget {
  const SourceFilterBar({
    super.key,
    required this.platforms,
    required this.selected,
    required this.onSelect,
    this.showAll = true,
    this.horizontalPadding = OvertoneSpacing.lg,
  });

  final List<MusicPlatform> platforms;

  /// `null` = 全部源（混排）。[showAll] 为 false 时该值不出现。
  final MusicPlatform? selected;
  final ValueChanged<MusicPlatform?> onSelect;

  /// 是否渲染「全部」chip。榜单等**不可混排**的列表传 false（单源模式）。
  final bool showAll;

  /// chips 的左右内边距。放进已有左右留白的页面（如「我的」）时传 0，
  /// 避免和页面留白叠加成双份。
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    if (platforms.length <= 1) return const SizedBox.shrink();
    final theme = OvertoneTheme.of(context);
    return Padding(
      // 与「我的」页标题→筛选条间距对齐：紧贴 AppBar / TabBar 会显得挤。
      padding: const EdgeInsets.only(top: OvertoneSpacing.md, bottom: OvertoneSpacing.sm),
      child: SizedBox(
        height: 32,
        child: OvertoneHScroll(
          fadeEdges: false,
          builder: (context, controller, _) => ListView(
            controller: controller,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            children: [
              if (showAll)
                _SourceChip(
                  label: '全部',
                  selected: selected == null,
                  onTap: () => onSelect(null),
                  theme: theme,
                ),
              for (var i = 0; i < platforms.length; i++) ...[
                if (showAll || i > 0) const SizedBox(width: OvertoneSpacing.sm),
                _SourceChip(
                  label: platforms[i].label,
                  selected: selected == platforms[i],
                  onTap: () => onSelect(platforms[i]),
                  theme: theme,
                ),
              ],
            ],
          ),
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
    required this.theme,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final OvertoneTheme theme;

  @override
  Widget build(BuildContext context) {
    return OvertoneClickable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(OvertoneRadius.chip),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(OvertoneRadius.chip),
          border: Border.all(color: selected ? theme.primary : theme.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check_rounded, size: 13, color: theme.primary),
              const SizedBox(width: 3),
            ],
            Text(
              label,
              style: theme.caption.copyWith(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? theme.primary : theme.textSecondary,
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
    this.showMv = true,
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

  /// 这首「可能」有 MV 时，在时长前露一个 MV 入口（桌面悬停显现）。
  ///
  /// 默认开：内容列表（歌单/搜索/专辑/歌手/收藏/历史/推荐）都能一键进 MV，
  /// 能力/`mixSongId` 不满足时按钮自身不占位。个别不想显示的页面传 `false`。
  final bool showMv;

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
  Widget build(BuildContext context) => RepaintBoundary(
    // 桌面端鼠标扫过列表时每行都会 hover setState + 140ms 的 AnimatedOpacity，
    // 没有重绘边界的话这些重绘会向上污染整段列表（本文件原先没有任何
    // RepaintBoundary）。边界把重绘限制在单行内，滚动时尤其明显。
    child: _HoverScope(
      builder: (context, hovered) => _buildRow(context, hovered),
    ),
  );

  Widget _buildRow(BuildContext context, bool hovered) {
    final theme = OvertoneTheme.of(context);
    final titleStyle = theme.body.copyWith(
      color: isPlaying ? theme.primary : theme.textPrimary,
    );

    return OvertoneClickable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(OvertoneRadius.tile),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: OvertoneSpacing.lg,
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
                  style: theme.caption.copyWith(
                    color: isPlaying
                        ? theme.primary
                        : theme.textTertiary,
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
                        borderRadius: BorderRadius.circular(OvertoneRadius.cover),
                      ),
                      child: Icon(
                        Icons.equalizer_rounded,
                        color: theme.primary,
                        size: 22,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: OvertoneSpacing.md),
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
                            style: theme.caption.copyWith(
                              color: onArtistTap == null
                                  ? theme.textSecondary
                                  : theme.primary,
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
              const SizedBox(width: OvertoneSpacing.md),
              SizedBox(
                width: 140,
                child: Text(
                  track.album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: theme.caption.copyWith(color: theme.textSecondary),
                ),
              ),
            ],
            if (showMv && canOpenMv(track)) ...[
              const SizedBox(width: OvertoneSpacing.xs),
              // 桌面端跟随整行 hover 显现（对齐 EchoMusic），移动端常驻。
              IgnorePointer(
                ignoring: isDesktopView(context) && !hovered,
                child: AnimatedOpacity(
                  opacity: !isDesktopView(context) || hovered ? 1 : 0,
                  duration: const Duration(milliseconds: 140),
                  child: MvEntryButton(track: track, size: 18),
                ),
              ),
            ],
            if (trailing != null)
              trailing!
            else if (showAlbum) ...[
              const SizedBox(width: OvertoneSpacing.md),
              SizedBox(
                width: 48,
                child: Text(
                  track.durationLabel,
                  textAlign: TextAlign.right,
                  style: theme.caption.copyWith(
                    color: theme.textTertiary,
                  ),
                ),
              ),
            ] else
              Text(
                track.durationLabel,
                style: theme.caption.copyWith(
                  color: theme.textTertiary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HoverScope extends StatefulWidget {
  const _HoverScope({required this.builder});

  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<_HoverScope> createState() => _HoverScopeState();
}

class _HoverScopeState extends State<_HoverScope> {
  bool _hovered = false;

  void _handleEnter(PointerEnterEvent _) {
    if (_hovered) return;
    setState(() => _hovered = true);
  }

  void _handleExit(PointerExitEvent _) {
    if (!_hovered || !mounted) return;
    setState(() => _hovered = false);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: _handleEnter,
    onExit: _handleExit,
    child: widget.builder(context, _hovered),
  );
}

class PlaylistCard extends StatelessWidget {
  const PlaylistCard({
    super.key,
    required this.playlist,
    this.width = 120,
    this.onTap,
    this.platform,
  });

  final PlaylistBrief playlist;
  final double width;
  final VoidCallback? onTap;

  /// 非 null 时在**封面左上角**浮一个来源角标（不占额外高度）。
  ///
  /// 调用点只在**多源**时传值：单源已有页头只读标签，
  /// 逐卡再挂同一个源属重复噪音。
  final MusicPlatform? platform;

  @override
  Widget build(BuildContext context) {
    final theme = OvertoneTheme.of(context);
    return OvertoneClickable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(OvertoneRadius.card),
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
                          ? OvertoneHeroTags.rankCover(playlist.id)
                          : OvertoneHeroTags.playlistCover(playlist.id),
                      seed: playlist.coverUrl,
                      size: width,
                      radius: OvertoneRadius.card,
                    )
                  else
                    CoverBox(
                      seed: playlist.coverUrl,
                      size: width,
                      radius: OvertoneRadius.card,
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
                          borderRadius: BorderRadius.circular(OvertoneRadius.chip),
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
                  // 来源角标贴在封面左上角，与右下角播放量小胶囊对角，不抢视线。
                  if (platform != null)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: SourceBadge(platform: platform!),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              playlist.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.body.copyWith(fontSize: 13, height: 1.3),
            ),
            if (playlist.description.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                playlist.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.caption,
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
    final theme = OvertoneTheme.of(context);
    final radius = round ? 26.0 : OvertoneRadius.cover;
    final cover = CoverBox(
      seed: imageSeed,
      size: 52,
      radius: radius,
      child: round && imageSeed.trim().isEmpty
          ? Icon(
              Icons.person_rounded,
              size: 24,
              color: theme.onAccent.withValues(alpha: 0.85),
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

    return RepaintBoundary(
      // 搜索结果行同样进长列表：给出重绘边界，避免行内变化（hover/封面淡入）
      // 把重绘范围扩散到整段列表。
      child: OvertoneClickable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(OvertoneRadius.tile),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: OvertoneSpacing.lg,
            vertical: 10,
          ),
          child: Row(
            children: [
              coverWidget,
              const SizedBox(width: OvertoneSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.body,
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.caption,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailingLabel.isNotEmpty) ...[
                const SizedBox(width: OvertoneSpacing.sm),
                Text(
                  trailingLabel,
                  style: theme.caption.copyWith(color: theme.textTertiary),
                ),
              ],
              if (platform != null) ...[
                const SizedBox(width: 6),
                SourceBadge(platform: platform!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class GlassSurface extends StatelessWidget {  const GlassSurface({
    super.key,
    required this.child,
    this.radius = OvertoneRadius.card,
    this.padding = const EdgeInsets.all(OvertoneSpacing.md),
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = OvertoneTheme.of(context);
    // Material (not a bare Container) so ListTile ink splashes inside the card
    // paint on this surface instead of reaching for a distant ancestor —
    // otherwise Flutter asserts and the ripples are invisible.
    return Material(
      color: theme.surface,
      elevation: theme.palette.isLight ? 1 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: theme.divider),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Themed bottom sheet chrome — background follows the **current** palette
/// (never pass a hardcoded color into showModalBottomSheet.backgroundColor).
class OvertoneSheetChrome extends StatelessWidget {
  const OvertoneSheetChrome({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = OvertoneTheme.of(context);
    // Material (not a bare Container) so ListTile ink splashes inside sheets
    // have a surface to paint on.
    return Material(
      color: theme.surfaceElevated,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: theme.divider),
      ),
      child: child,
    );
  }
}

/// Themed desktop side sheet chrome — docked to the right edge with desktop elevation,
/// border-left divider, and comfortable width (~400px).
class OvertoneDesktopSideSheetChrome extends StatelessWidget {
  const OvertoneDesktopSideSheetChrome({
    super.key,
    required this.child,
    this.width = 400,
  });

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = OvertoneTheme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: theme.surfaceElevated,
        elevation: 16,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        shape: Border(
          left: BorderSide(color: theme.divider, width: 1),
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

Future<T?> showOvertoneBottomSheet<T>({
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
        return OvertoneDesktopSideSheetChrome(
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
    builder: (sheetContext) => OvertoneSheetChrome(
      child: SafeArea(child: builder(sheetContext)),
    ),
  );
}
