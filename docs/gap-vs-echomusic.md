# kugoFlutter vs EchoMusic — 功能差距清单

> 对比日期：2026-09-19
> 基准：`D:\work\EchoMusic`（Electron + Vue3，v2.3.2-beta.5）
> 对象：`D:\work\kugoFlutter`（Flutter Android，v0.1.0，M0–M4 已完成）
> 用途：作为 kugo 的二期 backlog 输入

---

## 一、结论速览

| 维度 | kugo 现状 | EchoMusic | 差距 |
| --- | --- | --- | --- |
| 核心听歌闭环 | 完整（登录、搜索、播放、歌单/专辑/歌手、FM、榜单、每日推荐、歌词、评论只读、设置） | 完整 | 已对齐 |
| 内容形态 | **纯音频** | 音频 + MV + 动态封面 + 云盘 | 缺 MV / 云盘 |
| 社交与互动 | 评论**只读** | 评论只读 + 发评论 + 楼层回复 | 缺评论写入 |
| 用户资产管理 | 只读 | 自建歌单增删改 + 排序 + 封面编辑 | 缺歌单写入 |
| 歌词 | LRC 滚动 + 翻译 + 偏移 | LRC/**YRC 逐字** + 音译 + 换肤 + 写真 + 桌面歌词 + 弹幕 | 缺逐字/音译/换肤 |
| 音效 | 无 | 10 段 EQ + LUFS + 空间音效 + DSP 热插拔 | 缺音效引擎 |
| 播放能力 | 队列/模式/音质/定时 | + 倍速 + 歌曲过渡 + 音量 + 输出设备 + 独占 | 缺倍速（Port 已有） |
| 搜索 | **仅歌曲** | 歌曲/歌手/专辑/歌单/歌词/MV 六维 | 缺多 Tab |
| 分享 | 无 | 全内容分享 | 缺 |
| 扩展性 | 无 | 完整插件系统 + DSP Provider | 一期不做（已规划） |
| 平台集成 | 锁屏/通知栏 | 托盘、全局快捷键、mini 模式、桌面歌词 | 形态差异，不追 |

---

## 二、按优先级排列的缺口

### P0 · 纯 bug / 假入口（应当立即修）

| # | 问题 | 位置 | 说明 |
| --- | --- | --- | --- |
| ~~1~~ | ~~「本地音乐」点击无反应~~ | `profile_page.dart` | ✅ 待处理（本次未动） |
| ~~2~~ | ~~「下载管理」点击无反应~~ | `profile_page.dart` | ✅ 待处理（本次未动） |
| 3 | ~~「定时停止 / 音质设置 / 关于」不可点~~ | `profile_page.dart` | ✅ **已修（3327499）**：抽出 `shared/widgets/settings_pickers.dart` 共享给设置页与我的页；三个入口带当前值副标题；新增「关于」弹层 |
| 4 | ~~「歌单」统计数字硬编码 `12`~~ | `profile_page.dart:133` | ✅ **已修（90bd379）两/三步走的第一步**：「我喜欢」已接本地真值；「最近播放」新增 `KugoDb.countHistory()` 走 SQL COUNT 取真值，未就绪显示 `—`；「歌单」仍为 `—` 占位（未登录显「需登录」，已登录显「待接入」）。**第二步**（接 `/user/playlist`）跟随 P1 #7 自建歌单一起做，详见 `docs/profile-stats-plan.md` |
| 5 | 倍速功能未接线 | `audio_player_port.dart:17` 已定义 `setSpeed` | 接口层已就绪但 UI 无入口，设置页也没有开关 |

> 附带修掉一个**全站性**问题：`GlassSurface` 用裸 `Container` 做背景色，导致内部
> `ListTile` 的 ink splash 找不到最近的 `Material` 祖先 → Flutter 断言 + 涟漪不可见。
> 我的页所有卡片都受影响。已改为 `Material` 承载（阴影走 `elevation`），见 `common.dart`。

### P1 · 与参考项目的主要能力差

| # | 功能 | EchoMusic 实现 | kugo 现状 | 移动端建议 |
| --- | --- | --- | --- | --- |
| 6 | **搜索多维度** | `views/Search.vue`：歌曲/歌手/专辑/歌单/歌词/MV Tab | `search_repository.dart` 仅 `searchSongs` | 加 Tab，扩展 `searchSong` 接口的 `type` 参数 |
| 7 | **自建歌单** | 新建/改名/改标签/改简介/改封面/自动封面/自定义排序 | 无 | 移动端价值高，接 `playlist/add` 系列接口 |
| 8 | **收藏/订阅落库** | 歌单收藏、专辑收藏、歌手关注 | 只有「喜欢」一首歌（本地 + `/likes`） | 补齐 `playlist/subscribe`、`album/collect` 等 |
| 9 | **评论写入** | 发评论、查看楼层、回复指定评论 | 只读列表（`song_detail_page.dart:260`） | 可后置，但移动端发评体验天然更好 |
| 10 | **逐字歌词（YRC）** | `LyricScroller.vue` 支持 LRC/YRC | `core/utils/lrc_parser.dart` 仅 LRC 逐行 | 接口支持即可解析，提升「概念版气质」明显 |
| 11 | **歌词音译/注音** | v2.3.1 新增 | 无 | 字段已在 LRC 里时成本低 |
| 12 | **歌词换肤/写真** | `LyricSkinSettingsPanel.vue`、`PortraitMode.vue` | 无 | 移动端写真模式体验好，可二期 |
| 13 | **MV / 视频** | `views/details/MvDetail.vue`、`video.ts` | 无 | Track 模型已有 `hasMv` 字段但未用 |
| 14 | **分享** | 歌曲/歌单/专辑/歌手一键分享 | 无 | 移动端系统 share sheet 成本低、价值高 |
| 15 | **外部歌单导入** | 网易云/QQ/酷我/汽水/Spotify/Apple Music/截图导入 | 无 | 移动端截图导入很自然，可考虑 |

### P2 · 锦上添花

| # | 功能 | 说明 |
| --- | --- | --- |
| 16 | 音频增强（EQ / 响度 / 空间音效） | 移动端需原生 DSP，成本高；可先用 `just_audio` 生态的 `audio_session` 或平台音效 |
| 17 | 歌曲过渡 / 淡入淡出 | EchoMusic 有 `player transition` 设置；kugo 仅依赖系统 gapless |
| 18 | 音量/输出设备管理 | 移动端语义不同，通常不做 |
| 19 | 听歌识曲 | 麦克风采集 + 指纹匹配，成本高 |
| 20 | 一起听 | 需服务端房间，违背「不托管」原则 |
| 21 | 音乐云盘 | EchoMusic 有 `Cloud.vue` + `cloudUpload.ts` |
| 22 | 内容黑名单 | `contentBlacklist.ts`，可在 FM/推荐里屏蔽 |
| 23 | 听歌偏好设置 | `listeningPreferences.ts`，影响推荐 |
| 24 | 登录设备管理 | `loginDevices.ts`，查看/移除设备 |
| 25 | 个人资料编辑 | 头像/昵称修改 |
| 26 | 听歌时长上报 | `listenReport.ts` |
| 27 | 等级/乐龄展示 | 个人中心经验进度 |
| 28 | 主题背景透明/毛玻璃、主题色自定义 | kugo 已是 ThemeExtension 双主题，可扩展色相 |
| 29 | 应用内更新检查 | EchoMusic 内置版本检测 |
| 30 | 备份与恢复（设置/数据） | `ctx.backups` |

### P3 · 形态差异，明确不做

插件系统（含在线插件源、浮窗、插件任务）、桌面歌词窗口、系统托盘、全局快捷键、mini 模式、FM 弹幕、TCP/Graphics 插件 API、窗口控制。

---

## 三、kugo 相对 EchoMusic 的**优势项**（无需补齐）

- 移动端原生后台播放链路：`audio_service` + 媒体会话 + AVRCP（EchoMusic 靠 `echo-media-controls` addon，桌面场景不同）
- 锁屏 / 车机蓝牙歌词（近期 commit `d9d4c36` 专门修过 AVRCP 进度单调推送，桌面端无对应场景）
- 轻量：单 Flutter 代码库，无 Rust/FFmpeg 原生构建矩阵
- 概念版视觉（羊皮纸以外的深色沉浸 + 封面取色）已自成体系

---

## 四、建议的二期排期（依赖顺序）

```
第一步（已完成 3327499）：修 profile「定时停止/音质/关于」死入口
第一步续（1 天内可清）：修「本地音乐」「下载管理」死入口 + 假数字 + 倍速接线
第二步（1 周）：搜索多 Tab（歌手/专辑/歌单）
第三步（1 周）：自建歌单 CRUD + 收藏订阅
第四步（3–5 天）：逐字歌词 + 音译 + 分享
第五步（按需）：MV 播放、FM 黑名单、听歌偏好、登录设备管理
```

> 注：音频增强、听歌识曲、一起听、云盘建议明确划出二期范围甚至不做 —— 移动端成本与收益不匹配。
