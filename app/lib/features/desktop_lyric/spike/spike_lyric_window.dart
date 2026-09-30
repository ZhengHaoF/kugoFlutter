import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

File get _spikeLogFile => File(r'C:\Users\zheng\kugo_spike.log');

void _spikeLog(String msg) {
  try {
    _spikeLogFile.writeAsStringSync(
      '${DateTime.now().toIso8601String()} [child] $msg\n',
      mode: FileMode.append,
    );
  } catch (_) {}
}

/// Spike：传给桌面歌词测试窗口的 arguments 标识。
const String kSpikeLyricWindowArg = 'spike_desktop_lyric';

/// Spike：主窗 ↔ 歌词窗的测试通道名（bidirectional 配对）。
const String kSpikeChannelName = 'kugo/spike_lyric';

/// 桌面歌词 spike 子窗口。
///
/// 验证项：
/// 1. window_manager 在子窗内是否绑定到**自身 HWND**（而非主窗口）；
/// 2. 无边框 / 透明背景 / 置顶 / 隐藏任务栏；
/// 3. WindowMethodChannel 双向通信；
/// 4. setIgnoreMouseEvents（含 forward）点击穿透。
class SpikeLyricWindow extends StatefulWidget {
  const SpikeLyricWindow({super.key});

  @override
  State<SpikeLyricWindow> createState() => _SpikeLyricWindowState();
}

class _SpikeLyricWindowState extends State<SpikeLyricWindow> {
  static const _channel = WindowMethodChannel(kSpikeChannelName);

  final _logs = <String>[];
  final _focusNode = FocusNode();
  bool _clickThrough = false;
  String _windowId = '?';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _log(String line) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    _spikeLog(line);
    if (!mounted) return;
    setState(() => _logs.add('$ts  $line'));
  }

  Future<void> _step(String name, Future<void> Function() action) async {
    try {
      await action();
      _log('PASS  $name');
    } catch (e) {
      _log('FAIL  $name -> $e');
    }
  }

  Future<void> _boot() async {
    // 尽早注册通信 handler，等待主窗 invoke。
    try {
      await _channel.setMethodCallHandler((call) async {
        _log('RECV  ${call.method} ${call.arguments ?? ''}');
        if (call.method == 'ping') {
          return 'pong@${DateTime.now().millisecondsSinceEpoch}';
        }
        if (call.method == 'restore-click') {
          await _restoreClick();
          return 'ok';
        }
        return null;
      });
      _log('PASS  channel handler registered');
    } catch (e) {
      _log('FAIL  channel handler -> $e');
    }

    try {
      final self = await WindowController.fromCurrentEngine();
      _windowId = self.windowId;
    } catch (_) {}

    // ── 窗口样式初始化序列 ──
    await _step('ensureInitialized', windowManager.ensureInitialized);
    // window_manager 0.5.2 在 waitUntilReadyToShow 里才 CoCreateInstance
    // ITaskbarList3；不调它直接 setSkipTaskbar 会在 taskbar_->HrInit() 空指针 AV。
    await _step('waitUntilReadyToShow (init ITaskbarList3)',
        () => windowManager.waitUntilReadyToShow());

    // HWND 绑定验证：window_manager 在子窗内必须绑到自身根窗口。
    try {
      final childHwnd = await windowManager.getId();
      final mainHwnd = await _channel.invokeMethod('mainHwnd');
      _log('INFO  child HWND=$childHwnd  main HWND=$mainHwnd');
      if (childHwnd != mainHwnd) {
        _log('PASS  HWND binding (child != main)');
      } else {
        _log('FAIL  HWND binding (child == main or null)');
      }
    } catch (e) {
      _log('FAIL  HWND binding check -> $e');
    }

    await _step('setAsFrameless', windowManager.setAsFrameless);
    await _step('setSize 760x160',
        () => windowManager.setSize(const Size(760, 160)));
    try {
      final size = await windowManager.getSize();
      final ok = (size.width - 760).abs() < 2 && (size.height - 160).abs() < 2;
      _log('${ok ? 'PASS' : 'FAIL'}  getSize roundtrip -> $size');
    } catch (e) {
      _log('FAIL  getSize -> $e');
    }
    await _step('setAlignment topCenter',
        () => windowManager.setAlignment(Alignment.topCenter));
    await _step('setBackgroundColor transparent',
        () => windowManager.setBackgroundColor(Colors.transparent));
    await _step('setAlwaysOnTop(true)',
        () => windowManager.setAlwaysOnTop(true));
    try {
      final top = await windowManager.isAlwaysOnTop();
      _log('${top ? 'PASS' : 'FAIL'}  isAlwaysOnTop -> $top');
    } catch (e) {
      _log('FAIL  isAlwaysOnTop -> $e');
    }
    await _step('setSkipTaskbar(true)',
        () => windowManager.setSkipTaskbar(true));
    await _step('show', () => windowManager.show(inactive: true));

    // ── 通信：向主窗问好 ──
    try {
      final reply = await _channel.invokeMethod('hello', '子窗已就绪');
      _log('SEND  hello -> 回复: $reply');
    } catch (e) {
      _log('FAIL  hello -> $e');
    }

    // ── 穿透自测：开 → 关，确认 API 不抛错；forward 在 Windows 原生被忽略 ──
    await _step('setIgnoreMouseEvents(true, forward:true)',
        () => windowManager.setIgnoreMouseEvents(true, forward: true));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await _step('setIgnoreMouseEvents(false)',
        () => windowManager.setIgnoreMouseEvents(false));
    _log('INFO  Windows setIgnoreMouseEvents 不实现 forward（见 window_manager.cpp）');

    if (mounted) FocusScope.of(context).requestFocus(_focusNode);
  }

  Future<void> _sendPing() async {
    try {
      final r = await _channel.invokeMethod(
          'ping', DateTime.now().millisecondsSinceEpoch);
      _log('SEND  ping -> 回复: $r');
    } catch (e) {
      _log('FAIL  ping -> $e');
    }
  }

  Future<void> _enableClickThrough({bool forward = true}) async {
    try {
      await windowManager.setIgnoreMouseEvents(true, forward: forward);
      if (!mounted) return;
      setState(() => _clickThrough = true);
      _log('PASS  setIgnoreMouseEvents(true, forward:$forward)');
      _log('      鼠标已穿透，按 Esc 或从主窗恢复');
    } catch (e) {
      _log('FAIL  setIgnoreMouseEvents -> $e');
    }
  }

  Future<void> _restoreClick() async {
    try {
      await windowManager.setIgnoreMouseEvents(false);
      if (!mounted) return;
      setState(() => _clickThrough = false);
      _log('PASS  setIgnoreMouseEvents(false)');
      FocusScope.of(context).requestFocus(_focusNode);
    } catch (e) {
      _log('FAIL  restore click -> $e');
    }
  }

  Future<void> _close() async {
    _log('INFO  destroy window');
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: KeyboardListener(
        focusNode: _focusNode,
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape &&
              _clickThrough) {
            _restoreClick();
          }
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
              decoration: BoxDecoration(
                color: const Color(0xE615151A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _clickThrough
                      ? const Color(0xFFFF5C5C)
                      : const Color(0x33FFFFFF),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.lyrics_outlined,
                          color: Colors.white70, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '桌面歌词 Spike —— 这是一行测试歌词',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text('id: $_windowId',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _SpikeButton(
                        icon: Icons.send_rounded,
                        label: '发消息给主窗',
                        onTap: _sendPing,
                      ),
                      _SpikeButton(
                        icon: Icons.mouse_rounded,
                        label: '穿透(forward)',
                        highlight: _clickThrough,
                        onTap: () => _enableClickThrough(forward: true),
                      ),
                      _SpikeButton(
                        icon: Icons.mouse_rounded,
                        label: '穿透(纯)',
                        highlight: _clickThrough,
                        onTap: () => _enableClickThrough(forward: false),
                      ),
                      _SpikeButton(
                        icon: Icons.back_hand_rounded,
                        label: '恢复交互',
                        onTap: _restoreClick,
                      ),
                      _SpikeButton(
                        icon: Icons.close_rounded,
                        label: '关闭窗口',
                        onTap: _close,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 72,
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF000000),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView(
                      children: [
                        for (final l in _logs)
                          Text(
                            l,
                            style: const TextStyle(
                              color: Color(0xFF8FE38F),
                              fontSize: 11,
                              height: 1.35,
                              fontFamily: 'Consolas',
                            ),
                          ),
                      ],
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

class _SpikeButton extends StatelessWidget {
  const _SpikeButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlight ? const Color(0xFFFF5C5C) : const Color(0xFF2A2A32),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: Colors.white),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
