/// Global auth token holder so Dio can inject credentials without Riverpod.
class AuthTokenHolder {
  static final AuthTokenHolder instance = AuthTokenHolder._();
  AuthTokenHolder._();

  String token = '';
  String userId = '';
  String mid = 'kugo_flutter_mid';
  String guid = 'kugo_flutter_guid';
  String dfid = '';

  bool get hasToken => token.isNotEmpty;

  /// Authorization header value (EchoMusic-style k=v parts).
  String get authorizationHeader {
    final parts = <String>[
      if (token.isNotEmpty) 'token=$token',
      if (userId.isNotEmpty) 'userid=$userId',
      'KUGOU_API_MID=$mid',
      'KUGOU_API_GUID=$guid',
      if (dfid.isNotEmpty) 'dfid=$dfid',
    ];
    return parts.join(';');
  }

  void setSession({
    String? token,
    String? userId,
    String? mid,
    String? guid,
    String? dfid,
  }) {
    if (token != null) this.token = token;
    if (userId != null) this.userId = userId;
    if (mid != null) this.mid = mid;
    if (guid != null) this.guid = guid;
    if (dfid != null) this.dfid = dfid;
  }

  void clear() {
    token = '';
    userId = '';
    dfid = '';
  }
}
