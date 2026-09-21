import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repositories/login_repository.dart';
import '../../data/storage/device_identity.dart';
import 'auth_token_holder.dart';

class AuthUser {
  AuthUser({
    required this.userId,
    required this.nickname,
    this.token = '',
    this.avatarUrl = '',
    this.isVip = false,
    this.isLocalDemo = false,
    this.t1 = '',
  });

  final String userId;
  final String nickname;
  final String token;
  final String avatarUrl;
  final bool isVip;
  final bool isLocalDemo;
  final String t1;

  AuthUser copyWith({
    String? userId,
    String? nickname,
    String? token,
    String? avatarUrl,
    bool? isVip,
    bool? isLocalDemo,
    String? t1,
  }) {
    return AuthUser(
      userId: userId ?? this.userId,
      nickname: nickname ?? this.nickname,
      token: token ?? this.token,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isVip: isVip ?? this.isVip,
      isLocalDemo: isLocalDemo ?? this.isLocalDemo,
      t1: t1 ?? this.t1,
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'nickname': nickname,
        'token': token,
        'avatarUrl': avatarUrl,
        'isVip': isVip,
        'isLocalDemo': isLocalDemo,
        't1': t1,
      };

  static AuthUser? fromJson(Map<String, dynamic> json) {
    final id = json['userId']?.toString() ?? '';
    if (id.isEmpty) return null;
    return AuthUser(
      userId: id,
      nickname: json['nickname']?.toString() ?? '用户',
      token: json['token']?.toString() ?? '',
      avatarUrl: json['avatarUrl']?.toString() ?? '',
      isVip: json['isVip'] == true,
      isLocalDemo: json['isLocalDemo'] == true,
      t1: json['t1']?.toString() ?? '',
    );
  }
}

enum LoginStatus { unknown, guest, loading, logged, error }

/// QR poll status exposed to UI.
enum QrPhase { idle, loading, waiting, scanned, expired, success, error }

class AuthState {
  const AuthState({
    this.status = LoginStatus.unknown,
    this.user,
    this.errorMessage = '',
    this.smsCountdown = 0,
    this.restored = false,
    this.qrPhase = QrPhase.idle,
    this.qrContentUrl = '',
    this.qrKey = '',
  });

  final LoginStatus status;
  final AuthUser? user;
  final String errorMessage;
  final int smsCountdown;
  final bool restored;
  final QrPhase qrPhase;
  final String qrContentUrl;
  final String qrKey;

  bool get isLogged => status == LoginStatus.logged && user != null;
  bool get isGuest => status == LoginStatus.guest;

  AuthState copyWith({
    LoginStatus? status,
    AuthUser? user,
    String? errorMessage,
    int? smsCountdown,
    bool? restored,
    QrPhase? qrPhase,
    String? qrContentUrl,
    String? qrKey,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: errorMessage ?? this.errorMessage,
      smsCountdown: smsCountdown ?? this.smsCountdown,
      restored: restored ?? this.restored,
      qrPhase: qrPhase ?? this.qrPhase,
      qrContentUrl: qrContentUrl ?? this.qrContentUrl,
      qrKey: qrKey ?? this.qrKey,
    );
  }
}

/// Real gateway login only — never invents a local session on failure.
class AuthController extends Notifier<AuthState> {
  static const _kUser = 'auth.user.v1';
  static const _kGuest = 'auth.guest.v1';
  static const _kSeen = 'auth.seen.v1';

  SharedPreferences? _prefs;
  Timer? _countdownTimer;
  Timer? _qrTimer;
  int _qrGeneration = 0;
  Completer<void>? _ready;

  @override
  AuthState build() {
    ref.onDispose(() {
      _countdownTimer?.cancel();
      _qrTimer?.cancel();
    });
    _ready = Completer<void>();
    unawaited(
      _restore().whenComplete(() {
        final r = _ready;
        if (r != null && !r.isCompleted) r.complete();
      }),
    );
    return const AuthState();
  }

  /// Wait until local session has been restored into [AuthTokenHolder].
  Future<void> ensureReady() {
    final r = _ready;
    if (r == null) return Future.value();
    return r.future;
  }

  Future<void> _restore() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      // 先从本地恢复登录态，再补设备身份。
      // DeviceIdentity.ensure() 可能走 /risk/v2/r_register_dev，
      // 网络慢/失败时不能把 token 恢复一起堵死（FM 等功能会误判成未登录）。
      final raw = _prefs?.getString(_kUser);
      if (raw != null && raw.isNotEmpty) {
        final map = <String, dynamic>{};
        for (final part in raw.split('&')) {
          final i = part.indexOf('=');
          if (i <= 0) continue;
          map[Uri.decodeComponent(part.substring(0, i))] =
              Uri.decodeComponent(part.substring(i + 1));
        }
        final user = AuthUser.fromJson(map);
        if (user != null) {
          AuthTokenHolder.instance.setSession(
            token: user.token,
            userId: user.userId,
            t1: user.t1,
          );
          state = AuthState(
            status: LoginStatus.logged,
            user: user,
            restored: true,
          );
          // 设备 mid/guid/dfid 后台补齐；失败不影响已恢复的登录态。
          unawaited(() async {
            try {
              await DeviceIdentity.ensure();
            } catch (_) {}
          }());
          return;
        }
      }
      await _prefs?.setBool(_kGuest, true);
      AuthTokenHolder.instance.clear();
      state = const AuthState(status: LoginStatus.guest, restored: true);
      unawaited(DeviceIdentity.ensure());
    } catch (_) {
      state = const AuthState(status: LoginStatus.guest, restored: true);
    }
  }

  Future<void> markSeen() async {
    try {
      await _prefs?.setBool(_kSeen, true);
    } catch (_) {}
  }

  bool get seenOnboarding {
    try {
      return _prefs?.getBool(_kSeen) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> continueAsGuest() async {
    stopQrPolling();
    AuthTokenHolder.instance.clear();
    state = const AuthState(status: LoginStatus.guest, restored: true);
    try {
      await _prefs?.setBool(_kGuest, true);
      await _prefs?.remove(_kUser);
      await _prefs?.setBool(_kSeen, true);
    } catch (_) {}
  }

  // --- QR ---

  Future<void> startQrLogin() async {
    stopQrPolling();
    final gen = ++_qrGeneration;
    state = state.copyWith(
      qrPhase: QrPhase.loading,
      qrContentUrl: '',
      qrKey: '',
      errorMessage: '',
      status: state.status == LoginStatus.logged
          ? LoginStatus.logged
          : LoginStatus.guest,
    );
    final created = await loginRepository.createQrLogin();
    if (gen != _qrGeneration) return;
    if (created == null) {
      state = state.copyWith(
        qrPhase: QrPhase.error,
        errorMessage: loginRepository.lastError.isEmpty
            ? '获取二维码失败'
            : loginRepository.lastError,
      );
      return;
    }
    state = state.copyWith(
      qrPhase: QrPhase.waiting,
      qrContentUrl: created.contentUrl,
      qrKey: created.key,
    );
    _qrTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_pollQr(gen, created.key));
    });
  }

  Future<void> _pollQr(int gen, String key) async {
    if (gen != _qrGeneration) return;
    final res = await loginRepository.checkQrLogin(key);
    if (gen != _qrGeneration || res == null) return;
    switch (res.status) {
      case 0:
        state = state.copyWith(qrPhase: QrPhase.expired);
        stopQrPolling();
      case 2:
        state = state.copyWith(qrPhase: QrPhase.scanned);
      case 4:
        final session = res.session;
        if (session == null) {
          state = state.copyWith(
            qrPhase: QrPhase.error,
            errorMessage: '扫码成功但未返回会话',
          );
          stopQrPolling();
          return;
        }
        stopQrPolling();
        await _completeLogin(session);
      default:
        state = state.copyWith(qrPhase: QrPhase.waiting);
    }
  }

  void stopQrPolling() {
    _qrTimer?.cancel();
    _qrTimer = null;
    _qrGeneration++;
  }

  // --- SMS ---

  Future<bool> sendSmsCode(String phone) async {
    if (!_isValidPhone(phone)) {
      state = state.copyWith(errorMessage: '请输入 11 位手机号');
      return false;
    }
    state = state.copyWith(errorMessage: '');
    final ok = await loginRepository.sendSmsCode(phone.trim());
    if (!ok) {
      state = state.copyWith(
        errorMessage: loginRepository.lastError.isEmpty
            ? '发送验证码失败'
            : loginRepository.lastError,
      );
      return false;
    }
    _startCountdown();
    return true;
  }

  void _startCountdown() {
    state = state.copyWith(smsCountdown: 60);
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = state.smsCountdown - 1;
      if (left <= 0) {
        t.cancel();
        state = state.copyWith(smsCountdown: 0);
        return;
      }
      state = state.copyWith(smsCountdown: left);
    });
  }

  Future<bool> loginWithSms({
    required String phone,
    required String code,
    String userid = '',
  }) async {
    if (!_isValidPhone(phone)) {
      state = state.copyWith(errorMessage: '请输入 11 位手机号');
      return false;
    }
    if (code.trim().length < 4) {
      state = state.copyWith(errorMessage: '请输入至少 4 位验证码');
      return false;
    }
    state = state.copyWith(status: LoginStatus.loading, errorMessage: '');
    final session = await loginRepository.loginWithSms(
      mobile: phone.trim(),
      code: code.trim(),
      userid: userid,
    );
    if (session == null) {
      state = state.copyWith(
        status: LoginStatus.error,
        errorMessage: loginRepository.lastError.isEmpty
            ? '登录失败'
            : loginRepository.lastError,
      );
      return false;
    }
    await _completeLogin(session);
    return true;
  }

  // --- Password ---

  Future<bool> loginWithPassword({
    required String username,
    required String password,
  }) async {
    if (username.trim().isEmpty || password.isEmpty) {
      state = state.copyWith(errorMessage: '请输入账号和密码');
      return false;
    }
    state = state.copyWith(status: LoginStatus.loading, errorMessage: '');
    final session = await loginRepository.loginWithPassword(
      username: username.trim(),
      password: password,
    );
    if (session == null) {
      state = state.copyWith(
        status: LoginStatus.error,
        errorMessage: loginRepository.lastError.isEmpty
            ? '登录失败'
            : loginRepository.lastError,
      );
      return false;
    }
    await _completeLogin(session);
    return true;
  }

  Future<void> _completeLogin(LoginSession session) async {
    AuthTokenHolder.instance.setSession(
      token: session.token,
      userId: session.userId,
      t1: session.t1,
    );

    var nickname = session.nickname.isEmpty ? '用户' : session.nickname;
    var avatarUrl = session.avatarUrl;
    var isVip = session.isVip;

    // Enrich profile (nickname / avatar) from user detail.
    try {
      final profile = await loginRepository.fetchMyInfo(
        token: session.token,
        userId: session.userId,
      );
      if (profile != null) {
        if (profile.nickname.isNotEmpty && profile.nickname != '用户') {
          nickname = profile.nickname;
        }
        if (profile.avatarUrl.isNotEmpty) avatarUrl = profile.avatarUrl;
        isVip = profile.isVip || isVip;
      }
    } catch (_) {}

    final user = AuthUser(
      userId: session.userId,
      nickname: nickname,
      token: session.token,
      avatarUrl: avatarUrl,
      isVip: isVip,
      isLocalDemo: false,
      t1: session.t1,
    );
    state = AuthState(
      status: LoginStatus.logged,
      user: user,
      restored: true,
      qrPhase: QrPhase.success,
    );
    try {
      final encoded = user
          .toJson()
          .entries
          .map((e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent('${e.value}')}')
          .join('&');
      await _prefs?.setString(_kUser, encoded);
      await _prefs?.remove(_kGuest);
      await _prefs?.setBool(_kSeen, true);
    } catch (_) {}
  }

  /// Re-fetch profile (avatar / nickname) when opening 我的.
  Future<void> refreshProfile() async {
    final user = state.user;
    if (!state.isLogged || user == null || user.token.isEmpty) return;
    try {
      final profile = await loginRepository.fetchMyInfo(
        token: user.token,
        userId: user.userId,
      );
      if (profile == null) return;
      final next = user.copyWith(
        nickname: profile.nickname.isEmpty ? user.nickname : profile.nickname,
        avatarUrl:
            profile.avatarUrl.isEmpty ? user.avatarUrl : profile.avatarUrl,
        isVip: profile.isVip || user.isVip,
      );
      if (next.nickname == user.nickname &&
          next.avatarUrl == user.avatarUrl &&
          next.isVip == user.isVip) {
        return;
      }
      AuthTokenHolder.instance.setSession(
        token: next.token,
        userId: next.userId,
      );
      state = AuthState(
        status: LoginStatus.logged,
        user: next,
        restored: true,
      );
      try {
        final encoded = next
            .toJson()
            .entries
            .map((e) =>
                '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent('${e.value}')}')
            .join('&');
        await _prefs?.setString(_kUser, encoded);
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> logout() async {
    stopQrPolling();
    AuthTokenHolder.instance.clear();
    state = const AuthState(status: LoginStatus.guest, restored: true);
    try {
      await _prefs?.remove(_kUser);
      await _prefs?.setBool(_kGuest, true);
    } catch (_) {}
  }

  Future<void> onUnauthorized() async {
    if (!state.isLogged) return;
    await logout();
  }

  bool _isValidPhone(String phone) =>
      RegExp(r'^1\d{10}$').hasMatch(phone.trim());
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
