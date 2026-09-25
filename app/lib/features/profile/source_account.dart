import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/source/music_platform.dart';
import '../../core/source/registry.dart';
import '../auth/auth_controller.dart';
import '../auth/netease_login_controller.dart';
import '../settings/settings_controller.dart';

/// 账号摘要：把「酷狗的 [AuthController]」与「其余源的登录控制器」收成一张
/// 统一的脸，供「我的 / 个人中心」按当前账号源渲染。
///
/// 只读展示，不承载登录动作（登录/退出见 [loginRouteFor] / [logoutSource]）。
class SourceAccount {
  const SourceAccount({
    required this.platform,
    this.isLogged = false,
    this.restored = true,
    this.nickname = '',
    this.avatarUrl = '',
    this.isVip = false,
    this.userId = '',
  });

  final MusicPlatform platform;
  final bool isLogged;

  /// 登录态是否已从本地恢复完毕。false 时 UI 出占位（`…`）而不是「游客」，
  /// 避免本地已登录却先闪一下未登录。
  final bool restored;

  final String nickname;
  final String avatarUrl;
  final bool isVip;
  final String userId;
}

/// 该源的登录页路由（酷狗 `/login`，网易 `/netease-login`）。
String loginRouteFor(MusicPlatform platform) => switch (platform) {
      MusicPlatform.kugou => '/login',
      MusicPlatform.netease => '/netease-login',
    };

/// 退出该源的账号（酷狗走 [AuthController]，网易走 [NeteaseLoginController]）。
Future<void> logoutSource(WidgetRef ref, MusicPlatform platform) =>
    switch (platform) {
      MusicPlatform.kugou =>
        ref.read(authControllerProvider.notifier).logout(),
      MusicPlatform.netease =>
        ref.read(neteaseLoginControllerProvider.notifier).logout(),
    };

/// 「我的 / 个人中心」当前查看的账号源（`null` = 跟随设置里的默认源）。
///
/// **页面级**切换，不写进全局设置：与搜索 / 榜单 / 私人 FM 的切源栏同构。
final accountSourceProvider = StateProvider<MusicPlatform?>((ref) => null);

/// 实际生效的账号源：选择值被停用 / 未注册时回退到默认源。
final effectiveAccountSourceProvider = Provider<MusicPlatform>((ref) {
  final settings = ref.watch(settingsControllerProvider);
  final picked = ref.watch(accountSourceProvider);
  if (picked != null && settings.enabledSources.contains(picked)) {
    return picked;
  }
  return settings.effectiveDefaultSource;
});

/// 可切换的账号源（启用 + 已注册），按枚举序稳定输出。
final accountSourcePlatformsProvider = Provider<List<MusicPlatform>>((ref) {
  final enabled = ref.watch(settingsControllerProvider).enabledSources;
  final registered = musicSourceRegistry?.platforms ?? const <MusicPlatform>{};
  return [
    for (final p in MusicPlatform.values)
      if (enabled.contains(p) && registered.contains(p)) p,
  ];
});

/// 按源取账号摘要。酷狗读 [AuthController]，其余源读各自登录控制器。
final sourceAccountProvider =
    Provider.family<SourceAccount, MusicPlatform>((ref, platform) {
  switch (platform) {
    case MusicPlatform.kugou:
      final auth = ref.watch(authControllerProvider);
      return SourceAccount(
        platform: platform,
        isLogged: auth.isLogged,
        restored: auth.restored,
        nickname: auth.user?.nickname ?? '',
        avatarUrl: auth.user?.avatarUrl ?? '',
        isVip: auth.user?.isVip ?? false,
        userId: auth.user?.userId ?? '',
      );
    case MusicPlatform.netease:
      // 网易登录态由 [NeteaseLoginController] 缓存（其 build 会回填一次账号）。
      final acc = ref.watch(neteaseLoginControllerProvider).account;
      return SourceAccount(
        platform: platform,
        isLogged: acc != null,
        nickname: acc?.nickname ?? '',
        avatarUrl: acc?.avatarUrl ?? '',
        isVip: acc?.isVip ?? false,
        userId: acc?.userId ?? '',
      );
  }
});
