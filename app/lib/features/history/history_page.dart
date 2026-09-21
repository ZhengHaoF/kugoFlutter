import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/track.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../data/storage/kugo_db.dart';
import '../../data/storage/queue_store.dart';
import '../../features/player/player_controller.dart';
import '../../shared/widgets/async_body.dart';
import '../../shared/widgets/common.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  List<HistoryEntry> _entries = const [];
  bool _loading = true;
  int _selectedTab = 0; // 0: 播放记录, 1: 听歌统计

  // Search in records
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final store = await QueueStore.open();
      final entries = await store.loadHistoryEntriesAsync();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _entries = const [];
        _loading = false;
      });
    }
  }

  Future<void> _deleteItem(String trackId) async {
    try {
      final store = await QueueStore.open();
      await store.deleteHistory(trackId);
      if (!mounted) return;
      setState(() {
        _entries = _entries.where((e) => e.track.id != trackId).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已从播放历史中移除'),
          duration: Duration(seconds: 1),
        ),
      );
    } catch (_) {}
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空播放历史'),
        content: const Text('确定要清空全部播放历史吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
            ),
            child: const Text('清空'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final store = await QueueStore.open();
        await store.clearHistory();
        if (!mounted) return;
        setState(() {
          _entries = const [];
          _isSearching = false;
          _searchController.clear();
          _searchQuery = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('播放历史已清空'),
            duration: Duration(seconds: 2),
          ),
        );
      } catch (_) {}
    }
  }

  List<Track> _getFilteredTracks() {
    final tracks = _entries.map((e) => e.track).toList();
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return tracks;
    return tracks.where((t) {
      return t.name.toLowerCase().contains(q) ||
          t.artist.toLowerCase().contains(q) ||
          t.album.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final player = ref.watch(playerControllerProvider);
    final filteredTracks = _getFilteredTracks();

    return Scaffold(
      appBar: AppBar(
        title: _isSearching && _selectedTab == 0
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: kugo.body,
                decoration: InputDecoration(
                  hintText: '搜索历史歌曲、歌手...',
                  hintStyle: kugo.caption,
                  border: InputBorder.none,
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              )
            : const Text('播放历史'),
        actions: [
          if (_selectedTab == 0 && _entries.isNotEmpty) ...[
            IconButton(
              icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded),
              tooltip: _isSearching ? '关闭搜索' : '搜索历史',
              onPressed: () {
                setState(() {
                  if (_isSearching) {
                    _isSearching = false;
                    _searchController.clear();
                    _searchQuery = '';
                  } else {
                    _isSearching = true;
                  }
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: '清空历史',
              onPressed: _confirmClearHistory,
            ),
          ],
        ],
      ),
      body: _loading
          ? const SkeletonList()
          : Column(
              children: [
                // Tab selector
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KugoSpacing.lg,
                    vertical: KugoSpacing.xs,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(
                          value: 0,
                          label: Text('播放记录'),
                          icon: Icon(Icons.history_rounded, size: 18),
                        ),
                        ButtonSegment(
                          value: 1,
                          label: Text('听歌统计'),
                          icon: Icon(Icons.bar_chart_rounded, size: 18),
                        ),
                      ],
                      selected: {_selectedTab},
                      onSelectionChanged: (val) {
                        setState(() {
                          _selectedTab = val.first;
                          if (_selectedTab != 0 && _isSearching) {
                            _isSearching = false;
                            _searchController.clear();
                            _searchQuery = '';
                          }
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: KugoSpacing.xs),
                Expanded(
                  child: _selectedTab == 0
                      ? _buildRecordsTab(kugo, player, filteredTracks)
                      : _buildStatsTab(kugo),
                ),
              ],
            ),
    );
  }

  Widget _buildRecordsTab(
    KugoTheme kugo,
    PlayerState player,
    List<Track> filteredTracks,
  ) {
    if (_entries.isEmpty) {
      return AsyncBody(
        loading: false,
        hasError: false,
        isEmpty: true,
        emptyMessage: '还没有播放记录\n去搜索听一首吧',
        onRetry: _load,
        child: const SizedBox.shrink(),
      );
    }

    if (filteredTracks.isEmpty) {
      return AsyncBody(
        loading: false,
        hasError: false,
        isEmpty: true,
        emptyMessage: '未找到匹配的播放记录',
        onRetry: () {
          _searchController.clear();
          setState(() => _searchQuery = '');
        },
        child: const SizedBox.shrink(),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KugoSpacing.lg,
            KugoSpacing.sm,
            KugoSpacing.lg,
            KugoSpacing.sm,
          ),
          child: Row(
            children: [
              Text(
                _searchQuery.isNotEmpty
                    ? '找到 ${filteredTracks.length} 首 / 共 ${_entries.length} 首'
                    : '共 ${filteredTracks.length} 首',
                style: kugo.caption,
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () {
                  ref
                      .read(playerControllerProvider.notifier)
                      .playQueue(filteredTracks, startIndex: 0);
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
            itemCount: filteredTracks.length,
            itemBuilder: (context, index) {
              final track = filteredTracks[index];
              return Dismissible(
                key: Key('history_${track.id}_$index'),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.redAccent.withValues(alpha: 0.8),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete_rounded, color: Colors.white),
                ),
                onDismissed: (_) => _deleteItem(track.id),
                child: TrackTile(
                  track: track,
                  isPlaying: player.current?.id == track.id && player.isPlaying,
                  trailing: IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: kugo.textSecondary.withValues(alpha: 0.6),
                    ),
                    tooltip: '从历史移除',
                    onPressed: () => _deleteItem(track.id),
                  ),
                  onArtistTap: artistTapFor(context, track),
                  onTap: () {
                    ref
                        .read(playerControllerProvider.notifier)
                        .playQueue(filteredTracks, startIndex: index);
                    context.push('/player');
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatsTab(KugoTheme kugo) {
    if (_entries.isEmpty) {
      return AsyncBody(
        loading: false,
        hasError: false,
        isEmpty: true,
        emptyMessage: '暂无听歌数据\n听几首歌后再来看看分析吧',
        onRetry: _load,
        child: const SizedBox.shrink(),
      );
    }

    final totalSongs = _entries.length;
    final totalDurationMs = _entries.fold<int>(
      0,
      (sum, e) => sum + (e.track.durationMs > 0 ? e.track.durationMs : 180000),
    );
    final totalMinutes = (totalDurationMs / 60000).round();
    final durationText = totalMinutes < 60
        ? '$totalMinutes 分钟'
        : '${(totalMinutes / 60).toStringAsFixed(1)} 小时';

    // 1. Last 7 days trend
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dailyCounts = List<int>.filled(7, 0);
    const dayLabels = ['6天前', '5天前', '4天前', '3天前', '前天', '昨天', '今天'];

    for (final e in _entries) {
      final dt = DateTime.fromMillisecondsSinceEpoch(e.playedAt);
      final entryDate = DateTime(dt.year, dt.month, dt.day);
      final diffDays = today.difference(entryDate).inDays;
      if (diffDays >= 0 && diffDays < 7) {
        dailyCounts[6 - diffDays]++;
      }
    }
    final maxDaily = dailyCounts.reduce((a, b) => a > b ? a : b).clamp(1, 9999);

    // 2. Time of day buckets (凌晨 0-6, 上午 6-12, 下午 12-18, 夜晚 18-24)
    int nightCount = 0; // 0..5
    int morningCount = 0; // 6..11
    int afternoonCount = 0; // 12..17
    int eveningCount = 0; // 18..23

    for (final e in _entries) {
      final hour = DateTime.fromMillisecondsSinceEpoch(e.playedAt).hour;
      if (hour >= 0 && hour < 6) {
        nightCount++;
      } else if (hour >= 6 && hour < 12) {
        morningCount++;
      } else if (hour >= 12 && hour < 18) {
        afternoonCount++;
      } else {
        eveningCount++;
      }
    }

    // 3. Top artists
    final artistMap = <String, int>{};
    for (final e in _entries) {
      final artist = e.track.artist.trim();
      if (artist.isNotEmpty && artist != '未知歌手') {
        artistMap[artist] = (artistMap[artist] ?? 0) + 1;
      }
    }
    final topArtists = artistMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topArtistsList = topArtists.take(5).toList();

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        KugoSpacing.lg,
        KugoSpacing.md,
        KugoSpacing.lg,
        KugoSpacing.xxl,
      ),
      children: [
        // Metric Cards
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                icon: Icons.music_note_rounded,
                color: kugo.primary,
                label: '历史曲目',
                value: '$totalSongs 首',
              ),
            ),
            const SizedBox(width: KugoSpacing.md),
            Expanded(
              child: _MetricCard(
                icon: Icons.access_time_rounded,
                color: const Color(0xFF5B7CFF),
                label: '预估时长',
                value: durationText,
              ),
            ),
          ],
        ),
        const SizedBox(height: KugoSpacing.lg),

        // 7-day activity bar chart
        GlassSurface(
          padding: const EdgeInsets.all(KugoSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_today_rounded, size: 16, color: kugo.primary),
                  const SizedBox(width: 8),
                  Text('近 7 天听歌频次', style: kugo.section.copyWith(fontSize: 16)),
                ],
              ),
              const SizedBox(height: KugoSpacing.lg),
              SizedBox(
                height: 120,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (int i = 0; i < 7; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                '${dailyCounts[i]}',
                                style: kugo.caption.copyWith(
                                  fontSize: 10,
                                  color: dailyCounts[i] > 0
                                      ? kugo.primary
                                      : kugo.textSecondary.withValues(alpha: 0.5),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                height: (dailyCounts[i] / maxDaily * 70).clamp(4.0, 70.0),
                                decoration: BoxDecoration(
                                  gradient: dailyCounts[i] > 0
                                      ? kugo.accentGradient
                                      : null,
                                  color: dailyCounts[i] == 0
                                      ? kugo.surfaceElevated
                                      : null,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                dayLabels[i],
                                style: kugo.caption.copyWith(fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: KugoSpacing.lg),

        // Time of Day distribution
        GlassSurface(
          padding: const EdgeInsets.all(KugoSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.wb_twilight_rounded, size: 16, color: kugo.primary),
                  const SizedBox(width: 8),
                  Text('听歌时段偏好', style: kugo.section.copyWith(fontSize: 16)),
                ],
              ),
              const SizedBox(height: KugoSpacing.md),
              _TimeBucketRow(
                icon: Icons.nightlight_round,
                label: '凌晨 (00:00 - 05:59)',
                count: nightCount,
                total: totalSongs,
                color: const Color(0xFF8B7CF6),
              ),
              const SizedBox(height: KugoSpacing.sm),
              _TimeBucketRow(
                icon: Icons.wb_sunny_rounded,
                label: '上午 (06:00 - 11:59)',
                count: morningCount,
                total: totalSongs,
                color: const Color(0xFFE8B86D),
              ),
              const SizedBox(height: KugoSpacing.sm),
              _TimeBucketRow(
                icon: Icons.wb_cloudy_rounded,
                label: '下午 (12:00 - 17:59)',
                count: afternoonCount,
                total: totalSongs,
                color: const Color(0xFF5BB8A8),
              ),
              const SizedBox(height: KugoSpacing.sm),
              _TimeBucketRow(
                icon: Icons.dark_mode_rounded,
                label: '夜晚 (18:00 - 23:59)',
                count: eveningCount,
                total: totalSongs,
                color: const Color(0xFFE87A90),
              ),
            ],
          ),
        ),
        const SizedBox(height: KugoSpacing.lg),

        // Top Artists
        if (topArtistsList.isNotEmpty)
          GlassSurface(
            padding: const EdgeInsets.all(KugoSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.person_pin_rounded, size: 16, color: kugo.primary),
                    const SizedBox(width: 8),
                    Text('常听歌手 TOP 榜', style: kugo.section.copyWith(fontSize: 16)),
                  ],
                ),
                const SizedBox(height: KugoSpacing.md),
                for (int i = 0; i < topArtistsList.length; i++) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: i == 0
                                ? const Color(0xFFFFD700).withValues(alpha: 0.2)
                                : i == 1
                                    ? const Color(0xFFC0C0C0).withValues(alpha: 0.2)
                                    : i == 2
                                        ? const Color(0xFFCD7F32).withValues(alpha: 0.2)
                                        : kugo.surfaceElevated,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: i == 0
                                  ? const Color(0xFFFFB300)
                                  : i == 1
                                      ? const Color(0xFF9E9E9E)
                                      : i == 2
                                          ? const Color(0xFFB87333)
                                          : kugo.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: KugoSpacing.md),
                        Expanded(
                          child: Text(
                            topArtistsList[i].key,
                            style: kugo.body.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${topArtistsList[i].value} 次',
                          style: kugo.caption,
                        ),
                      ],
                    ),
                  ),
                  if (i < topArtistsList.length - 1)
                    Divider(height: 1, color: kugo.divider.withValues(alpha: 0.3)),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return GlassSurface(
      padding: const EdgeInsets.all(KugoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 8),
              Text(label, style: kugo.caption),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: kugo.title.copyWith(fontSize: 18),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _TimeBucketRow extends StatelessWidget {
  const _TimeBucketRow({
    required this.icon,
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final ratio = total > 0 ? (count / total).clamp(0.0, 1.0) : 0.0;
    final percent = (ratio * 100).toStringAsFixed(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label, style: kugo.caption),
            const Spacer(),
            Text('$count 首 ($percent%)', style: kugo.caption),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            backgroundColor: kugo.surfaceElevated,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}
