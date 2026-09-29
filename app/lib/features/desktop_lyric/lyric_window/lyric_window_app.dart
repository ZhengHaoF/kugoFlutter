import 'package:flutter/material.dart';

import '../desktop_lyric_bridge.dart';
import '../desktop_lyric_host.dart';
import '../desktop_lyric_store.dart';
import 'lyric_window_controller.dart';
import 'lyric_window_view.dart';

/// 桌面歌词子窗 App：轻量入口，不初始化音频/托盘/数据源。
///
/// 窗口操作一律走 [DesktopLyricHost]（绑定本引擎 HWND），不用 window_manager。
class DesktopLyricApp extends StatefulWidget {
  const DesktopLyricApp({super.key});

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
    final bounds = await DesktopLyricBoundsStore.load();
    await initDesktopLyricWindow(bounds: bounds);
    _controller.markWindowReady();
    if (!mounted) return;
    setState(() => _booted = true);
    // 等一帧让歌词卡真正上屏，再 show，避免空窗。
    await WidgetsBinding.instance.endOfFrame;
    await showDesktopLyricWindow();
    lyricLog('lyric window shown');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: !_booted
          ? const SizedBox.shrink()
          : DesktopLyricView(controller: _controller),
    );
  }
}
