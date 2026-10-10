import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/models/track.dart';
import '../../../core/utils/lrc_parser.dart';
import '../desktop_lyric_host.dart';
import '../desktop_lyric_ipc.dart';
import '../desktop_lyric_protocol.dart';
import '../desktop_lyric_store.dart';
import '../desktop_lyric_style.dart';

/// 歌词进程本地状态：收主进程 snapshot，播放中本地 Ticker 自走对齐进度。
///
/// 通信走 [LyricIpc]（TCP），不再用 desktop_multi_window 的 WindowMethodChannel。
class DesktopLyricController extends ChangeNotifier {
  DesktopLyricController();

  @visibleForTesting
  DesktopLyricController.withSnapshot(DesktopLyricSnapshot snapshot) {
    _snap = snapshot;
    _lyrics = snapshot.lyrics;
    _localPosMs = snapshot.effectivePositionMs;
    _anchorPosMs = _localPosMs;
  }

  DesktopLyricSnapshot _snap = const DesktopLyricSnapshot();
  List<LyricLine> _lyrics = const [];
  int _revision = -1;
  int _localPosMs = 0;
  DateTime _anchorWall = DateTime.now();
  int _anchorPosMs = 0;
  Timer? _tick;
  bool _readySent = false;
  bool _windowReady = false;
  bool transparentBackground = true;
  bool _detaching = false;
  double? _windowFontScale;
  DesktopLyricSnapshot? _pendingSnap;
  bool? _pendingLock;

  LyricIpcWriter? _writer;
  LyricIpcReader? _reader;
  StreamSubscription<Map<String, Object?>>? _msgSub;

  DesktopLyricSnapshot get snapshot => _snap;
  List<LyricLine> get lyrics => _lyrics;
  bool get isPlaying => _snap.isPlaying;
  bool get locked => _snap.locked;
  String get title => _snap.title;
  String get artist => _snap.artist;

  /// 歌词游标锚点（本地 Ticker 自走的基准）。
  /// [anchorWall] 是收到 snapshot 时的墙钟，[anchorPosMs] 是当时（含 offset）的游标。
  DateTime get anchorWall => _anchorWall;
  int get anchorPosMs => _anchorPosMs;

  /// 当前歌词游标（含 offset）。
  int get positionMs => _localPosMs;

  int get activeIndex => findLyricIndex(_lyrics, _localPosMs);

  /// 当前整行（供逐字渲染取 chars/时间轴）；无词时 null。
  LyricLine? get currentLyric {
    final i = activeIndex;
    if (i < 0 || i >= _lyrics.length) return null;
    return _lyrics[i];
  }

  String get currentLine {
    final line = currentLyric;
    if (line == null) {
      return _snap.title.isEmpty ? '桌面歌词' : _snap.title;
    }
    return line.text;
  }

  String? get nextLine {
    final i = activeIndex + 1;
    if (i < 0 || i >= _lyrics.length) return null;
    return _lyrics[i].text;
  }

  String? get currentTranslation {
    final i = activeIndex;
    if (i < 0 || i >= _lyrics.length) return null;
    return _lyrics[i].translated;
  }

  /// 接上主进程 IPC。连接建立后立刻可收 snapshot。
  Future<void> attachIpc(Socket socket) async {
    await detachIpc();
    final reader = LyricIpcReader(socket);
    _reader = reader;
    _writer = LyricIpcWriter(socket);
    _msgSub = reader.messages.listen(
      _onIpcMessage,
      onDone: () {
        // The main process is gone: an orphan click-through window must not stay.
        if (Platform.isLinux &&
            Platform.environment[LyricIpc.envProcess] == '1' &&
            !_detaching) {
          exit(0);
        }
      },
    );
  }

  Future<void> detachIpc() async {
    _detaching = true;
    await _msgSub?.cancel();
    _msgSub = null;
    await _reader?.close();
    _reader = null;
    await _writer?.close();
    _writer = null;
    _detaching = false;
  }

  void _onIpcMessage(Map<String, Object?> msg) {
    switch (msg['t']) {
      case LyricIpc.typeSnapshot:
        final wire = msg['d'];
        final snap = DesktopLyricSnapshot.fromWire(wire);
        final lyricsOmitted = (wire as Map?)?['lyricsOmitted'] == true;
        _applySnap(snap, lyricsOmitted: lyricsOmitted);
      case LyricIpc.typeClose:
        if (Platform.isLinux &&
            Platform.environment[LyricIpc.envProcess] == '1') {
          exit(0);
        }
        unawaited(DesktopLyricHost.hide());
      case LyricIpc.typeHide:
        unawaited(DesktopLyricHost.hide());
      case LyricIpc.typeShow:
        unawaited(_showVisible());
      case LyricIpc.typeReposition:
        unawaited(resetPosition());
    }
  }

  Future<void> _showVisible() async {
    if (Platform.isLinux) await DesktopLyricHost.ensureVisible();
    await DesktopLyricHost.show(inactive: true);
  }

  Future<void> _fitWindow(DesktopLyricSnapshot snapshot) async {
    if (!Platform.isLinux || Platform.environment[LyricIpc.envProcess] != '1') {
      return;
    }
    final scale = snapshot.style.fontScale.clamp(0.6, 2.0);
    if (_windowFontScale == scale) return;
    _windowFontScale = scale;
    try {
      final bounds = await DesktopLyricHost.getPosition();
      await DesktopLyricHost.setSize(bounds.width, (88 * scale).clamp(88, 176));
      await DesktopLyricHost.ensureVisible();
    } catch (e) {
      debugPrint('[desktop_lyric] resize unavailable: ${e.runtimeType}');
    }
  }

  /// 回到默认位：工作区顶部居中（离顶端 12px）。
  Future<void> resetPosition() {
    return DesktopLyricHost.centerTop(width: 720, height: 88, top: 12);
  }

  void _applySnap(DesktopLyricSnapshot snap, {required bool lyricsOmitted}) {
    // 窗口样式初始化完成前先暂存：init 期间并发 window 调用会死锁。
    if (!_windowReady) {
      _pendingSnap = snap;
      return;
    }
    unawaited(_fitWindow(snap));

    final trackChanged = snap.trackId != _snap.trackId;
    final revChanged = snap.revision != _revision;

    if (!lyricsOmitted &&
        (trackChanged || revChanged || snap.lyrics.isNotEmpty)) {
      _lyrics = snap.lyrics;
      _revision = snap.revision;
    } else if (trackChanged || revChanged) {
      // 主窗切歌清词但本次省略了数组 → 先清掉防串词。
      if (lyricsOmitted && (trackChanged || revChanged)) {
        _lyrics = const [];
        _revision = snap.revision;
      }
    }

    _snap = snap.copyWith(lyrics: _lyrics);
    _localPosMs = snap.effectivePositionMs;
    _anchorWall = DateTime.now();
    _anchorPosMs = _localPosMs;
    _syncTicker();
    _applyLock(snap.locked);
    // 主窗播放中每 400ms 推一次 positionOnly 快照，其中绝大多数不改变任何
    // 可见内容（歌词行、标题、播放态都没变）。无条件通知会让整个歌词窗
    // 每秒重建 2–3 次，因此只在可见内容真的变化时才通知。
    if (_visibleSignatureChanged()) notifyListeners();
  }

  /// 上次通知时窗口可见内容与当前行号的快照（用于去重通知）。
  Object? _lastSignature;

  /// 触发重建只取决这些量：外形（标题/播放态/锁定/译文/字号/样式）+ 当前行内容。
  /// 游标推进本身不需要重建——[KaraokeSweepLine] 有独立 Ticker 自算扫光。
  Object _visibleSignature() => visibleLyricSignature(
    title: _snap.title,
    artist: _snap.artist,
    isPlaying: _snap.isPlaying,
    locked: _snap.locked,
    translation: _snap.translation,
    fontScale: _snap.fontScale,
    style: _snap.style,
    activeIndex: activeIndex,
    lyrics: _lyrics,
  );

  bool _visibleSignatureChanged() {
    final next = _visibleSignature();
    if (next == _lastSignature) return false;
    _lastSignature = next;
    return true;
  }

  bool _lockApplied = false;

  /// P1 锁定 = 全窗点击穿透。只改本窗 WS_EX_TRANSPARENT，不动 LAYERED。
  Future<void> _applyLock(bool locked) async {
    if (!_windowReady) {
      _pendingLock = locked;
      return;
    }
    if (_lockApplied == locked) return;
    _lockApplied = locked;
    try {
      await DesktopLyricHost.setIgnoreMouseEvents(locked);
    } catch (e) {
      debugPrint('[desktop_lyric] setIgnoreMouseEvents failed: $e');
    }
  }

  /// 窗口样式 init 完成后调用：冲刷暂存的 snapshot / 锁定态。
  void markWindowReady() {
    _windowReady = true;
    final lock = _pendingLock;
    _pendingLock = null;
    if (lock != null) _applyLock(lock);
    final snap = _pendingSnap;
    _pendingSnap = null;
    if (snap != null) {
      _applySnap(snap, lyricsOmitted: false);
    }
    // 暂存的快照在 _applySnap 里可能因为签名未变而不通知（首帧必然变化，
    // 但为了不依赖这一点，这里显式保证窗口一就绪就渲染一次）。
    _lastSignature = null;
    _visibleSignatureChanged();
    notifyListeners();
  }

  void _syncTicker() {
    _tick?.cancel();
    _tick = null;
    if (!_snap.isPlaying) return;
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final elapsed = DateTime.now().difference(_anchorWall).inMilliseconds;
      _localPosMs = _anchorPosMs + elapsed;
      // 只在跨到新歌词行时才通知：游标推进本身由 [KaraokeSweepLine] 的
      // 独立 Ticker 自算扫光，原先每 100ms 无条件重建整个歌词窗。
      if (_visibleSignatureChanged()) notifyListeners();
    });
  }

  /// 向主进程发命令。
  Future<void> send(String method, [Object? args]) async {
    final w = _writer;
    if (w == null || !w.isOpen) return;
    w.send(LyricIpc.cmd(method, args));
  }

  Future<void> notifyReady() async {
    if (_readySent) return;
    _readySent = true;
    await send(DesktopLyricCommand.ready);
  }

  Future<void> playPause() => send(DesktopLyricCommand.playPause);
  Future<void> next() => send(DesktopLyricCommand.next);
  Future<void> previous() => send(DesktopLyricCommand.previous);
  Future<void> requestClose() => send(DesktopLyricCommand.close);
  Future<void> toggleLock() => send(DesktopLyricCommand.toggleLock);

  Future<void> reportBounds(double x, double y, double w, double h) {
    return send(DesktopLyricCommand.bounds, {
      'x': x,
      'y': y,
      'width': w,
      'height': h,
    });
  }

  Future<void> notifyClosed() => send(DesktopLyricCommand.closed);

  @override
  void dispose() {
    _tick?.cancel();
    unawaited(detachIpc());
    super.dispose();
  }
}

/// 歌词窗「可见内容」指纹：值相同就不需要重建界面。
///
/// 歌词窗原先在播放中每 100ms 无条件 `notifyListeners()`（外加主窗每 400ms
/// 的 positionOnly 快照也通知一次），而其中绝大多数事件的可见内容完全没变——
/// 游标推进只影响 [KaraokeSweepLine] 的扫光，那由它自己的 Ticker 按帧驱动。
/// 抽成纯函数便于直接覆盖「跨行才变、同行为不同游标不变」这条关键性质。
Object visibleLyricSignature({
  required String title,
  required String artist,
  required bool isPlaying,
  required bool locked,
  required bool translation,
  required double fontScale,
  required DesktopLyricStyle style,
  required int activeIndex,
  required List<LyricLine> lyrics,
}) {
  final hasLine = activeIndex >= 0 && activeIndex < lyrics.length;
  final next = activeIndex + 1;
  return Object.hash(
    title,
    artist,
    isPlaying,
    locked,
    translation,
    fontScale,
    // 外观整包参与指纹：改颜色/描边/背景/字重都必须触发重建，
    // 否则设置面板调完色歌词窗不刷新。
    style,
    activeIndex,
    lyrics.length,
    hasLine ? lyrics[activeIndex].text : '',
    // 主行下方显示的是「译文优先、否则下一行」——两者都参与指纹。
    hasLine ? lyrics[activeIndex].translated : null,
    next >= 0 && next < lyrics.length ? lyrics[next].text : null,
  );
}

/// 歌词窗窗口样式初始化。
///
/// **只用 [DesktopLyricHost]**（绑定本进程 HWND）；不用 window_manager——
/// 多引擎下会串到主窗，把主窗口点穿/假死。
///
/// 样式旗标互不依赖，一次发出（平台线程仍按序执行）以省掉串行 round-trip；
/// 几何随后设。默认位固定为**屏幕（工作区）顶部居中**，离顶端 12px——
/// Windows 保持顶部居中；Linux 恢复历史坐标后检查显示器工作区。
Future<void> initDesktopLyricWindow({DesktopLyricBounds? bounds}) async {
  await Future.wait([
    DesktopLyricHost.setFrameless(),
    DesktopLyricHost.setTransparentBg(),
    DesktopLyricHost.setAlwaysOnTop(true),
    DesktopLyricHost.setSkipTaskbar(true),
  ]);

  final w = bounds?.width ?? 720;
  final h = bounds?.height ?? 88;
  if (Platform.isLinux && bounds?.hasPosition == true) {
    await DesktopLyricHost.setSize(w, h);
    await DesktopLyricHost.setPosition(bounds!.x!, bounds.y!);
    await DesktopLyricHost.ensureVisible();
  } else {
    await DesktopLyricHost.centerTop(width: w, height: h, top: 12);
  }
}

Future<void> showDesktopLyricWindow() async {
  await DesktopLyricHost.show(inactive: true);
}

Future<void> destroyDesktopLyricWindow() async {
  try {
    await DesktopLyricHost.destroy();
  } catch (_) {}
}
