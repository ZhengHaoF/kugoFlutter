import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/track.dart';
import '../../core/source/capabilities.dart';
import '../../core/source/features.dart';
import '../../core/source/music_platform.dart';
import '../../core/source/registry.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../core/theme/responsive.dart';
import '../../features/settings/settings_controller.dart';
import '../../shared/widgets/async_body.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/kugo_clickable.dart';
import '../../shared/widgets/smooth_scroll.dart';

import 'rank_hero.dart';

/// 榜单墙：源筛选（可选）+ 加载/错误/空态 + 榜单卡片网格。
///
/// 探索发现「排行榜」Tab 与 `/ranks` 页共用同一份实现与取数逻辑。
/// 以前 Tab 里是「下拉选单个榜 + 全部榜单按钮 + 该榜歌曲列表」，浏览模型和
/// 歌单/新碟/歌手几个 Tab 不一致（它们都是先浏览集合），20 个榜也只露 1 个。
class RankBoardsGrid extends ConsumerStatefulWidget {
  const RankBoardsGrid({super.key, this.showSourceFilter = false});

  /// 是否在网格上方渲染一条源筛选条。
  /// 探索发现页顶部已有全局筛选条，传 false；`/ranks` 页自己收口，传 true。
  final bool showSourceFilter;

  @override
  ConsumerState<RankBoardsGrid> createState() => _RankBoardsGridState();
}

class _RankBoardsGridState extends ConsumerState<RankBoardsGrid> {
  List<PlaylistBrief> _ranks = const [];
  bool _loading = true;
  String _error = '';

  /// 当前榜单来源；`null` = 无可用源（均未注册或未启用）。
  MusicPlatform? _source;

  @override
  void initState() {
    super.initState();
    _source = _resolveSource(_availableSources());
    _load();
  }

  /// 已注册、已启用且**该源榜单功能未关**、并具备 [RankSource] 的音源。
  ///
  /// 榜单两源同名榜不可混排，故必须选定单源（不做「全部」）。
  List<MusicPlatform> _availableSources() {
    final registry = musicSourceRegistry;
    if (registry == null) return const [];
    final settings = ref.read(settingsControllerProvider);
    return registry.platforms
        .where((p) =>
            settings.isFeatureEnabled(p, SourceFeature.rank) &&
            registry.capability<RankSource>(p) != null)
        .toList();
  }

  /// 首选项是设置里的「默认源」；不可用时退首个可用源。
  MusicPlatform? _resolveSource(List<MusicPlatform> available) {
    if (available.isEmpty) return null;
    final preferred =
        ref.read(settingsControllerProvider).effectiveDefaultSource;
    return available.contains(preferred) ? preferred : available.first;
  }

  Future<void> _load() async {
    final source = _source;
    final rankSource = source == null
        ? null
        : musicSourceRegistry?.capability<RankSource>(source);
    if (rankSource == null) {
      setState(() {
        _ranks = const [];
        _loading = false;
        _error = '';
      });
      return;
    }
    setState(() {
      _loading = true;
    });
    var ranks = const <PlaylistBrief>[];
    var error = '';
    var filtered = false;
    try {
      ranks = await rankSource.rankBoards();
    } catch (e) {
      if (e.toString().contains('拦截') || e.toString().contains('URL过滤')) {
        filtered = true;
      }
      error = '排行榜加载失败，请检查网络后重试';
    }
    // 切源后到达的旧响应直接丢弃。
    if (!mounted || source != _source) return;
    setState(() {
      _ranks = ranks;
      _loading = false;
      if (ranks.isEmpty) {
        _error = filtered
            ? '当前网络被网关拦截（URL过滤），无法访问酷狗。\n请换手机热点后重试。'
            : error;
      }
    });
  }

  void _switchTo(MusicPlatform platform) {
    if (platform == _source) return;
    setState(() => _source = platform);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    // 整源 / 功能开关变化要重算来源；**默认源被别处改写**（如探索发现页顶部的
    // 源筛选条）也要跟着重取，否则 Tab 与页面筛选条不联动。
    ref.listen<AppSettings>(settingsControllerProvider, (prev, next) {
      final sourcesChanged = prev?.enabledSources != next.enabledSources ||
          prev?.disabledFeatures != next.disabledFeatures;
      final defaultChanged =
          prev?.effectiveDefaultSource != next.effectiveDefaultSource;
      if (!sourcesChanged && !defaultChanged) return;
      final available = _availableSources();
      if (available.isEmpty) {
        if (_source != null) {
          setState(() {
            _source = null;
            _ranks = const [];
            _loading = false;
            _error = '';
          });
        }
        return;
      }
      final want = defaultChanged ? _resolveSource(available) : _source;
      if (want != null && want != _source) _switchTo(want);
    });

    final desktop = isDesktopView(context);
    final available = _availableSources();
    final source = _source;
    final active = source ?? (available.isEmpty ? null : available.first);
    return Column(
      children: [
        if (widget.showSourceFilter && available.length > 1)
          SourceFilterBar(
            platforms: available,
            selected: active,
            showAll: false,
            onSelect: (p) {
              // 切源同时改写全局默认源（「全部」不写），下个入口跟着走同一源。
              ref
                  .read(settingsControllerProvider.notifier)
                  .syncDefaultSourceFromFilter(p);
              if (p != null) _switchTo(p);
            },
          ),
        Expanded(
          child: available.isEmpty
              ? SourceDisabledView(
                  platform: ref
                      .read(settingsControllerProvider)
                      .effectiveDefaultSource,
                  feature: ref
                      .read(settingsControllerProvider)
                      .featureSwitchCause(SourceFeature.rank),
                )
              : AsyncBody(
                  loading: _loading || source == null,
                  hasError: !_loading && _ranks.isEmpty && _error.isNotEmpty,
                  isEmpty: !_loading && _ranks.isEmpty && _error.isEmpty,
                  emptyMessage: '暂无榜单',
                  errorMessage: _error,
                  onRetry: _load,
                  // 不再居中限宽：网格列数自适应，铺满侧栏之外的宽度。
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth.isFinite &&
                              constraints.maxWidth > 0
                          ? constraints.maxWidth
                          : MediaQuery.sizeOf(context).width;
                      return SmoothGridViewBuilder(
                        padding: EdgeInsets.fromLTRB(
                          KugoSpacing.lg,
                          KugoSpacing.md,
                          KugoSpacing.lg,
                          desktop ? KugoSpacing.xxl : 120,
                        ),
                        gridDelegate: coverGridDelegateForWidth(
                          context,
                          width,
                          preferredExtent: kDesktopCoverExtent,
                          mobileAspectRatio: 0.78,
                          desktopAspectRatio: 0.78,
                          mainAxisSpacing: KugoSpacing.lg,
                          crossAxisSpacing: KugoSpacing.lg,
                          maxColumns: 10,
                        ),
                        itemCount: _ranks.length,
                        itemBuilder: (context, index) {
                          final rank = _ranks[index];
                          // 非酷狗源必须带 `?src=`，详情页据此取数（同 common.dart）。
                          final src = rank.platform == MusicPlatform.kugou
                              ? ''
                              : '?src=${rank.platform.wireName}';
                          return _RankGridCard(
                            rank: rank,
                            onTap: () => context.push(
                              '/rank/${rank.id}$src',
                              extra: rank,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _RankGridCard extends StatelessWidget {
  const _RankGridCard({required this.rank, required this.onTap});

  final PlaylistBrief rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final desktop = isDesktopView(context);
    return KugoClickable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KugoRadius.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(KugoRadius.card),
              child: Hero(
                tag: rankCoverHeroTag(rank.id),
                flightShuttleBuilder: rankHeroFlightShuttle,
                child: RankCardSurface(
                  brief: rank,
                  showTitle: desktop,
                  dense: desktop,
                ),
              ),
            ),
          ),
          if (!desktop) ...[
            const SizedBox(height: 8),
            Text(
              rank.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: kugo.body.copyWith(fontSize: 14, height: 1.25),
            ),
          ],
        ],
      ),
    );
  }
}
