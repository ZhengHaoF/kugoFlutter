import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/models/mv_models.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../player/player_controller.dart';
import 'mv_controller.dart';

/// MV 播放页。路由 `/mv?id=&hash=&name=&artist=&cover=&platform=`
///
/// 视频走独立的 `media_kit.Player`，与音频 [PlayerController] 隔离：
/// 进入页面暂停音乐，退出后音频链路保持原队列。
class MvPlayerPage extends ConsumerStatefulWidget {
  const MvPlayerPage({
    super.key,
    required this.id,
    this.hash = '',
    this.name = '',
    this.artist = '',
    this.coverUrl = '',
    this.mixSongId = '',
  });

  final String id;
  final String hash;
  final String name;
  final String artist;
  final String coverUrl;
  final String mixSongId;

  @override
  ConsumerState<MvPlayerPage> createState() => _MvPlayerPageState();
}

class _MvPlayerPageState extends ConsumerState<MvPlayerPage> {
  Player? _player;
  VideoController? _videoController;
  bool _controlsVisible = true;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // 进 MV 前暂停音乐，避免双声道叠播。
    final player = ref.read(playerControllerProvider.notifier);
    if (ref.read(playerControllerProvider).isPlaying) {
      player.togglePlay();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final brief = MvBrief(
      id: widget.id,
      hash: widget.hash.toLowerCase(),
      name: widget.name,
      coverUrl: widget.coverUrl,
      artist: widget.artist,
      mixSongId: widget.mixSongId,
    );
    await ref.read(mvPlayerProvider.notifier).load(brief);
    if (!mounted) return;
    _openFromState(ref.read(mvPlayerProvider));
  }

  void _openFromState(MvPlayerState state) {
    final url = state.playUrl?.url ?? '';
    if (url.isEmpty) return;
    _player ??= Player();
    _videoController ??= VideoController(_player!);
    if (!_started) {
      _started = true;
      _player!.open(Media(url), play: true);
    }
  }

  @override
  void dispose() {
    final p = _player;
    _player = null;
    _videoController = null;
    if (p != null) {
      // 同步释放，避免页面销毁后仍占解码器。
      // ignore: discarded_futures
      p.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mvPlayerProvider);
    // 取流成功后打开播放器（覆盖加载完成、切清晰度两条路径）。
    ref.listen(mvPlayerProvider, (prev, next) {
      if (next.canPlay && next.playUrl?.url != prev?.playUrl?.url) {
        final url = next.playUrl!.url;
        _player ??= Player();
        _videoController ??= VideoController(_player!);
        _player!.open(Media(url), play: true);
        _started = true;
      }
    });

    final kugo = KugoTheme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _controlsVisible = !_controlsVisible),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 视频画面
            if (_videoController != null && state.canPlay)
              Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Video(
                    controller: _videoController!,
                    controls: NoVideoControls,
                  ),
                ),
              )
            else
              _CoverPlaceholder(coverUrl: state.brief?.coverUrl ?? widget.coverUrl),

            // 顶部栏
            AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: Align(
                alignment: Alignment.topCenter,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: KugoSpacing.sm,
                      vertical: KugoSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          color: Colors.white,
                          onPressed: () => context.pop(),
                          icon: const Icon(Icons.keyboard_arrow_down),
                        ),
                        const SizedBox(width: KugoSpacing.xs),
                        Expanded(
                          child: Text(
                            state.brief?.name ?? widget.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (state.detail != null &&
                            state.detail!.sources.length > 1)
                          _QualityButton(
                            state: state,
                            onSelect: (s) =>
                                ref.read(mvPlayerProvider.notifier).selectSource(s),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 状态层
            if (state.status == MvLoadStatus.loading)
              const Center(
                child: CircularProgressIndicator(color: Colors.white70),
              )
            else if (state.status == MvLoadStatus.error)
              _ErrorOverlay(
                message: state.error,
                onRetry: () =>
                    ref.read(mvPlayerProvider.notifier).load(state.brief ??
                        MvBrief(
                          id: widget.id,
                          hash: widget.hash,
                          name: widget.name,
                          coverUrl: widget.coverUrl,
                        )),
              ),

            // 底部信息
            AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(KugoSpacing.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.brief?.artist.isNotEmpty == true
                              ? state.brief!.artist
                              : widget.artist,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        if ((state.source?.label.isNotEmpty ?? false))
                          Padding(
                            padding: const EdgeInsets.only(top: KugoSpacing.xs),
                            child: Text(
                              state.source!.label +
                                  (state.source!.codec.isNotEmpty
                                      ? ' · ${state.source!.codec}'
                                      : ''),
                              style: TextStyle(
                                color: kugo.primary.withValues(alpha: 0.9),
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({required this.coverUrl});

  final String coverUrl;

  @override
  Widget build(BuildContext context) {
    if (coverUrl.isEmpty) {
      return const ColoredBox(color: Color(0xFF0A0C10));
    }
    return Image.network(
      coverUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF0A0C10)),
    );
  }
}

class _ErrorOverlay extends StatelessWidget {
  const _ErrorOverlay({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KugoSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off, color: Colors.white54, size: 40),
            const SizedBox(height: KugoSpacing.md),
            Text(
              message.isEmpty ? '视频加载失败' : message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: KugoSpacing.lg),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _QualityButton extends StatelessWidget {
  const _QualityButton({required this.state, required this.onSelect});

  final MvPlayerState state;
  final ValueChanged<MvPlaySource> onSelect;

  @override
  Widget build(BuildContext context) {
    final sources = state.detail?.sources ?? const <MvPlaySource>[];
    return PopupMenuButton<MvPlaySource>(
      color: const Color(0xFF1C2230),
      icon: const Icon(Icons.high_quality, color: Colors.white70),
      onSelected: onSelect,
      itemBuilder: (context) => [
        for (final s in sources)
          PopupMenuItem(
            value: s,
            child: Row(
              children: [
                if (s.hash == state.source?.hash)
                  const Icon(Icons.check, size: 16, color: Colors.white70)
                else
                  const SizedBox(width: 16),
                const SizedBox(width: KugoSpacing.sm),
                Text(
                  s.label + (s.codec.isNotEmpty ? ' ${s.codec}' : ''),
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
