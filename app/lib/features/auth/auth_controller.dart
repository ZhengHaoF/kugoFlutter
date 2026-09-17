import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/endpoints.dart';
import '../../core/api/kugo_client.dart';
import 'auth_token_holder.dart';

class AuthUser {
  AuthUser({
    required this.userId,
    required this.nickname,
    this.token = '',
    this.avatarUrl = '',
    this.isVip = false,
    this.isLocalDemo = false,
  });

  final String userId;
  final String nickname;
  final String token;
  final String avatarUrl;
  final bool isVip;

  /// True when created without a real gateway login (offline / blocked).
  final bool isLocalDemo;

  AuthUser copyWith({
    String? userId,
    String? nickname,
    String? token,
    String? avatarUrl,
    bool? isVip,
    bool? isLocalDemo,
  }) {
    return AuthUser(
      userId: userId ?? this.userId,
      nickname: nickname ?? this.nickname,
      token: token ?? this.token,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isVip: isVip ?? this.isVip,
      isLocalDemo: isLocalDemo ?? this.isLocalDemo,
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'nickname': nickname,
        'token': token,
        'avatarUrl': avatarUrl,
        'isVip': isVip,
        'isLocalDemo': isLocalDemo,
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
    );
  }
}

enum LoginStatus { unknown, guest, loading, logged, error }

class AuthState {
  const AuthState({
    this.status = LoginStatus.unknown,
    this.user,
    this.errorMessage = '',
    this.smsCountdown = 0,
    this.restored = false,
  });

  final LoginStatus status;
  final AuthUser? user;
  final String errorMessage;
  final int smsCountdown;

  /// True after prefs restore finished (guest or logged).
  final bool restored;

  bool get isLogged => status == LoginStatus.logged && user != null;
  bool get isGuest => status == LoginStatus.guest;

  AuthState copyWith({
    LoginStatus? status,
    AuthUser? user,
    String? errorMessage,
    int? smsCountdown,
    bool? restored,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: errorMessage ?? this.errorMessage,
      smsCountdown: smsCountdown ?? this.smsCountdown,
      restored: restored ?? this.restored,
    );
  }
}

/// 手机号+验证码登录；网关不可达时降级为本地演示会话。
/// 游客模式完全可用：搜索/浏览/播放不依赖登录。
class AuthController extends Notifier<AuthState> {
  static const _kUser = 'auth.user.v1';
  static const _kGuest = 'auth.guest.v1';
  static const _kSeen = 'auth.seen.v1';

  SharedPreferences? _prefs;
  Timer? _countdownTimer;

  @override
  AuthState build() {
    ref.onDispose(() => _countdownTimer?.cancel());
    unawaited(_restore());
    return const AuthState();
  }

  Future<void> _restore() async {
    try {
      _prefs = await SharedPreferences.getInstance();
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
          );
          state = AuthState(
            status: LoginStatus.logged,
            user: user,
            restored: true,
          );
          return;
        }
      }
      // Default: guest (first launch or explicit guest).
      await _prefs?.setBool(_kGuest, true);
      AuthTokenHolder.instance.clear();
      state = const AuthState(status: LoginStatus.guest, restored: true);
    } catch (_) {
      state = const AuthState(status: LoginStatus.guest, restored: true);
    }
  }

  /// Mark onboarding seen (guest-first).
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

  /// 游客继续：可完整使用公开接口，不绑定账号。
  Future<void> continueAsGuest() async {
    AuthTokenHolder.instance.clear();
    state = const AuthState(status: LoginStatus.guest, restored: true);
    try {
      await _prefs?.setBool(_kGuest, true);
      await _prefs?.remove(_kUser);
      await _prefs?.setBool(_kSeen, true);
    } catch (_) {}
  }

  /// 发送验证码。优先走网关；失败仍启动倒计时并提示「演示模式」。
  Future<bool> sendSmsCode(String phone) async {
    if (!_isValidPhone(phone)) {
      state = state.copyWith(errorMessage: '请输入 11 位手机号');
      return false;
    }
    state = state.copyWith(errorMessage: '');

    var ok = false;
    var hint = '';
    try {
      final url = buildUrl(
        KugoEndpoints.mobileCdn,
        '/api/v3/captcha/sent',
        {'mobile': phone.trim(), 'type': 'login'},
      );
      final data = await kugoClient.getJson(url);
      final s = data.toString();
      if (s.contains('{') && !s.contains('URL过滤')) {
        ok = true;
      } else {
        hint = '（网关未返回可用验证码通道）';
      }
    } catch (e) {
      hint = '（网关不可达，已进入演示模式）';
    }

    _startCountdown();
    if (!ok) {
      state = state.copyWith(
        errorMessage: '验证码接口暂不可用$hint。网络受限时请用游客模式',
      );
    }
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

  /// 手机号 + 验证码登录。仅走真实网关，失败不创建本地会话。
  Future<bool> loginWithSms({
    required String phone,
    required String code,
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

    AuthUser? remote;
    String failMsg = '登录失败';
    try {
      final url = buildUrl(
        KugoEndpoints.mobileCdn,
        '/api/v3/login/cellphone',
        {'mobile': phone.trim(), 'code': code.trim()},
      );
      final data = await kugoClient.getJson(url);
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        final body = map['data'] is Map
            ? Map<String, dynamic>.from(map['data'] as Map)
            : map;
        final uid = (body['userid'] ?? body['user_id'] ?? '').toString();
        final token = (body['token'] ?? '').toString();
        final err = (body['error_code'] ?? body['errcode'] ?? '').toString();
        if (uid.isNotEmpty || token.isNotEmpty) {
          remote = AuthUser(
            userId: uid.isEmpty ? phone.trim() : uid,
            nickname:
                (body['username'] ?? body['nickname'] ?? '用户').toString(),
            token: token,
            isVip: body['vip'] == 1 || body['isvip'] == 1,
            isLocalDemo: false,
          );
        } else if (err.isNotEmpty && err != '0') {
          failMsg = '网关返回错误 code=$err';
        } else {
          failMsg = '网关未返回有效账号信息';
        }
      } else {
        failMsg = '登录接口响应异常';
      }
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('URL过滤') ||
          msg.contains('Handshake') ||
          msg.contains('timeout') ||
          msg.contains('Connection')) {
        failMsg = '登录网关不可达（网络受限）。可使用游客模式继续听歌';
      } else {
        failMsg = '登录失败：${msg.split('\n').first}';
      }
    }

    if (remote == null) {
      state = state.copyWith(
        status: LoginStatus.error,
        errorMessage: failMsg,
      );
      return false;
    }

    AuthTokenHolder.instance.setSession(
      token: remote.token,
      userId: remote.userId,
    );
    state = AuthState(status: LoginStatus.logged, user: remote, restored: true);
    try {
      final encoded = remote
          .toJson()
          .entries
          .map((e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent('${e.value}')}')
          .join('&');
      await _prefs?.setString(_kUser, encoded);
      await _prefs?.remove(_kGuest);
      await _prefs?.setBool(_kSeen, true);
    } catch (_) {}
    return true;
  }

  Future<void> logout() async {
    AuthTokenHolder.instance.clear();
    state = const AuthState(status: LoginStatus.guest, restored: true);
    try {
      await _prefs?.remove(_kUser);
      await _prefs?.setBool(_kGuest, true);
    } catch (_) {}
  }

  /// Called when a request returns 401 — keep guest browse, drop invalid session.
  Future<void> onUnauthorized() async {
    if (!state.isLogged) return;
    await logout();
  }

  bool _isValidPhone(String phone) =>
      RegExp(r'^1\d{10}$').hasMatch(phone.trim());
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
