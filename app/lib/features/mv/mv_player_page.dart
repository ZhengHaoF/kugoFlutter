import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/models/mv_models.dart';
import '../../core/platform.dart' show isWindowsPlatform;
import '../../core/source/capabilities.dart';
import '../../core/source/music_platform.dart';
import '../../core/source/registry.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../shared/widgets/common.dart' show showKugoBottomSheet;
import '../player/player_controller.dart';
import '../settings/settings_controller.dart';
import 'mv_barrage_controls.dart';
import 'mv_barrage_layer.dart';
import 'mv_collection_controller.dart';
import 'mv_controller.dart';

/// MV 播放页。路由 `/mv?id=&hash=&name=&artist=&cover=&mixSongId=`
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

  /// Windows 硬解经常「有声有进度无画」且 width/height 照样上报，
  /// 软解回退判据踩空；直接默认软解。其它平台仍硬解优先。
  bool _hwAccel = !isWindowsPlatform;
  bool _swFallbackTried = false;
  StreamSubscription<int?>? _widthSub;
  StreamSubscription<int?>? _heightSub;
  Timer? _swFallbackTimer;
  int _videoWidth = 0;
  int _videoHeight = 0;

  // ── 播控游标（来自 media_kit stream，不进 Riverpod）──
  final ValueNotifier<int> _positionMs = ValueNotifier(0);
  final ValueNotifier<int> _durationMs = ValueNotifier(0);
  final ValueNotifier<bool> _playing = ValueNotifier(false);
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<bool>? _playingSub;

  /// 拖动进度条时用本地值盖住引擎回推，松手后 seek。
  bool _dragging = false;
  double _dragProgress = 0;

  /// 切清晰度时暂存的播放进度（ms），open 后 seek 回去。
  int _resumeMs = 0;

  Map<String, String> _httpHeaders = const {};

  /// 弹幕层句柄：发送成功后把自己发的弹幕立即放出来。
  final GlobalKey<MvBarrageLayerState> _barrageKey =
      GlobalKey<MvBarrageLayerState>();

  @override
  void initState() {
    super.initState();
    // 全部副作用放到帧后：initState 仍属 build 阶段，这里改 provider 会触发
    // Riverpod「Tried to modify a provider while the widget tree was building」。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 进 MV 前暂停音乐，避免双声道叠播。
      final player = ref.read(playerControllerProvider.notifier);
      if (ref.read(playerControllerProvider).isPlaying) {
        player.togglePlay();
      }
      unawaited(_bootstrap());
    });
  }

  Future<void> _bootstrap() async {
    // 先把 Player + Video 挂上树，再 open —— 与 media_kit 官方示例一致，
    // 避免「先 open 后挂 Video」时纹理未注册导致有声无画。
    _ensurePlayer();
    if (mounted) setState(() {});
    await Future<void>.delayed(Duration.zero);

    final brief = MvBrief(
      id: widget.id,
      hash: widget.hash.toLowerCase(),
      name: widget.name,
      coverUrl: widget.coverUrl,
      artist: widget.artist,
      mixSongId: widget.mixSongId,
    );
    // 收藏状态与主播放并行；登录态空则静默。
    unawaited(
      ref
          .read(mvCollectionProvider.notifier)
          .ensureLoaded(platform: brief.platform),
    );
    await ref.read(mvPlayerProvider.notifier).load(brief);
    if (!mounted) return;
    await _openFromState(ref.read(mvPlayerProvider), resume: false);
  }

  VideoController _createController(Player p) {
    return VideoController(
      p,
      configuration: VideoControllerConfiguration(
        // Windows 默认软解（见 _hwAccel）；其它平台硬解，失败再降级。
        enableHardwareAcceleration: _hwAccel,
        hwdec: _hwAccel ? null : 'no',
      ),
    );
  }

  void _ensurePlayer() {
    if (_player != null) return;
    final p = Player();
    _player = p;
    _videoController = _createController(p);
    _posSub = p.stream.position.listen((d) {
      if (_dragging) return;
      _positionMs.value = d.inMilliseconds;
    });
    _durSub = p.stream.duration.listen((d) {
      _durationMs.value = d.inMilliseconds;
    });
    _playingSub = p.stream.playing.listen((v) {
      _playing.value = v;
      if (v) _lastEngineError = '';
    });
    // 视频轨宽高：出画的唯一可靠信号。有声无画时它们一直是 null/0。
    _widthSub = p.stream.width.listen(_onVideoSize);
    _heightSub = p.stream.height.listen(_onVideoSize);
    _errorSub = p.stream.error.listen((msg) {
      _lastEngineError = msg;
    });
  }

  String _lastEngineError = '';
  StreamSubscription<String>? _errorSub;

  void _onVideoSize(int? _) {
    final p = _player;
    if (p == null) return;
    final w = p.state.width ?? 0;
    final h = p.state.height ?? 0;
    if (w == _videoWidth && h == _videoHeight) return;
    _videoWidth = w;
    _videoHeight = h;
    if (w > 0 && h > 0) {
      _swFallbackTimer?.cancel();
      _swFallbackTimer = null;
    }
  }

  /// 有声音、有进度，但 N 秒后仍无视频宽高 → 判定硬解黑屏，降级软解重开。
  void _armSwFallback(int seekTo) {
    _swFallbackTimer?.cancel();
    if (_swFallbackTried || !_hwAccel) return;
    _swFallbackTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _player == null) return;
      if ((_player!.state.width ?? 0) > 0 && (_player!.state.height ?? 0) > 0) {
        return; // 已经出画
      }
      // 还在 loading / 没起播就先不降级，避免误判。
      if (_durationMs.value <= 0 && !_playing.value) return;
      _swFallbackTried = true;
      _hwAccel = false;
      unawaited(_recreateControllerForSoftDecode(seekTo: seekTo));
    });
  }

  String _lastMediaUrl = '';

  /// 当前已成功 open 的版本标识（`id|hash`），用于区分「切清晰度」与「换版本」。
  /// `selectVersion` / `selectSource` 都会先 `clearPlayUrl`，`prev.playUrl` 拿不到
  /// 旧值，不能靠它判断。
  String _openedBriefKey = '';

  static String _briefKeyOf(MvBrief? brief) =>
      brief == null ? '' : '${brief.id}|${brief.hash}';

  /// [resume] 为 true 时用 [_resumeMs] 续播（切清晰度路径）。
  Future<void> _openFromState(MvPlayerState state, {required bool resume}) async {
    final play = state.playUrl;
    if (play == null || play.allUrls.isEmpty) return;
    final headers = play.headers;
    final url = play.url;
    // 同一地址已在播 / 正在 open：跳过（load 路径 listener 与 bootstrap 会各触发一次）。
    if (_started && url == _lastMediaUrl) return;
    _httpHeaders = headers;
    _lastMediaUrl = url;
    _ensurePlayer();
    if (mounted) setState(() {});
    _started = true;
    final seekTo = resume ? _resumeMs : 0;
    _lastEngineError = '';
    if (resume) _resumeMs = 0;
    _openedBriefKey = _briefKeyOf(state.brief);

    // 依次尝试：主地址（带防盗链头）→ 主地址（裸）→ 备用地址。
    // EchoMusic 网页端是裸 URL 直出，说明头不是必须；但带上更稳。
    final attempts = <(String, Map<String, String>)>[
      (play.url, headers),
      (play.url, const {}),
      for (final b in play.backupUrls) (b, headers),
      for (final b in play.backupUrls) (b, const {}),
    ];
    Object? lastErr;
    for (final (url, hdr) in attempts) {
      if (!mounted || _player == null) return;
      _lastMediaUrl = url;
      _httpHeaders = hdr;
      try {
        await _player!.open(
          Media(url, httpHeaders: hdr.isEmpty ? null : hdr),
          play: true,
        );
        if (!mounted) return;
        if (seekTo > 0) {
          await _player!.seek(Duration(milliseconds: seekTo));
        }
        _armSwFallback(seekTo);
        return;
      } catch (e) {
        lastErr = e;
        continue;
      }
    }
    _lastEngineError = lastErr == null ? '无法打开视频地址' : '$lastErr';
  }

  /// 硬解黑屏时丢掉 controller 再建；Player 本体复用。
  Future<void> _recreateControllerForSoftDecode({required int seekTo}) async {
    final p = _player;
    if (p == null) return;
    _videoController = _createController(p);
    if (mounted) setState(() {});
    final url = _lastMediaUrl;
    if (url.isEmpty) return;
    try {
      await p.open(
        Media(url, httpHeaders: _httpHeaders.isEmpty ? null : _httpHeaders),
        play: true,
      );
      if (!mounted || seekTo <= 0) return;
      await p.seek(Duration(milliseconds: seekTo));
    } catch (e) {
      _lastEngineError = '软解重开失败：$e';
    }
  }

  void _togglePlay() {
    final p = _player;
    if (p == null || !_started) return;
    if (p.state.playing) {
      p.pause();
    } else {
      p.play();
    }
  }

  void _seekTo(double progress) {
    final p = _player;
    final dur = _durationMs.value;
    if (p == null || dur <= 0) return;
    final ms = (progress * dur).round().clamp(0, dur);
    p.seek(Duration(milliseconds: ms));
    _positionMs.value = ms;
  }

  @override
  void dispose() {
    final p = _player;
    _player = null;
    _videoController = null;
    _swFallbackTimer?.cancel();
    _swFallbackTimer = null;
    unawaited(_posSub?.cancel());
    unawaited(_durSub?.cancel());
    unawaited(_playingSub?.cancel());
    unawaited(_widthSub?.cancel());
    unawaited(_heightSub?.cancel());
    unawaited(_errorSub?.cancel());
    _posSub = null;
    _durSub = null;
    _playingSub = null;
    _widthSub = null;
    _heightSub = null;
    _errorSub = null;
    _positionMs.dispose();
    _durationMs.dispose();
    _playing.dispose();
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
    // 取流成功后打开播放器（覆盖加载完成、切清晰度、换版本三条路径）。
    // 版本切换会 clearPlayUrl，prev.playUrl 为空，不能拿它判断「是否在切清晰度」；
    // 改看已 open 的版本标识是否变化。
    ref.listen(mvPlayerProvider, (prev, next) {
      if (next.canPlay && next.playUrl?.url != prev?.playUrl?.url) {
        final switching = _briefKeyOf(next.brief) == _openedBriefKey &&
            next.playUrl?.url.isNotEmpty == true;
        if (switching) {
          _resumeMs = _positionMs.value;
        }
        unawaited(_openFromState(next, resume: switching));
      }
    });

    final settings = ref.watch(settingsControllerProvider);
    final barrageHash = _barrageHashOf(state, widget.hash);
    final barragePlatform = _barragePlatformOf(state);
    final barrageSource = barrageHash.isEmpty
        ? null
        : musicSourceRegistry?.capability<MvBarrageSource>(barragePlatform);

    final kugo = KugoTheme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _controlsVisible = !_controlsVisible),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 视频画面：controller 一建好就挂上，open 前也能注册纹理。
            if (_videoController != null)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black,
                  child: Video(
                    controller: _videoController!,
                    controls: NoVideoControls,
                    fit: BoxFit.contain,
                  ),
                ),
              )
            else
              _CoverPlaceholder(coverUrl: state.brief?.coverUrl ?? widget.coverUrl),

            // 弹幕飞层：叠在视频上、指针穿透；播放暂停时自动暂停。
            if (barrageSource != null)
              Positioned.fill(
                child: ValueListenableBuilder<bool>(
                  valueListenable: _playing,
                  builder: (context, playing, child) => MvBarrageLayer(
                    key: _barrageKey,
                    hash: barrageHash,
                    name: state.brief?.name ?? widget.name,
                    platform: barragePlatform,
                    enabled: settings.mvBarrageEnabled,
                    playing: playing,
                    config: settings.mvBarrageConfig,
                  ),
                ),
              ),

            // 顶部栏
            AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
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
                          if (barrageSource != null)
                            MvBarrageButton(
                              hash: barrageHash,
                              name: state.brief?.name ?? widget.name,
                              platform: barragePlatform,
                              enabled: settings.mvBarrageEnabled,
                              config: settings.mvBarrageConfig,
                              onEnabledChanged: (v) => ref
                                  .read(settingsControllerProvider.notifier)
                                  .setMvBarrageEnabled(v),
                              onConfigChanged: (cfg, {required persist}) => ref
                                  .read(settingsControllerProvider.notifier)
                                  .setMvBarrageConfig(cfg, persist: persist),
                              onSent: (text) =>
                                  _barrageKey.currentState?.showOwn(text),
                            ),
                          if (state.detail != null &&
                              state.detail!.sources.length > 1)
                            _QualityButton(
                              state: state,
                              onSelect: (s) => ref
                                  .read(mvPlayerProvider.notifier)
                                  .selectSource(s),
                            ),
                          _CollectButton(
                            videoId: state.brief?.id ?? widget.id,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 中央播放/暂停
            if (state.canPlay)
              AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: Center(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _playing,
                      builder: (context, playing, _) => _PlayPauseButton(
                        playing: playing,
                        onTap: _togglePlay,
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
            else if (state.status == MvLoadStatus.error ||
                (_lastEngineError.isNotEmpty && !_playing.value && _started))
              _ErrorOverlay(
                message: state.status == MvLoadStatus.error
                    ? state.error
                    : '播放器错误：$_lastEngineError',
                onRetry: () {
                  _lastEngineError = '';
                  _started = false;
                  _swFallbackTried = false;
                  // 恢复平台默认，而不是一律硬解（Windows 默认软解）。
                  _hwAccel = !isWindowsPlatform;
                  unawaited(
                    ref.read(mvPlayerProvider.notifier).load(state.brief ??
                        MvBrief(
                          id: widget.id,
                          hash: widget.hash,
                          name: widget.name,
                          coverUrl: widget.coverUrl,
                        )),
                  );
                },
              ),

            // 底部：进度条 + 信息
            AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        KugoSpacing.lg,
                        KugoSpacing.sm,
                        KugoSpacing.lg,
                        KugoSpacing.lg,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (state.canPlay) ...[
                            ValueListenableBuilder<int>(
                              valueListenable: _durationMs,
                              builder: (context, durationMs, _) {
                                final dur = durationMs <= 0 ? 1 : durationMs;
                                return ValueListenableBuilder<int>(
                                  valueListenable: _positionMs,
                                  builder: (context, positionMs, _) {
                                    final current = _dragging
                                        ? (_dragProgress * dur).round()
                                        : positionMs.clamp(0, dur);
                                    return Row(
                                      children: [
                                        Text(
                                          _fmt(current),
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                          ),
                                        ),
                                        const SizedBox(width: KugoSpacing.sm),
                                        Expanded(
                                          child: SliderTheme(
                                            data: SliderTheme.of(context)
                                                .copyWith(
                                              trackHeight: 3,
                                              thumbShape:
                                                  const RoundSliderThumbShape(
                                                enabledThumbRadius: 5,
                                              ),
                                              overlayShape:
                                                  const RoundSliderOverlayShape(
                                                overlayRadius: 10,
                                              ),
                                              activeTrackColor: kugo.primary,
                                              inactiveTrackColor:
                                                  Colors.white24,
                                              thumbColor: Colors.white,
                                            ),
                                            child: Slider(
                                              value: (current / dur)
                                                  .clamp(0.0, 1.0),
                                              onChanged: (v) => setState(() {
                                                _dragging = true;
                                                _dragProgress = v;
                                              }),
                                              onChangeEnd: (v) {
                                                _seekTo(v);
                                                setState(() {
                                                  _dragging = false;
                                                });
                                              },
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: KugoSpacing.sm),
                                        Text(
                                          _fmt((dur - current).clamp(0, dur)),
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                          const SizedBox(height: KugoSpacing.xs),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  state.brief?.artist.isNotEmpty == true
                                      ? state.brief!.artist
                                      : widget.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              if (state.versions.length > 1)
                                _VersionPickerButton(
                                  state: state,
                                  onSelect: (i) => ref
                                      .read(mvPlayerProvider.notifier)
                                      .selectVersion(i),
                                ),
                              TextButton(
                                onPressed: () => _openDetailSheet(state),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white70,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: KugoSpacing.sm,
                                  ),
                                  minimumSize: const Size(0, 32),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text('详情'),
                              ),
                            ],
                          ),
                          // 统计行：播放 / 时长 / 发行 / 清晰度
                          _StatsLine(state: state, durationFmt: _fmt),
                        ],
                      ),
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

  static String _fmt(int ms) {
    final safe = ms < 0 ? 0 : ms;
    final d = Duration(milliseconds: safe);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// 弹幕分池用的 MV 主 hash：优先当前版本 hash，其次当前片源 hash。
  /// 与 EchoMusic `meta?.hash || currentSourceHash` 同序。
  static String _barrageHashOf(MvPlayerState state, String fallback) {
    final briefHash = state.brief?.hash.trim() ?? '';
    if (briefHash.isNotEmpty) return briefHash;
    return state.source?.hash.trim() ?? fallback.trim();
  }

  static MusicPlatform _barragePlatformOf(MvPlayerState state) =>
      state.brief?.platform ?? MusicPlatform.kugou;

  void _openDetailSheet(MvPlayerState state) {
    final detail = state.detail;
    final brief = detail?.brief ?? state.brief;
    if (detail == null && brief == null) return;
    showKugoBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MvDetailSheet(
        name: brief?.name ?? widget.name,
        artist: brief?.artist.isNotEmpty == true
            ? brief!.artist
            : (detail?.authors.join(' / ') ?? widget.artist),
        publishDate: brief?.publishDate ?? '',
        durationMs: brief?.durationMs ?? 0,
        playCountLabel: detail?.playCountLabel ?? '',
        downloadCountLabel: detail?.downloadCountLabel ?? '',
        collectionCountLabel: detail?.collectionCountLabel ?? '',
        description: detail?.description ?? '',
        qualityLabel: state.source == null
            ? ''
            : state.source!.label +
                (state.source!.codec.isNotEmpty
                    ? ' · ${state.source!.codec}'
                    : ''),
      ),
    );
  }
}

/// 同曲多版本切换：点「其他版本」弹出版本列表。
class _VersionPickerButton extends StatelessWidget {
  const _VersionPickerButton({required this.state, required this.onSelect});

  final MvPlayerState state;
  final ValueChanged<int> onSelect;

  Future<void> _openList(BuildContext context) async {
    final selected = await showKugoBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _VersionListSheet(
        versions: state.versions,
        currentIndex: state.versionIndex,
      ),
    );
    if (selected == null || selected == state.versionIndex) return;
    onSelect(selected);
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => _openList(context),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white70,
        padding: const EdgeInsets.symmetric(horizontal: KugoSpacing.xs),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.chevron_right, size: 18, color: Colors.white54),
      iconAlignment: IconAlignment.end,
      label: Text(
        '其他版本 ${state.versions.length}',
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }
}

/// 版本列表弹层：两行信息 + 角标，当前项打勾。
class _VersionListSheet extends StatelessWidget {
  const _VersionListSheet({
    required this.versions,
    required this.currentIndex,
  });

  final List<MvBrief> versions;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KugoSpacing.xl,
              KugoSpacing.md,
              KugoSpacing.xl,
              KugoSpacing.sm,
            ),
            child: Row(
              children: [
                Text('其他版本', style: kugo.section),
                const Spacer(),
                Text(
                  '${versions.length} 个',
                  style: kugo.caption.copyWith(color: kugo.textSecondary),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: KugoSpacing.lg),
              itemCount: versions.length,
              itemBuilder: (context, index) {
                final v = versions[index];
                final selected = index == currentIndex;
                return _VersionTile(
                  version: v,
                  selected: selected,
                  onTap: () => Navigator.of(context).pop(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 版本列表行：封面 + 标题（UP 名）+ 副标题（作者 · 时长 · 清晰度 · 日期）+ 角标。
class _VersionTile extends StatelessWidget {
  const _VersionTile({
    required this.version,
    required this.selected,
    required this.onTap,
  });

  final MvBrief version;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final titleColor = selected ? kugo.primary : kugo.textPrimary;
    final meta = <String>[
      if (version.artist.trim().isNotEmpty &&
          version.artist.trim() != version.displayTitle)
        version.artist.trim(),
      if (version.name.trim().isNotEmpty &&
          version.name.trim() != version.displayTitle)
        version.name.trim(),
      if (version.durationMs > 0) version.durationLabel,
      if (version.qualityMark.isNotEmpty) version.qualityMark,
      if (version.publishDate.trim().isNotEmpty)
        version.publishDate.trim().split(' ').first,
    ];
    return Material(
      color: selected
          ? kugo.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KugoSpacing.lg,
            vertical: KugoSpacing.sm,
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(KugoRadius.chip),
                child: SizedBox(
                  width: 80,
                  height: 48,
                  child: version.coverUrl.isEmpty
                      ? ColoredBox(
                          color: kugo.primary.withValues(alpha: 0.15),
                          child: const Icon(
                            Icons.music_video,
                            size: 20,
                            color: Colors.white54,
                          ),
                        )
                      : Image.network(
                          version.coverUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => ColoredBox(
                            color: kugo.primary.withValues(alpha: 0.15),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: KugoSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      version.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kugo.body.copyWith(
                        color: titleColor,
                        fontWeight: selected ? FontWeight.w600 : null,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kugo.caption.copyWith(color: kugo.textSecondary),
                      ),
                    ],
                    if (version.isRecommend || version.tags.isNotEmpty) ...[
                      const SizedBox(height: KugoSpacing.xs),
                      Wrap(
                        spacing: KugoSpacing.xs,
                        runSpacing: KugoSpacing.xs,
                        children: [
                          if (version.isRecommend)
                            _VersionChip(
                              label: '官方推荐',
                              color: kugo.primary,
                            ),
                          for (final tag in version.tags.take(2))
                            _VersionChip(label: tag, color: kugo.textSecondary),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: KugoSpacing.sm),
              if (selected)
                Icon(Icons.check_circle, size: 18, color: kugo.primary)
              else
                const SizedBox(width: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _VersionChip extends StatelessWidget {
  const _VersionChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          height: 1.3,
        ),
      ),
    );
  }
}

/// MV 收藏：数字 video_id 才可点；hash / 空 id 禁用。
class _CollectButton extends ConsumerWidget {
  const _CollectButton({required this.videoId});

  final String videoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = normalizeMvCollectId(videoId);
    final collection = ref.watch(mvCollectionProvider);
    final collected = collection.isCollected(id);
    final pending = collection.isPending(id);
    final enabled = id.isNotEmpty && !pending && !collection.loading;
    return IconButton(
      tooltip: id.isEmpty
          ? '暂无可用的 MV 收藏信息'
          : (collected ? '取消收藏' : '收藏 MV'),
      onPressed: enabled
          ? () async {
              final next = await ref
                  .read(mvCollectionProvider.notifier)
                  .toggle(id);
              if (!context.mounted) return;
              final err = ref.read(mvCollectionProvider).error;
              if (next == null) {
                if (err.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(err)),
                  );
                }
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(next ? '已收藏' : '已取消收藏'),
                  duration: const Duration(milliseconds: 1200),
                ),
              );
            }
          : null,
      icon: Icon(
        collected ? Icons.favorite : Icons.favorite_border,
        color: collected ? Colors.redAccent : Colors.white70,
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.playing, required this.onTap});

  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black38,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(KugoSpacing.lg),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 40,
          ),
        ),
      ),
    );
  }
}

/// 底部统计摘要：播放量 · 时长 · 发行 · 清晰度（有啥显示啥）。
class _StatsLine extends StatelessWidget {
  const _StatsLine({required this.state, required this.durationFmt});

  final MvPlayerState state;
  final String Function(int ms) durationFmt;

  @override
  Widget build(BuildContext context) {
    final detail = state.detail;
    final brief = detail?.brief ?? state.brief;
    final parts = <String>[
      if (detail?.playCountLabel.isNotEmpty ?? false)
        '播放 ${detail!.playCountLabel}',
      if ((brief?.durationMs ?? 0) > 0) durationFmt(brief!.durationMs),
      if ((brief?.publishDate.isNotEmpty ?? false)) brief!.publishDate,
      if ((state.source?.label.isNotEmpty ?? false))
        state.source!.label +
            (state.source!.codec.isNotEmpty
                ? ' · ${state.source!.codec}'
                : ''),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: KugoSpacing.xs),
      child: Text(
        parts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.55),
          fontSize: 11,
        ),
      ),
    );
  }
}

class _MvDetailSheet extends StatelessWidget {
  const _MvDetailSheet({
    required this.name,
    required this.artist,
    required this.publishDate,
    required this.durationMs,
    required this.playCountLabel,
    required this.downloadCountLabel,
    required this.collectionCountLabel,
    required this.description,
    required this.qualityLabel,
  });

  final String name;
  final String artist;
  final String publishDate;
  final int durationMs;
  final String playCountLabel;
  final String downloadCountLabel;
  final String collectionCountLabel;
  final String description;
  final String qualityLabel;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final stats = <(String, String)>[
      if (playCountLabel.isNotEmpty) ('播放', playCountLabel),
      if (collectionCountLabel.isNotEmpty) ('收藏', collectionCountLabel),
      if (downloadCountLabel.isNotEmpty) ('下载', downloadCountLabel),
      if (durationMs > 0) ('时长', _fmt(durationMs)),
      if (publishDate.isNotEmpty) ('发行', publishDate),
      if (qualityLabel.isNotEmpty) ('画质', qualityLabel),
    ];
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          KugoSpacing.xl,
          KugoSpacing.md,
          KugoSpacing.xl,
          KugoSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: KugoSpacing.lg),
                decoration: BoxDecoration(
                  color: kugo.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              name,
              style: kugo.section,
            ),
            if (artist.isNotEmpty) ...[
              const SizedBox(height: KugoSpacing.xs),
              Text(artist, style: kugo.body.copyWith(color: kugo.textSecondary)),
            ],
            if (stats.isNotEmpty) ...[
              const SizedBox(height: KugoSpacing.lg),
              Wrap(
                spacing: KugoSpacing.md,
                runSpacing: KugoSpacing.sm,
                children: [
                  for (final (label, value) in stats)
                    _StatChip(label: label, value: value),
                ],
              ),
            ],
            if (description.trim().isNotEmpty) ...[
              const SizedBox(height: KugoSpacing.lg),
              Text('简介', style: kugo.body),
              const SizedBox(height: KugoSpacing.sm),
              Text(
                description.trim(),
                style: kugo.body.copyWith(
                  color: kugo.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _fmt(int ms) {
    final d = Duration(milliseconds: ms < 0 ? 0 : ms);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KugoSpacing.md,
        vertical: KugoSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: kugo.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(KugoRadius.chip),
      ),
      child: Text(
        '$label $value',
        style: kugo.caption.copyWith(color: kugo.textPrimary),
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
