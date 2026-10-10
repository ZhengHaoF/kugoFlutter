# 哔哩哔哩接入实现与验收记录

本次基于 `b133f99` 继续实现 B3/B4。仓库原有 B1 协议、B2 搜索/取流及 B5 装配；本次补充账号与只读内容，但尚不能标为端到端发布完成。原始阶段范围见 [仓库方案](https://github.com/ZhengHaoF/kugoFlutter/blob/b133f99/%E5%93%94%E5%93%A9%E5%93%94%E5%93%A9%E6%8E%A5%E5%85%A5%E6%96%B9%E6%A1%88.md)。

## 本次实现

- 扫码登录：`DeviceLoginSource`、二维码页、`/bili-login`、等待/已扫/过期/确认状态、串行轮询、刷新与离页停止、旧会话失效。
- 登录存储：独立 `bili.auth.v1`，账号校验后保存，启动恢复、退出清理，拒绝非法 Cookie。沿用项目 SharedPreferences 本机存储方式，不宣称加密存储。
- 账号入口：设置页账号管理、个人中心账号摘要、退出分发和登录能力门控。
- 收藏夹：自建/收藏读取、收藏口 count 分页、自建 list-all 不完整时分页补齐、收藏合集 type=21 的类型分流。
- 内容详情：`fav:<id>`、`season:<mid>:<id>`、`series:<mid>:<id>`、`video:<bvid>`；分页去重和无进展保护、分 P 独立身份、来源保留。
- UP 主：资料、投稿分页与热门/最新排序；新增 `ArtistContentSource` 供页面分页显示合集/系列，未将合集伪装成专辑。
- 异常处理：歌单评论按 `ResourceCommentSource` 门控；UP 主请求失败结束加载并展示错误，风控码 -352/-401 映射为可重试的 `RateLimited`。
- 协议层仍可由纯 Dart CLI 使用，Flutter 存储仅在应用启动和登录控制器使用。

内容端点、参数和响应结构对照了 [NeriPlayer BiliClient](https://github.com/cwuom/NeriPlayer/blob/main/modules/platform/src/main/java/moe/ouom/neriplayer/platform/bilibili/api/client/BiliClient.kt) 及其收藏夹与 UP 主接口测试。参考实现不是本项目实网成功的替代证据；下节区分了实网测试、模拟测试与未验收部分。

## 自动化验证

环境为 Linux，Flutter 3.47.7 / Dart 3.13.5。依赖由原 pubspec 解析，没有升级项目约束，也未交付临时生成的依赖锁文件。

```bash
cd app
flutter pub get
flutter analyze --no-pub
flutter test --reporter expanded
dart run tool/smoke_bili_source.dart --keyword 晴天
dart run tool/smoke_bili_content.dart
```

- 静态分析：无问题。
- 全量测试：最终 998 项全部通过；`flutter analyze --no-pub` 无问题，`git diff --check` 通过。
- 新增测试覆盖 Cookie 校验/保存/恢复/清理、扫码状态与并发控制、过期/刷新/退出防串号、收藏夹分页、无进展保护、内容 ID 校验、合集 WBI 参数、系列元数据、UP 主分页及多 P 身份。
- 测试中的扫码成功、登录账号与收藏夹响应使用注入的假客户端或 Dio 脚本响应，不代表已用真实账号验收。

## 实网验证

2026-10-09，从本次运行环境以游客态验证：

- 搜索“晴天”返回 17 条映射曲目，来源正确。
- 同一视频裸 bvid 和 bvid:cid 两种身份均可取流，携带源下发 UA/Referer 的音轨请求均返回 HTTP 206。
- 合集/系列列表返回 20 项，服务端总数 108；首个合集 `season:9666167:5726252` 详情返回 8 个视频。
- `video:<bvid>` 分 P 展开通过，本例为 1 P；多 P 情况由模拟响应测试覆盖。
- 扫码二维码生成及等待扫码状态通过，没有扫码或获取任何真实账号凭据。
- UP 主资料与投稿遇到 B 站“风控校验失败”，不能作为实网通过项。应用显示可读错误，不绕过验证码或风控，不高频重试。
- 真实收藏夹、自建私密收藏夹、真实登录重启恢复和系列详情的实网验收未执行。

实网摘要属于本次测试运行记录，不承诺接口或临时音轨地址持续可用。可重复执行上述 CLI 工具复核，不应把签名音轨 URL 当成长期资源地址。

## 剩余验收及发布门槛

- 将补丁应用到仓库，审阅并提交分支/PR。当前没有可用的 GitHub 写入授权，本次未推送、更未合并到远端。
- 在 Android 与 Windows 执行构建和真机测试：进入二维码页、扫码确认、切换账号、退出、重启恢复、不影响另外两个音源。
- 使用实际账号核验公开/私密自建收藏夹、收藏的他人夹、收藏合集、超过一页的列表、失效视频过滤与播放。
- 在用户常用网络或登录态复核 UP 主资料/投稿，确认风控情况下有错误提示并可手动重试，且合集区域不被阻断。
- 核验系列详情与多 P 视频在界面、队列、历史中的身份稳定性，以及 Android/Windows 真实音频播放和封面防盗链。
- B 站仍不实现云端红心、音乐推荐、歌词、评论或写操作；这些不属于本期缺口，不应为了“完成”制造空能力入口。

## 应用补丁

随邮件交付的是 Git format-patch 文件，包含实现、测试和本记录。建议在干净工作区从基线或包含该基线的分支应用。

```bash
git switch -c feat/bili-account-content
git am /path/to/kugo-bilibili-integration.patch
cd app
flutter pub get
flutter analyze --no-pub
flutter test
```

如果主分支已有后续改动导致冲突，应先检查冲突再人工合并，不要强制覆盖。未完成真实账号与平台验收前，请勿标记为生产发布完成。
