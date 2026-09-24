import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/netease/netease_client.dart';
import '../../core/source/capabilities.dart';
import '../../data/sources/netease/netease_source.dart';
import '../../data/storage/netease_auth_store.dart';

/// 网易扫码登录的二维码阶段（与酷狗 [QrPhase] 分开，避免两套登录串状态）。
enum NeteaseQrPhase { idle, loading, waiting, scanned, expired, success, error }

class NeteaseLoginState {
  const NeteaseLoginState({
    this.phase = NeteaseQrPhase.idle,
    this.qrContentUrl = '',
    this.account,
    this.errorMessage = '',
  });

  final NeteaseQrPhase phase;
  final String qrContentUrl;
  final LoginAccount? account;
  final String errorMessage;

  bool get isLogged => account != null;

  /// [account] 为 null 表示「不变」；登出请直接构造 [NeteaseLoginState]。
  NeteaseLoginState copyWith({
    NeteaseQrPhase? phase,
    String? qrContentUrl,
    LoginAccount? account,
    String? errorMessage,
  }) {
    return NeteaseLoginState(
      phase: phase ?? this.phase,
      qrContentUrl: qrContentUrl ?? this.qrContentUrl,
      account: account ?? this.account,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// 网易云扫码登录状态机。
///
/// 与 [AuthController]（酷狗）同构：`_qrGeneration` 防串号 + [Timer] 轮询。
/// 轮询间隔 2s（Neri 用 1s，但扫码是人工操作，2s 足够且更省风控额度）。
class NeteaseLoginController extends Notifier<NeteaseLoginState> {
  Timer? _timer;
  int _generation = 0;
  LoginQrSession? _session;

  @override
  NeteaseLoginState build() {
    ref.onDispose(_stopPolling);
    // 首次创建时回填已恢复的登录态；游客态 currentAccount() 直接返回 null，
    // 不发请求。microtask 确保晚于 build() 返回再写 state。
    Future.microtask(refreshAccount);
    return const NeteaseLoginState();
  }

  DeviceLoginSource get _source => ref.read(neteaseLoginSourceProvider);

  /// 进页初始化：先回填账号，未登录才拉二维码（已登录不重复扫码）。
  Future<void> bootstrap() async {
    await refreshAccount();
    if (!state.isLogged) await startQr();
  }

  /// 拉二维码并开始轮询。重复调用会作废旧会话。
  Future<void> startQr() async {
    final gen = ++_generation;
    _stopPolling();
    state = const NeteaseLoginState(phase: NeteaseQrPhase.loading);
    try {
      final session = await _source.createLoginQr();
      if (gen != _generation) return;
      _session = session;
      state = state.copyWith(
        phase: NeteaseQrPhase.waiting,
        qrContentUrl: session.qrContent,
      );
      _timer = Timer.periodic(
        ref.read(neteaseLoginPollIntervalProvider),
        (_) => _poll(gen),
      );
    } catch (e) {
      if (gen != _generation) return;
      state = state.copyWith(
        phase: NeteaseQrPhase.error,
        errorMessage: _msg(e),
      );
    }
  }

  Future<void> _poll(int gen) async {
    final session = _session;
    if (session == null || gen != _generation) return;
    final LoginQrPoll poll;
    try {
      poll = await _source.pollLoginQr(session);
    } catch (_) {
      return; // 单次失败不打断轮询，下一拍再试。
    }
    if (gen != _generation) return;
    switch (poll.status) {
      case LoginQrStatus.waiting:
        state = state.copyWith(phase: NeteaseQrPhase.waiting);
      case LoginQrStatus.scanned:
        state = state.copyWith(phase: NeteaseQrPhase.scanned);
      case LoginQrStatus.expired:
        _stopPolling();
        state = state.copyWith(phase: NeteaseQrPhase.expired);
      case LoginQrStatus.confirmed:
        _stopPolling();
        await _onConfirmed(gen);
      case LoginQrStatus.unknown:
        break; // 未知码静默重试。
    }
  }

  Future<void> _onConfirmed(int gen) async {
    // 803 后 cookie 已在客户端内存里，这里落盘 + 确认账号。
    await NeteaseAuthStore.save(neteaseClient);
    LoginAccount? account;
    try {
      account = await _source.currentAccount();
    } catch (_) {
      account = null;
    }
    if (gen != _generation) return;
    state = state.copyWith(
      phase: account == null ? NeteaseQrPhase.error : NeteaseQrPhase.success,
      account: account,
      errorMessage: account == null ? '登录态确认失败，请重试' : '',
    );
  }

  /// 读取当前登录账号（启动恢复后 / 进入设置页时调用）。
  Future<void> refreshAccount() async {
    LoginAccount? account;
    try {
      account = await _source.currentAccount();
    } catch (_) {
      account = null;
    }
    state = account == null
        ? const NeteaseLoginState()
        : NeteaseLoginState(
            phase: NeteaseQrPhase.success,
            account: account,
          );
  }

  /// 退出登录：清客户端内存会话 + 本地落盘。
  Future<void> logout() async {
    _generation++;
    _stopPolling();
    await _source.logout();
    await NeteaseAuthStore.clear();
    state = const NeteaseLoginState();
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  String _msg(Object e) {
    final s = e.toString().split('\n').first.trim();
    return s.isEmpty ? '网络异常' : s;
  }
}

/// 扫码登录使用的音源（默认全局网易源；测试覆盖成假源）。
final neteaseLoginSourceProvider = Provider<DeviceLoginSource>(
  (ref) => neteaseSource,
);

/// 扫码轮询间隔（测试覆盖成更小值以加速）。
final neteaseLoginPollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 2),
);

final neteaseLoginControllerProvider =
    NotifierProvider<NeteaseLoginController, NeteaseLoginState>(
  NeteaseLoginController.new,
);
