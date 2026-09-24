import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/api/kugo_crypto.dart';
import '../../core/api/kugo_sign.dart';
import '../../core/api/mappers.dart' show normalizeCoverUrl;
import '../../data/storage/device_identity.dart';
import '../../features/auth/auth_token_holder.dart';
import '../../features/profile/user_profile_detail.dart';

class LoginSession {
  const LoginSession({
    required this.userId,
    required this.token,
    this.nickname = '用户',
    this.username = '',
    this.avatarUrl = '',
    this.isVip = false,
    this.vipType = 0,
    this.vipToken = '',
    this.t1 = '',
  });

  final String userId;
  final String token;
  final String nickname;
  final String username;
  final String avatarUrl;
  final bool isVip;
  final int vipType;
  final String vipToken;
  final String t1;

  LoginSession copyWith({
    String? nickname,
    String? username,
    String? avatarUrl,
    bool? isVip,
  }) {
    return LoginSession(
      userId: userId,
      token: token,
      nickname: nickname ?? this.nickname,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isVip: isVip ?? this.isVip,
      vipType: vipType,
      vipToken: vipToken,
      t1: t1,
    );
  }
}

/// Real gateway login: QR / SMS / password (KuGouMusicApi-compatible).
class LoginRepository {
  LoginRepository({Dio? dio}) : _dio = dio ?? _createDio();

  final Dio _dio;
  String lastError = '';

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        responseType: ResponseType.plain,
        validateStatus: (c) => c != null && c >= 200 && c < 500,
      ),
    );
  }

  Future<Map<String, dynamic>?> _signedGet(
    String url, {
    Map<String, dynamic>? params,
    Map<String, String>? headers,
    bool webSign = false,
    bool skipDefaultParams = false,
  }) async {
    final device = await DeviceIdentity.ensure();
    final auth = AuthTokenHolder.instance;
    final merged = <String, dynamic>{
      if (!skipDefaultParams)
        ...KugoSign.defaultParams(dfid: device.dfid, mid: device.mid),
      ...?params,
    };
    if (auth.hasToken) merged['token'] = auth.token;
    if (auth.userId.isNotEmpty && auth.userId != '0') {
      merged['userid'] = int.tryParse(auth.userId) ?? auth.userId;
    }

    if (webSign) {
      merged['signature'] = KugoSign.signatureWebParams(merged);
    } else {
      merged['signature'] = KugoSign.signatureAndroidParams(merged);
    }

    try {
      final res = await _dio.get<dynamic>(
        url,
        queryParameters: merged,
        options: Options(
          headers: {
            'User-Agent': KugoSign.userAgent,
            'dfid': device.dfid,
            'mid': device.mid,
            'clienttime':
                '${merged['clienttime'] ?? DateTime.now().millisecondsSinceEpoch ~/ 1000}',
            ...?headers,
          },
        ),
      );
      return _decode(res.data);
    } on DioException catch (e) {
      lastError = e.message ?? '网络错误';
      return null;
    }
  }

  Map<String, dynamic>? _decode(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    final s = raw?.toString() ?? '';
    if (s.isEmpty) return null;
    try {
      final v = jsonDecode(s);
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return null;
  }

  bool _ok(Map<String, dynamic>? body) {
    if (body == null) return false;
    final status = body['status'];
    final code = body['error_code'] ?? body['errcode'] ?? body['err_code'];
    if (status == 1 || status == '1') return true;
    if (status == true) return true;
    return code == 0 || code == '0';
  }

  String _err(Map<String, dynamic>? body, String fallback) {
    if (body == null) return lastError.isEmpty ? fallback : lastError;
    final msg = body['error'] ?? body['errmsg'] ?? body['msg'] ?? body['message'];
    if (msg is String && msg.isNotEmpty) return msg;
    final code = body['error_code'] ?? body['errcode'];
    if (code != null) return '$fallback (code=$code)';
    return fallback;
  }

  // --- QR ---

  /// Returns QR payload URL to render, plus key for polling.
  Future<({String key, String contentUrl})?> createQrLogin() async {
    lastError = '';
    final body = await _signedGet(
      'https://login-user.kugou.com/v2/qrcode',
      params: {
        'appid': 1001,
        'type': 1,
        'plat': 4,
        'qrcode_txt':
            'https://h5.kugou.com/apps/loginQRCode/html/index.html?appid=${KugoSign.appId}&',
        'srcappid': KugoSign.srcAppId,
      },
      webSign: true,
    );
    if (!_ok(body)) {
      lastError = _err(body, '获取二维码失败');
      return null;
    }
    final data = body!['data'];
    if (data is! Map) {
      lastError = '二维码响应异常';
      return null;
    }
    final map = Map<String, dynamic>.from(data);
    final key = (map['qrcode'] ?? map['key'] ?? '').toString();
    if (key.isEmpty) {
      lastError = '二维码 key 为空';
      return null;
    }
    final contentUrl =
        'https://h5.kugou.com/apps/loginQRCode/html/index.html?qrcode=$key';
    return (key: key, contentUrl: contentUrl);
  }

  /// status: 0 expired, 1 waiting, 2 scanned, 4 confirmed+login.
  Future<({int status, LoginSession? session})?> checkQrLogin(String key) async {
    final body = await _signedGet(
      'https://login-user.kugou.com/v2/get_userinfo_qrcode',
      params: {
        'plat': 4,
        'appid': int.parse(KugoSign.appId),
        'srcappid': KugoSign.srcAppId,
        'qrcode': key,
      },
      webSign: true,
    );
    if (body == null) return null;
    final data = body['data'];
    if (data is! Map) return (status: 0, session: null);
    final map = Map<String, dynamic>.from(data);
    final status = int.tryParse('${map['status']}') ?? 0;
    if (status != 4) return (status: status, session: null);

    final token = (map['token'] ?? '').toString();
    final userid = (map['userid'] ?? map['user_id'] ?? '0').toString();
    if (token.isEmpty) return (status: 4, session: null);
    return (
      status: 4,
      session: LoginSession(
        userId: userid,
        token: token,
        nickname: (map['username'] ?? map['nickname'] ?? '用户').toString(),
        username: (map['username'] ?? '').toString(),
        isVip: map['vip'] == 1 || map['vip_type'] == 1,
      ),
    );
  }

  // --- SMS ---

  Future<bool> sendSmsCode(String mobile) async {
    lastError = '';
    final device = await DeviceIdentity.ensure();
    final query = KugoSign.defaultParams(dfid: device.dfid, mid: device.mid);
    final data = {
      'businessid': 5,
      'mobile': mobile,
      'plat': 3,
    };
    final bodyJson = jsonEncode(data);
    query['signature'] =
        KugoSign.signatureAndroidParams(query, data: bodyJson);
    try {
      final res = await _dio.post<dynamic>(
        'http://login.user.kugou.com/v7/send_mobile_code',
        data: data,
        queryParameters: query,
        options: Options(
          headers: {
            'User-Agent': KugoSign.userAgent,
            'Content-Type': 'application/json',
            'mid': device.mid,
            'dfid': device.dfid,
          },
        ),
      );
      final body = _decode(res.data);
      if (_ok(body)) return true;
      lastError = _err(body, '发送验证码失败');
      return false;
    } on DioException catch (e) {
      lastError = e.message ?? '网络错误';
      return false;
    }
  }

  // --- SMS login ---

  Future<LoginSession?> loginWithSms({
    required String mobile,
    required String code,
    String userid = '',
  }) async {
    lastError = '';
    final device = await DeviceIdentity.ensure();
    final dateTime = DateTime.now().millisecondsSinceEpoch;
    final encrypt = KugoCrypto.aesEncrypt(
      jsonEncode({'mobile': mobile, 'code': code}),
    ) as Map;
    final encKey = encrypt['key']! as String;
    final encStr = encrypt['str']! as String;

    const t2Key = 'fd14b35e3f81af3817a20ae7adae7020';
    const t2Iv = '17a20ae7adae7020';
    const t1Key = '5e4ef500e9597fe004bd09a46d8add98';
    const t1Iv = '04bd09a46d8add98';
    final t2 = KugoCrypto.aesEncrypt(
      '${device.guid}|0f607264fc6318a92b9e13c65db7cd3c|${device.mac}|${device.dev}|$dateTime',
      key: t2Key,
      iv: t2Iv,
    ) as String;
    final t1 = KugoCrypto.aesEncrypt('|$dateTime', key: t1Key, iv: t1Iv)
        as String;

    final pkRaw = KugoCrypto.rsaEncryptRaw(
      jsonEncode({'clienttime_ms': dateTime, 'key': encKey}),
    );

    final mobileMasked =
        '${mobile.substring(0, 2)}*****${mobile.substring(mobile.length - 1)}';

    final query = KugoSign.defaultParams(dfid: device.dfid, mid: device.mid);
    query['signature'] = KugoSign.signatureAndroidParams(query);

    final data = {
      'plat': 1,
      'support_multi': 1,
      't1': t1,
      't2': t2,
      'clienttime_ms': dateTime,
      'mobile': mobileMasked,
      'key': KugoSign.signParamsKey('$dateTime'),
      'pk': pkRaw.toUpperCase(),
      'params': encStr,
      'dfid': device.dfid,
      'dev': device.dev,
      'gitversion': '5f0b7c4',
      if (userid.isNotEmpty) 'userid': int.tryParse(userid) ?? userid,
    };

    try {
      final res = await _dio.post<dynamic>(
        'https://loginserviceretry.kugou.com/v7/login_by_verifycode',
        data: data,
        queryParameters: query,
        options: Options(
          headers: {
            'User-Agent': 'Android16-1070-11440-130-0-LOGIN-wifi',
            'Content-Type': 'application/json',
            'support-calm': '1',
            'dfid': device.dfid,
            'mid': device.mid,
          },
        ),
      );
      final body = _decode(res.data);
      return _parseLoginBody(body, encKey: encKey);
    } on DioException catch (e) {
      lastError = e.message ?? '网络错误';
      return null;
    }
  }

  // --- Password ---

  Future<LoginSession?> loginWithPassword({
    required String username,
    required String password,
  }) async {
    lastError = '';
    final device = await DeviceIdentity.ensure();
    final dateTime = DateTime.now().millisecondsSinceEpoch;
    final encrypt = KugoCrypto.aesEncrypt(
      jsonEncode({
        'pwd': password,
        'code': '',
        'clienttime_ms': dateTime,
      }),
    ) as Map;
    final encKey = encrypt['key']! as String;
    final encStr = encrypt['str']! as String;
    final pkRaw = KugoCrypto.rsaEncryptRaw(
      jsonEncode({'clienttime_ms': dateTime, 'key': encKey}),
    );

    final query = KugoSign.defaultParams(dfid: device.dfid, mid: device.mid);
    query['signature'] = KugoSign.signatureAndroidParams(query);

    final data = {
      'plat': 1,
      'support_multi': 1,
      'clienttime_ms': dateTime,
      't1':
          '562a6f12a6e803453647d16a08f5f0c2ff7eee692cba2ab74cc4c8ab47fc467561a7c6b586ce7dc46a63613b246737c03a1dc8f8d162d8ce1d2c71893d19f1d4b797685a4c6d3d81341cbde65e488c4829a9b4d42ef2df470eb102979fa5adcdd9b4eecfea8b909ff7599abeb49867640f10c3c70fc444effca9d15db44a9a6c907731e2bb0f22cd9b3536380169995693e5f0e2424e3378097d3813186e3fe96bbe7023808a0981b4e2b6135a76faac',
      't2':
          '31c4daf4cf480169ccea1cb7d4a209295865a9d2b788510301694db229b87807469ea0d41b4d4b9173c2151da7294aeebfc9738df154bbdf11a4e117bb5dff6a3af8ce5ce333e681c1f29a44038f27567d58992eb81283e080778ac77db1400fdf49b7cf7e26be2e5af4da7830cc3be4',
      't3': 'MCwwLDAsMCwwLDAsMCwwLDA=',
      'dev': device.dev,
      'username': username,
      'params': encStr,
      'pk': pkRaw.toUpperCase(),
    };

    try {
      final res = await _dio.post<dynamic>(
        'https://gateway.kugou.com/v9/login_by_pwd',
        data: data,
        queryParameters: query,
        options: Options(
          headers: {
            'User-Agent': KugoSign.userAgent,
            'Content-Type': 'application/json',
            'x-router': 'login.user.kugou.com',
            'dfid': device.dfid,
            'mid': device.mid,
          },
        ),
      );
      final body = _decode(res.data);
      return _parseLoginBody(body, encKey: encKey);
    } on DioException catch (e) {
      lastError = e.message ?? '网络错误';
      return null;
    }
  }

  LoginSession? _parseLoginBody(
    Map<String, dynamic>? body, {
    required String encKey,
  }) {
    if (body == null) return null;
    if (!_ok(body)) {
      lastError = _err(body, '登录失败');
      return null;
    }
    final data = body['data'];
    if (data is! Map) {
      lastError = '登录响应异常';
      return null;
    }
    final map = Map<String, dynamic>.from(data);
    var token = (map['token'] ?? '').toString();
    final secu = (map['secu_params'] ?? '').toString();
    if (token.isEmpty && secu.isNotEmpty) {
      final plain = KugoCrypto.aesDecryptHex(secu, encKey);
      if (plain != null && plain.isNotEmpty) {
        try {
          final decoded = jsonDecode(plain);
          if (decoded is Map) {
            final dm = Map<String, dynamic>.from(decoded);
            token = (dm['token'] ?? token).toString();
            map.addAll(dm);
          } else {
            token = decoded.toString();
          }
        } catch (_) {
          token = plain;
        }
      }
    }
    final userId = (map['userid'] ?? map['user_id'] ?? '0').toString();
    if (token.isEmpty) {
      lastError = '登录成功但未返回 token';
      return null;
    }
    return LoginSession(
      userId: userId,
      token: token,
      nickname: (map['username'] ?? map['nickname'] ?? '用户').toString(),
      username: (map['username'] ?? '').toString(),
      isVip: map['vip'] == 1 || (map['vip_type'] ?? 0) != 0,
      vipType: int.tryParse('${map['vip_type'] ?? 0}') ?? 0,
      vipToken: (map['vip_token'] ?? '').toString(),
      t1: (map['t1'] ?? '').toString(),
    );
  }

  /// Fetch profile (nickname / avatar / archive / social / vip / grade).
  ///
  /// EchoMusic `/user/detail` = usercenter `get_my_info` (full archive + social),
  /// `/user/vip/detail` = `get_union_vip` (busi_vip), `/user/grade/info` =
  /// `get_grade_info` (listen seconds + grade progress). Relation
  /// `get_my_userinfo` only carries basic identity — never short-circuit on it.
  Future<MyProfile?> fetchMyInfo({
    required String token,
    required String userId,
  }) async {
    lastError = '';
    final fromRelation = await _fetchMyUserInfoRelation(token: token, userId: userId);
    final fromUsercenter = await _fetchMyInfoUsercenter(token: token, userId: userId);
    final fromVip = await _fetchVipDetail(token: token, userId: userId);
    final fromGrade = await _fetchGradeInfo(token: token, userId: userId);

    final sources = [
      ?fromRelation,
      ?fromUsercenter,
    ];
    if (sources.isEmpty && fromVip == null && fromGrade == null) {
      return null;
    }

    var detail = UserProfileDetail.empty;
    MyProfile? base;
    for (final profile in sources) {
      base = base == null
          ? profile
          : MyProfile(
              nickname: profile.nickname.isNotEmpty && profile.nickname != '用户'
                  ? profile.nickname
                  : base.nickname,
              avatarUrl: profile.avatarUrl.isNotEmpty
                  ? profile.avatarUrl
                  : base.avatarUrl,
              isVip: profile.isVip || base.isVip,
              userId: profile.userId.isNotEmpty ? profile.userId : base.userId,
              detail: base.detail.merge(profile.detail),
            );
      detail = detail.merge(profile.detail);
    }
    detail = detail.merge(fromVip ?? UserProfileDetail.empty);
    detail = detail.merge(fromGrade ?? UserProfileDetail.empty);

    final resolved = base ??
        MyProfile(
          nickname: '用户',
          userId: userId,
          isVip: detail.tvipActive || detail.svipActive,
          detail: detail,
        );
    return MyProfile(
      nickname: resolved.nickname,
      avatarUrl: resolved.avatarUrl,
      isVip: resolved.isVip || detail.tvipActive || detail.svipActive,
      userId: resolved.userId.isEmpty ? userId : resolved.userId,
      detail: detail,
    );
  }

  Map<String, String> _authHeaders(DeviceIdentity device, String token, String userId) {
    final t1 = AuthTokenHolder.instance.t1;
    final parts = <String>[
      'token=$token',
      'userid=$userId',
      if (t1.isNotEmpty) 't1=$t1',
      'dfid=${device.dfid}',
      'KUGOU_API_MID=${device.mid}',
      'KUGOU_API_GUID=${device.guid}',
      'KUGOU_API_DEV=${device.dev}',
    ];
    return {
      'Authorization': parts.join(';'),
      'dfid': device.dfid,
      'mid': device.mid,
    };
  }

  /// POST http://relation.user.kugou.com/v1/get_my_userinfo
  Future<MyProfile?> _fetchMyUserInfoRelation({
    required String token,
    required String userId,
  }) async {
    final device = await DeviceIdentity.ensure();
    final clienttime = DateTime.now().millisecondsSinceEpoch;
    // JS object key order: { clienttime, token }
    final p = KugoCrypto.rsaEncryptRaw(
      jsonEncode({'clienttime': clienttime, 'token': token}),
    ).toUpperCase();

    // KuGouMusicApi always injects token/userid into query — missing them
    // yields error_code=20018 (登录态无效) even with a valid Cookie.
    final query = <String, dynamic>{
      ...KugoSign.defaultParams(dfid: device.dfid, mid: device.mid),
      'token': token,
      'userid': int.tryParse(userId) ?? 0,
    };
    final data = {
      'p': p,
      'appid': int.parse(KugoSign.appId),
      'mid': device.mid,
      'clientver': int.parse(KugoSign.clientVer),
      'source': 0,
      'clienttime': clienttime,
      'uuid': '-',
      'userid': int.tryParse(userId) ?? 0,
      'key': KugoSign.signParamsKey('$clienttime'),
    };
    final bodyJson = jsonEncode(data);
    query['signature'] =
        KugoSign.signatureAndroidParams(query, data: bodyJson);

    try {
      final res = await _dio.post<dynamic>(
        'http://relation.user.kugou.com/v1/get_my_userinfo',
        data: data,
        queryParameters: query,
        options: Options(
          headers: {
            'User-Agent': KugoSign.userAgent,
            'Content-Type': 'application/json',
            'Host': 'relation.user.kugou.com',
            ..._authHeaders(device, token, userId),
          },
        ),
      );
      final body = _decode(res.data);
      if (_ok(body)) {
        return _mapProfile(body!, fallbackUserId: userId);
      }
      lastError = _err(body, '获取用户资料失败(relation)');
    } on DioException catch (e) {
      lastError = e.message ?? '网络错误';
    }
    return null;
  }

  /// POST gateway /v3/get_my_info (usercenter)
  Future<MyProfile?> _fetchMyInfoUsercenter({
    required String token,
    required String userId,
  }) async {
    final device = await DeviceIdentity.ensure();
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // JS object key order: { token, clienttime }
    final pk = KugoCrypto.rsaEncryptRaw(
      jsonEncode({'token': token, 'clienttime': clienttime}),
    ).toUpperCase();

    final query = <String, dynamic>{
      ...KugoSign.defaultParams(dfid: device.dfid, mid: device.mid),
      'plat': 1,
      'token': token,
      'userid': int.tryParse(userId) ?? 0,
    };
    final data = {
      'visit_time': clienttime,
      'usertype': 1,
      'p': pk,
      'userid': int.tryParse(userId) ?? 0,
    };
    final bodyJson = jsonEncode(data);
    query['signature'] =
        KugoSign.signatureAndroidParams(query, data: bodyJson);

    try {
      final res = await _dio.post<dynamic>(
        'https://gateway.kugou.com/v3/get_my_info',
        data: data,
        queryParameters: query,
        options: Options(
          headers: {
            'User-Agent': KugoSign.userAgent,
            'Content-Type': 'application/json',
            'x-router': 'usercenter.kugou.com',
            ..._authHeaders(device, token, userId),
          },
        ),
      );
      final body = _decode(res.data);
      if (!_ok(body)) {
        lastError = _err(body, '获取用户资料失败');
        return null;
      }
      return _mapProfile(body!, fallbackUserId: userId);
    } on DioException catch (e) {
      lastError = e.message ?? '网络错误';
      return null;
    }
  }

  /// GET kugouvip /v1/get_union_vip (EchoMusic `/user/vip/detail`).
  ///
  /// Returns tvip/svip from `data.busi_vip[]`; missing busi_vip stays inactive.
  Future<UserProfileDetail?> _fetchVipDetail({
    required String token,
    required String userId,
  }) async {
    final device = await DeviceIdentity.ensure();
    final query = <String, dynamic>{
      ...KugoSign.defaultParams(dfid: device.dfid, mid: device.mid),
      'busi_type': 'concept',
      'token': token,
      'userid': int.tryParse(userId) ?? 0,
    };
    query['signature'] = KugoSign.signatureAndroidParams(query);

    try {
      final res = await _dio.get<dynamic>(
        'https://kugouvip.kugou.com/v1/get_union_vip',
        queryParameters: query,
        options: Options(
          headers: {
            'User-Agent': KugoSign.userAgent,
            ..._authHeaders(device, token, userId),
          },
        ),
      );
      final body = _decode(res.data);
      if (!_ok(body)) return null;
      final root = body!;
      final data = root['data'];
      final vipNode = data is Map ? Map<String, dynamic>.from(data) : root;
      return _mapVipDetail(vipNode, [vipNode, root]);
    } catch (_) {
      return null;
    }
  }

  /// POST userinfo.user /v2/get_grade_info (EchoMusic `/user/grade/info` query mode).
  ///
  /// Fills listen seconds + grade progress that usercenter does not return.
  Future<UserProfileDetail?> _fetchGradeInfo({
    required String token,
    required String userId,
  }) async {
    final device = await DeviceIdentity.ensure();
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // lite v2 protocol: key = md5(appid + appkey + clientver + clienttime).
    const gradeClientVer = '10597';
    const gradeAppKey = 'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA';
    final key = KugoSign.md5Hex(
      '${KugoSign.appId}$gradeAppKey$gradeClientVer$clienttime',
    );
    // Query mode p plaintext is {clienttime, userid} — no token field.
    final p = KugoCrypto.rsaEncryptRaw(
      jsonEncode({'clienttime': clienttime, 'userid': int.tryParse(userId) ?? 0}),
    ).toUpperCase();
    final data = {
      'mid': device.mid,
      'type': 1,
      'uuid': device.guid,
      'userid': int.tryParse(userId) ?? 0,
      'p': p,
      'appid': int.parse(KugoSign.appId),
      'clientver': int.parse(gradeClientVer),
      'clienttime': clienttime,
      'key': key,
    };

    try {
      final res = await _dio.post<dynamic>(
        'http://userinfo.user.kugou.com/v2/get_grade_info',
        data: jsonEncode(data),
        queryParameters: {'dfid': device.dfid},
        options: Options(
          headers: {
            'Content-Type': 'text/plain; charset=ISO-8859-1',
            'User-Agent':
                'Android15-1070-$gradeClientVer-201-0-get_user_grade_info-wifi',
            'KG-THash': KugoCrypto.randomAlnum(7, lower: true),
            'KG-Rec': '1',
            'KG-RC': '1',
            ..._authHeaders(device, token, userId),
          },
        ),
      );
      final body = _decode(res.data);
      if (!_ok(body)) return null;
      final root = body!;
      final dataNode = root['data'];
      if (dataNode is! Map) return null;
      final m = Map<String, dynamic>.from(dataNode);
      int? asInt(Object? v) =>
          v is num ? v.toInt() : int.tryParse('${v ?? ''}');
      return UserProfileDetail(
        listenSeconds: asInt(m['d_sec']),
        grade: asInt(m['p_grade']),
        currentPoint: asInt(m['p_current_point']),
        nextGrade: asInt(m['p_next_grade']),
        nextGradePoint: asInt(m['p_next_grade_point']),
      );
    } catch (_) {
      return null;
    }
  }

  MyProfile _mapProfile(
    Map<String, dynamic> json, {
    String fallbackUserId = '',
  }) {
    // Flatten common nesting: data / info / userinfo / user_info / profile / base
    final candidates = <Map<String, dynamic>>[json];
    for (final key in const [
      'data',
      'info',
      'userinfo',
      'user_info',
      'profile',
      'base',
      'extendsInfo',
      'extends',
    ]) {
      final v = json[key];
      if (v is Map) {
        candidates.add(Map<String, dynamic>.from(v));
      }
    }

    // EchoMusic keeps archive/social fields under extendsInfo.detail and VIP
    // under extendsInfo.vip — walk those leaves explicitly so they are not
    // flattened away by the generic pick().
    Map<String, dynamic> asMap(Object? v) =>
        v is Map ? Map<String, dynamic>.from(v) : const {};

    final detailLeaf = <String, dynamic>{};
    for (final map in candidates) {
      detailLeaf.addAll(asMap(map['detail']));
      final ext = asMap(map['extendsInfo']);
      detailLeaf.addAll(asMap(ext['detail']));
      detailLeaf.addAll(asMap(asMap(map['extends'])['detail']));
    }
    // Some payloads put social counters at the top of extendsInfo itself.
    final extendsLeaf = <String, dynamic>{};
    for (final map in candidates) {
      extendsLeaf.addAll(asMap(map['extendsInfo']));
      extendsLeaf.addAll(asMap(map['extends']));
    }

    int? numFrom(
      List<String> keys, {
      List<Map<String, dynamic>>? scopes,
    }) {
      final maps = scopes ?? [...candidates, detailLeaf, extendsLeaf];
      for (final map in maps) {
        for (final k in keys) {
          final v = map[k];
          if (v == null || v == '') continue;
          final n = v is num ? v : num.tryParse(v.toString());
          if (n == null) continue;
          return n.toInt();
        }
      }
      return null;
    }

    String pick(List<String> keys) {
      final maps = [...candidates, detailLeaf, extendsLeaf];
      for (final map in maps) {
        for (final k in keys) {
          final v = map[k];
          if (v == null) continue;
          final s = v.toString().trim();
          if (s.isNotEmpty && s != 'null') return s;
        }
      }
      return '';
    }

    final nickname = pick([
      'nickname',
      'username',
      'userName',
      'nick_name',
      'nickName',
    ]);
    final picRaw = pick([
      'pic',
      'userPic',
      'user_pic',
      'avatar',
      'avatarUrl',
      'headpic',
      'head_pic',
      'photo',
      'icon',
    ]);
    var avatarUrl = '';
    if (picRaw.isNotEmpty) {
      avatarUrl = normalizeCoverUrl(picRaw, size: '200');
      if (avatarUrl.startsWith('mock://')) avatarUrl = '';
    }
    final vipType = int.tryParse(pick(['vip_type', 'viptype', 'vipType'])) ?? 0;
    final vip = pick(['vip']);
    final userId = pick(['userid', 'userId', 'user_id', 'uid']);
    final signature = pick(['descri', 'signature', 'sign']);
    final province = pick(['province']);
    final city = pick(['city']);
    final ipLocation = pick(['loc', 'ip_loc', 'ipLocation', 'ip_location']);

    // 0/1/2 are real gender codes — pick() would drop a legitimate `0`.
    int? gender;
    for (final map in [detailLeaf, ...candidates]) {
      final v = map['gender'] ?? map['sex'];
      if (v == null || v == '') continue;
      gender = v is num ? v.toInt() : int.tryParse(v.toString());
      if (gender != null) break;
    }

    final detail = UserProfileDetail(
      gender: gender,
      signature: signature,
      province: province,
      city: city,
      ipLocation: ipLocation,
      follows: numFrom(['follows', 'follow', 'follow_count']),
      fans: numFrom(['fans', 'fans_count', 'fan_count']),
      visitors: numFrom(['hvisitors', 'visitors', 'visitor', 'visit_count']),
      registerTime: numFrom(['rtime', 'reg_time', 'register_time', 'createTime']),
      listenSeconds: numFrom(['d_sec', 'dsec', 'listen_seconds']),
      listenMinutes: numFrom(['duration', 'listen_duration']),
      grade: numFrom(['p_grade', 'grade']),
      currentPoint: numFrom(['p_current_point', 'current_point']),
      nextGrade: numFrom(['p_next_grade', 'next_grade']),
      nextGradePoint: numFrom(['p_next_grade_point', 'next_grade_point']),
    ).merge(_mapVipDetail(json, candidates));

    return MyProfile(
      nickname: nickname.isEmpty ? '用户' : nickname,
      avatarUrl: avatarUrl,
      isVip: vipType != 0 || vip == '1' || detail.tvipActive || detail.svipActive,
      userId: userId.isEmpty ? fallbackUserId : userId,
      detail: detail,
    );
  }

  /// Parse `extendsInfo.vip.busi_vip[]` (Echo `tvip` / `svip` product types).
  UserProfileDetail _mapVipDetail(
    Map<String, dynamic> json,
    List<Map<String, dynamic>> candidates,
  ) {
    List<Map<String, dynamic>> busi = const [];
    void absorb(Object? node) {
      if (node is! Map) return;
      final m = Map<String, dynamic>.from(node);
      final list = m['busi_vip'] ?? m['busiVip'];
      if (list is List) {
        busi = [
          ...busi,
          for (final item in list)
            if (item is Map) Map<String, dynamic>.from(item),
        ];
      }
    }

    absorb(json['vip']);
    for (final map in candidates) {
      absorb(map['vip']);
      absorb(map['extendsInfo']);
      final ext = map['extendsInfo'];
      if (ext is Map) absorb(ext['vip']);
      absorb(map);
    }

    Map<String, dynamic>? findType(String type) {
      for (final item in busi) {
        final t = '${item['product_type'] ?? item['productType'] ?? ''}';
        if (t == type) return item;
      }
      return null;
    }

    Map<String, dynamic>? active(String type) {
      final item = findType(type);
      if (item == null) return null;
      final isVip = item['is_vip'] ?? item['isVip'];
      final on = isVip is num ? isVip == 1 : '$isVip' == '1' || isVip == true;
      return on ? item : null;
    }

    final tvip = active('tvip');
    final svip = active('svip');
    return UserProfileDetail(
      tvipActive: tvip != null,
      svipActive: svip != null,
      tvipBegin: tvip?['vip_begin_time'] ?? tvip?['vipBeginTime'],
      tvipEnd: tvip?['vip_end_time'] ?? tvip?['vipEndTime'],
      svipBegin: svip?['vip_begin_time'] ?? svip?['vipBeginTime'],
      svipEnd: svip?['vip_end_time'] ?? svip?['vipEndTime'],
    );
  }
}


final loginRepository = LoginRepository();
