import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/bili/bili_qr_login.dart';
import 'package:kugo/core/source/capabilities.dart';

/// 扫码轮询码映射单测（纯函数，不联外网）。
/// 码值口径对齐 NeriPlayer `BiliQrLoginActivity`：86101 等待 / 86090 已扫 /
/// 86038 过期 / 0 成功。
void main() {
  group('BiliQrLoginClient.statusFromCode', () {
    test('已知码映射', () {
      expect(BiliQrLoginClient.statusFromCode(0), LoginQrStatus.confirmed);
      expect(BiliQrLoginClient.statusFromCode(86090), LoginQrStatus.scanned);
      expect(BiliQrLoginClient.statusFromCode(86101), LoginQrStatus.waiting);
      expect(BiliQrLoginClient.statusFromCode(86038), LoginQrStatus.expired);
    });

    test('未知码 → unknown（不猜）', () {
      expect(BiliQrLoginClient.statusFromCode(-1), LoginQrStatus.unknown);
      expect(BiliQrLoginClient.statusFromCode(86102), LoginQrStatus.unknown);
    });
  });

  group('BiliQrLoginPoll', () {
    test('isConfirmed 仅 code==0', () {
      expect(
        const BiliQrLoginPoll(code: 0, message: '', cookies: {}).isConfirmed,
        isTrue,
      );
      expect(
        const BiliQrLoginPoll(code: 86090, message: '', cookies: {}).isConfirmed,
        isFalse,
      );
    });
  });
}
