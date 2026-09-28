# kugoFlutter vs EchoMusic — 功能差距清单

> 对比日期：2026-09-19 · **状态按代码刷新：2026-09-28（并入 Windows 系统集成）**
> 基准：`D:\work\EchoMusic`（Electron + Vue3，v2.3.2-beta.5）
> 对象：`D:\work\kugoFulutter\app`（Flutter，Android + Windows）
> 用途：作为 kugo 的二期 backlog 输入（业务能力 + Windows 系统集成；原 `windows-gap-vs-echomusic.md` 已并入 §三）

---

## 一、结论速览

| 维度 | kugo 现状 | EchoMusic | 差距 |
| --- | --- | --- | --- |
| 核心听歌闭环 | 完整（登录、搜索、播放、歌单/专辑/歌手、FM、榜单、每日推荐、歌词、评论、设置、云端我喜欢/收藏） | 完整 | 已对齐 |
| 内容形态 | 音频 + **MV（简版）** | 音频 + MV + 动态封面 + 云盘 | MV 缺播控/收藏/弹幕；缺云盘 |
| 社交与互动 | 评论读写（歌曲/歌单/专辑）+ 楼层 + 分类/热词 + 弹幕 + 点赞（网易） | 评论读写 + 楼层 + 弹幕 | 基本对齐；余楼层内二次回复、收藏数 |
| 用户资产管理 | 收藏/关注/云端我喜欢同步；**缺自建歌单 CRUD** | 自建歌单增删改 + 排序 + 封面编辑 | 缺歌单写入 |
| 歌词 | **LRC + KRC 逐字**（卡拉 OK 着色）+ 译文 + 音译副行 + 字号/行间距滑块 | LRC/YRC 逐字 + 音译 + 换肤 + 写真 + 桌面歌词 + 弹幕 | 缺换肤/写真/桌面歌词 |
| 音效 | 无 | 10 段 EQ + LUFS + 空间音效 + DSP 热插拔 | 缺音效引擎 |
| 播放能力 | 队列/模式/音质/定时 | + 倍速 + 歌曲过渡 + 音量 + 输出设备 + 独占 | 缺倍速 UI（Port/引擎已有） |
| 搜索 | **歌曲/歌单/专辑/歌手/MV** 五 Tab | 歌曲/歌手/专辑/歌单/歌词/MV 六维 | 缺歌词（接口 404） |
| 分享 | 无 | 全内容分享 | 缺 |
| 扩展性 | 无 | 完整插件系统 + DSP Provider | 一期不做（已规划） |
| 平台集成 | Android 锁屏/通知栏 + SMTC；Windows 桌面壳 + SMTC/托盘/Thumbar/进度条 | 托盘、全局快捷键、mini 模式、桌面歌词 | Windows 余全局快捷键、Mini 窗、材质、自启（§三） |

---

## 二、按优先级排列的缺口

### P0 · 纯 bug / 假入口

| # | 问题 | 位置 | 状态 |
| --- | --- | --- | --- |
| 1 | 「本地音乐」 | `profile_page.dart` | ✅ **已砍**（2026-09）：占位入口从 UI 移除。EchoMusic 侧**同样没有**该功能（只有 `main/localMusic.ts` 等 270 行无人调用的扫描地基）；若将来要做，另立需求，不按「对齐 EchoMusic」立项 |
| 2 | 「下载管理」 | `profile_page.dart` | ✅ **已砍**（2026-09）：占位入口从 UI 移除。参考项目**无任何实现**（其「下载」仅指更新包/音效/插件/封面），自研成本远高于收益 |
| 3 | 「定时停止 / 音质设置 / 关于」不可点 | `profile_page.dart` | ✅ **已修**：`settings_pickers.dart` 共享；带当前值；「关于」弹层 |
| 4 | 「歌单」统计硬编码 | `profile_page.dart` | ✅ **已修**：我喜欢/最近播放/歌单三数皆真值（`countHistory` + `/user/playlist` 经 `user_collections_controller`）；未就绪显 `—` |
| 5 | 倍速未接线 | `audio_player_port.dart` | ⬜ `setSpeed` 在 just_audio / media_kit 均已实现，**仍无 UI 入口** |
| 5.5 | 「点歌手」传名字当 id | 多处 `onArtistTap` | ✅ **已修**：`Track.artistId` + `artistTapFor()` 统一跳 `/artist/:id` |

> 附带修掉一个**全站性**问题：`GlassSurface` 用裸 `Container` 做背景色，导致内部
> `ListTile` 的 ink splash 找不到最近的 `Material` 祖先 → Flutter 断言 + 涟漪不可见。
> 我的页所有卡片都受影响。已改为 `Material` 承载（阴影走 `elevation`），见 `common.dart`。

### P1 · 与参考项目的主要能力差

| # | 功能 | EchoMusic 实现 | kugo 现状 | 移动端建议 |
| --- | --- | --- | --- | --- |
| 6 | **搜索多维度** | 六 Tab | ✅ **已落地** 五 Tab（歌曲/歌单/专辑/歌手/**MV**）；歌词接口 404 不做。字段见 `api-notes.md` |
| 7 | **自建歌单** | 新建/改名/改标签/改简介/改封面/排序 | 云端歌单可浏览/收藏同步；**无写入 CRUD** | 移动端价值高，接 `playlist/add` 系列接口 |
| 8 | **收藏/订阅落库** | 歌单收藏、专辑收藏、歌手关注 | ✅ **大部分已落地**：云端我喜欢、收藏歌单/专辑、关注歌手（`user_collections_controller`） |
| 9 | **评论写入** | 发评论、楼层、回复 | ✅ **已落地**（酷狗 + 网易）：发评论 / 楼层回复 /（网易）点赞；歌曲 + 歌单 + 专辑三池。余项见下方「评论余项」 | — |
| 10 | **逐字歌词** | LRC/YRC | ✅ **已落地**：KRC 逐字 + 卡拉 OK 已唱着色（`krc_parser` / `LyricLine.chars`） | 余：换肤/写真 |
| 11 | **歌词音译/注音** | 有 | ✅ **已落地**：KRC `[language:]` type=0 罗马音副行 + 设置开关 | — |
| 12 | **歌词换肤/写真** | 有 | 无 | 可二期 |
| 13 | **MV / 视频** | 详情页 + 收藏 + 弹幕 + 多版本切换 + 原生播控 | 🟡 **简版已落地**：取流协议、搜索 MV Tab、歌曲详情入口、`/mv` 播放页（media_kit + **播控** + 清晰度切换保进度）、详情统计/简介弹层、**多版本切换**、**MV 收藏**、**歌手 MV 横滑条**、mapper 单测。余：弹幕、MV 评论 |
| 14 | **分享** | 全内容 | 无 | 系统 share sheet 成本低 |
| 15 | **外部歌单导入** | 多平台 | 无 | 可考虑 |

#### 评论余项（原 `评论接入评估.md` 未做项，2026-09-28 迁入）

| # | 项 | 说明 | 建议 |
| --- | --- | --- | --- |
| 9.1 | **带 token 真机发一条评论** | 写口链路（lite 参数 + `key` 签名 + `index.php` 路由）已用空正文探针验证通过，但从未用真实账号发出过内容。需要使用者本人点一次，会产生真实评论 | 接入验收时做，不占开发排期 |
| 9.2 | **回复楼层内的某条回复** | 当前只支持「在主评论下发新回复」（`is_t=1` / `pid=0`）。上游可用 `is_t=0` + `pid=target.id` 挂到楼层内某条回复下 | 低频，可后置 |
| 9.3 | **收藏数** | `favorite_count`（`/count/v1/audio/mget_collect`，按 `mixsongids` 批量）文档评估过、从未实现；评论数已有 | 有展示需求再做 |
| 9.4 | **SSA 20028 指纹验证（`sidedt`）** | 有意不做：依赖 14KB 浏览器指纹模拟，Dart 移植成本高且易失效。当前只给降级文案「需在酷狗官方客户端完成安全验证」 | **维持不做**，除非风控大面积拦截写口 |

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

插件系统（含在线插件源、浮窗、插件任务）、桌面歌词独立窗口、FM 弹幕、TCP/Graphics 插件 API。

> 系统托盘 / 全局快捷键 / mini 窗**不再**算形态差异：托盘与 Thumbar 已落地，其余 Windows 集成缺口见 §三。

---

## 三、Windows 系统集成

> 原 `windows-gap-vs-echomusic.md` 专册，2026-09-28 并入。基准为 EchoMusic 的 Windows 桌面集成层
> （`src/main/*`、`window/*`、`native/echo-media-controls`）；行为规格可参考其实现，不必移植。
>
> 历史说明：P3 曾把托盘 / 全局快捷键 / mini 模式标为「形态差异，不追」，前提是 Android 优先。
> 有 Windows 壳后，该判断只对「桌面歌词窗 / 插件浮窗」仍成立，其余按桌面播放器底线重排。

### 已落地（桌面播放器底线）

| 能力 | 位置 |
| --- | --- |
| media_kit / libmpv 出声 | `features/player/media_kit_player.dart` |
| 桌面侧边栏 + 底部播控条 | `shared/shell/desktop_sidebar.dart`、`shared/widgets/desktop_player_bar.dart` |
| 窗口内快捷键（空格 / ←→ ±5s） | `shared/shell/root_shell.dart` |
| 深色标题栏（`DWMWA_USE_IMMERSIVE_DARK_MODE`） | `windows/runner/win32_window.cpp` |
| 系统媒体 SMTC / 媒体键 / 系统媒体卡 | `audio_service` + `audio_service_win`；`features/player/audio_service_handler.dart`；`core/platform.dart` `hasSystemMediaSession` |
| 系统托盘（图标 / 菜单 / 播控 / 模式 / 音量 / 退出） | `shared/tray/desktop_tray.dart`、`shared/tray/desktop_shell.dart` |
| 关闭到托盘（每次询问 / 最小化到托盘 / 退出应用，默认询问） | `settings_controller.closeBehavior` + `close_behavior_dialog.dart`；旧 `closeToTray` 自动迁移 |
| Thumbar 播控 4 钮（上一曲 / 播停 / 下一曲 / **收藏**） | `windows/runner/taskbar_host.cpp` + `shared/taskbar/taskbar_bridge.dart` |
| 任务栏进度条（normal / paused / indeterminate / none，可关） | 同上；Dart 侧 200ms 节流 |
| 窗口自由缩放 + 启动夹到工作区 | `win32_window.cpp`（4:3 约束已去掉） |
| 音频探针工具 / 托盘图标 | `tool/windows_audio_probe.dart`、`assets/tray_icon.ico` |

### 缺口

| # | 功能 | 现状 | 优先级 |
| --- | --- | --- | --- |
| W1 | **全局快捷键** | 仅窗口内 3 键；焦点不在窗口时媒体键外无热键，无录制 UI | **P0 首位** |
| W2 | 任务栏封面预览 / 窗口标题曲名 | 标题固定 `kugo`（`main.cpp` + `desktop_shell` 两处），未随曲目更新 | P1 |
| W3 | 任务栏快捷播控横条 | 无（Echo `taskbarMediaBar` / `taskbarDock`） | P1，工作量最大 |
| W4 | 独立迷你播放器窗口 | 仅应用内 `DesktopPlayerBar` / `MiniPlayerBar` | P1 |
| W5 | 窗口材质（Mica / Acrylic） | 标准 Flutter 窗 + 深色标题栏 | P1 |
| W6 | 自定义标题栏 / 全屏钮 / 界面缩放 Ctrl± | 系统标题栏 | P1 |
| W7 | 记住窗口大小位置 | 每次启动 `main.cpp` 固定 1280×960 居中 | P1 |
| W8 | 开机自启 + 启动最小化到托盘 | 无（`pubspec` 无 `launch_at_startup`） | P2 |
| W9 | 电源管理（播放防休眠 / 挂起暂停 / 唤醒恢复） | 无 | P2 |
| W10 | 音频输出设备 / 独占模式 | media_kit 默认输出 | P2 |
| W11 | 倍速 UI | 与 P0 #5 同一缺口：Port/引擎已有 `setSpeed` | P2 |

**窗口约束（续做别改错）**：自由缩放（原 4:3 已移除）。最小尺寸是**双层**——win32 `WM_GETMINMAXINFO` 外框 **840×600** + `window_manager` `minimumSize` **900×640**（兜住 `isDesktopView` 的 800px 断点，生效取更严者）。启动 1280×960 逻辑像素，按 monitor DPI 夹到工作区；`desktop_shell` 刻意不设 `size`/`center`，避免运行中重置用户调过的尺寸。

### 落地备忘（踩过的坑）

- **SMTC 不必自研 WinRT**：`audio_service_win` 覆盖媒体键 / 系统媒体卡 / 进度；`KugoAudioHandler` 已按 AVRCP 语义推送 3 槽 carousel。只缺缩略图质量或音频类别时再补 `Windows.Media.Control` 旁路。
- **`audio_session` 仍无 Windows 实现**（`hasAudioFocusSession=false`），不要在 Windows 路径调 `AudioSession.instance`。
- **退桌别用 `windowManager.destroy()`**：Windows 上它只 `PostQuitMessage(0)`，跳过窗口销毁与引擎收尾，进程卡住不退出（leanflutter/window_manager#478 / #502 / #590）。`DesktopShell.quit()` 走 `setPreventClose(false)` + `windowManager.close()` 标准路径。
- **托盘与关闭行为同居 `DesktopShell`**：`setPreventClose(true)` 统一拦截，`closeBehavior` 决定 hide / `quit()` / 弹窗；托盘「退出」直接 `quit()` 不再二次询问；`_closePromptOpen` 防止叠出多个对话框。
- **任务栏通道双向**：Dart → `updateButtons` / `updateProgress` / `refresh`；原生 → `thumbarEvent`（`previous` / `playPause` / `next` / `favorite`）。`TaskbarCreated` 与窗口 restore 都要 Refresh。
- **进度节流双层**：Dart 200ms + 1‰ 门槛；C++ 再做 mode/permille 去重；paused 最低 10‰ 避免黄条看不见。
- **Thumbar 收藏**：`favorite` → `taskbar_bridge` → `likes_controller`；心形 filled/outline 双 glyph。
- media_kit（libmpv）只负责解码输出；媒体键 / SMTC / 任务栏状态都不在它职责内。

### 建议顺序

```text
✅ SMTC + 媒体键
✅ 托盘 + 关闭到托盘
✅ Thumbar（含收藏）+ 任务栏进度条
⬜ ① 全局快捷键（可先 5 项：播停 / 上下曲 / 音量）  ← 当前首位
⬜ ② 窗口材质 / 记住窗口 / 界面缩放
⬜ ③ 独立 Mini 窗口
⬜ ④ 任务栏封面预览 / 播控横条                ← 最重，可最后
⬜ ⑤ 开机自启 / 电源 / 输出设备 / 倍速 UI
```

依赖简述：① 无硬依赖，`hotkey_manager` 或 `RegisterHotKey` 原生通道，与窗口内 `Shortcuts` 分轨。②「记住窗口」在 `DesktopShell` 的 `WindowListener` 落盘 bounds 即可（无比例约束）；材质走 DWM 或评估 `bitsdojo_window` / `flutter_acrylic`。③ 依赖 `window_manager` 置顶/跳过任务栏/无边框。④ 封面预览依赖 `core/cache/cover_cache.dart` 与窗口标题同步；横条还要任务栏几何探测。⑤ 自启用 `launch_at_startup`，电源用 `SetThreadExecutionState` 原生通道。

### 明确可暂缓（Windows）

桌面歌词独立窗口、插件浮窗、taskbar layout helper（`TaskbarLayout.cs`）、托盘菜单里的桌面歌词开关/锁定。

### 验收口径（抽查）

| 项 | 及格标准 |
| --- | --- |
| 媒体键 / SMTC | 耳机/键盘媒体键可播停切歌；系统媒体卡可见曲名封面 |
| 托盘 | 关窗后进程在托盘；菜单可播停 / 显示主窗 / 退出 |
| 关闭行为 | 默认弹窗可选退出/到托盘；「记住我的选择」重启仍生效；旧设置能迁移 |
| Thumbar / 进度 | 四钮点击有效、收藏态与应用内一致；进度可关 |
| 全局快捷键（待） | 焦点在其他窗口仍可播停；设置可开关 |
| 记住窗口 / 缩放（待） | 重启恢复；Ctrl± 可缩放并持久化 |

---

## 四、kugo 相对 EchoMusic 的**优势项**（无需补齐）

- 移动端原生后台播放链路：`audio_service` + 媒体会话 + AVRCP（EchoMusic 靠 `echo-media-controls` addon，桌面场景不同）
- 锁屏 / 车机蓝牙歌词（近期 commit `d9d4c36` 专门修过 AVRCP 进度单调推送，桌面端无对应场景）
- 轻量：单 Flutter 代码库，无 Rust/FFmpeg 原生构建矩阵
- 概念版视觉（羊皮纸以外的深色沉浸 + 封面取色）已自成体系

### 通知栏/锁屏「歌曲信息卡」验收

> 产品命题：播放时，系统下拉菜单栏里应出现歌曲信息卡片。  
> 本节钉住**既有** `audio_service` 媒体会话行为（验收，非新功能）。自动化断言见 `app/test/audio_service_handler_test.dart`。

| 项 | 标准 |
| --- | --- |
| 表面 | Android **系统通知栏** + **锁屏**（同一 `MediaItem`/`PlaybackState`）；车机 AVRCP 不绑进本条 |
| 及格字段 | 曲名 + 歌手 + 封面 + 进度/时长 + 至少播放/暂停（上一首/下一首由实现提供，非本条底线） |
| 生命周期 | 有 `track` 且会话未 `idle`（**播放中与暂停中**）必须有卡；允许消失：用户滑掉通知、主动 stop、系统杀进程 |
| 封面 | `MediaItem.artUri` 非空且指向该曲 cover 即 pass；实机大图空白先重试/清缓存，仍无图再记问题 |
| FM | 与普通曲目**同等验收**（同一 handler，无特例） |
| 前置条件 | 测试机 **通知权限已授予**；权限被拒/系统关通知 → 不算产品 fail |
| 歌词副标题 | 主路径在设置 **「锁屏/蓝牙显示歌词」关闭** 时测（`artist == track.artist`）；开启时副标题可为「歌手 · 歌词」，另条观察，不挡本条 |
| 范围外 | App 内 MiniBar/下拉面板、定制系统通知布局、授权引导 UI、AVRCP 专项 |

**实机抽测（人工）**

1. 授予通知权限，播放任意歌曲（含私人 FM）。
2. 下拉系统通知栏：可见大媒体卡（封面、曲名、歌手、进度、播放/暂停）。
3. 锁屏：可见同等歌曲信息与控制。
4. 暂停后再下拉：卡片信息仍在（非整卡消失）。
5. 滑掉通知：允许消失且暂停；再次在 App 内播放应能重新出现卡片。

---

## 五、建议的二期排期（依赖顺序）

```
✅ 已清：profile 死入口 / 假数字 / 歌手 id / 搜索多 Tab / 收藏订阅 / 云端我喜欢
✅ MV 核心播放闭环（2026-09）：取流协议 + 搜索 Tab + 歌曲详情入口 + /mv 播放页 + 清晰度切换（余项见 P1 #13）
✅ MV 收尾（2026-09-28）：播控 / 详情区 / 多版本 / 收藏 / 歌手 MV 条 / mapper 单测；余弹幕与 MV 评论
✅ 已砍：本地音乐 / 下载管理两个占位入口（2026-09，UI 已移除，见 P0 #1 #2）
✅ 多音源阶段 A（M5）已完成：MusicSource / KugouSource / platform 身份（见 多音源接入方案.md §8.1）
✅ 逐字歌词 + 音译副行已完成（KRC）
✅ 歌词字号 / 行间距可调已完成（播放页「歌词显示」弹层连续滑块，双端同一套值）
✅ 评论读写已完成（酷狗 P0–P2 + 网易 N1–N3：列表/排序/楼层/评论数/发评/回复/分类热词/弹幕/铭牌/点赞；余项见 P1 #9 评论余项）

当前排期主线：产品二期（M6）或网易云接口调试（另文）
  —— 酷狗音源抽象已收口；功能页仍有部分直接走 Repository，第二源接入时再收薄。

产品二期 backlog（未排期，另立 M6）：
  倍速 UI（0.5d）/ 自建歌单 CRUD（5d）/ 分享（1d）
  另：歌单封面/排序、MV 弹幕/评论、听歌偏好、登录设备管理
  评论余项（真机发评验收 / 楼层内二次回复 / 收藏数）见 P1 #9，均不阻塞主线
  Windows 集成余项（全局快捷键 / Mini 窗 / 材质 / 自启…）见 §三，与上列可并行
```

> 注：音频增强、听歌识曲、一起听、云盘建议明确划出二期范围甚至不做 —— 移动端成本与收益不匹配。
> 私人 FM 细项见 `personal-fm-vs-echomusic.md`；Windows 系统集成见本文 §三。
