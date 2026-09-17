/// Global auth token holder so Dio can inject credentials without Riverpod.
class AuthTokenHolder {
  static final AuthTokenHolder instance = AuthTokenHolder._();
  AuthTokenHolder._();

  String token = '';
  String userId = '';
  String mid = 'kugo_flutter_mid';
  String guid = 'kugo_flutter_guid';
  String dfid = '';
  String t1 = '';

  bool get hasToken => token.isNotEmpty;

  /// Authorization header value (EchoMusic-style k=v parts).
  String get authorizationHeader {
    final parts = <String>[
      if (token.isNotEmpty) 'token=$token',
      if (userId.isNotEmpty) 'userid=$userId',
      if (t1.isNotEmpty) 't1=$t1',
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
    String? t1,
  }) {
    if (token != null) this.token = token;
    if (userId != null) this.userId = userId;
    if (mid != null) this.mid = mid;
    if (guid != null) this.guid = guid;
    if (dfid != null) this.dfid = dfid;
    if (t1 != null) this.t1 = t1;
  }

  void clear() {
    token = '';
    userId = '';
    t1 = '';
    // Do NOT clear dfid/mid/guid — device identity must survive logout/guest
    // so play-signature mid stays stable across reinstall of the same data.
  }

  /// Wipe everything including device (only for tests / full reset).
  void clearDevice() {
    clear();
    dfid = '';
    mid = 'kugo_flutter_mid';
    guid = 'kugo_flutter_guid';
  }
}
