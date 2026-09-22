import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/track.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../core/theme/responsive.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../shared/widgets/async_body.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    List<PlaylistBrief> ranks = const [];
    var filtered = false;
    try {
      ranks = await playlistRepository.fetchRankList();
    } catch (e) {
      if (e.toString().contains('拦截') || e.toString().contains('URL过滤')) {
        filtered = true;
      }
    }
    if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktopView(context);
    return Scaffold(
      appBar: AppBar(title: const Text('排行榜')),
      body: AsyncBody(
        loading: _loading,
        hasError: !_loading && _ranks.isEmpty && _error.isNotEmpty,
        isEmpty: !_loading && _ranks.isEmpty && _error.isEmpty,
        emptyMessage: '暂无榜单',
        errorMessage: _error,
        onRetry: _load,
        child: DesktopContentConstraint(
          maxWidth: desktop ? 1280 : double.infinity,
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
                  maxColumns: 6,
                ),
                itemCount: _ranks.length,
                itemBuilder: (context, index) {
                  final rank = _ranks[index];
                  return _RankGridCard(
                    rank: rank,
                    onTap: () => context.push('/rank/${rank.id}', extra: rank),
                  );
                },
              );
            },
          ),
        ),
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
