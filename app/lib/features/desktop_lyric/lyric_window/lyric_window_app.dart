import 'package:flutter/material.dart';
import 'dart:io';

import '../../../core/theme/kugo_theme.dart';
import '../desktop_lyric_bridge.dart';
import '../desktop_lyric_host.dart';
import '../desktop_lyric_ipc.dart';
import '../desktop_lyric_store.dart';
import 'lyric_window_controller.dart';
import 'lyric_window_view.dart';

/// 桌面歌词独立进程的 App：轻量入口，不初始化音频/托盘/数据源。
///
/// 由主进程 spawn（`exe desktop_lyric --ipc-port=N`），窗口操作一律走
/// [DesktopLyricHost]（绑定本进程 HWND）。
class DesktopLyricApp extends StatefulWidget {
  const DesktopLyricApp({super.key, required this.ipcPort});

  /// 主进程 LyricIpcServer 监听端口。
  final int? ipcPort;

  @override
  State<DesktopLyricApp> createState() => _DesktopLyricAppState();
}

class _DesktopLyricAppState extends State<DesktopLyricApp> {
  late final DesktopLyricController _controller;
  bool _booted = false;

  @override
  void initState() {
    super.initState();
    _controller = DesktopLyricController();
    _boot();
  }

  Future<void> _boot() async {
    await _connectIpc();
    try {
      if (Platform.isLinux) {
        DesktopLyricHost.listenBounds(_controller.reportBounds);
        final caps = await DesktopLyricHost.capabilities();
        _controller.transparentBackground = caps['transparent'] == true;
      }
      final bounds = await DesktopLyricBoundsStore.load();
      await initDesktopLyricWindow(bounds: bounds);
    } catch (e) {
      // 样式初始化失败也要把窗露出来，否则用户只能看到「桌面歌词不见了」。
      lyricLog('init window failed: $e');
    }
    _controller.markWindowReady();
    if (!mounted) return;
    setState(() => _booted = true);
    // 窗口创建时保持隐藏，渲染可在隐藏态完成。只等一帧让歌词卡上屏，
    // 超时 50ms 直接 show——宁可极短空窗，也不要把首次开窗拖到 300ms。
    try {
      await WidgetsBinding.instance.endOfFrame.timeout(
        const Duration(milliseconds: 50),
      );
    } catch (_) {}
    try {
      await showDesktopLyricWindow();
      lyricLog('lyric process window shown');
    } catch (e) {
      lyricLog('show window failed: $e');
    }
  }

  Future<void> _connectIpc() async {
    final port = widget.ipcPort;
    if (port == null) {
      if (Platform.isLinux) exit(64);
      lyricLog('missing ipc port, lyric process will idle');
      return;
    }
    try {
      final socket = await connectLyricIpc(port);
      await _controller.attachIpc(socket);
      if (Platform.isLinux) {
        final token = Platform.environment[LyricIpc.envToken];
        if (token == null || token.isEmpty) exit(64);
        await _controller.send('hello', {'token': token});
      }
      lyricLog('ipc connected to port $port');
    } catch (e) {
      lyricLog('ipc connect failed: $e');
      if (Platform.isLinux) exit(2);
    }
  }

  @override
  void dispose() {
    if (Platform.isLinux) DesktopLyricHost.listenBounds(null);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 与主窗同一套字体（打包 MiSans + 系统回退），避免歌词窗落到 Roboto。
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        textTheme: ThemeData.dark(useMaterial3: true).textTheme.apply(
          fontFamily: kugoFontFamily,
          fontFamilyFallback: kugoFontFamilyFallback,
        ),
      ),
      home: !_booted
          ? const SizedBox.shrink()
          : DesktopLyricView(controller: _controller),
    );
  }
}
