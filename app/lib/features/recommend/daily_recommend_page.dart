import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/daily_recommend.dart';
import '../../core/models/track.dart';
import '../../core/source/capabilities.dart';
import '../../core/source/features.dart';
import '../../core/source/music_platform.dart';
import '../../core/source/music_source.dart';
import '../../core/source/registry.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/player/player_controller.dart';
import '../../features/settings/settings_controller.dart';
import '../../shared/widgets/async_body.dart';
import '../../shared/widgets/common.dart';
import '../../core/theme/hero_tags.dart';
import '../../core/theme/kugo_theme.dart';
import '../../shared/widgets/smooth_scroll.dart';

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

  /// 当前推荐来源；`null` = 无可用源（均未注册或未启用）。
  MusicPlatform? _source;

  @override
  void initState() {
    super.initState();
    _source = _resolveSource(_availableSources());
    _load();
  }

  /// 已注册、已启用且**该源日推功能未关**、并具备 [DailyRecommendSource] 的音源。
  ///
  /// 日推是「一整个今日歌单」，两源混排无意义，故必须选定单源（不做「全部」）。
  List<MusicPlatform> _availableSources() {
    final registry = musicSourceRegistry;
    if (registry == null) return const [];
    final settings = ref.read(settingsControllerProvider);
    return registry.platforms
        .where((p) =>
            settings.isFeatureEnabled(p, SourceFeature.dailyRecommend) &&
            registry.capability<DailyRecommendSource>(p) != null)
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
    final dailySource = source == null
        ? null
        : musicSourceRegistry?.capability<DailyRecommendSource>(source);
    if (dailySource == null) {
      setState(() {
        _tracks = const [];
        _loading = false;
        _error = '';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    DailyRecommendResult result;
    try {
      result = await dailySource.dailyRecommend();
    } catch (e) {
      result = DailyRecommendResult(
        tracks: const [],
        error: e is SourceFailure && e.message.isNotEmpty
            ? e.message
            : '每日推荐加载失败，请检查网络后重试',
      );
    }
    // 切源后到达的旧响应直接丢弃。
    if (!mounted || source != _source) return;
    setState(() {
      _tracks = result.tracks;
      _personalized = result.personalized;
      _needLogin = result.needLogin;
      _error = result.error;
      _loading = false;
    });
  }

  void _switchTo(MusicPlatform platform) {
    if (platform == _source) return;
    setState(() => _source = platform);
    _load();
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
    final dateLabel = dailyRecommendDateLabel();
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

    // 设置里改动整源开关或该源日推功能开关后回到本页：重算可用源，必要时切源重取。
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
            _tracks = const [];
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

    final available = _availableSources();
    final source = _source;
    final active = source ?? (available.isEmpty ? null : available.first);

    // 整源开关：无具备日推能力的启用源时整页空态。
    if (available.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('每日推荐')),
        body: SourceDisabledView(
          platform: ref.read(settingsControllerProvider).effectiveDefaultSource,
          feature: ref
              .read(settingsControllerProvider)
              .featureSwitchCause(SourceFeature.dailyRecommend),
        ),
      );
    }

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
      body: Column(
        children: [
          if (available.length > 1)
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
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KugoSpacing.lg,
              KugoSpacing.md,
              KugoSpacing.lg,
              KugoSpacing.sm,
            ),
            child: Row(
              children: [
                Hero(
                  tag: KugoHeroTags.dailyRecommendBadge,
                  flightShuttleBuilder:
                      KugoHeroTags.dailyRecommendBadgeFlightShuttle,
                  child: Material(
                    type: MaterialType.transparency,
                    child: Container(
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
                              decoration: TextDecoration.none,
                            ),
                          ),
                          Text(
                            day,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
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
                        _loading
                            ? '正在为你定制推荐...'
                            : (_personalized
                                ? '${_tracks.length} 首 · 个性化推荐'
                                : '${_tracks.length} 首'),
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
            child: AsyncBody(
              loading: _loading || source == null,
              hasError: !_loading && _tracks.isEmpty && _error.isNotEmpty,
              isEmpty: !_loading && _tracks.isEmpty && _error.isEmpty,
              emptyMessage: _needLogin ? '登录后查看每日推荐' : '今日暂无推荐',
              errorMessage: _error,
              onRetry: _load,
              child: SmoothListViewBuilder(
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
          ),
        ],
      ),
    );
  }
}
