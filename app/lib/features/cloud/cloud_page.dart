import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/cloud_models.dart';
import '../../core/models/track.dart';
import '../../core/source/capabilities.dart';
import '../../core/source/music_platform.dart';
import '../../core/source/music_source.dart';
import '../../core/source/registry.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../core/theme/responsive.dart';
import '../../features/player/player_controller.dart';
import '../../features/profile/source_account.dart';
import '../../features/settings/settings_controller.dart';
import '../../shared/widgets/async_body.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/smooth_scroll.dart';
import 'cloud_upload_picker.dart';

/// 音乐云盘（用户私有文件库，按当前账号源取数）。
///
/// 取数一律经 `registry.capability<CloudDiskSource>()`，不直连 Repository。
/// 酷狗 / 网易双源都实现了该能力（网易 J 组 2026-10-09 接），入口由能力显隐；
/// 当前看哪个源由「账号源」决定（与「我的 / 个人中心」同一份选择）。
class CloudPage extends ConsumerStatefulWidget {
  const CloudPage({super.key});

  @override
  ConsumerState<CloudPage> createState() => _CloudPageState();
}

class _CloudPageState extends ConsumerState<CloudPage> {
  final TextEditingController _searchController = TextEditingController();
  final List<Track> _tracks = [];
  CloudDiskCapacity _capacity = CloudDiskCapacity.empty;
  int _total = 0;
  int _page = 0;
  bool _hasMore = false;
  bool _loading = false;
  bool _loadingMore = false;
  bool _resolvingRest = false;
  bool _deleting = false;
  String _error = '';

  /// 已加载完毕的账号源；与当前源不一致就重拉（切源重取）。
  MusicPlatform? _loadedPlatform;
  String _searchQuery = '';
  final Set<String> _pendingDeleteIds = {};

  // 上传
  bool _uploading = false;
  int _uploadDone = 0;
  int _uploadTotal = 0;
  int _uploadSecond = 0;
  int _uploadFailed = 0;
  String _uploadLabel = '';

  /// 当前账号源（与「我的 / 个人中心」共用同一份选择；被停用时回落默认源）。
  MusicPlatform get _platform => ref.watch(effectiveAccountSourceProvider);

  CloudDiskSource? get _source =>
      musicSourceRegistry?.capability<CloudDiskSource>(_platform);

  CloudUploadSource? get _uploader =>
      musicSourceRegistry?.capability<CloudUploadSource>(_platform);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final src = _source;
    if (src == null) {
      setState(() {
        _error = '当前音源不支持云盘';
        _loading = false;
      });
      return;
    }
    if (!src.isCloudDiskLoggedIn) {
      setState(() {
        _loading = false;
        _error = '';
        _tracks.clear();
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final page = await src.fetchCloudDiskPage(page: 1, pageSize: 50);
      if (!mounted) return;
      setState(() {
        _tracks
          ..clear()
          ..addAll(page.tracks);
        _capacity = page.capacity;
        _total = page.total;
        _page = 1;
        _hasMore = page.hasMore;
        _loading = false;
      });
      if (_hasMore) unawaited(_resolveRemaining());
    } on SourceFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  /// 后台补齐剩余页（对齐 EchoMusic resolveAllCloudSongs）。
  Future<void> _resolveRemaining() async {
    final src = _source;
    if (src == null || _resolvingRest) return;
    setState(() => _resolvingRest = true);
    try {
      while (mounted && _hasMore && _tracks.length < _total) {
        final nextPage = _page + 1;
        final page = await src.fetchCloudDiskPage(page: nextPage, pageSize: 50);
        if (!mounted) return;
        if (page.tracks.isEmpty) {
          setState(() => _hasMore = false);
          break;
        }
        final seen = _tracks.map((t) => t.id).toSet();
        final fresh = page.tracks.where((t) => !seen.contains(t.id)).toList();
        setState(() {
          _tracks.addAll(fresh);
          _page = nextPage;
          _hasMore = page.hasMore && fresh.isNotEmpty;
          if (page.capacity.totalBytes > 0) _capacity = page.capacity;
        });
      }
    } catch (_) {
      // 后台补页失败不打断已加载列表。
      if (mounted) setState(() => _hasMore = false);
    } finally {
      if (mounted) setState(() => _resolvingRest = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _resolvingRest) return;
    final src = _source;
    if (src == null) return;
    setState(() => _loadingMore = true);
    try {
      final page =
          await src.fetchCloudDiskPage(page: _page + 1, pageSize: 50);
      if (!mounted) return;
      final seen = _tracks.map((t) => t.id).toSet();
      final fresh = page.tracks.where((t) => !seen.contains(t.id)).toList();
      setState(() {
        _tracks.addAll(fresh);
        if (fresh.isNotEmpty) _page += 1;
        _hasMore = page.hasMore && fresh.isNotEmpty;
        if (page.capacity.totalBytes > 0) _capacity = page.capacity;
      });
    } on SourceFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  List<Track> get _displayed {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _tracks;
    return _tracks
        .where(
          (t) =>
              t.name.toLowerCase().contains(q) ||
              t.artist.toLowerCase().contains(q) ||
              t.album.toLowerCase().contains(q),
        )
        .toList();
  }

  void _playAll(List<Track> queue) {
    if (queue.isEmpty) return;
    ref.read(playerControllerProvider.notifier).playQueue(queue, startIndex: 0);
    context.push('/player');
  }

  void _playAt(List<Track> queue, int index) {
    if (queue.isEmpty || index < 0 || index >= queue.length) return;
    ref
        .read(playerControllerProvider.notifier)
        .playQueue(queue, startIndex: index);
    context.push('/player');
  }

  Future<void> _startUpload() async {
    final uploader = _uploader;
    if (uploader == null || _uploading) return;
    final disk = _source;
    if (disk == null || !disk.isCloudDiskLoggedIn) {
      context.push(loginRouteFor(_platform));
      return;
    }

    final errors = <String>[];
    final picks = await pickCloudUploadFiles(errors: errors);
    if (picks.isEmpty) {
      if (errors.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errors.first)),
        );
      }
      return;
    }

    setState(() {
      _uploading = true;
      _uploadDone = 0;
      _uploadTotal = picks.length;
      _uploadSecond = 0;
      _uploadFailed = 0;
      _uploadLabel = picks.first.name;
    });

    for (final pick in picks) {
      if (!mounted) return;
      setState(() => _uploadLabel = pick.name);
      try {
        final result = await uploader.uploadCloudFile(
          bytes: pick.bytes,
          title: pick.title,
          extendname: pick.extension,
          authorName: pick.artist.isEmpty ? null : pick.artist,
        );
        if (!mounted) return;
        setState(() {
          _uploadDone += 1;
          if (result.secondUpload) _uploadSecond += 1;
        });
      } on SourceFailure catch (e) {
        if (!mounted) return;
        setState(() {
          _uploadDone += 1;
          _uploadFailed += 1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${pick.name}: ${e.message}')),
        );
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _uploadDone += 1;
          _uploadFailed += 1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${pick.name}: $e')),
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _uploading = false;
      _uploadLabel = '';
    });
    final ok = _uploadTotal - _uploadFailed;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _uploadFailed == 0
              ? (_uploadSecond > 0
                  ? '上传完成：$ok 首（其中 $_uploadSecond 首秒传）'
                  : '上传完成：$ok 首')
              : '上传完成：成功 $ok 首，失败 $_uploadFailed 首',
        ),
      ),
    );
    unawaited(_load());
  }

  Future<void> _confirmDelete(Track track) async {
    final src = _source;
    if (src == null) return;
    final target = cloudDeleteTargetFromTrack(track);
    if (!target.canDelete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('缺少云盘文件标识，无法删除')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('从云盘删除'),
          content: Text('确认删除『${track.name}』？此操作无法撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;

    setState(() {
      _deleting = true;
      _pendingDeleteIds.add(track.id);
    });
    try {
      await src.deleteCloudTracks([target]);
      if (!mounted) return;
      setState(() {
        _tracks.removeWhere((t) => t.id == track.id);
        _total = (_total - 1).clamp(0, 1 << 30);
        _pendingDeleteIds.remove(track.id);
        _deleting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已从云盘删除')),
      );
      // 容量可能已变，静默刷新首页。
      unawaited(_load());
    } on SourceFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _pendingDeleteIds.remove(track.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _pendingDeleteIds.remove(track.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$e')),
      );
    }
  }

  String get _capacityLabel {
    final total = _capacity.totalBytes;
    if (total <= 0) return '';
    return '已用 ${_formatBytes(_capacity.used)} / ${_formatBytes(total)}';
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var i = 0;
    while (value >= 1024 && i < units.length - 1) {
      value /= 1024;
      i++;
    }
    return '${value.toStringAsFixed(value >= 10 || i == 0 ? 0 : 1)} ${units[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final player = ref.watch(playerControllerProvider);
    final desktop = isDesktopView(context);
    final platforms = ref.watch(accountSourcePlatformsProvider);
    final src = _source;
    final logged = src?.isCloudDiskLoggedIn ?? false;
    final displayed = _displayed;

    // 切源重取：云盘是账号资产，换源必须整块重拉（不混源、不清空旧数据）。
    if (_loadedPlatform != _platform) {
      _loadedPlatform = _platform;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              KugoSpacing.lg,
              desktop ? KugoSpacing.lg : KugoSpacing.md,
              KugoSpacing.lg,
              KugoSpacing.sm,
            ),
            child: Row(
              children: [
                // 桌面端靠侧栏导航，返回键冗余；移动端才显示。
                if (!desktop) ...[
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: '返回',
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    '音乐云盘',
                    style: kugo.section.copyWith(fontSize: 20),
                  ),
                ),
                if (logged && _uploader != null)
                  IconButton(
                    onPressed: _uploading ? null : _startUpload,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    tooltip: '上传到云盘',
                  ),
                if (logged && _tracks.isNotEmpty)
                  IconButton(
                    onPressed: _loading || _uploading ? null : _load,
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: '刷新',
                  ),
              ],
            ),
          ),
          // 账号源切换：多源启用才出 chips（云盘是账号资产，不混排）；
          // 单源给一行只读小字——与其它多源页面同一套口径（见「我的」页）。
          if (platforms.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KugoSpacing.lg,
                0,
                KugoSpacing.lg,
                KugoSpacing.sm,
              ),
              child: SourceFilterBar(
                platforms: platforms,
                selected: _platform,
                showAll: false,
                horizontalPadding: 0,
                onSelect: (p) {
                  // 切源同时改写全局默认源（「全部」不写），下个入口跟着走同一源。
                  ref
                      .read(settingsControllerProvider.notifier)
                      .syncDefaultSourceFromFilter(p);
                  if (p != null) {
                    ref.read(accountSourceProvider.notifier).state = p;
                  }
                },
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KugoSpacing.lg,
                0,
                KugoSpacing.lg,
                KugoSpacing.sm,
              ),
              child: SourceLabel(platform: _platform, compact: true),
            ),
          if (logged && _capacity.totalBytes > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KugoSpacing.lg,
                0,
                KugoSpacing.lg,
                KugoSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      // 只有 totalBytes > 0 才会走到这里；usedRatio==0（空盘）
                      // 也必须给确定值 0，传 null 会渲染成不确定进度条，
                      // 看起来像「一直在加载」。
                      value: _capacity.usedRatio,
                      minHeight: 4,
                      backgroundColor: kugo.primary.withValues(alpha: 0.12),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(_capacityLabel, style: kugo.caption),
                ],
              ),
            ),
          if (_uploading)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KugoSpacing.lg,
                0,
                KugoSpacing.lg,
                KugoSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _uploadTotal == 0
                          ? null
                          : _uploadDone / _uploadTotal,
                      minHeight: 4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '上传中 $_uploadDone / $_uploadTotal · $_uploadLabel',
                    style: kugo.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          if (!logged)
            Expanded(child: _buildLoginPrompt(kugo))
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KugoSpacing.lg,
                KugoSpacing.sm,
                KugoSpacing.lg,
                KugoSpacing.sm,
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '搜索云盘歌曲',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(KugoRadius.tile),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: kugo.primary.withValues(alpha: 0.06),
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
            if (displayed.isNotEmpty || _loading)
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
                          ? '找到 ${displayed.length} 首 / 共 $_total 首'
                          : '共 ${_tracks.length} 首'
                              '${_resolvingRest ? '（正在补全…）' : ''}',
                      style: kugo.caption,
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: displayed.isEmpty
                          ? null
                          : () => _playAll(displayed),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('播放全部'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: AsyncBody(
                loading: _loading,
                hasError: _error.isNotEmpty && _tracks.isEmpty,
                isEmpty: !_loading && _error.isEmpty && _tracks.isEmpty,
                emptyMessage: '云盘暂无歌曲',
                errorMessage: _error.isEmpty ? '加载失败' : _error,
                onRetry: _load,
                child: SmoothListViewBuilder(
                  padding: EdgeInsets.fromLTRB(
                    0,
                    0,
                    0,
                    isDesktopView(context) ? 48 : 120,
                  ),
                  itemCount: displayed.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= displayed.length) {
                      return Padding(
                        padding: const EdgeInsets.all(KugoSpacing.lg),
                        child: Center(
                          child: _loadingMore || _resolvingRest
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : TextButton(
                                  onPressed: _loadMore,
                                  child: const Text('加载更多'),
                                ),
                        ),
                      );
                    }
                    final track = displayed[index];
                    final isCurrent = player.current?.id == track.id;
                    return TrackTile(
                      track: track,
                      index: index + 1,
                      showAlbum: true,
                      isPlaying: isCurrent && player.isPlaying,
                      onTap: () => _playAt(displayed, index),
                      trailing: IconButton(
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          size: 20,
                          color: _pendingDeleteIds.contains(track.id)
                              ? Colors.redAccent
                              : kugo.textSecondary,
                        ),
                        tooltip: '从云盘删除',
                        onPressed: _deleting
                            ? null
                            : () => _confirmDelete(track),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoginPrompt(KugoTheme kugo) {
    final label = _platform.label;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KugoSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_outlined,
              size: 56,
              color: kugo.textSecondary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: KugoSpacing.lg),
            Text(
              '登录后查看云盘',
              style: kugo.section.copyWith(fontSize: 18),
            ),
            const SizedBox(height: KugoSpacing.sm),
            Text(
              '云盘是$label账号的私有文件库',
              style: kugo.caption,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KugoSpacing.lg),
            FilledButton(
              onPressed: () => context.push(loginRouteFor(_platform)),
              child: Text('登录$label账号'),
            ),
          ],
        ),
      ),
    );
  }
}
