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

import 'rank_hero.dart';
import '../../shared/widgets/smooth_scroll.dart';
export 'rank_hero.dart';

class RankListPage extends ConsumerStatefulWidget {
  const RankListPage({super.key});

  @override
  ConsumerState<RankListPage> createState() => _RankListPageState();
}

class _RankListPageState extends ConsumerState<RankListPage> {
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
      _error = '';
    });
    List<PlaylistBrief> ranks = const [];
    var filtered = false;
    try {
      ranks = await rankSource.rankBoards();
    } catch (e) {
      if (e.toString().contains('拦截') || e.toString().contains('URL过滤')) {
        filtered = true;
      }
    }
    // 切源后到达的旧响应直接丢弃。
    if (!mounted || source != _source) return;
    setState(() {
      _ranks = ranks;
      _loading = false;
      if (ranks.isEmpty) {
        _error = filtered
            ? '当前网络被网关拦截（URL过滤），无法访问酷狗。\n请换手机热点后重试。'
            : '排行榜加载失败，请检查网络后重试';
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
    // 设置里改动整源开关或该源的榜单功能开关后回到本页：重算可用源，必要时切源重取。
    ref.listen(settingsControllerProvider, (prev, next) {
      if (prev?.enabledSources == next.enabledSources &&
          prev?.disabledFeatures == next.disabledFeatures) {
        return;
      }
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
      if (_source == null || !available.contains(_source)) {
        _switchTo(_resolveSource(available) ?? available.first);
      }
    });

    final desktop = isDesktopView(context);
    final available = _availableSources();
    final source = _source;
    final active = source ?? (available.isEmpty ? null : available.first);
    return Scaffold(
      appBar: AppBar(title: const Text('排行榜')),
      body: available.isEmpty
          ? SourceDisabledView(
              platform:
                  ref.read(settingsControllerProvider).effectiveDefaultSource,
              feature: ref
                  .read(settingsControllerProvider)
                  .featureSwitchCause(SourceFeature.rank),
            )
          : Column(
              children: [
                if (available.length > 1)
                  SourceFilterBar(
                    platforms: available,
                    selected: active,
                    showAll: false,
                    onSelect: (p) {
                      if (p != null) _switchTo(p);
                    },
                  ),
                Expanded(
                  child: AsyncBody(
                    loading: _loading || source == null,
                    hasError:
                        !_loading && _ranks.isEmpty && _error.isNotEmpty,
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
            ),
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
    return GestureDetector(
      onTap: onTap,
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
