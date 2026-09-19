import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/track.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../data/repositories/recommend_repository.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/player/player_controller.dart';
import '../../shared/widgets/async_body.dart';
import '../../shared/widgets/common.dart';
import '../../core/theme/kugo_theme.dart';

class DailyRecommendPage extends ConsumerStatefulWidget {
  const DailyRecommendPage({super.key});

  @override
  ConsumerState<DailyRecommendPage> createState() => _DailyRecommendPageState();
}

class _DailyRecommendPageState extends ConsumerState<DailyRecommendPage> {
  List<Track> _tracks = const [];
  bool _loading = true;
  String _error = '';
  bool _personalized = false;
  bool _needLogin = false;

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
    final result = await recommendRepository.fetchDaily();
    if (!mounted) return;
    setState(() {
      _tracks = result.tracks;
      _personalized = result.personalized;
      _needLogin = result.needLogin;
      _error = result.error;
      _loading = false;
    });
  }

  String get _subtitle {
    if (_personalized) return '为你量身定制的每日歌单';
    if (_needLogin && _tracks.isNotEmpty) return '登录后可获取个性化每日推荐';
    if (_needLogin && _tracks.isEmpty) return '登录后查看今日推荐';
    if (_tracks.isNotEmpty) return '今日公开歌单';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final player = ref.watch(playerControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final dateLabel = recommendRepository.dateLabel();
    final day = DateTime.now().day.toString().padLeft(2, '0');
    final month = DateTime.now().month.toString().padLeft(2, '0');
    final loggedIn = auth.isLogged;

    // Login success → reload so personalized daily recommend can refresh.
    ref.listen(authControllerProvider, (prev, next) {
      final wasLogged = prev?.isLogged ?? false;
      if (!wasLogged && next.isLogged && !_loading) {
        _load();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('每日推荐'),
        actions: [
          if (_needLogin && !loggedIn)
            TextButton(
              onPressed: () => context.push('/login'),
              child: const Text('登录'),
            ),
        ],
      ),
      body: AsyncBody(
        loading: _loading,
        hasError: !_loading && _tracks.isEmpty && _error.isNotEmpty,
        isEmpty: !_loading && _tracks.isEmpty && _error.isEmpty,
        emptyMessage: _needLogin ? '登录后查看每日推荐' : '今日暂无推荐',
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
                      gradient: kugo.accentGradient,
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
                        Text(dateLabel, style: kugo.section),
                        const SizedBox(height: 4),
                        Text(
                          _subtitle,
                          style: kugo.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _personalized
                              ? '${_tracks.length} 首 · 个性化推荐'
                              : '${_tracks.length} 首',
                          style: kugo.caption.copyWith(
                            color: kugo.textTertiary,
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
            if (_needLogin && _tracks.isEmpty && !_loading)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  KugoSpacing.lg,
                  KugoSpacing.sm,
                  KugoSpacing.lg,
                  0,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => context.push('/login'),
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: const Text('去登录，获取个性化每日推荐'),
                  ),
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
                    onArtistTap: artistTapFor(context, track),
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
