import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/kugo_sign.dart';
import '../../features/auth/auth_token_holder.dart';
import '../repositories/device_repository.dart';

/// Persistent device identity for signed login/play/comment requests.
///
/// KuGou risk control rejects an *unknown* dfid on risk-controlled endpoints
/// (comments, some playlist APIs) with `err_code=20028` + a `ssa-code` header,
/// so a real device is registered once via `/risk/v2/r_register_dev`.
/// When that fails we fall back to the official anonymous value `-`, which the
/// same endpoints accept.
class DeviceIdentity {
  DeviceIdentity._({
    required this.dfid,
    required this.guid,
    required this.mid,
    required this.dev,
    required this.mac,
    required this.registered,
  });

  final String dfid;
  final String guid;
  final String mid;
  final String dev;
  final String mac;

  /// True when [dfid] came from the register endpoint (not the `-` fallback).
  final bool registered;

  static const _kDfid = 'kugo_device_dfid';
  static const _kGuid = 'kugo_device_guid';
  static const _kMid = 'kugo_device_mid';
  static const _kDev = 'kugo_device_dev';
  static const _kRegistered = 'kugo_device_dfid_registered';
  static const _kTriedAt = 'kugo_device_dfid_tried_at';

  /// Do not hit the register endpoint again within this window after a failure.
  static const _retryAfter = Duration(hours: 6);

  static DeviceIdentity? _cached;

  static Future<DeviceIdentity> ensure() async {
    final cached = _cached;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    var dfid = prefs.getString(_kDfid) ?? '';
    var guid = prefs.getString(_kGuid) ?? '';
    var dev = prefs.getString(_kDev) ?? '';
    if (guid.isEmpty) {
      guid = KugoSign.md5Hex(
        'kugo-flutter-${DateTime.now()}-${KugoSign.randomAlnum(16)}',
      );
      await prefs.setString(_kGuid, guid);
    }
    if (dev.isEmpty) {
      dev = 'kugoFlutter';
      await prefs.setString(_kDev, dev);
    }
    var mid = prefs.getString(_kMid) ?? KugoSign.calculateMid(guid);

    var registered = prefs.getBool(_kRegistered) ?? false;
    if (!registered && _shouldRetry(prefs)) {
      await prefs.setInt(_kTriedAt, DateTime.now().millisecondsSinceEpoch);
      final reg = await DeviceRepository().register(mid: mid, guid: guid);
      if (reg != null) {
        dfid = reg.dfid;
        if (reg.guid.isNotEmpty && reg.guid != guid) {
          guid = reg.guid;
          await prefs.setString(_kGuid, guid);
          // mid derives from guid, so recompute unless the server sent one.
          if (reg.mid.isEmpty) mid = KugoSign.calculateMid(guid);
        }
        if (reg.mid.isNotEmpty) {
          mid = reg.mid;
          await prefs.setString(_kMid, mid);
        }
        registered = true;
        await prefs.setString(_kDfid, dfid);
        await prefs.setBool(_kRegistered, true);
      } else {
        // Unregistered random dfid is what triggers SSA 20028 — use the
        // anonymous value instead, and retry registration later.
        dfid = DeviceRepository.anonymousDfid;
        await prefs.setString(_kDfid, dfid);
      }
    }
    if (dfid.isEmpty) {
      dfid = DeviceRepository.anonymousDfid;
      await prefs.setString(_kDfid, dfid);
    }

    const mac = '02:00:00:00:00:00';
    final id = DeviceIdentity._(
      dfid: dfid,
      guid: guid,
      mid: mid,
      dev: dev,
      mac: mac,
      registered: registered,
    );
    AuthTokenHolder.instance.setSession(
      mid: mid,
      guid: guid,
      dfid: dfid,
    );
    _cached = id;
    return id;
  }

  /// Allows the first attempt, then throttles retries to [_retryAfter].
  static bool _shouldRetry(SharedPreferences prefs) {
    final last = prefs.getInt(_kTriedAt);
    if (last == null) return true;
    final elapsed = DateTime.now().millisecondsSinceEpoch - last;
    return elapsed >= _retryAfter.inMilliseconds;
  }

  /// Drop the cached identity (settings "clear device" / tests).
  static Future<void> reset() async {
    _cached = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kDfid);
    await prefs.remove(_kGuid);
    await prefs.remove(_kMid);
    await prefs.remove(_kRegistered);
    await prefs.remove(_kTriedAt);
  }
}
