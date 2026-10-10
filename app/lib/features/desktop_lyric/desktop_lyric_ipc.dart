import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 桌面歌词双进程 IPC：主窗进程 ↔ 歌词进程。
///
/// 走 127.0.0.1 TCP + 换行分隔 JSON（一帧一行），不用 desktop_multi_window：
/// dmw 的 Windows 多引擎会踩坏主窗 task runner（见 桌面歌词接入方案.md §12）。
///
/// 消息形态：
/// - 主 → 歌词：`{"t":"snapshot","d":{...}}` / `{"t":"show"|"hide"|"close"}`
/// - 歌词 → 主：`{"t":"cmd","m":"ready|playPause|...","d":{...}?}`
abstract final class LyricIpc {
  static const typeSnapshot = 'snapshot';
  static const typeCmd = 'cmd';
  static const typeShow = 'show';
  static const typeHide = 'hide';
  static const typeClose = 'close';
  static const typeReposition = 'reposition';

  /// 进程启动参数：歌词进程标记 + 服务端口。
  static const argProcess = 'desktop_lyric';
  static const argPortPrefix = '--ipc-port=';

  /// 环境变量兜底（CLI 传参之外，原生层也能读到）。
  static const envProcess = 'KUGO_LYRIC_PROCESS';
  static const envPort = 'KUGO_LYRIC_IPC_PORT';
  static const envToken = 'KUGO_LYRIC_IPC_TOKEN';

  static bool isAuthenticatedHello(Map<String, Object?> message, String token) {
    final data = message['d'];
    return token.isNotEmpty &&
        message['t'] == typeCmd &&
        message['m'] == 'hello' &&
        data is Map &&
        data['token'] == token;
  }

  static Map<String, Object?> snapshot(Object? wire) => {
    't': typeSnapshot,
    'd': wire,
  };

  static Map<String, Object?> cmd(String method, [Object? data]) => {
    't': typeCmd,
    'm': method,
    'd': ?data,
  };

  static Map<String, Object?> signal(String type) => {'t': type};

  static int? portFromArgs(List<String> args) {
    for (final a in args) {
      if (a.startsWith(argPortPrefix)) {
        return int.tryParse(a.substring(argPortPrefix.length));
      }
    }
    return int.tryParse(Platform.environment[envPort] ?? '');
  }

  static bool isLyricProcessArgs(List<String> args) =>
      args.contains(argProcess) || Platform.environment[envProcess] == '1';

  static String encodeLine(Map<String, Object?> msg) => jsonEncode(msg);

  static Map<String, Object?>? decodeLine(String line) {
    final t = line.trim();
    if (t.isEmpty) return null;
    try {
      final v = jsonDecode(t);
      if (v is Map) return v.cast<String, Object?>();
    } catch (_) {}
    return null;
  }
}

/// 读 socket 字节流，按 `\n` 切帧回调。
class LyricIpcReader {
  LyricIpcReader(this._socket) {
    _sub = _socket.listen(
      _onData,
      onError: (_) => close(),
      onDone: close,
      cancelOnError: true,
    );
  }

  final Socket _socket;
  final _controller = StreamController<Map<String, Object?>>.broadcast();
  final List<int> _buf = [];
  StreamSubscription<List<int>>? _sub;
  bool _closed = false;

  Stream<Map<String, Object?>> get messages => _controller.stream;

  void _onData(List<int> chunk) {
    _buf.addAll(chunk);
    while (true) {
      final nl = _buf.indexOf(0x0A);
      if (nl < 0) break;
      final line = utf8.decode(_buf.sublist(0, nl), allowMalformed: true);
      _buf.removeRange(0, nl + 1);
      final msg = LyricIpc.decodeLine(line);
      if (msg != null) _controller.add(msg);
    }
    // 防御异常大帧（未换行的脏数据）撑爆内存。
    if (_buf.length > 8 << 20) close();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub?.cancel();
    await _controller.close();
    try {
      _socket.destroy();
    } catch (_) {}
  }
}

/// 写一端：线程安全地发一行 JSON。
class LyricIpcWriter {
  LyricIpcWriter(this._socket);

  final Socket _socket;
  bool _closed = false;

  bool get isOpen => !_closed;

  void send(Map<String, Object?> msg) {
    if (_closed) return;
    try {
      _socket.write('${LyricIpc.encodeLine(msg)}\n');
    } catch (e) {
      debugPrint('[desktop_lyric] ipc send failed: $e');
      close();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _socket.flush();
    } catch (_) {}
    try {
      _socket.destroy();
    } catch (_) {}
  }
}

/// 主窗侧：听本地端口，等歌词进程连上来。
class LyricIpcServer {
  ServerSocket? _server;

  Future<int> listen({int port = 0}) async {
    await close();
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    _server = s;
    return s.port;
  }

  int? get port => _server?.port;

  Stream<Socket>? get connections => _server?.asBroadcastStream();

  Future<void> close() async {
    final s = _server;
    _server = null;
    try {
      await s?.close();
    } catch (_) {}
  }
}

/// 歌词侧：连主窗开好的端口；失败自动重试几次（进程刚 spawn 时端口已就绪，正常一次成）。
Future<Socket> connectLyricIpc(int port, {int retries = 20}) async {
  Object? last;
  for (var i = 0; i < retries; i++) {
    try {
      return await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 500),
      );
    } catch (e) {
      last = e;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  throw StateError('lyric ipc connect failed: $last');
}
