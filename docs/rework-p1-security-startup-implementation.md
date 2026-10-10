# Rework P1: 安全存储与启动治理

## 范围与基线

本批接续 [P1 首批 PR #5](https://github.com/ZhengHaoF/kugoFlutter/pull/5)，处理 R13 与 R14。P2、Wayland 专项及 Linux 应用交付不在本批范围；Android/Windows 制品构建配置另一个提交和 PR 交付。

## 安全存储

- 统一 `CredentialStore`：酷狗 `auth.user.v1`、网易 `netease.auth.v1`、B 站 `bili.auth.v1` 使用平台安全存储，而非普通 SharedPreferences 保存 token/Cookie。非秘密设置继续使用 SharedPreferences。
- 锁定 `flutter_secure_storage 10.3.4`：11.x 的 Windows win32 依赖与当前 file_picker 不兼容，不通过强制 dependency_overrides 或无关组件大升级掩盖冲突。
- 旧值先写安全存储，再读回核对，成功后才删除旧普通配置。失败时旧值保留用于后续迁移，但绝不从该明文值直接建立登录态。
- 按音源串行读写，失败不毒化后续队列，完成后释放队列记录。写失败不回退明文。
- 新会话替换与退出使用普通配置里的非秘密阻断标记。退出标记不等待前一原生写入；迟到旧写入不能清掉新退出标记。即使安全存储暂时无法删除，重启也不能恢复旧会话。
- 恢复代次与登录 epoch 防止迟到恢复、扫码、资料、401 响应重建已经退出的会话。
- 安全存储保存失败显示本次登录无法保存；清理失败显示已退出但清理未完成，不泄露底层凭据或错误内容。
- Android 使用默认 RSA OAEP/AES-GCM 方案，启用迁移备份并关闭异常自动重置，Android 最低 API 23，禁止应用自动备份。平台加密不是对恶意同用户进程、root、调试读取内存的防护。

插件平台及备份设置参考 [flutter_secure_storage 10.3.4](https://pub.dev/packages/flutter_secure_storage/versions/10.3.4)。本批离线测试使用内存实现及故障 MethodChannel，不把模拟存储称作原生 OS 安全存储验收。

## 启动治理

- 在同一个 `runZonedGuarded` 内初始化 Flutter binding、安装崩溃捕获并调用 runApp，修复 [Flutter Zone 约束](https://docs.flutter.dev/release/breaking-changes/zone-errors) 问题。
- `StartupGate` 先绘制启动界面，30 秒未就绪给出明确提示，初始化真正失败后可重试；失败释放 ProviderContainer 和网络日志订阅。
- 不把 Future.timeout 当作取消。必要任务超时但尚未结束时不并发重试，避免两个播放器或 native 服务抢占。必须结束当前操作或重启进程后才能重新执行该必要任务。
- 登录恢复等待上限 8 秒。酷狗超时切游客并作废旧恢复 epoch；网易/B 站恢复失败或超时清当前内存 Cookie、作废迟到恢复代次，并保留磁盘凭据。
- 设置与队列准备后显示主应用；系统媒体会话、FM 认领、桌面托盘/歌词及 Android 悬浮歌词改为首帧后初始化。每个可选服务等待上限 8 秒，失败或超时记脱敏崩溃日志、显示可关闭的降级提示，继续启动其他独立服务。
- 超时可选服务没有强行取消：迟到成功允许完成一次，不发起重试或创建重叠服务。核心播放 bridge 本来可空，因此媒体卡不可用不伪装为播放器本身不可用。

## 回归与交付边界

新增回归覆盖迁移清除明文、读回不一致、锁定存储、替换失败、原生删除失败、保存/退出排序、后续恢复、B 站迟到恢复；启动回归覆盖首帧壳、超时、失败重试、dispose 后完成、可选服务失败及超时降级。

原 P0/P1 登录和 Cookie 回归仍保留，只把“秘密应保存在普通配置”的旧断言改为“秘密在安全存储、普通配置不含秘密”，没有删减旧会话竞态验收。

全量测试和远端检查的最终结果以相关 PR 的 Actions 运行及后续验收更新为准。真实账号短信/扫码/云盘、Android/Windows 物理设备、长期播放、正式签名和恶意本地进程威胁模型均未因离线测试而自动通过；整个 P1 不能因此宣称全部完成。

本地静态分析无问题，聚焦凭据、启动和三音源登录的 94 项回归通过。测试日志保存在 `docs/rework-p1-security-evidence/core-tests.log`；全量结果另外记录，远端 CI 对最终提交重新验证。
