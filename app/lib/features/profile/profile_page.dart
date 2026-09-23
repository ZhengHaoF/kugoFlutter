import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/track.dart';
import '../../core/theme/hero_tags.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../core/theme/responsive.dart';
import '../../data/storage/queue_store.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/likes/likes_controller.dart';
import '../../features/profile/user_collections_controller.dart';
import '../../features/rank/rank_hero.dart' show rankHeroFlightShuttle;
import '../../features/settings/settings_controller.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/cover_box.dart';
import '../../shared/widgets/settings_pickers.dart';
import '../../shared/widgets/smooth_scroll.dart';

/// 「我的」— 乐库入口页。
///
/// 只放：紧凑用户入口（→ `/profile/detail` 个人中心）、乐库统计、歌单、设置快捷。
/// 账号身份 / 等级 / 关注粉丝 / 档案 / 会员**不在此页**，见 [ProfileDetailPage]。
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  /// Distinct tracks in local play history. `null` until the DB answers, so the
  /// tile can render a placeholder instead of a wrong `0`.
  int? _historyCount;
  int _selectedPlaylistTab = 0;
  final GlobalKey _playlistsSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier).refreshProfile();
      _loadHistoryCount();
    });
  }

  Future<void> _loadHistoryCount() async {
    try {
      final store = await QueueStore.open();
      final count = await store.historyCount();
      if (!mounted) return;
      setState(() => _historyCount = count);
    } catch (_) {
      // Leave null → renders as placeholder rather than a misleading 0.
    }
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final isDesktop = isDesktopView(context);
    ref.watch(settingsControllerProvider.select((s) => s.themeMode));
    final settings = ref.watch(settingsControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final collections = ref.watch(userCollectionsProvider);
    final likesCount = ref.watch(likesProvider).length;
    final realLikesCount = auth.isLogged
        ? (collections.defaultLikedPlaylist?.trackCount ??
            (collections.cloudFavoriteTracks.isNotEmpty
                ? collections.cloudFavoriteTracks.length
                : likesCount))
        : likesCount;
    final user = auth.user;

    final displayName = auth.isLogged
        ? (user?.nickname ?? '用户')
        : (auth.restored ? '游客' : '…');
    final displaySub = auth.isLogged
        ? (user!.isVip ? '概念会员' : '已登录 · 查看个人中心')
        : '未登录 · 公开内容可用';
    final avatarUrl = user?.avatarUrl ?? '';
    final sleepLabel = settings.sleepMinutes == 0
        ? '关闭'
        : '${settings.sleepMinutes} 分钟';

    final playlistStatValue = !auth.isLogged
        ? '—'
        : (collections.isLoadingPlaylists && !collections.loaded
            ? '—'
            : '${collections.totalPlaylistsCount}');
    final playlistStatHint = !auth.isLogged ? '需登录' : null;

    return SmoothListView(
      padding: EdgeInsets.fromLTRB(
        KugoSpacing.lg,
        KugoSpacing.xl,
        KugoSpacing.lg,
        isDesktop ? 48 : 140,
      ),
      children: [
        Text('我的', style: kugo.greeting),
        const SizedBox(height: KugoSpacing.lg),
        GlassSurface(
          padding: const EdgeInsets.all(KugoSpacing.lg),
          child: Column(
            children: [
              // 紧凑用户入口 → 独立「个人中心」页（对齐 Echo 的 Profile 内容页）。
              InkWell(
                borderRadius: BorderRadius.circular(KugoRadius.tile),
                onTap: () => context.push('/profile/detail'),
                child: Row(
                  children: [
                    CoverBox(
                      seed: avatarUrl.isNotEmpty ? avatarUrl : 'avatar-guest',
                      size: 56,
                      radius: 999,
                      child: avatarUrl.isNotEmpty
                          ? null
                          : const Icon(
                              Icons.person_rounded,
                              color: Colors.white70,
                              size: 28,
                            ),
                    ),
                    const SizedBox(width: KugoSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(displayName, style: kugo.title),
                          const SizedBox(height: 4),
                          Text(
                            displaySub,
                            style: kugo.caption.copyWith(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: kugo.textSecondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: KugoSpacing.lg),
              Row(
                children: [
                  const _Divider(),
                  Expanded(
                    child: _Stat(
                      label: '我喜欢',
                      value: '$realLikesCount',
                      onTap: () => context.push('/likes'),
                    ),
                  ),
                  const _Divider(),
                  Expanded(
                    child: _Stat(
                      label: '最近播放',
                      value: _historyCount == null ? '—' : '$_historyCount',
                      onTap: () => context.push('/history'),
                    ),
                  ),
                  const _Divider(),
                  Expanded(
                    child: _Stat(
                      label: '歌单',
                      value: playlistStatValue,
                      hint: playlistStatHint,
                      onTap: () {
                        if (!auth.isLogged) {
                          context.push('/login');
                        } else {
                          final ctx = _playlistsSectionKey.currentContext;
                          if (ctx != null) {
                            Scrollable.ensureVisible(
                              ctx,
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.easeInOut,
                            );
                          }
                        }
                      },
                    ),
                  ),
                  const _Divider(),
                ],
              ),
              if (auth.isLogged) ...[
                const SizedBox(height: KugoSpacing.xs),
                TextButton(
                  onPressed: () =>
                      ref.read(authControllerProvider.notifier).logout(),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(64, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    visualDensity: VisualDensity.compact,
                    foregroundColor: Colors.redAccent,
                  ),
                  child: const Text('退出登录'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: KugoSpacing.lg),
        // 用户卡与「我的歌单」之间不再放入口卡片：
        // * 「本地音乐」/「下载管理」两个占位入口已砍掉（旧版只弹「开发中」提示，无真实能力）；
        // * 「播放历史」与用户卡「最近播放」重复，统一从统计进 /history。
        // 将来新增入口时在此重建卡片；不要留只弹提示的假入口。
        GlassSurface(
          key: _playlistsSectionKey,
          padding: const EdgeInsets.all(KugoSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '我的歌单',
                    style: kugo.section.copyWith(fontSize: 16),
                  ),
                  const Spacer(),
                  if (auth.isLogged)
                    IconButton(
                      icon: collections.isLoadingPlaylists
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 20),
                      tooltip: '刷新歌单',
                      onPressed: collections.isLoadingPlaylists
                          ? null
                          : () => ref
                              .read(userCollectionsProvider.notifier)
                              .loadPlaylists(),
                    ),
                ],
              ),
              const SizedBox(height: KugoSpacing.md),
              if (!auth.isLogged) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: KugoSpacing.md,
                    vertical: KugoSpacing.lg,
                  ),
                  decoration: BoxDecoration(
                    color: kugo.surfaceElevated.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(KugoRadius.tile),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.queue_music_rounded,
                        size: 38,
                        color: kugo.textSecondary.withValues(alpha: 0.7),
                      ),
                      const SizedBox(height: KugoSpacing.sm),
                      Text(
                        '登录酷狗账号后，即可同步自建与收藏歌单',
                        style: kugo.caption.copyWith(fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: KugoSpacing.md),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 8,
                          ),
                        ),
                        onPressed: () => context.push('/login'),
                        child: const Text('立即登录'),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Center(
                  child: SegmentedButton<int>(
                    segments: [
                      ButtonSegment<int>(
                        value: 0,
                        label: Text('自建 (${collections.createdPlaylists.length})'),
                      ),
                      ButtonSegment<int>(
                        value: 1,
                        label: Text('收藏 (${collections.collectedPlaylists.length})'),
                      ),
                    ],
                    selected: {_selectedPlaylistTab},
                    onSelectionChanged: (set) =>
                        setState(() => _selectedPlaylistTab = set.first),
                  ),
                ),
                const SizedBox(height: KugoSpacing.md),
                ..._buildPlaylistList(
                  _selectedPlaylistTab == 0
                      ? collections.createdPlaylists
                      : collections.collectedPlaylists,
                  isCreatedTab: _selectedPlaylistTab == 0,
                  isLoading: collections.isLoadingPlaylists && !collections.loaded,
                  error: collections.playlistsError,
                  kugo: kugo,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: KugoSpacing.lg),
        GlassSurface(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              _LinkTile(
                icon: Icons.settings_outlined,
                title: '设置',
                onTap: () => context.push('/settings'),
              ),
              // Theme-colored tiles must not be const — Flutter skips rebuild
              // when the const instance is identical after a theme switch.
              _LinkTile(
                icon: Icons.timer_outlined,
                title: '定时停止',
                subtitle: sleepLabel,
                onTap: () => _showSleepSheet(context),
              ),
              _LinkTile(
                icon: Icons.music_note_rounded,
                title: '音质设置',
                subtitle: settings.qualityLabel,
                onTap: () => _showQualitySheet(context),
              ),
              _LinkTile(
                icon: Icons.palette_outlined,
                title: '主题外观',
                subtitle: settings.themeModeLabel,
                onTap: () => _showThemeSheet(context),
              ),
              _LinkTile(
                icon: Icons.info_outline_rounded,
                title: '关于',
                onTap: () => _showAboutSheet(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildPlaylistList(
    List<PlaylistBrief> playlists, {
    required bool isCreatedTab,
    required bool isLoading,
    required String error,
    required KugoTheme kugo,
  }) {
    if (isLoading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: KugoSpacing.xl),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (playlists.isEmpty) {
      final emptyHint = error.isNotEmpty
          ? error
          : (isCreatedTab ? '暂无自建歌单' : '暂无收藏歌单');
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: KugoSpacing.xl),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.music_note_rounded,
                  size: 36,
                  color: kugo.textSecondary.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 8),
                Text(emptyHint, style: kugo.caption),
              ],
            ),
          ),
        ),
      ];
    }

    return playlists.map((p) {
      final sub =
          '${p.trackCount} 首${p.creator.isNotEmpty ? ' · ${p.creator}' : ''}';
      return InkWell(
        borderRadius: BorderRadius.circular(KugoRadius.tile),
        onTap: () => context.push('/playlist/${p.id}', extra: p),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [
              _PlaylistTileCover(playlist: p, size: 48),
              const SizedBox(width: KugoSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: kugo.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sub,
                      style: kugo.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: kugo.textSecondary),
            ],
          ),
        ),
      );
    }).toList();
  }

  /// 定时停止 / 音质设置 / 关于 reuse the exact pickers the Settings page
  /// uses, so a change made here is reflected there and vice versa.
  void _showSleepSheet(BuildContext context) =>
      showSleepPicker(context, ref);

  void _showQualitySheet(BuildContext context) =>
      showQualityPicker(context, ref);

  void _showAboutSheet(BuildContext context) => showAboutSheet(context);

  void _showThemeSheet(BuildContext context) {
    showKugoBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final kugo = KugoTheme.of(context);
            final current = ref.watch(settingsControllerProvider).themeMode;
            Widget tile(
              AppThemeMode value,
              IconData icon,
              String title,
              String sub,
            ) {
              final selected = current == value;
              return ListTile(
                leading: Icon(
                  icon,
                  color: selected ? kugo.primary : kugo.textSecondary,
                ),
                title: Text(title, style: kugo.body),
                subtitle: Text(sub, style: kugo.caption),
                trailing: selected
                    ? Icon(Icons.check_rounded, color: kugo.primary)
                    : null,
                onTap: () async {
                  await ref
                      .read(settingsControllerProvider.notifier)
                      .setThemeMode(value);
                  if (sheetContext.mounted) {
                    setSheetState(() {});
                    Navigator.of(sheetContext).pop();
                  }
                },
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Text('主题外观', style: kugo.section),
                const SizedBox(height: 8),
                tile(
                  AppThemeMode.dark,
                  Icons.dark_mode_rounded,
                  '深色',
                  '概念版默认深色',
                ),
                tile(
                  AppThemeMode.light,
                  Icons.light_mode_rounded,
                  '浅色',
                  '浅色完整适配',
                ),
                tile(
                  AppThemeMode.system,
                  Icons.brightness_auto_rounded,
                  '跟随系统',
                  '随系统深浅色切换',
                ),
                const SizedBox(height: 12),
              ],
            );
          },
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.hint,
    this.onTap,
  });

  final String label;
  final String value;

  /// Optional secondary line under the value (e.g. why a value is missing).
  final String? hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    // Fixed height so a placeholder (`—`) and a real number don't shift the
    // row when the async values land. Sized for label + value + hint.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KugoRadius.tile),
      child: SizedBox(
        // 有 hint 时再撑高，避免无副标题时统计区底部空一截、退出登录显得过远。
        height: hint != null ? 76 : 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(label, style: kugo.caption),
            const SizedBox(height: 4),
            Text(value, style: kugo.section.copyWith(fontSize: 20)),
            if (hint != null) ...[
              const SizedBox(height: 3),
              Text(
                hint!,
                style: kugo.caption.copyWith(fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 36, color: KugoTheme.of(context).divider);
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;

  /// Shown as a secondary line, and as the trailing value when short enough
  /// to read as a status (e.g. 「15 分钟」/「HQ」/「深色」).
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Prefer Material onSurface so titles stay readable even if static
    // Kugo tokens are briefly stale during a theme switch.
    final scheme = Theme.of(context).colorScheme;
    final kugo = KugoTheme.of(context);
    final body = kugo.body.copyWith(color: scheme.onSurface);
    final sub = subtitle;
    return ListTile(
      leading: Icon(icon, color: scheme.onSurfaceVariant),
      title: Text(title, style: body),
      subtitle: sub == null || sub.isEmpty
          ? null
          : Text(sub, style: kugo.caption),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: scheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}

class _PlaylistTileCover extends ConsumerWidget {
  const _PlaylistTileCover({
    required this.playlist,
    this.size = 48,
  });

  final PlaylistBrief playlist;
  final double size;

  static bool _isNetwork(String? url) {
    if (url == null) return false;
    final s = url.trim();
    return (s.startsWith('http://') || s.startsWith('https://')) &&
        !s.contains('mock://');
  }

  /// Matches [PlaylistDetailPage]'s non-rank header Hero so the tile flies.
  Widget _withHero(Widget cover) {
    final id = playlist.id;
    if (id.isEmpty) return cover;
    return Hero(
      tag: KugoHeroTags.playlistCover(id),
      flightShuttleBuilder: rankHeroFlightShuttle,
      child: cover,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = playlist;
    final collections = ref.watch(userCollectionsProvider);

    final isLiked = p.isDefault &&
        (p.name == '我喜欢' ||
            p.name.contains('喜欢') ||
            p.name.toLowerCase().contains('like'));
    final isDefaultCollect = p.isDefault &&
        (p.name == '默认收藏' || p.name.contains('收藏'));

    // Check if we have a direct valid cover URL
    String targetCover = _isNetwork(p.coverUrl) ? p.coverUrl : '';

    // If it's "我喜欢" and direct cover is empty, check if first song in cloudFavoriteTracks has cover
    if (isLiked && targetCover.isEmpty) {
      final firstSongCover = collections.cloudFavoriteTracks
          .where((t) => _isNetwork(t.coverUrl))
          .firstOrNull
          ?.coverUrl;
      if (firstSongCover != null && firstSongCover.isNotEmpty) {
        targetCover = firstSongCover;
      }
    }

    // 1. If we have a valid network cover, show CoverBox with real image!
    if (targetCover.isNotEmpty) {
      final coverWidget = _withHero(
        CoverBox(
          seed: targetCover,
          size: size,
          radius: KugoRadius.card,
          child: isLiked
              ? const Icon(Icons.favorite_rounded, color: Colors.white70, size: 24)
              : (isDefaultCollect
                  ? const Icon(Icons.bookmark_rounded, color: Colors.white70, size: 24)
                  : const Icon(Icons.queue_music_rounded, color: Colors.white70, size: 24)),
        ),
      );

      // If it's "我喜欢", add a subtle corner heart badge on top of the first song's cover
      if (isLiked) {
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              coverWidget,
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE84364),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.favorite_rounded,
                    size: 10,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return coverWidget;
    }

    // 2. No network cover available: render dedicated iconic gradient cover!
    if (isLiked) {
      return _withHero(
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KugoRadius.card),
            gradient: const LinearGradient(
              colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF416C).withValues(alpha: 0.3),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.favorite_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      );
    }

    if (isDefaultCollect) {
      return _withHero(
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KugoRadius.card),
            gradient: const LinearGradient(
              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF667EEA).withValues(alpha: 0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.bookmark_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      );
    }

    // 3. Generic playlist fallback
    return _withHero(
      CoverBox(
        seed: p.id,
        size: size,
        radius: KugoRadius.card,
        child: const Icon(
          Icons.queue_music_rounded,
          color: Colors.white70,
          size: 24,
        ),
      ),
    );
  }
}
