import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/netease/netease_account_models.dart';
import 'package:kugo/core/api/netease/netease_account_source.dart';
import 'package:kugo/core/api/netease/netease_mappers.dart';
import 'package:kugo/core/source/capabilities.dart';
import 'package:kugo/core/source/music_source.dart';
import 'package:kugo/features/auth/netease_login_controller.dart';
import 'package:kugo/features/profile/netease_account_profile.dart';

import 'fakes/fake_device_login_source.dart';

/// H 组账号档案 / 会员。fixture 全部取自 2026-10-08 真机探针输出
/// （`--suite account`，uid 1593114455），不是编的。
void main() {
  // ── fixture ────────────────────────────────────────────────

  const userDetailRaw = r'''
{"level":9,"listenSongs":10904,
 "userPoint":{"userId":1593114455,"balance":0,"updateTime":1791474505774,
              "version":10,"status":0,"blockBalance":0},
 "mobileSign":false,"pcSign":false,
 "profile":{"privacyItemUnlimit":{"area":true,"gender":true},
   "avatarDetail":null,"vipType":0,"mutual":false,"remarkName":null,
   "defaultAvatar":false,
   "avatarUrl":"http://p3.music.126.net/a==/109951166577614628.jpg",
   "backgroundUrl":"http://p1.music.126.net/b==/109951165424649829.jpg",
   "userType":0,"experts":{},"birthday":-2209017600000,
   "nickname":"MZHENGHF","gender":0,"province":330000,"city":330100,
   "description":"","createTime":1536474759615,"userId":1593114455,
   "signature":"","authority":0,"followeds":1,"follows":16,
   "playlistCount":8,"cCount":0,"sCount":0,"newFollows":0},
 "code":200}''';

  const vipInfoRaw = r'''
{"message":"成功","data":{
  "redVipLevelIcon":"https://p5.music.126.net/icon.png",
  "redVipLevel":7,"redVipAnnualCount":-1,
  "musicPackage":{"vipCode":220,"expireTime":1786031999000,
    "iconUrl":"https://p6.music.126.net/mp.png","dynamicIconUrl":"",
    "vipLevel":7,"isSign":false,"isSignIap":false,
    "isSignDeduct":false,"isSignIapDeduct":false},
  "associator":{"vipCode":100,"expireTime":1786031999000,
    "iconUrl":"https://p5.music.126.net/as.png","dynamicIconUrl":"",
    "vipLevel":7,"isSign":false,"isSignIap":false,
    "isSignDeduct":false,"isSignIapDeduct":false},
  "familyVip":null,"redVipDynamicIconUrl":"","redVipDynamicIconUrl2":"",
  "redplus":{"vipCode":0,"expireTime":0,
    "iconUrl":"https://p5.music.126.net/rp.png","dynamicIconUrl":null,
    "vipLevel":0,"isSign":false,"isSignIap":false,
    "isSignDeduct":false,"isSignIapDeduct":false}},
 "code":200}''';

  const userLevelRaw = r'''
{"full":false,"data":{"userId":1593114455,
 "info":"60G音乐网盘免费容量$黑名单上限120$云音乐商城满100减12元优惠券$价值1200云贝",
 "progress":0.242,"nextPlayCount":12000,"nextLoginCount":350,
 "nowPlayCount":2904,"nowLoginCount":350,"level":9},"code":200}''';

  // 2026-08-06 15:59:59 UTC —— 探针账号的会员到期时刻。
  final expiredAt = DateTime.fromMillisecondsSinceEpoch(1786031999000);
  // 服务端 `now`（2026-10-08），会员已过期约两个月。
  final probeNow = DateTime.fromMillisecondsSinceEpoch(1791474512712);
  // 到期前一个月，会员仍生效。
  final beforeExpiry = DateTime.fromMillisecondsSinceEpoch(1780000000000);

  group('mapNeteaseUserDetail（H6）', () {
    test('真实响应：社交数 / 生涯统计 / 档案全部落位', () {
      final d = mapNeteaseUserDetail(userDetailRaw);

      expect(d.userId, '1593114455');
      expect(d.nickname, 'MZHENGHF');
      expect(d.level, 9);
      expect(d.listenSongs, 10904);
      expect(d.follows, 16);
      expect(d.followeds, 1);
      expect(d.playlistCount, 8);
      expect(d.cloudBeanBalance, 0);
      // 毫秒时间戳原样保留（格式化时再 /1000）。
      expect(d.createTime, 1536474759615);
      expect(d.gender, 0);
      expect(d.provinceCode, '330000');
      expect(d.cityCode, '330100');
      // http → https，与 mapper 其它图片字段同口径。
      expect(d.avatarUrl, startsWith('https://'));
    });

    test('profile 缺失时退化为空模型，不抛', () {
      final d = mapNeteaseUserDetail('{"code":200,"level":9}');
      expect(d.userId, isEmpty);
      expect(d.level, 9);
      expect(d.follows, 0);
    });

    test('业务码非 200 抛 SourceFailure', () {
      expect(
        () => mapNeteaseUserDetail('{"code":301}'),
        throwsA(isA<SourceFailure>()),
      );
    });
  });

  group('mapNeteaseVipInfo（H1）', () {
    test('真实响应：等级 + 两条会员，未开通的 redplus 为 null', () {
      final vip = mapNeteaseVipInfo(vipInfoRaw);

      expect(vip.level, 7);
      expect(vip.heijiao, isNotNull);
      expect(vip.heijiao!.vipCode, 100);
      expect(vip.heijiao!.vipLevel, 7);
      expect(vip.heijiao!.expireTime, 1786031999000);
      expect(vip.musicPackage, isNotNull);
      expect(vip.musicPackage!.vipCode, 220);
      // vipCode == 0 → 未开通，不进模型。
      expect(vip.redplus, isNull);
      expect(vip.familyVip, isNull);
      // 主会员取黑胶VIP。
      expect(vip.primary!.vipCode, 100);
    });

    test('判生效必须比对 expireTime：等级 7 但已过期 → 无生效会员', () {
      final vip = mapNeteaseVipInfo(vipInfoRaw);

      expect(vip.level, 7, reason: '历史等级不归零');
      expect(vip.activeAt(probeNow), isEmpty);
      expect(vip.activeAt(beforeExpiry), hasLength(2));
      expect(vip.heijiao!.isActiveAt(probeNow), isFalse);
      expect(vip.heijiao!.isActiveAt(beforeExpiry), isTrue);
      expect(vip.heijiao!.expireAt, expiredAt);
    });

    test('无到期时间视为长期有效', () {
      const raw = '{"code":200,"data":{"redVipLevel":3,'
          '"associator":{"vipCode":100,"expireTime":0,"vipLevel":3}}}';
      final vip = mapNeteaseVipInfo(raw);
      expect(vip.heijiao!.isActiveAt(probeNow), isTrue);
      expect(vip.heijiao!.expireAt, isNull);
    });

    test('业务码非 200 抛 SourceFailure', () {
      expect(
        () => mapNeteaseVipInfo('{"code":404}'),
        throwsA(isA<SourceFailure>()),
      );
    });
  });

  group('mapNeteaseUserLevel（H2）', () {
    test('真实响应：progress 原样 + info 拆成权益列表', () {
      final lv = mapNeteaseUserLevel(userLevelRaw);

      expect(lv.level, 9);
      expect(lv.progress, closeTo(0.242, 1e-9));
      expect(lv.nowPlayCount, 2904);
      expect(lv.nextPlayCount, 12000);
      expect(lv.nowLoginCount, 350);
      expect(lv.nextLoginCount, 350);
      expect(lv.privileges, [
        '60G音乐网盘免费容量',
        '黑名单上限120',
        '云音乐商城满100减12元优惠券',
        '价值1200云贝',
      ]);
    });

    test('派生量：下一级 / 还差多少首 / 登录要求已满足', () {
      final lv = mapNeteaseUserLevel(userLevelRaw);

      expect(lv.nextLevel, 10);
      expect(lv.remainingPlays, 12000 - 2904);
      expect(lv.loginRequirementMet, isTrue);
    });

    test('progress 脏值钳到 0–1；info 缺省返回空列表', () {
      final lv = mapNeteaseUserLevel(
        '{"code":200,"data":{"level":5,"progress":9.9}}',
      );
      expect(lv.progress, 1);
      expect(lv.privileges, isEmpty);
      expect(lv.remainingPlays, 0, reason: '没给 nextPlayCount 时不敢瞎猜');
    });

    test('业务码非 200 抛 SourceFailure', () {
      expect(
        () => mapNeteaseUserLevel('{"code":301}'),
        throwsA(isA<SourceFailure>()),
      );
    });
  });

  group('格式化', () {
    test('省级编码 → 名称，取前两位', () {
      expect(neteaseProvinceName('330000'), '浙江');
      expect(neteaseProvinceName('33'), '浙江');
      expect(neteaseProvinceName('330100'), '浙江');
      expect(neteaseProvinceName('110000'), '北京');
      expect(neteaseProvinceName('810000'), '香港');
      // 无法识别返回空串，UI 出「—」而不是裸编码。
      expect(neteaseProvinceName('990000'), isEmpty);
      expect(neteaseProvinceName(''), isEmpty);
    });

    test('乐龄把毫秒转成秒再算', () {
      // 1536474759615ms = 2018-09-09；探针 now 是 2026-10-08。
      expect(
        neteaseAccountAge(1536474759615, now: probeNow),
        contains('8 年'),
      );
      expect(neteaseAccountAge(null), '未知');
      expect(neteaseAccountAge(-1), '未知');
    });

    test('徽章文案：生效中给会员名，过期不给', () {
      final vip = mapNeteaseVipInfo(vipInfoRaw);

      expect(neteaseVipBadgeLabel(vip, now: beforeExpiry), '黑胶VIP');
      expect(neteaseVipBadgeLabel(vip, now: probeNow), isNull);
    });

    test('累计听歌是歌曲数，不是时长', () {
      expect(neteaseListenSongsLabel(10904), '10904 首');
      expect(neteaseListenSongsLabel(0), '—');
    });

    test('等级标签与酷狗同形', () {
      expect(neteaseLevelLabel(9), 'Lv.9');
      expect(neteaseLevelLabel(0), '—');
    });
  });

  group('NeteaseAccountProfileNotifier', () {
    ProviderContainer makeContainer(
      NeteaseAccountSource source, {
      String? userId,
    }) {
      final container = ProviderContainer(
        overrides: [
          neteaseAccountSourceProvider.overrideWithValue(source),
          neteaseLoginSourceProvider.overrideWithValue(
            FakeDeviceLoginSource()
              ..account = userId == null
                  ? null
                  : LoginAccount(userId: userId, nickname: 'x'),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Future<void> settle(ProviderContainer c) async {
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final s = c.read(neteaseAccountProfileProvider);
        if (s.loaded && !s.loading) return;
      }
    }

    test('未登录不发请求', () async {
      final source = FakeNeteaseAccountSource();
      final c = makeContainer(source);

      await settle(c);
      final s = c.read(neteaseAccountProfileProvider);

      expect(source.calls, 0);
      expect(s.loaded, isFalse);
      expect(s.error, isEmpty);
    });

    test('登录后三个口各拉一次并全部落位', () async {
      final source = FakeNeteaseAccountSource()
        ..detail = mapNeteaseUserDetail(userDetailRaw)
        ..vip = mapNeteaseVipInfo(vipInfoRaw)
        ..level = mapNeteaseUserLevel(userLevelRaw);
      final c = makeContainer(source, userId: '1593114455');

      await settle(c);
      final s = c.read(neteaseAccountProfileProvider);

      expect(source.calls, 1);
      expect(s.loaded, isTrue);
      expect(s.error, isEmpty);
      expect(s.detail.follows, 16);
      expect(s.detail.listenSongs, 10904);
      expect(s.vip.level, 7);
      expect(s.level.progress, closeTo(0.242, 1e-9));
    });

    test('单口失败不拖垮另外两个', () async {
      final source = _PartialFailAccountSource();
      final c = makeContainer(source, userId: '1593114455');

      await settle(c);
      final s = c.read(neteaseAccountProfileProvider);

      expect(s.loaded, isTrue);
      expect(s.error, isNotEmpty, reason: '要把失败原因带给 UI');
      expect(s.detail.follows, 16, reason: '成功的口照常出数据');
      expect(s.vip.level, 0, reason: '失败的口留 empty');
    });

    test('loaded 后不重复拉；force 才重拉', () async {
      final source = FakeNeteaseAccountSource()
        ..detail = mapNeteaseUserDetail(userDetailRaw);
      final c = makeContainer(source, userId: '1593114455');

      await settle(c);
      expect(source.calls, 1);

      await c.read(neteaseAccountProfileProvider.notifier).load();
      expect(source.calls, 1, reason: '已加载过，直接返回');

      await c.read(neteaseAccountProfileProvider.notifier).load(force: true);
      expect(source.calls, 2);
    });

    test('uid 缺失（登录态异常）时不发请求，给「需登录」', () async {
      final source = FakeNeteaseAccountSource();
      // 有 account 但 userId 不是数字 —— 解析成 0。
      final c = makeContainer(source, userId: 'not-a-number');

      await settle(c);
      final s = c.read(neteaseAccountProfileProvider);

      expect(source.calls, 0);
      expect(s.error, '需登录后查看');
    });
  });
}

/// 只让 userDetail 成功，另外两个口抛错。
class _PartialFailAccountSource implements NeteaseAccountSource {
  @override
  Future<NeteaseUserDetail> userDetail(int uid) async =>
      mapNeteaseUserDetail(_detailRaw);

  @override
  Future<NeteaseVipInfo> vipInfo({required int userId}) async =>
      throw const UpstreamChanged('vip boom');

  @override
  Future<NeteaseLevelInfo> userLevel() async =>
      throw const UpstreamChanged('level boom');
}

const _detailRaw = r'''
{"code":200,"profile":{"userId":"42","nickname":"小明","follows":16}}''';

/// 测试用假账号档案源（H 组三口）：不碰网络，可注入错误。
class FakeNeteaseAccountSource implements NeteaseAccountSource {
  NeteaseUserDetail detail = NeteaseUserDetail.empty;
  NeteaseVipInfo vip = NeteaseVipInfo.empty;
  NeteaseLevelInfo level = NeteaseLevelInfo.empty;
  Object? error;
  int calls = 0;

  @override
  Future<NeteaseUserDetail> userDetail(int uid) async {
    calls++;
    _throwIfNeeded();
    return detail;
  }

  @override
  Future<NeteaseVipInfo> vipInfo({required int userId}) async {
    _throwIfNeeded();
    return vip;
  }

  @override
  Future<NeteaseLevelInfo> userLevel() async {
    _throwIfNeeded();
    return level;
  }

  void _throwIfNeeded() {
    final e = error;
    if (e != null) throw e;
  }
}
