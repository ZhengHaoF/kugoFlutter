import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/track.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../data/repositories/recommend_repository.dart';
import '../../features/player/player_controller.dart';
import '../../shared/widgets/async_body.dart';
import '../../shared/widgets/common.dart';

class DailyRecommendPage extends ConsumerStatefulWidget {
  const DailyRecommendPage({super.key});

  @override
  ConsumerState<DailyRecommendPage> createState() => _DailyRecommendPageState();
}

class _DailyRecommendPageState extends ConsumerState<DailyRecommendPage> {
  List<Track> _tracks = const [];
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
    List<Track> tracks = const [];
    var filtered = false;
    try {
      tracks = await recommendRepository.fetchDaily();
    } catch (e) {
      if (e.toString().contains('拦截') || e.toString().contains('URL过滤')) {
        filtered = true;
      }
    }
    if (!mounted) return;
    setState(() {
      _tracks = tracks;
      _loading = false;
      if (tracks.isEmpty) {
        _error = filtered
            ? '当前网络被网关拦截（URL过滤），无法访问酷狗。\n请换手机热点后重试。'
            : '每日推荐加载失败，请检查网络后重试';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerControllerProvider);
    final dateLabel = recommendRepository.dateLabel();
    final mood = recommendRepository.moodLabel();
    final day = DateTime.now().day.toString().padLeft(2, '0');
    final month = DateTime.now().month.toString().padLeft(2, '0');

    return Scaffold(
      appBar: AppBar(title: const Text('每日推荐')),
      body: AsyncBody(
        loading: _loading,
        hasError: !_loading && _tracks.isEmpty && _error.isNotEmpty,
        isEmpty: !_loading && _tracks.isEmpty && _error.isEmpty,
        emptyMessage: '今日暂无推荐',
        errorMessage: _error,
        onRetry: _load,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KugoSpacing.lg,
                KugoSpacing.md,
                KugoSpacing.lg,
                KugoSpacing.sm,
              ),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: KugoColors.accentGradient,
                      borderRadius: BorderRadius.circular(KugoRadius.card),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          month,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          day,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: KugoSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(dateLabel, style: KugoTypography.section),
                        const SizedBox(height: 4),
                        Text(
                          '今日主题 · $mood',
                          style: KugoTypography.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_tracks.length} 首',
                          style: KugoTypography.caption.copyWith(
                            color: KugoColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _tracks.isEmpty
                        ? null
                        : () {
                            ref
                                .read(playerControllerProvider.notifier)
                                .playQueue(_tracks, startIndex: 0);
                            context.push('/player');
                          },
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('播放全部'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                itemCount: _tracks.length,
                itemBuilder: (context, index) {
                  final track = _tracks[index];
                  return TrackTile(
                    track: track,
                    index: index + 1,
                    isPlaying:
                        player.current?.id == track.id && player.isPlaying,
                    onArtistTap: () => context.push(
                      '/artist/${Uri.encodeComponent(track.artist)}',
                    ),
                    onTap: () {
                      ref
                          .read(playerControllerProvider.notifier)
                          .playQueue(_tracks, startIndex: index);
                      context.push('/player');
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
