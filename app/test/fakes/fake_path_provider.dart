import 'dart:io';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 把 `getApplicationSupportDirectory()` 指到临时目录的假平台实现。
///
/// `CrashLog` / `CoverCache` 都靠它落盘；不装这个，flutter test 里
/// `getApplicationSupportDirectory()` 会抛 MissingPluginException，
/// 两条分支都被 `catch (_)` 吞掉，测到的只是「优雅降级」而不是真逻辑。
class FakePathProviderPlatform extends PathProviderPlatform {
  FakePathProviderPlatform(this.dir);

  final Directory dir;

  @override
  Future<String?> getApplicationSupportPath() async => dir.path;
}

/// 装假平台并返回临时目录；用例结束后由 [Directory] 的调用方负责清理。
FakePathProviderPlatform installFakePathProvider(Directory dir) {
  final fake = FakePathProviderPlatform(dir);
  PathProviderPlatform.instance = fake;
  return fake;
}
