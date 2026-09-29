import 'dart:async';

import 'package:floating/floating.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/models/mv_models.dart';
import '../../core/platform.dart' show isAndroidPlatform, isDesktopPlatform;
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
import 'mv_desktop_mini.dart';
import 'mv_player_host.dart';

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
  bool _controlsVisible = true;

  // ── 全屏（P0）──
  // 桌面走窗口全屏（window_manager）；移动端转横屏 + 沉浸式。
  bool _fullscreen = false;

  /// 进入全屏时的主题亮度，退出时恢复系统栏样式用。
  Brightness? _sysUiBrightnessOnEnter;

  // ── 桌面迷你窗（P2-2）──
  /// 是否处于「主窗瘦身为置顶小窗」状态。
  bool _desktopMini = false;

  /// 进入迷你态前的窗口形态（尺寸/位置/最大化），退出时还原。
  MvDesktopMiniState? _savedWindow;

  // ── 控制层自动隐藏（P1）──
  Timer? _controlsHideTimer;

  // ── 播放器手势（P1）──
  double _screenW = 0;

  /// 双击快进/快退：记录双击落点 x（判定左右半屏）。
  double _doubleTapDx = 0;
  int _seekHintDir = 0; // -1 快退 / +1 快进 / 0 无
  Timer? _seekHintTimer;

  /// 横向拖动快进：起点与目标。
  bool _scrubbing = false;
  double _scrubStartDx = 0;
  int _scrubOriginMs = 0;
  int _scrubTargetMs = 0;

  /// 右半屏竖向拖动调音量。
  bool _volumeGesture = false;
  double _volStartDx = 0;
  double _volStartDy = 0;
  double _volStartValue = 0;
  Timer? _volumeOverlayTimer;

  /// 桌面端键盘快捷键（空格/F/Esc/方向键）。
  final FocusNode _keyNode = FocusNode();

  /// 当前已成功 open 的版本标识（`id|hash`），用于区分「切清晰度」与「换版本」。
  /// `selectVersion` / `selectSource` 都会先 `clearPlayUrl`，`prev.playUrl` 拿不到
  /// 旧值，不能靠它判断。
  String _openedBriefKey = '';

  /// 弹幕层句柄：发送成功后把自己发的弹幕立即放出来。
  final GlobalKey<MvBarrageLayerState> _barrageKey =
      GlobalKey<MvBarrageLayerState>();

  // ── 引擎宿主（应用级，见 mv_player_host.dart）──
  // 页面只是 Video 的一个挂载点；退页是否停播由宿主的 mini 位决定。
  MvPlayerHostController get _host => ref.read(mvPlayerHostProvider.notifier);
  MvHostState get _hostState => ref.read(mvPlayerHostProvider);

  static String _briefKeyOf(MvBrief? brief) =>
      brief == null ? '' : '${brief.id}|${brief.hash}';

  @override
  void initState() {
    super.initState();
    // 引擎播放状态变化 → 控制层自动显隐 + Android 画中画注册。
    // （引擎是应用级的，页面只借宿主的 listenable。）
    _host.playing.addListener(_onPlayingChanged);
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

  /// 引擎起播 → 定时收起控制层 + 注册「离台进 PiP」；暂停 → 亮起控制层。
  void _onPlayingChanged() {
    if (!_hostState.engineActive) return;
    if (_host.playing.value) {
      _scheduleControlsHide();
      unawaited(_enablePipOnLeave());
    } else {
      _controlsHideTimer?.cancel();
      unawaited(_cancelPipOnLeave());
      if (mounted && !_controlsVisible) {
        setState(() => _controlsVisible = true);
      }
    }
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
    // 收藏状态与主播放并行；登录态空则静默。
    unawaited(
      ref
          .read(mvCollectionProvider.notifier)
          .ensureLoaded(platform: brief.platform),
    );
    // 小窗 / 列表重复入口回到全页：同曲会话直接接管——不重拉详情、
    // 不重开引擎，mvPlayerProvider 里的取流结果也还在，续播不回跳。
    if (_host.takeover(brief)) {
      _openedBriefKey = _briefKeyOf(ref.read(mvPlayerProvider).brief ?? brief);
      _onPlayingChanged();
      return;
    }
    // load → ready 的状态变化由 build 里的 ref.listen 接住并喂给宿主。
    await ref.read(mvPlayerProvider.notifier).load(brief);
  }

  void _togglePlay() => _host.togglePlay();

  void _seekTo(double progress) => _host.seekTo(progress);

  /// 相对当前进度快进/快退 [deltaMs] 毫秒（双击 / 键盘方向键共用）。
  void _seekBy(int deltaMs) => _host.seekBy(deltaMs);

  // ── 控制层自动隐藏 ──

  void _scheduleControlsHide() {
    _controlsHideTimer?.cancel();
    if (!_controlsVisible || !_host.playing.value || !_hostState.engineActive) {
      return;
    }
    _controlsHideTimer = Timer(const Duration(milliseconds: 3200), () {
      if (mounted && _host.playing.value && _controlsVisible) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleControlsHide();
  }

  // ── 全屏（P0）──

  /// 桌面：窗口级全屏；移动端：锁横屏 + 沉浸式（隐藏状态栏/导航栏）。
  Future<void> _toggleFullscreen() async {
    final next = !_fullscreen;
    if (isDesktopPlatform) {
      try {
        await windowManager.setFullScreen(next);
      } catch (_) {
        // 窗口未初始化（如测试）时静默失败。
      }
    } else if (next) {
      _sysUiBrightnessOnEnter ??= Theme.of(context).brightness;
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await _exitFullscreenSystemUi();
    }
    if (!mounted) return;
    setState(() => _fullscreen = next);
    if (next) _scheduleControlsHide();
  }

  /// 退出全屏：解锁方向 + 恢复 edge-to-edge 与系统栏配色。
  Future<void> _exitFullscreenSystemUi() async {
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    applyKugoSystemUi(_sysUiBrightnessOnEnter ?? Brightness.dark);
  }

  // ── 迷你窗（桌面 P2-2 / 移动端 P2-3）──

  /// 桌面：把**主窗**缩成置顶小窗——可拖到桌面任意位置、压在其他应用之上；
  /// 移动端：退页进入应用内浮动小窗（真正「移出应用」由 P2-1 系统 PiP 负责）。
  Future<void> _toggleMini() async {
    if (isDesktopPlatform) {
      if (_desktopMini) {
        await MvDesktopMini.exit(_savedWindow);
        _savedWindow = null;
        if (!mounted) return;
        setState(() => _desktopMini = false);
        _scheduleControlsHide();
      } else {
        // 先退出窗口全屏，不然迷你尺寸会被全屏覆盖。
        if (_fullscreen) await _toggleFullscreen();
        final prev = await MvDesktopMini.enter(_hostState.videoAspect);
        if (!mounted) return;
        setState(() {
          _savedWindow = prev;
          _desktopMini = true;
          _controlsVisible = true;
        });
        _scheduleControlsHide();
      }
      return;
    }
    // 移动端：应用内浮动小窗（P2-3）。
    _host.enterMini();
    context.pop();
  }

  /// 桌面迷你态的画面：视频铺满 + 自绘拖拽区 + 极简控件。
  /// 窗口无原生标题栏，拖动只能走 `windowManager.startDragging()`。
  Widget _buildDesktopMiniBody(
    MvPlayerState state,
    MvHostState hostState,
    MvPlayerHostController host,
  ) {
    final kugo = KugoTheme.of(context);
    final videoController = host.videoController;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (videoController != null)
          Positioned.fill(
            key: ValueKey('mv-mini-video-${hostState.controllerEpoch}'),
            child: ColoredBox(
              color: Colors.black,
              child: Video(
                controller: videoController,
                controls: NoVideoControls,
                fit: BoxFit.contain,
              ),
            ),
          )
        else
          _CoverPlaceholder(coverUrl: state.brief?.coverUrl ?? widget.coverUrl),

        // 整窗拖拽区（点按切换控件显隐）。
        Positioned.fill(
          child: MouseRegion(
            cursor: SystemMouseCursors.move,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => unawaited(windowManager.startDragging()),
              onTap: _toggleControls,
            ),
          ),
        ),

        // 顶部：还原窗口 / 停止并关闭
        AnimatedOpacity(
          opacity: _controlsVisible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: IgnorePointer(
            ignoring: !_controlsVisible,
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: KugoSpacing.xs),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    const Spacer(),
                    IconButton(
                      tooltip: '还原窗口',
                      color: Colors.white,
                      iconSize: 18,
                      onPressed: _toggleMini,
                      icon: const Icon(
                        Icons.open_in_full,
                        color: Colors.white70,
                      ),
                    ),
                    IconButton(
                      tooltip: '停止并关闭',
                      color: Colors.white,
                      iconSize: 18,
                      onPressed: () async {
                        await _toggleMini();
                        if (!mounted) return;
                        context.pop();
                      },
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // 底部：播放/暂停 + 进度（合成一行，小窗里少占画面）
        AnimatedOpacity(
          opacity: _controlsVisible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: IgnorePointer(
            ignoring: !_controlsVisible,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: KugoSpacing.xs),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: host.playing,
                      builder: (context, playing, _) => IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: playing ? '暂停' : '播放',
                        color: Colors.white,
                        iconSize: 22,
                        onPressed: _togglePlay,
                        icon: Icon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                    ),
                    if (state.canPlay)
                      Expanded(
                        child: _MvProgressBar(
                          position: host.position,
                          duration: host.duration,
                          buffered: host.buffered,
                          activeColor: kugo.primary,
                          onSeek: _seekTo,
                        ),
                      )
                    else
                      const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 倍速 / 音量（P1，引擎在宿主）──

  void _setRate(double rate) => _host.setRate(rate);

  void _toggleMute() => _host.toggleMute();

  /// 直接设定音量（手势/键盘路径，0 即静音）。
  void _setVolume(double v) => _host.setVolume(v);

  // ── 播放器手势（P1）──

  /// 双击：左半屏快退 10s，右半屏快进 10s。
  void _onDoubleTap() {
    if (!_hostState.engineActive || _host.duration.value <= 0) return;
    final forward = _doubleTapDx > _screenW / 2;
    _seekBy(forward ? 10000 : -10000);
    setState(() => _seekHintDir = forward ? 1 : -1);
    _seekHintTimer?.cancel();
    _seekHintTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _seekHintDir = 0);
    });
    _scheduleControlsHide();
  }

  /// 横向拖动快进：1 逻辑像素 ≈ 0.6s。
  void _onHorizontalDragStart(DragStartDetails d) {
    if (!_hostState.engineActive || _host.duration.value <= 0) return;
    _scrubbing = true;
    _scrubStartDx = d.localPosition.dx;
    _scrubOriginMs = _host.position.value;
    _scrubTargetMs = _scrubOriginMs;
    _scheduleControlsHide();
    setState(() {});
  }

  void _onHorizontalDragUpdate(DragUpdateDetails d) {
    if (!_scrubbing) return;
    final dur = _host.duration.value;
    if (dur <= 0) return;
    final deltaMs = ((d.localPosition.dx - _scrubStartDx) * 0.6 * 1000).round();
    setState(() {
      _scrubTargetMs = (_scrubOriginMs + deltaMs).clamp(0, dur);
    });
    _scheduleControlsHide();
  }

  void _onHorizontalDragEnd(DragEndDetails d) {
    if (!_scrubbing) return;
    _scrubbing = false;
    final dur = _host.duration.value;
    if (_hostState.engineActive && dur > 0) {
      _host.seekTo(_scrubTargetMs / dur);
    }
    setState(() {});
  }

  /// 右半屏竖向拖动调播放器音量（1 逻辑像素 ≈ 0.4）。
  void _onVerticalDragStart(DragStartDetails d) {
    _volStartDx = d.localPosition.dx;
    _volStartDy = d.localPosition.dy;
    _volumeGesture = _hostState.engineActive && _volStartDx > _screenW / 2;
    if (!_volumeGesture) return;
    _volumeOverlayTimer?.cancel();
    _volStartValue = _hostState.muted ? 0 : _hostState.volume;
    _scheduleControlsHide();
    setState(() {});
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (!_volumeGesture) return;
    final dy = d.localPosition.dy - _volStartDy;
    _setVolume(_volStartValue - dy * 0.4);
    _scheduleControlsHide();
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    if (!_volumeGesture) return;
    _volumeGesture = false;
    // 松手后浮层再停留一下，随后自然消隐。
    _volumeOverlayTimer?.cancel();
    _volumeOverlayTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() {});
    });
    setState(() {});
  }

  bool get _volumeOverlayVisible =>
      _volumeGesture || (_volumeOverlayTimer?.isActive ?? false);

  // ── 桌面端键盘快捷键 ──

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      unawaited(_toggleFullscreen());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && _fullscreen) {
      unawaited(_toggleFullscreen());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-5000);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _seekBy(5000);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _setVolume(_hostState.volume + 5);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _setVolume(_hostState.volume - 5);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Android 系统画中画（P2-1）──
  // 注册 OnLeavePiP：用户按 Home / 切走时由系统自动缩小（走的是
  // onUserLeaveHint，不会误触权限弹窗等 inactive 场景）。暂停或离开
  // MV 页时取消注册，避免在别的页面按 Home 也进 PiP。

  Future<void> _enablePipOnLeave() async {
    if (!isAndroidPlatform) return;
    try {
      await Floating().enable(
        OnLeavePiP(aspectRatio: _rationalFor(_hostState.videoAspect)),
      );
    } catch (_) {
      // 设备不支持（Android < 8 / 厂商限制）：静默降级为普通后台。
    }
  }

  Future<void> _cancelPipOnLeave() async {
    if (!isAndroidPlatform) return;
    try {
      await Floating().cancelOnLeavePiP();
    } catch (_) {}
  }

  /// Android 支持的宽高比区间是 [1/2.39, 2.39]，用整数比近似当前视频画幅。
  static Rational _rationalFor(double aspect) {
    final a = aspect <= 0 ? 16 / 9 : aspect;
    final clamped = a.clamp(1 / 2.39, 2.39);
    return Rational((clamped * 100).round(), 100);
  }

  @override
  void dispose() {
    _host.playing.removeListener(_onPlayingChanged);
    _controlsHideTimer?.cancel();
    _controlsHideTimer = null;
    _seekHintTimer?.cancel();
    _seekHintTimer = null;
    _volumeOverlayTimer?.cancel();
    _volumeOverlayTimer = null;
    _keyNode.dispose();
    // 离开 MV 页即解除「离台自动 PiP」。
    unawaited(_cancelPipOnLeave());
    // 非小窗退出：结束会话（销毁引擎、释放屏幕常亮与小窗）。
    // 小窗退出（enterMini 后 pop）引擎保持存活，由小窗接手。
    if (!_hostState.mini) {
      unawaited(_host.shutdown());
    }
    // 迷你态退出（pop / 系统返回）：还原窗口尺寸与置顶。
    if (_desktopMini) {
      unawaited(MvDesktopMini.exit(_savedWindow));
    }
    // 从全屏状态下直接退出页面（pop / 返回手势）：还原方向与系统栏。
    if (!isDesktopPlatform && _fullscreen) {
      unawaited(_exitFullscreenSystemUi());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mvPlayerProvider);
    final hostState = ref.watch(mvPlayerHostProvider);
    final host = _host;
    // 取流成功后交给应用级宿主打流（覆盖加载完成、切清晰度、换版本三条路径）。
    // 版本切换会 clearPlayUrl，prev.playUrl 为空，不能拿它判断「是否在切清晰度」；
    // 改看已 open 的版本标识是否变化。
    ref.listen(mvPlayerProvider, (prev, next) {
      if (next.canPlay && next.playUrl?.url != prev?.playUrl?.url) {
        final brief = next.brief;
        final play = next.playUrl;
        if (brief == null || play == null) return;
        final switching =
            _briefKeyOf(brief) == _openedBriefKey && play.url.isNotEmpty;
        // 切清晰度续播：open 会重置进度，先取当前游标。
        final resumeMs = switching ? host.position.value : 0;
        _openedBriefKey = _briefKeyOf(brief);
        unawaited(host.openPlayUrl(brief, play, resumeMs: resumeMs));
      }
    });

    final settings = ref.watch(settingsControllerProvider);
    final barrageHash = _barrageHashOf(state, widget.hash);
    final barragePlatform = _barragePlatformOf(state);
    final barrageSource = barrageHash.isEmpty
        ? null
        : musicSourceRegistry?.capability<MvBarrageSource>(barragePlatform);

    final kugo = KugoTheme.of(context);
    return Focus(
      focusNode: _keyNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        // 桌面迷你态走独立布局：整窗拖拽移动，手势快进/音量在这里没有意义
        // （还会和窗口拖拽抢手势）。
        body: _desktopMini
            ? _buildDesktopMiniBody(state, hostState, host)
            : LayoutBuilder(
                builder: (context, constraints) {
                  // 手势判定用：双击/竖向拖动的左右半屏分界。
                  _screenW = constraints.maxWidth;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleControls,
                    onDoubleTapDown: (d) => _doubleTapDx = d.localPosition.dx,
                    onDoubleTap: _onDoubleTap,
                    onHorizontalDragStart: _onHorizontalDragStart,
                    onHorizontalDragUpdate: _onHorizontalDragUpdate,
                    onHorizontalDragEnd: _onHorizontalDragEnd,
                    onVerticalDragStart: _onVerticalDragStart,
                    onVerticalDragUpdate: _onVerticalDragUpdate,
                    onVerticalDragEnd: _onVerticalDragEnd,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // 视频画面：宿主 controller 一建好就挂上，open 前也能注册纹理。
                        // controllerEpoch 变化（软解回退重建）时重挂。
                        if (host.videoController != null)
                          Positioned.fill(
                            key: ValueKey(
                              'mv-video-${hostState.controllerEpoch}',
                            ),
                            child: ColoredBox(
                              color: Colors.black,
                              child: Video(
                                controller: host.videoController!,
                                controls: NoVideoControls,
                                fit: BoxFit.contain,
                              ),
                            ),
                          )
                        else
                          _CoverPlaceholder(
                            coverUrl: state.brief?.coverUrl ?? widget.coverUrl,
                          ),

                        // 弹幕飞层：叠在视频上、指针穿透；播放暂停时自动暂停。
                        if (barrageSource != null)
                          Positioned.fill(
                            child: ValueListenableBuilder<bool>(
                              valueListenable: host.playing,
                              builder: (context, playing, child) =>
                                  MvBarrageLayer(
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
                                        icon: const Icon(
                                          Icons.keyboard_arrow_down,
                                        ),
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
                                          name:
                                              state.brief?.name ?? widget.name,
                                          platform: barragePlatform,
                                          enabled: settings.mvBarrageEnabled,
                                          config: settings.mvBarrageConfig,
                                          onEnabledChanged: (v) => ref
                                              .read(
                                                settingsControllerProvider
                                                    .notifier,
                                              )
                                              .setMvBarrageEnabled(v),
                                          onConfigChanged:
                                              (cfg, {required persist}) => ref
                                                  .read(
                                                    settingsControllerProvider
                                                        .notifier,
                                                  )
                                                  .setMvBarrageConfig(
                                                    cfg,
                                                    persist: persist,
                                                  ),
                                          onSent: (text) => _barrageKey
                                              .currentState
                                              ?.showOwn(text),
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
                                      // 迷你窗：桌面把主窗瘦成置顶小窗（可移出应用）；
                                      // 移动端退页进应用内浮动小窗。
                                      if (hostState.engineActive &&
                                          host.started)
                                        IconButton(
                                          tooltip: isDesktopPlatform
                                              ? '缩为置顶迷你窗'
                                              : '缩小为小窗',
                                          color: Colors.white,
                                          onPressed: _toggleMini,
                                          icon: const Icon(
                                            Icons.picture_in_picture_alt,
                                            color: Colors.white70,
                                          ),
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
                                  valueListenable: host.playing,
                                  builder: (context, playing, _) =>
                                      _PlayPauseButton(
                                        playing: playing,
                                        onTap: _togglePlay,
                                      ),
                                ),
                              ),
                            ),
                          ),

                        // 手势反馈浮层（独立于控制层显隐）
                        _SeekHint(dir: _seekHintDir),
                        if (_scrubbing)
                          _ScrubOverlay(
                            deltaMs: _scrubTargetMs - _scrubOriginMs,
                            targetMs: _scrubTargetMs,
                            durationMs: host.duration.value,
                          ),
                        if (_volumeOverlayVisible)
                          _VolumeOverlay(
                            volume: hostState.volume,
                            muted: hostState.muted,
                          ),

                        // 状态层
                        if (state.status == MvLoadStatus.loading)
                          const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white70,
                            ),
                          )
                        else if (state.status == MvLoadStatus.error ||
                            (host.engineError.value.isNotEmpty &&
                                !host.playing.value &&
                                hostState.engineActive))
                          _ErrorOverlay(
                            message: state.status == MvLoadStatus.error
                                ? state.error
                                : '播放器错误：${host.engineError.value}',
                            onRetry: () {
                              // 复位宿主 open 状态与解码策略，重走地址重试链。
                              _host.resetForRetry();
                              unawaited(
                                ref
                                    .read(mvPlayerProvider.notifier)
                                    .load(
                                      state.brief ??
                                          MvBrief(
                                            id: widget.id,
                                            hash: widget.hash,
                                            name: widget.name,
                                            coverUrl: widget.coverUrl,
                                          ),
                                    ),
                              );
                            },
                          ),

                        // 底部：进度条 + 核心控件 + 信息（全屏时只留核心控件）
                        AnimatedOpacity(
                          opacity: _controlsVisible ? 1 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: IgnorePointer(
                            ignoring: !_controlsVisible,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: SafeArea(
                                child: Padding(
                                  // 全屏（横屏）下收紧底部留白，把画面撑满。
                                  padding: _fullscreen
                                      ? const EdgeInsets.fromLTRB(
                                          KugoSpacing.lg,
                                          KugoSpacing.sm,
                                          KugoSpacing.lg,
                                          KugoSpacing.sm,
                                        )
                                      : const EdgeInsets.fromLTRB(
                                          KugoSpacing.lg,
                                          KugoSpacing.sm,
                                          KugoSpacing.lg,
                                          KugoSpacing.lg,
                                        ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (state.canPlay)
                                        _MvProgressBar(
                                          position: host.position,
                                          duration: host.duration,
                                          buffered: host.buffered,
                                          activeColor: kugo.primary,
                                          onSeek: _seekTo,
                                        ),
                                      // 核心控件行：播放/暂停 · 倍速 · 静音 · 全屏
                                      Row(
                                        children: [
                                          if (state.canPlay)
                                            ValueListenableBuilder<bool>(
                                              valueListenable: host.playing,
                                              builder: (context, playing, _) =>
                                                  IconButton(
                                                    tooltip: playing
                                                        ? '暂停'
                                                        : '播放',
                                                    color: Colors.white,
                                                    iconSize: 26,
                                                    onPressed: _togglePlay,
                                                    icon: Icon(
                                                      playing
                                                          ? Icons.pause_rounded
                                                          : Icons
                                                                .play_arrow_rounded,
                                                    ),
                                                  ),
                                            ),
                                          if (state.canPlay)
                                            _SpeedButton(
                                              rate: hostState.rate,
                                              onSelect: _setRate,
                                            ),
                                          if (state.canPlay)
                                            _MuteButton(
                                              muted: hostState.muted,
                                              volume: hostState.volume,
                                              onToggle: _toggleMute,
                                            ),
                                          const Spacer(),
                                          _FullscreenButton(
                                            fullscreen: _fullscreen,
                                            onToggle: _toggleFullscreen,
                                          ),
                                        ],
                                      ),
                                      // 信息区：竖屏 / 窗口模式才展示，全屏让位给画面。
                                      if (!_fullscreen) ...[
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                state
                                                            .brief
                                                            ?.artist
                                                            .isNotEmpty ==
                                                        true
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
                                                    .read(
                                                      mvPlayerProvider.notifier,
                                                    )
                                                    .selectVersion(i),
                                              ),
                                            TextButton(
                                              onPressed: () =>
                                                  _openDetailSheet(state),
                                              style: TextButton.styleFrom(
                                                foregroundColor: Colors.white70,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal:
                                                          KugoSpacing.sm,
                                                    ),
                                                minimumSize: const Size(0, 32),
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ),
                                              child: const Text('详情'),
                                            ),
                                          ],
                                        ),
                                        // 统计行：播放 / 时长 / 发行 / 清晰度
                                        _StatsLine(
                                          state: state,
                                          durationFmt: _fmt,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
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
  const _VersionListSheet({required this.versions, required this.currentIndex});

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
                            _VersionChip(label: '官方推荐', color: kugo.primary),
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
        style: TextStyle(color: color, fontSize: 10, height: 1.3),
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
      tooltip: id.isEmpty ? '暂无可用的 MV 收藏信息' : (collected ? '取消收藏' : '收藏 MV'),
      onPressed: enabled
          ? () async {
              final next = await ref
                  .read(mvCollectionProvider.notifier)
                  .toggle(id);
              if (!context.mounted) return;
              final err = ref.read(mvCollectionProvider).error;
              if (next == null) {
                if (err.isNotEmpty) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(err)));
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
            (state.source!.codec.isNotEmpty ? ' · ${state.source!.codec}' : ''),
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
            Text(name, style: kugo.section),
            if (artist.isNotEmpty) ...[
              const SizedBox(height: KugoSpacing.xs),
              Text(
                artist,
                style: kugo.body.copyWith(color: kugo.textSecondary),
              ),
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

/// 自绘 MV 进度条（P1）：已播 / 已缓冲 / 拖动时间气泡，支持点按跳转与横向拖动。
///
/// 不用 Material `Slider`：它画不了缓冲段，也没有拖动气泡。
class _MvProgressBar extends StatefulWidget {
  const _MvProgressBar({
    required this.position,
    required this.duration,
    required this.buffered,
    required this.activeColor,
    required this.onSeek,
  });

  final ValueListenable<int> position;
  final ValueListenable<int> duration;
  final ValueListenable<int> buffered;
  final Color activeColor;

  /// 拖动结束 / 点按时回调（0–1）。
  final ValueChanged<double> onSeek;

  @override
  State<_MvProgressBar> createState() => _MvProgressBarState();
}

class _MvProgressBarState extends State<_MvProgressBar> {
  bool _dragging = false;
  double _dragValue = 0; // 0–1

  double _fractionAt(double dx, double width) =>
      width <= 0 ? 0.0 : (dx / width).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.duration,
      builder: (context, durationMs, _) {
        final dur = durationMs <= 0 ? 1 : durationMs;
        return ValueListenableBuilder<int>(
          valueListenable: widget.position,
          builder: (context, positionMs, _) {
            return ValueListenableBuilder<int>(
              valueListenable: widget.buffered,
              builder: (context, bufferedMs, _) {
                final value = _dragging
                    ? _dragValue
                    : (positionMs.clamp(0, dur) / dur).clamp(0.0, 1.0);
                final buffered = (bufferedMs.clamp(0, dur) / dur).clamp(
                  0.0,
                  1.0,
                );
                final current = (value * dur).round();
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
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          return SizedBox(
                            height: 46,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              // 点按直接跳；拖动则实时预览、松手 seek。
                              onTapDown: (d) => widget.onSeek(
                                _fractionAt(d.localPosition.dx, width),
                              ),
                              onHorizontalDragStart: (d) {
                                setState(() {
                                  _dragging = true;
                                  _dragValue = _fractionAt(
                                    d.localPosition.dx,
                                    width,
                                  );
                                });
                              },
                              onHorizontalDragUpdate: (d) {
                                setState(() {
                                  _dragValue = _fractionAt(
                                    d.localPosition.dx,
                                    width,
                                  );
                                });
                              },
                              onHorizontalDragEnd: (_) {
                                setState(() => _dragging = false);
                                widget.onSeek(_dragValue);
                              },
                              child: CustomPaint(
                                size: Size(double.infinity, 46),
                                painter: _ProgressPainter(
                                  progress: value,
                                  buffered: buffered,
                                  activeColor: widget.activeColor,
                                  showBubble: _dragging,
                                  bubbleText: _fmt(current),
                                ),
                              ),
                            ),
                          );
                        },
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
        );
      },
    );
  }

  static String _fmt(int ms) {
    final safe = ms < 0 ? 0 : ms;
    final d = Duration(milliseconds: safe);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// 进度条轨道：背景 / 已缓冲 / 已播 / 拖块 / 拖动时间气泡。
class _ProgressPainter extends CustomPainter {
  _ProgressPainter({
    required this.progress,
    required this.buffered,
    required this.activeColor,
    required this.showBubble,
    required this.bubbleText,
  });

  final double progress;
  final double buffered;
  final Color activeColor;
  final bool showBubble;
  final String bubbleText;

  static const _trackHeight = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final trackY = h - 12; // 轨道中心线
    final radius = _trackHeight / 2;
    RRect rrect(double x0, double x1) => RRect.fromRectAndRadius(
      Rect.fromLTRB(x0, trackY - radius, x1, trackY + radius),
      const Radius.circular(_trackHeight / 2),
    );

    // 背景轨
    canvas.drawRRect(rrect(0, w), Paint()..color = Colors.white24);
    // 已缓冲
    if (buffered > 0) {
      canvas.drawRRect(
        rrect(0, w * buffered),
        Paint()..color = Colors.white.withValues(alpha: 0.35),
      );
    }
    // 已播
    if (progress > 0) {
      canvas.drawRRect(rrect(0, w * progress), Paint()..color = activeColor);
    }
    // 拖块
    final thumbX = w * progress;
    canvas.drawCircle(
      Offset(thumbX, trackY),
      showBubble ? 9.0 : 5.0,
      Paint()..color = Colors.white,
    );
    // 拖动时间气泡
    if (showBubble) {
      final tp = TextPainter(
        text: TextSpan(
          text: bubbleText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      const hPad = 7.0;
      const vPad = 4.0;
      final bw = tp.width + hPad * 2;
      final bh = tp.height + vPad * 2;
      final cx = thumbX.clamp(bw / 2 + 2, w - bw / 2 - 2);
      final rect = Rect.fromCenter(
        center: Offset(cx, trackY - 22),
        width: bw,
        height: bh,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        Paint()..color = const Color(0xE61C2230),
      );
      tp.paint(canvas, rect.topLeft + const Offset(hPad, vPad));
    }
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.progress != progress ||
      old.buffered != buffered ||
      old.showBubble != showBubble ||
      old.bubbleText != bubbleText ||
      old.activeColor != activeColor;
}

/// 倍速按钮（P1）：0.5x–2.0x，当前倍速非 1 时显示角标。
class _SpeedButton extends StatelessWidget {
  const _SpeedButton({required this.rate, required this.onSelect});

  final double rate;
  final ValueChanged<double> onSelect;

  static const _rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      color: const Color(0xFF1C2230),
      tooltip: '倍速',
      initialValue: rate,
      onSelected: onSelect,
      itemBuilder: (context) => [
        for (final r in _rates)
          PopupMenuItem(
            value: r,
            child: Row(
              children: [
                if (r == rate)
                  const Icon(Icons.check, size: 16, color: Colors.white70)
                else
                  const SizedBox(width: 16),
                const SizedBox(width: KugoSpacing.sm),
                Text(
                  r == 1.0 ? '正常' : '${r}x',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KugoSpacing.sm,
          vertical: KugoSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.speed,
              size: 18,
              color: rate != 1.0 ? Colors.white : Colors.white70,
            ),
            if (rate != 1.0) ...[
              const SizedBox(width: 2),
              Text(
                '${rate}x',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 静音按钮（P1）。
class _MuteButton extends StatelessWidget {
  const _MuteButton({
    required this.muted,
    required this.volume,
    required this.onToggle,
  });

  final bool muted;
  final double volume;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final effective = muted || volume <= 0;
    final icon = effective
        ? Icons.volume_off
        : (volume < 50 ? Icons.volume_down : Icons.volume_up);
    return IconButton(
      color: Colors.white,
      tooltip: effective ? '取消静音' : '静音',
      onPressed: onToggle,
      icon: Icon(icon, color: Colors.white70),
    );
  }
}

/// 全屏按钮（P0）。
class _FullscreenButton extends StatelessWidget {
  const _FullscreenButton({required this.fullscreen, required this.onToggle});

  final bool fullscreen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      color: Colors.white,
      tooltip: fullscreen ? '退出全屏' : '全屏',
      onPressed: onToggle,
      icon: Icon(
        fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
        color: Colors.white70,
      ),
    );
  }
}

/// 双击快进/快退反馈：贴左/右半屏的半透明胶囊（dir=0 时淡出）。
class _SeekHint extends StatelessWidget {
  const _SeekHint({required this.dir});

  /// -1 快退 / +1 快进 / 0 无。
  final int dir;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: dir != 0 ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Align(
          alignment: dir >= 0 ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: MediaQuery.sizeOf(context).width * 0.14,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: KugoSpacing.lg,
                vertical: KugoSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(KugoRadius.chip),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    dir >= 0 ? Icons.fast_forward : Icons.fast_rewind,
                    color: Colors.white,
                    size: 26,
                  ),
                  const SizedBox(width: KugoSpacing.xs),
                  const Text(
                    '10 秒',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 横向拖动快进浮层：快进/快退时长 + 目标时间。
class _ScrubOverlay extends StatelessWidget {
  const _ScrubOverlay({
    required this.deltaMs,
    required this.targetMs,
    required this.durationMs,
  });

  final int deltaMs;
  final int targetMs;
  final int durationMs;

  static String _fmt(int ms) {
    final safe = ms < 0 ? 0 : ms;
    final d = Duration(milliseconds: safe);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  static String _fmtDelta(int ms) {
    final d = Duration(milliseconds: ms.abs());
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m > 0) return '$m 分 $s 秒';
    return '$s 秒';
  }

  @override
  Widget build(BuildContext context) {
    final forward = deltaMs >= 0;
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, -0.55),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: KugoSpacing.md,
            vertical: KugoSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(KugoRadius.chip),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                forward ? Icons.fast_forward : Icons.fast_rewind,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: KugoSpacing.xs),
              Text(
                '${forward ? '快进' : '快退'} ${_fmtDelta(deltaMs)} · '
                '${_fmt(targetMs.clamp(0, durationMs))}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 右半屏竖向拖动的音量浮层：图标 + 百分比 + 竖条。
class _VolumeOverlay extends StatelessWidget {
  const _VolumeOverlay({required this.volume, required this.muted});

  final double volume;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final effective = muted || volume <= 0;
    final icon = effective
        ? Icons.volume_off
        : (volume < 50 ? Icons.volume_down : Icons.volume_up);
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 48,
          padding: const EdgeInsets.symmetric(vertical: KugoSpacing.lg),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(KugoRadius.chip),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(height: KugoSpacing.xs),
              Text(
                effective ? '静音' : '${volume.round()}%',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
              const SizedBox(height: KugoSpacing.sm),
              SizedBox(
                width: 4,
                height: 120,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  clipBehavior: Clip.none,
                  children: [
                    Container(width: 3, height: 120, color: Colors.white24),
                    FractionallySizedBox(
                      heightFactor: (volume / 100).clamp(0.0, 1.0),
                      child: Container(width: 3, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
