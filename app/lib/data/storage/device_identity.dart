import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/kugo_sign.dart';
import '../../features/auth/auth_token_holder.dart';

/// Persistent device identity for signed login/play requests.
class DeviceIdentity {
  DeviceIdentity._({
    required this.dfid,
    required this.guid,
    required this.mid,
    required this.dev,
    required this.mac,
  });

  final String dfid;
  final String guid;
  final String mid;
  final String dev;
  final String mac;

  static const _kDfid = 'kugo_device_dfid';
  static const _kGuid = 'kugo_device_guid';
  static const _kDev = 'kugo_device_dev';

  static DeviceIdentity? _cached;

  static Future<DeviceIdentity> ensure() async {
    final cached = _cached;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    var dfid = prefs.getString(_kDfid) ?? '';
    var guid = prefs.getString(_kGuid) ?? '';
    var dev = prefs.getString(_kDev) ?? '';
    if (dfid.isEmpty) {
      dfid = KugoSign.randomAlnum(24);
      await prefs.setString(_kDfid, dfid);
    }
    if (guid.isEmpty) {
      guid = KugoSign.md5Hex('kugo-flutter-$dfid-${DateTime.now()}');
      await prefs.setString(_kGuid, guid);
    }
    if (dev.isEmpty) {
      dev = 'kugoFlutter';
      await prefs.setString(_kDev, dev);
    }
    final mid = KugoSign.calculateMid(guid);
    const mac = '02:00:00:00:00:00';
    final id = DeviceIdentity._(
      dfid: dfid,
      guid: guid,
      mid: mid,
      dev: dev,
      mac: mac,
    );
    AuthTokenHolder.instance.setSession(
      mid: mid,
      guid: guid,
      dfid: dfid,
    );
    _cached = id;
    return id;
  }
}
