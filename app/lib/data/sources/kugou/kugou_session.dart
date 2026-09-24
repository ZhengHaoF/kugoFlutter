import '../../../features/auth/auth_token_holder.dart';

/// 酷狗会话边界。阶段 A 薄封装 [AuthTokenHolder]，第二源再拆独立 Session。
/// KugouSource / 播放签名只应依赖本类，不再直接摸全局 Holder。
class KugouSession {
  const KugouSession();

  AuthTokenHolder get _auth => AuthTokenHolder.instance;

  bool get hasToken => _auth.hasToken;

  String get token => _auth.token;

  String get userId => _auth.userId;

  String get mid => _auth.mid;

  String get guid => _auth.guid;

  String get dfid => _auth.dfid;

  void setSession({
    String? token,
    String? userId,
    String? mid,
    String? guid,
    String? dfid,
    String? t1,
  }) {
    _auth.setSession(
      token: token,
      userId: userId,
      mid: mid,
      guid: guid,
      dfid: dfid,
      t1: t1,
    );
  }

  void clear() => _auth.clear();
}

/// 默认酷狗会话；后续可注入。
const kugouSession = KugouSession();
