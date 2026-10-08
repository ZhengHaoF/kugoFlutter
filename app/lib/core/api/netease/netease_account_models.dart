/// 网易云账号档案 / 会员的**协议层模型**（H 组，2026-10-08 探针实测）。
///
/// 与酷狗侧 `UserProfileDetail`（`features/profile/`）平行，但**不合并**：
/// 两边字段语义不同（酷狗 `tvip/svip` 双会员 vs 网易黑胶VIP/音乐包；
/// 酷狗 `p_grade/p_current_point` vs 网易 `progress` 直接给比值），
/// 硬塞一个模型会把两边口径搅浑。
///
/// 三个模型分别来自三个明文口，见 `NeteaseEndpoints` H 组注释。
library;

/// H1：一条会员记录（`associator` 黑胶VIP / `musicPackage` 音乐包 /
/// `redplus` / `familyVip`）。
///
/// ⚠️ [vipCode] > 0 只代表**开通过**，不代表**生效中**——实测账号
/// `vipCode=100` 但 `expireTime` 已过两个月，而顶层 `redVipLevel` 仍是 7
/// （历史等级不归零）。判生效必须用 [isActiveAt]。
class NeteaseVipMembership {
  const NeteaseVipMembership({
    required this.vipCode,
    this.expireTime,
    this.vipLevel = 0,
    this.isAutoRenew = false,
  });

  /// 业务码。实测 `100` = 黑胶VIP，`220` = 音乐包，`0` = 未开通。
  final int vipCode;

  /// 到期时间，**epoch 毫秒**。`null` 或 `0` = 未开通 / 无期限。
  final int? expireTime;

  final int vipLevel;

  /// 自动续费（`isSign` 系列字段，任一为真即视为续费中）。
  final bool isAutoRenew;

  bool get isOpened => vipCode > 0;

  /// 是否在 [now] 时刻生效中。无到期时间视为长期有效。
  bool isActiveAt(DateTime now) {
    if (vipCode <= 0) return false;
    final exp = expireTime;
    if (exp == null || exp <= 0) return true;
    return exp > now.millisecondsSinceEpoch;
  }

  /// 到期时间 → [DateTime]；未开通 / 无期限返回 null。
  DateTime? get expireAt {
    final exp = expireTime;
    if (exp == null || exp <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(exp);
  }
}

/// H1：`/api/music-vip-membership/front/vip/info` → VIP 总览。
class NeteaseVipInfo {
  const NeteaseVipInfo({
    this.level = 0,
    this.levelIconUrl = '',
    this.annualCount = 0,
    this.heijiao,
    this.musicPackage,
    this.redplus,
    this.familyVip,
  });

  static const empty = NeteaseVipInfo();

  /// `redVipLevel`。**历史等级，过期不归零**，勿单独用于判会员。
  final int level;

  /// `redVipLevelIcon`（服务端图标；UI 目前用自己的文字徽章，暂不用）。
  final String levelIconUrl;

  /// `redVipAnnualCount`，`-1` 表示无意义。
  final int annualCount;

  /// 黑胶VIP（`associator`，`vipCode=100`）。
  final NeteaseVipMembership? heijiao;

  /// 音乐包（`musicPackage`，`vipCode=220`）。
  final NeteaseVipMembership? musicPackage;

  final NeteaseVipMembership? redplus;

  final NeteaseVipMembership? familyVip;

  /// 展示用主会员：黑胶VIP 优先，其次音乐包。
  NeteaseVipMembership? get primary => heijiao ?? musicPackage;

  /// 生效中的会员列表（按优先级）。
  List<NeteaseVipMembership> activeAt(DateTime now) => [
        for (final m in [heijiao, musicPackage, redplus, familyVip])
          if (m != null && m.isActiveAt(now)) m,
      ];
}

/// H2：`/api/user/level` → 听歌等级进度。
///
/// 与酷狗口径的关键差异：[progress] 是服务端算好的 **0–1 比值**
/// （酷狗要给 `p_current_point`/`p_next_grade_point` 自己算），且
/// **没有下一级字段**——下一级就是 [nextLevel]。
class NeteaseLevelInfo {
  const NeteaseLevelInfo({
    this.level = 0,
    this.progress = 0,
    this.nowPlayCount = 0,
    this.nextPlayCount = 0,
    this.nowLoginCount = 0,
    this.nextLoginCount = 0,
    this.privileges = const [],
  });

  static const empty = NeteaseLevelInfo();

  final int level;

  /// 0–1。服务端算好，直接 `*100` 喂进度条。
  final double progress;

  /// **当前等级内**听歌量，不是生涯累计（累计走 [NeteaseUserDetail.listenSongs]）。
  final int nowPlayCount;

  /// 升下一级需要的听歌量。
  final int nextPlayCount;

  final int nowLoginCount;
  final int nextLoginCount;

  /// `info` 按 `$` 拆分的等级权益（实测 `60G音乐网盘免费容量$…`）。
  final List<String> privileges;

  int get nextLevel => level + 1;

  /// 距下一级还差多少首。已满级或服务端没给目标时为 0。
  int get remainingPlays {
    if (nextPlayCount <= 0 || nextPlayCount <= nowPlayCount) return 0;
    return nextPlayCount - nowPlayCount;
  }

  /// 登录天数要求是否已满足（实测账号 350/350 已满，卡点在听歌量）。
  bool get loginRequirementMet => nextLoginCount <= 0 ||
      nowLoginCount >= nextLoginCount;
}

/// H6：`/api/v1/user/detail/{uid}` → 用户详情。
///
/// 这一个口同时给了身份、社交数、生涯统计和档案，故产品侧**不再**打
/// `getfollows` / `getfolloweds` / `subcount`：
/// `profile.followeds` 与 `getfolloweds` 的 `size`、`profile.playlistCount`
/// 与 `subcount` 的 `createdPlaylistCount` 实测均一致。
class NeteaseUserDetail {
  const NeteaseUserDetail({
    this.userId = '',
    this.nickname = '',
    this.avatarUrl = '',
    this.backgroundUrl = '',
    this.signature = '',
    this.description = '',
    this.level = 0,
    this.listenSongs = 0,
    this.follows = 0,
    this.followeds = 0,
    this.playlistCount = 0,
    this.cloudBeanBalance = 0,
    this.createTime,
    this.gender,
    this.provinceCode = '',
    this.cityCode = '',
  });

  static const empty = NeteaseUserDetail();

  final String userId;
  final String nickname;
  final String avatarUrl;

  /// 个人主页背景图（`profile.backgroundUrl`）。
  final String backgroundUrl;

  final String signature;

  /// `profile.description`（简介，与 `signature` 可能同时存在）。
  final String description;

  /// 听歌等级（与 H2 `level` 同源，重复拿到一次）。
  final int level;

  /// **生涯累计听歌数**（实测 10904）。别和 H2 的 `nowPlayCount` 混。
  final int listenSongs;

  /// 关注数（`profile.follows`）。
  final int follows;

  /// 粉丝数（`profile.followeds`）。
  final int followeds;

  /// 自建歌单数（`profile.playlistCount`）。
  final int playlistCount;

  /// 云贝余额（`userPoint.balance`）。
  final int cloudBeanBalance;

  /// 注册时间，**epoch 毫秒**（实测 1536474759615 = 2018-09-09）。
  ///
  /// ⚠️ `formatAccountAge` 要的是**秒**，用的时候记得 `/1000`。
  final int? createTime;

  /// 0 女 · 1 男 · null 保密（与酷狗 `formatGender` 同口径）。
  final int? gender;

  /// 省级行政区划编码（实测 `330000` = 浙江）。
  final String provinceCode;

  /// 市级行政区划编码（实测 `330100` = 杭州）。
  final String cityCode;
}
