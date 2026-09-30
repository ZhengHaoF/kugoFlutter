import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/track.dart';
import '../../../core/utils/lrc_parser.dart';
import '../desktop_lyric_host.dart';
import '../desktop_lyric_protocol.dart';
import '../desktop_lyric_store.dart';

/// 歌词窗本地状态：接收 snapshot，播放中本地 Ticker 自走对齐进度。
class DesktopLyricController extends ChangeNotifier {
  DesktopLyricController() {
    _channel.setMethodCallHandler(_onMainCall);
  }

  static const _channel = WindowMethodChannel(kDesktopLyricChannel);

  DesktopLyricSnapshot _snap = const DesktopLyricSnapshot();
  List<LyricLine> _lyrics = const [];
  int _revision = -1;
  int _localPosMs = 0;
  DateTime _anchorWall = DateTime.now();
  int _anchorPosMs = 0;
  Timer? _tick;
  bool _readySent = false;
  bool _windowReady = false;
  DesktopLyricSnapshot? _pendingSnap;
  bool? _pendingLock;

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

  Future<dynamic> _onMainCall(MethodCall call) async {
    switch (call.method) {
      case 'snapshot':
        final snap = DesktopLyricSnapshot.fromWire(call.arguments);
        final lyricsOmitted =
            (call.arguments as Map?)?['lyricsOmitted'] == true;
        _applySnap(snap, lyricsOmitted: lyricsOmitted);
        return 'ok';
      case 'close':
      case 'hide':
        await DesktopLyricHost.hide();
        return 'ok';
      case 'show':
        await DesktopLyricHost.show(inactive: true);
        return 'ok';
      default:
        return null;
    }
  }

  void _applySnap(DesktopLyricSnapshot snap, {required bool lyricsOmitted}) {
    // 窗口样式初始化完成前先暂存：init 期间并发 window_manager 调用会死锁。
    if (!_windowReady) {
      _pendingSnap = snap;
      return;
    }

    final trackChanged = snap.trackId != _snap.trackId;
    final revChanged = snap.revision != _revision;

    if (!lyricsOmitted && (trackChanged || revChanged || snap.lyrics.isNotEmpty)) {
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

  /// 触发重建只取决这些量：外形（标题/播放态/锁定/译文/字号）+ 当前行内容。
  /// 游标推进本身不需要重建——[KaraokeSweepLine] 有独立 Ticker 自算扫光。
  Object _visibleSignature() => visibleLyricSignature(
        title: _snap.title,
        artist: _snap.artist,
        isPlaying: _snap.isPlaying,
        locked: _snap.locked,
        translation: _snap.translation,
        fontScale: _snap.fontScale,
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
      final elapsed =
          DateTime.now().difference(_anchorWall).inMilliseconds;
      _localPosMs = _anchorPosMs + elapsed;
      // 只在跨到新歌词行时才通知：游标推进本身由 [KaraokeSweepLine] 的
      // 独立 Ticker 自算扫光，原先每 100ms 无条件重建整个歌词窗。
      if (_visibleSignatureChanged()) notifyListeners();
    });
  }

  /// 向主窗发命令。
  Future<void> send(String method, [Object? args]) async {
    try {
      await _channel.invokeMethod(method, args);
    } catch (e) {
      debugPrint('[desktop_lyric] send $method failed: $e');
    }
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
    _channel.setMethodCallHandler(null);
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
/// **只用 [DesktopLyricHost]**（绑定本引擎 HWND）；不用 window_manager——
/// 多引擎下会串到主窗，把主窗口点穿/假死。
Future<void> initDesktopLyricWindow({
  DesktopLyricBounds? bounds,
}) async {
  await DesktopLyricHost.setFrameless();
  await DesktopLyricHost.setTransparentBg();
  await DesktopLyricHost.setAlwaysOnTop(true);
  await DesktopLyricHost.setSkipTaskbar(true);

  final w = bounds?.width ?? 720;
  final h = bounds?.height ?? 88;

  if (bounds != null && bounds.hasPosition && bounds.x! >= 0 && bounds.y! >= 0) {
    await DesktopLyricHost.setSize(w, h);
    await DesktopLyricHost.setPosition(bounds.x!, bounds.y!);
  } else {
    // 居中靠顶显示（下移 56px 避免遮挡主窗标题栏按钮）
    await DesktopLyricHost.centerTop(width: w, height: h, top: 56);
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
