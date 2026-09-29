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

  /// 当前歌词游标（含 offset）。
  int get positionMs => _localPosMs;

  int get activeIndex => findLyricIndex(_lyrics, _localPosMs);

  String get currentLine {
    final i = activeIndex;
    if (i < 0 || i >= _lyrics.length) {
      return _snap.title.isEmpty ? '桌面歌词' : _snap.title;
    }
    return _lyrics[i].text;
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
        // 主窗 close() 下发：自毁本窗，避免只 hide 留下僵尸引擎。
        unawaited(destroyDesktopLyricWindow());
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
    notifyListeners();
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
  }

  void _syncTicker() {
    _tick?.cancel();
    _tick = null;
    if (!_snap.isPlaying) return;
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final elapsed =
          DateTime.now().difference(_anchorWall).inMilliseconds;
      _localPosMs = _anchorPosMs + elapsed;
      notifyListeners();
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
  await DesktopLyricHost.setSize(w, h);

  if (bounds != null && bounds.hasPosition) {
    await DesktopLyricHost.setPosition(bounds.x!, bounds.y!);
  } else {
    // 顶中、略下移，避免盖住主窗标题栏按钮。
    try {
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final dpr = view.devicePixelRatio;
      final sw = view.physicalSize.width / dpr;
      final x = (sw - w) / 2;
      await DesktopLyricHost.setPosition(x, 56);
    } catch (_) {
      await DesktopLyricHost.setPosition(100, 56);
    }
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
