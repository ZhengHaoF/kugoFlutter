import 'netease_account_models.dart';

/// H 组账号档案 / 会员数据源（个人中心网易侧）。
///
/// 与 `neteaseCollectionsSourceProvider` 同构：控制器只认这个接口，测试可
/// 替换成假源（真机实现是 [NeteaseSource]，见 `data/sources/netease/`）。
///
/// **不放 `core/source/capabilities.dart`**：那里面是跨源统一契约
/// （[Track] / [PlaylistBrief] …），而这里返回的是网易专属模型
/// （[NeteaseVipInfo] / [NeteaseLevelInfo] / [NeteaseUserDetail]）。
/// 酷狗侧的档案走 `LoginRepository.fetchMyInfo()`，本就不是能力接口。
abstract interface class NeteaseAccountSource {
  /// H6 `/api/v1/user/detail/{uid}` —— 身份 / 社交数 / 生涯统计 / 档案。
  Future<NeteaseUserDetail> userDetail(int uid);

  /// H1 `/api/music-vip-membership/front/vip/info` —— VIP 等级 + 到期。
  Future<NeteaseVipInfo> vipInfo({required int userId});

  /// H2 `/api/user/level` —— 听歌等级升级进度。
  Future<NeteaseLevelInfo> userLevel();
}
