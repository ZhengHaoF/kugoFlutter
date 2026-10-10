# kugoFlutter Rework 评估

评估日期为 2026-10-10，原始审查基线为 `main@0154f6361d5450ff63a146f9b8033d24ba2a1db2`。这是修复前的历史评估，不应把下面的基线复现结果当成后续修复提交的当前状态；本轮四项 P0 的修改和新验证见 [P0 实施与验收记录](rework-p0-implementation.md)。

## 结论与边界

不需要推倒重写，应先解决凭据保护和异步状态一致性，再处理持久化与交付质量。原始审查没有修改业务代码，没有使用真实账号或发起评论/弹幕等写操作，也没有完成物理桌面、Android/Windows 真机验收。

- **原始分析**：`flutter analyze --no-pub` 无问题。
- **原始测试**：总计 1,023 项，1,022 通过、1 项封面异步写盘断言失败；该文件单独复跑 17 项通过，不据此认定封面下载功能失效。
- **复现标准**：11 个离线/loopback 夹具用例确认 12 项错误行为；原始夹具断言“错误存在”，不是正确行为的回归测试。
- **证据边界**：代码设计风险与真机验证缺口单独记录，不把它们计入已复现缺陷，也不声称已完成穷尽安全审计。

## 已确认缺陷

| ID | 原始优先级 | 基线复现结果 | 建议修复契约 |
|---|---|---|---|
| R01 | P0 | 资料 HTTP 请求 query 和 Authorization 含虚构 token | 凭据仅发送到可信 HTTPS 目标，无证书绕过/HTTP 回退 |
| R02 | P0 | A 首地址挂起、B 加载后，A 备用地址覆盖引擎；UI 仍 B | 逐代次取消、原生加载串行化、旧结果不覆盖当前源 |
| R06 | P0 | logout 后迟到资料响应恢复 logged、token 和持久用户 | 会话 epoch、退出清理和异步落盘顺序一致 |
| R10 | P0 | 导出日志保留 query 和响应 body 的虚构 secret | 存储前、导出时统一脱敏，不仅处理请求头 |
| R03 | P1 | A 音质目录迟到后把 B 当前队列项替换为 A | 音质结果绑定曲目身份和加载代次 |
| R04 | P1 | 暂停于 45 秒，切音质后起播且归零 | 同曲换质量保留暂停意图与恢复位置 |
| R05 | P1 | stop 后待完成 resolver 仍触发播放调用，idle 改 paused | stop 使加载/回退失效 |
| R07 | P1 | 酷狗 42、网易 42 的两条历史仅留后一条 | 历史去重及主键包含平台身份 |
| R08 | P1 | SQLite 队列往返丢失 artistId、云盘身份和音质目录 | 完整持久化路由/身份字段，临时源可刷新 |
| R09 | P1 | `usePersistedCookies:false` 仍发送旧 MUSIC_U | 新扫码会话隔离旧账号 Cookie |
| R11 | P1 | 401 后内存 token 清除，UI/prefs 仍登录 | 认证失效统一更新三层状态，旧 401 不影响新账号 |
| R12 | P1 | 首次不暂停播放超过 4 秒，无周期位置记录 | 每次成功起播建立周期保存生命周期 |

### 关键代码依据

- **R01**：资料聚合使用 HTTP relation/grade 并附带会话字段，请求体中的 RSA 字段不保护 URL/Authorization 中的 token。[基线 LoginRepository](https://github.com/ZhengHaoF/kugoFlutter/blob/0154f6361d5450ff63a146f9b8033d24ba2a1db2/app/lib/data/repositories/login_repository.dart)
- **播放器组**：备用地址循环缺少逐次代次保护，音质补拉无身份校验，同曲重载强制播放并清位置。[基线 PlayerController](https://github.com/ZhengHaoF/kugoFlutter/blob/0154f6361d5450ff63a146f9b8033d24ba2a1db2/app/lib/features/player/player_controller.dart)
- **R06/R11**：资料刷新缺少会话生命周期保护，401 仅清 token holder。[基线 AuthController](https://github.com/ZhengHaoF/kugoFlutter/blob/0154f6361d5450ff63a146f9b8033d24ba2a1db2/app/lib/features/auth/auth_controller.dart) [基线 KugoClient](https://github.com/ZhengHaoF/kugoFlutter/blob/0154f6361d5450ff63a146f9b8033d24ba2a1db2/app/lib/core/api/kugou/kugo_client.dart)
- **R10**：仅 Authorization/Cookie 请求头脱敏，body 截断不是脱敏。[基线日志实现](https://raw.githubusercontent.com/ZhengHaoF/kugoFlutter/0154f6361d5450ff63a146f9b8033d24ba2a1db2/app/lib/core/api/network_log.dart)
- **R07/R08**：历史删除只用 trackId，持久字段不包含部分 Track 身份/路由字段。[基线数据库](https://github.com/ZhengHaoF/kugoFlutter/blob/0154f6361d5450ff63a146f9b8033d24ba2a1db2/app/lib/data/storage/kugo_db.dart)
- **R09**：全局请求拦截器无条件注入持久 Cookie。[基线网易客户端](https://github.com/ZhengHaoF/kugoFlutter/blob/0154f6361d5450ff63a146f9b8033d24ba2a1db2/app/lib/core/api/netease/netease_client.dart)

## 静态风险及待补验收

- **R13，P1**：多音源凭据写 SharedPreferences，未有应用层安全存储；这是本地文件/备份暴露面，不代表已发生真实泄露。[B 站存储](https://raw.githubusercontent.com/ZhengHaoF/kugoFlutter/0154f6361d5450ff63a146f9b8033d24ba2a1db2/app/lib/data/storage/bili_auth_store.dart) [网易存储](https://raw.githubusercontent.com/ZhengHaoF/kugoFlutter/0154f6361d5450ff63a146f9b8033d24ba2a1db2/app/lib/data/storage/netease_auth_store.dart)
- **R14，P1**：binding 在 guarded Zone 外初始化，runApp 在 Zone 内；默认 debug 报告 mismatch，不据此宣称 Release 必然崩溃，首帧前的多服务 await 也需超时/降级治理。[基线 main](https://github.com/ZhengHaoF/kugoFlutter/blob/0154f6361d5450ff63a146f9b8033d24ba2a1db2/app/lib/main.dart) [Flutter Zone 约束](https://docs.flutter.dev/release/breaking-changes/zone-errors)
- **R15，P1**：Linux CI 不替代 Android/Windows 构建和真机证据；Android release 缺签名配置时回退 debug 签名，应与正式分发任务分离。[Linux CI](https://github.com/ZhengHaoF/kugoFlutter/blob/0154f6361d5450ff63a146f9b8033d24ba2a1db2/.github/workflows/linux.yml) [签名配置](https://github.com/ZhengHaoF/kugoFlutter/blob/0154f6361d5450ff63a146f9b8033d24ba2a1db2/app/android/app/build.gradle.kts)
- **R16，P1**：封面测试使用十轮零延迟事件循环等待异步写盘，存在不稳定线索，应提供明确完成契约。[基线测试](https://raw.githubusercontent.com/ZhengHaoF/kugoFlutter/0154f6361d5450ff63a146f9b8033d24ba2a1db2/app/test/cover_cache_test.dart)
- **R17，P2**：封面磁盘无自动容量/过期治理；清理与在途写入并行回填仅作代码风险，未独立做压力复现。[基线缓存](https://raw.githubusercontent.com/ZhengHaoF/kugoFlutter/0154f6361d5450ff63a146f9b8033d24ba2a1db2/app/lib/core/cache/cover_cache.dart)

真实账号扫码、凭据失效/分页权限、GNOME Xorg/KDE X11、多显示器混合 DPI、两小时播放和 Android/Windows 物理设备仍需分别验收，不能以虚拟桌面探针替代。[已有 Linux 验收边界](https://github.com/ZhengHaoF/kugoFlutter/blob/0154f6361d5450ff63a146f9b8033d24ba2a1db2/docs/linux-x11-lyrics.md)

## 已授权实施范围

本轮按报告后的确认实施四项 P0：R01、R02、R06、R10，并提交 PR，不直接合并 main。R05 的停止取消因与 R02 共用加载生命周期而随修复覆盖；其他 P1/P2 不据此自动宣称完成。

Wayland 专项适配继续暂缓，保留现有基础播放、应用内歌词、MPRIS、存储与其基础回归；不把原生 Wayland 全局悬浮歌词列为当前 bug，不新增协议/桌面扩展或发行打包。[已提交延期决策](https://github.com/ZhengHaoF/kugoFlutter/blob/0154f6361d5450ff63a146f9b8033d24ba2a1db2/docs/linux-x11-lyrics.md)
