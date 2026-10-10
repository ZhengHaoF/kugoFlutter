# kugoFlutter P1 首批 Rework 实施与验收记录

本轮沿用上次提出的音质切换、持久化及相邻会话一致性范围，基于 P0 提交 `f456d271d7d28863ddafb2777bf87d6d8398a402`，分支为 `fix/rework-p1-quality-persistence`。P0 的 [PR #4](https://github.com/ZhengHaoF/kugoFlutter/pull/4) 在本轮开始时仍未合并，因此 P1 PR 以 P0 分支为基线供独立审查，不直接合并主分支。

## 实施范围与状态

本轮修复原报告已复现的 R03/R04/R07/R08/R09/R11/R12，并为 R16 的封面写盘测试补充明确完成契约。R05 已在 P0 的加载生命周期修复中覆盖，本轮继续保留其停止取消回归，不把安全存储、启动治理和多平台交付风险一起标成完成。

| 编号 | 改动 | 验收要点 |
|---|---|---|
| R03 | 音质目录回写核对加载代次和跨源曲目身份 | A 的迟到结果不覆盖 B；相同 id 的不同平台也隔离；同曲重载后的旧目录作废 |
| R04 | 同曲换音质保留游标与播放意图，原生端支持静默加载 | 暂停在 0/45 秒后不自动出声；播放中切换先 seek 后继续；加载中暂停仍生效 |
| R07 | SQLite 主键、去重、内存缓存及 UI 删除/撤销使用平台身份 | 同 id 的酷狗/网易历史共存；删除一个平台不移除另一个；相同时间戳也不冲突 |
| R08 | schema v3 增加版本化 Track 元数据，补齐队列和历史往返 | artistId、云盘路由字段、音质目录及推荐信息完整恢复；v1/v2 数据库迁移保留旧内容 |
| R09 | 新扫码使用独立 Cookie 集及 QR 代次，不继承旧 MUSIC_U/CSRF | 请求头和响应 Cookie 均隔离；旧扫码/退出后的响应不回填；没有新凭据不能把旧账号当作成功 |
| R11 | 当前已认证请求的 401 通知 AuthController，统一清理内存/UI/prefs | 新账号不被旧 401 登出；匿名 401 不清会话；响应路径与异常路径均覆盖 |
| R12 | 每次成功起播建立周期保存，停止/清队列/错误取消生命周期 | 首次播放不经过暂停也每 4 秒保存；停止后不继续周期覆盖；位置 save/clear 顺序串行 |
| R16 | 封面缓存提供 `flushDiskWrites()`，测试等待明确写盘完成 | 不再靠十轮零延迟事件循环推测文件存在；下载接口仍不等待磁盘 |

## 关键实现

### 播放与音质

`AudioPlayerPort.playUrl` 新增默认兼容的 `play` 参数，media_kit 和 just_audio 在 `play:false` 时只加载而不起播。质量切换保存当前 position 和 `_wantPlaying`，恢复 seek 放进原生串行尾部，确保旧在途 seek 完成后新曲目才进入引擎；退出、停止和新曲目仍通过 P0 的代次检查取消旧结果。

质量目录响应绑定 `identityKey` 与加载代次，回写时基于最新当前 Track 合并，避免覆盖已更新的时长。目录更新会写回持久队列；播放周期保存只在真正的 playing 状态执行，暂停、停止、清队列和播放错误取消定时器。

不能强行取消任意后端正在执行的原生 Future，因此新加载仍可能等待旧 native 操作结束。这里解决的是状态与副作用的顺序一致性，不宣称实现了底层网络零延迟取消。

### 数据库与恢复

Drift schema 从 v2 升到 v3，队列和历史增加 `track_metadata` JSON 列；历史主键增加 `platform_name`，删除及去重同时匹配平台和 trackId。v1 先补平台列，再迁移到 v3；历史表重建时新增元数据使用空对象默认值，不猜测旧数据中已丢失的字段。

元数据保存 artistId、availableQualities、relateGoods、qualityCatalogComplete、推荐/语种及完整 CloudAudioSource 身份字段。没有保存解析后的临时播放直链或签名 URL；恢复后仍通过平台 resolver 获取当前播放地址，云盘项不会因为丢失身份而误入普通曲库路由，损坏元数据则保留可用基础行。

### 认证与扫码隔离

酷狗通用客户端对实际附带当前 Authorization 的请求记录凭据代次，401 只使相同代次失效；AuthController 订阅失效事件，复用 P0 的串行会话清理。监听器随 provider 销毁移除，重复响应不重复触发有效会话失效。

网易扫码使用独立 Cookie 集，移除 Dio 默认 Cookie 后仅发送当前扫码 Cookie；响应也只更新所属扫码代次。确认时仅采用新扫码 Cookie/refresh token，替换旧账号与旧 CSRF；没有新凭据时返回失败，Source 不把上游 803 直接冒充已登录。

这些回归使用虚构账号、离线 adapter 与本地媒体，不等同于真实平台账号权限验收。安全存储迁移、磁盘不可写时的可靠擦除和真实平台业务 code 的全覆盖仍需后续处理。

## 自动验证

本轮使用仓库 CI 同版本的 Flutter 3.47.7 / Dart 3.13.5，依赖版本未升级；sqlite3 从传递依赖调整为直接 dev dependency，用于建立真实旧版数据库夹具。本地环境为 Ubuntu 26.04，远端 workflow 则使用既有 Ubuntu 22.04/24.04 矩阵，二者证据不混称。

| 验证 | 已完成结果 | 证据 |
|---|---|---|
| 本地完整测试 | 前一完整批次 1,102 项全部通过，含当时新增的 32 项 P1 回归 | [完整测试日志](rework-p1-evidence/full-1102-before-final-two-tests.log) |
| 最终 P1 核心测试 | 最后补充暂停重载失败、非 QR 手机登录 Cookie 两项后，共新增 34 项，34 项全部通过 | [最终核心测试日志](rework-p1-evidence/p1-core-34.log) |
| 最终静态分析 | `flutter analyze --no-pub` 无问题 | 本地执行；远端同样执行 |
| 最终生产入口构建 | `flutter build linux --release --no-pub` 通过 | [生产构建日志](rework-p1-evidence/linux-release.log) |
| 扩展原生探针 | X11、libmpv、实际恢复游标、首次周期保存、MPRIS、视频、迷你窗全部通过 | [原生验收日志](rework-p1-evidence/x11-libmpv.log) |
| 远端最终全量 | 最终应为 1,104 项；本地前一完整批次不冒充最终远端结果 | P1 PR 的 checks 和 Actions 实际结果 |

SQLite 迁移测试同时建立独立的旧版内存库和当前测试库，会出现 Drift 的重复实例 debug 提示，执行器并不共享。迁移的真实表结构、旧行保留、新字段往返及跨源主键检查均已通过，不把该提示称为生产数据库损坏。

核心回归入口：

```sh
cd app
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub --concurrency 4 --reporter expanded
flutter build linux --release --no-pub
flutter build linux --release --no-pub -t tool/linux_integration_probe.dart
xvfb-run -a dbus-run-session -- bash tool/run_linux_probe.sh \
  build/linux/x64/release/bundle/kugo build/p1-native-probe
```

本轮还扩展既有 Linux 原生探针，验证首次真实 libmpv 播放的周期保存、暂停换音质和播放中换音质；虚拟音频输出只证明合成音频解码与时钟，不代表物理扬声器、真实歌曲或真机验收。

暂停换音质时检查应用保存游标及原生 `playing=false`，恢复起播后再核对 libmpv 的实际时钟位置。这样既验证暂停意图，又不把暂停期间尚未刷新的原生时钟误判为 seek 失败；本次虚拟 PulseAudio 输出峰值 8,000、非零样本 361,566。

## 未完成事项与合并顺序

- **R13：安全存储**：多音源凭据目前仍使用 SharedPreferences；本轮 Cookie/401 修复不是加密存储，后续需要按各平台密钥服务实现迁移、失败关闭和退出擦除。
- **R14：启动治理**：binding/guarded Zone 一致性、首帧前初始化超时和降级仍待独立修改与回归。
- **R15：交付矩阵**：Android/Windows 构建与真机、正式 release 签名政策仍待独立交付批次，不以 Linux CI 替代。
- **真实业务**：真实短信、扫码、凭据失效、云盘 HTTPS 上传/取流、长时间播放与多桌面环境尚未验收。
- **P2/Wayland**：P2 不做，Wayland 专项继续暂缓；保留现有基础播放和应用内歌词及相关回归。
- **合并顺序**：先审查并合并 P0 PR #4，再把 P1 PR 基线转为 main，复核只剩 P1 增量并重跑 CI；本轮不自动合并任何 PR。

以上待办使整个 P1 仍未全部完成。首批修复的完成状态以此文档中的最终验证记录为准，不把待验收项隐藏在“全部通过”的测试结论里。
