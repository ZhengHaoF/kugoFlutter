# kugo Windows 端 vs EchoMusic — 功能对齐清单

> 对比日期：2026-09-23
> 基准：`D:\work\EchoMusic`（Electron + Vue3，Windows 桌面集成层）
> 对象：`D:\work\kugoFulutter\app`（Flutter，Windows runner + media_kit）
> 用途：Windows 桌面体验 backlog；与 `gap-vs-echomusic.md` 互补——那份偏内容/业务能力，本份专讲 **Windows 系统集成**。
>
> 历史说明：`gap-vs-echomusic.md` 曾把托盘、全局快捷键、桌面歌词等标为「形态差异，不追」，前提是 Android 优先。kugo 已有 Windows 壳后，该判断只对「桌面歌词窗口 / 插件浮窗」仍成立，其余需按桌面播放器底线重排。

---

## 一、结论速览

kugo 在 Windows 上目前只有：

| 已有 | 位置 |
| --- | --- |
| 能出声（media_kit / libmpv） | `features/player/media_kit_player.dart` |
| 桌面侧边栏 + 底部播控条 | `shared/shell/desktop_sidebar.dart`、`desktop_player_bar.dart` |
| 窗口内快捷键（空格 / ←→ 快退快进） | `shared/shell/root_shell.dart` |
| 深色标题栏（`DWMWA_USE_IMMERSIVE_DARK_MODE`） | `windows/runner/win32_window.cpp` |
| 微软雅黑 | `core/theme/kugo_theme.dart` |
| Windows 音频探针工具 | `tool/windows_audio_probe.dart` |

EchoMusic 的 Windows 专属能力几乎整层缺失：**SMTC、托盘、任务栏增强、独立迷你窗、全局快捷键、窗口材质、自启动/关托盘**。

```text
听歌闭环（出声/队列/歌词）     ████████████  已对齐
应用内桌面布局（侧栏+底栏）   ████████████  已对齐
系统媒体 / 按键 / 托盘        ░░░░░░░░░░░░  全缺
任务栏增强（Thumbar 等）      ░░░░░░░░░░░░  全缺
独立窗口形态（Mini/桌面歌词） ░░░░░░░░░░░░  全缺
窗口材质 / 状态 / 缩放        ██░░░░░░░░░░  仅深色标题栏
```

---

## 二、未对齐清单

### P0 · 听歌时直接缺的能力

| # | 功能 | EchoMusic 实现 | kugo 现状 | 说明 |
| --- | --- | --- | --- | --- |
| 1 | **系统媒体控制 SMTC** | `native/echo-media-controls` + `main/mediaControls.ts`：媒体键、进度、封面 thumbnail、音频类别 | `core/platform.dart` 的 `hasSystemMediaSession=false`；`main.dart` 整段跳过 `audio_service` | **媒体键、蓝牙耳机按键、系统媒体卡全无**。桌面播放器底线能力 |
| 2 | **系统托盘** | `main/tray.ts` + `ipc/tray.ts`：图标、播放状态同步、播放模式、音量、显示/隐藏主窗、桌面歌词开关/锁定、退出 | 无 | 无法后台驻留 |
| 3 | **关闭行为** | `closeBehavior: 'tray' \| quit`，设置可选 | 无设置，点关闭即退出 | 依赖托盘 |
| 4 | **全局快捷键** | `ipc/shortcuts.ts` + `renderer/utils/shortcuts.ts`：15 项命令，窗口内 + 全局双轨，逐项录制与恢复默认；Windows 本地快捷键绕过输入法抢占 | 仅窗口内 3 键（空格 / ±5s） | 焦点不在窗口时按键无效；无录制 UI |

### P1 · 任务栏 / 窗口形态（Windows 专属）

| # | 功能 | EchoMusic 实现 | kugo 现状 |
| --- | --- | --- | --- |
| 5 | **Thumbar 播控按钮** | `main/thumbar.ts`：上一曲 / 播放暂停 / 下一曲 + 收藏；纯 JS 生成抗锯齿图标 | 无 |
| 6 | **任务栏进度条** | `main/taskbarProgress.ts`：normal / paused / indeterminate / none，节流更新 | 无 |
| 7 | **任务栏封面预览** | `main/taskbarThumbnail.ts` + `taskbarCard.ts`：DWM iconic 缩略图 + Aero Peek 实时预览；窗口标题「歌手 - 歌名」 | 无 |
| 8 | **任务栏快捷播控横条** | `main/taskbarMediaBar.ts` + `taskbarDock.ts` + `taskbarShell.ts`：贴任务栏空闲区，可拖出小窗；详见 Echo `docs/windows-taskbar-player.md` | 无 |
| 9 | **独立迷你播放器窗口** | `main/miniPlayer.ts`：无边框透明、置顶、跳过任务栏、收起/展开、位置记忆 | 仅应用内 `DesktopPlayerBar` / `MiniPlayerBar`，无独立窗 |
| 10 | **窗口材质** | `window/windowsComposition.ts` + `backgroundMaterial.ts`：Win11 Mica/clear、Acrylic、Accent；拖动时暂停 Acrylic；legacy 帧修复 | 标准 Flutter 窗 + 深色标题栏，无透明 / 毛玻璃 |
| 11 | **自定义标题栏 / 全屏按钮 / 界面缩放** | `window/titleBar.ts` overlay、全屏钮开关、Ctrl± 缩放并持久化（`window/zoom.ts`） | 系统标题栏；无缩放 |
| 12 | **记住窗口大小位置** | `windowBoundsPersistence.ts`，会话结束前落盘 | 每次启动默认尺寸 |

### P2 · 系统行为 / 播放引擎增强

| # | 功能 | EchoMusic 实现 | kugo 现状 |
| --- | --- | --- | --- |
| 13 | **开机自启动 + 启动最小化到托盘** | 设置项 `autoLaunch`、`startMinimized` | 无 |
| 14 | **电源管理** | `powerMonitor.ts`：播放防休眠、挂起暂停 / 唤醒恢复、解锁屏兜底 | 无 |
| 15 | **会话结束落盘** | `systemShutdown.ts`：关机前写窗口状态 | 队列有持久化，无会话钩子 |
| 16 | **音频输出设备 / 独占模式** | `echo-audio-player`：WASAPI 设备枚举、热插拔、独占输出 | media_kit 默认输出，无设备管理 |
| 17 | **倍速** | 播放栏 0.1x–5x | `audio_player_port.dart` 已有 `setSpeed`，UI 未接线（见 `gap-vs-echomusic.md` #5） |

### 明确可暂缓

| 功能 | 理由 |
| --- | --- |
| 桌面歌词独立窗口 | 需多窗口 + 置顶 + 透明；Flutter 成本高，原 gap 文档 P3 仍成立 |
| 插件浮窗 / 插件系统 | 一期明确不做 |
| 任务栏 layout 外挂 helper（`TaskbarLayout.cs`）完整对等 | 仅服务「播控横条」贴任务栏；横条本身可暂缓 |

---

## 三、EchoMusic 参考入口（行为规格，不必移植实现）

| 能力 | 主要源文件 | 配套 |
| --- | --- | --- |
| SMTC | `src/main/mediaControls.ts`、`native/echo-media-controls/src/sys_media/windows.rs` | `src/main/nowPlaying.ts` |
| 托盘 | `src/main/tray.ts`、`src/main/ipc/tray.ts` | `src/shared/tray.ts` |
| Thumbar | `src/main/thumbar.ts` | `renderer/stores/player.ts` 播放态同步 |
| 任务栏进度 | `src/main/taskbarProgress.ts` | 设置 `taskbarProgress` |
| 任务栏封面预览 | `src/main/taskbarThumbnail.ts`、`taskbarCard.ts` | 设置 `taskbarCoverPreview` |
| 任务栏播控横条 | `src/main/taskbarMediaBar.ts`、`taskbarDock.ts`、`taskbarShell.ts` | `docs/windows-taskbar-player.md`、`taskbar-player.html` |
| 迷你播放器 | `src/main/miniPlayer.ts` | `renderer/miniPlayer/` |
| 全局快捷键 | `src/main/ipc/shortcuts.ts`、`renderer/utils/shortcuts.ts` | 设置「快捷键」分区 |
| 窗口材质 | `src/main/window/windowsComposition.ts`、`backgroundMaterial.ts` | `src/shared/windowBackground*.ts` |
| 关闭/自启/最小化 | `src/main/window/index.ts`、`src/renderer/views/settings/components/WindowSettingsSection.vue` | 设置「窗口与启动」分区 |
| 窗口状态持久化 | `src/main/windowBoundsPersistence.ts` | |
| 电源 / 关机 | `src/main/powerMonitor.ts`、`systemShutdown.ts` | |

设置侧对照：Echo「窗口与启动」分区 = 界面缩放、记住窗口大小、全屏按钮、任务栏封面预览、任务栏进度条、任务栏快捷播控、关闭行为、开机自启、启动时最小化。

---

## 四、建议对齐顺序

```text
① SMTC + 媒体键              ← 不做等于 Windows 不能当播放器用
② 托盘 + 关闭到托盘 + 开机自启
③ 全局快捷键（可先 5 项：播停 / 上下曲 / 音量）
④ Thumbar + 任务栏进度条      ← 原生 Win32，Flutter 走 MethodChannel
⑤ 独立 Mini 窗口
⑥ 窗口材质 / 记住窗口 / 界面缩放
⑦ 任务栏封面预览 / 播控横条    ← 最重，可最后
```

依赖关系简述：

- ② 依赖托盘图标与窗口 show/hide 通道；① 可与 ② 并行。
- ④ 依赖 ① 的播放状态源（isPlaying / position / track），图标与进度更新宜节流。
- ⑤ 依赖窗口管理能力（置顶、跳过任务栏、无边框）；可与 ④ 并行。
- ⑦ 的「封面预览」依赖封面缓存已有（`core/cache/cover_cache.dart`）；「播控横条」额外需要任务栏几何探测，工作量最大。

---

## 五、落地路径备忘

| 路线 | 适用 | 备注 |
| --- | --- | --- |
| Flutter 插件先铺骨架 | ②③⑤⑥ | 常见组合：`tray_manager`、`window_manager`、`hotkey_manager`、`launch_at_startup`、`bitsdojo_window` / `flutter_acrylic`。注意 Windows 实现质量参差，上线前需实测 |
| `windows/runner` + MethodChannel 自研 | ①④ 及需要精确控制的部分 | SMTC 用 `Windows.Media.Control`（WinRT）；Thumbar / 进度条用 `ITaskbarList3`；封面预览用 DWM iconic thumbnail API |
| 暂不做 | 桌面歌词窗、插件浮窗、taskbar layout helper | 见「明确可暂缓」 |

约束提醒：

- Windows 上 `audio_session` / `audio_service` 均无实现（见 `core/platform.dart` 注释），SMTC 必须另起原生通道，不能指望现有 bridge。
- media_kit（libmpv）只负责解码输出；媒体键 / 系统媒体卡 / 任务栏状态都不在它职责内。
- 托盘与「关闭到托盘」应一起设计：先有托盘再改关闭行为，避免用户关窗后进程残留却找不到入口。

---

## 六、验收口径（对齐完成后）

| 项 | 及格标准 |
| --- | --- |
| 媒体键 | 耳机 / 键盘媒体键可播停、上下曲；系统音量浮层或媒体卡可见曲名封面 |
| 托盘 | 关窗后进程在托盘；托盘菜单可播停 / 显示主窗 / 退出；播放中图标或 tooltip 可反映状态 |
| 全局快捷键 | 焦点在其他窗口时仍可播停；设置页可开关 |
| Thumbar | 悬停任务栏图标出现上一曲 / 播停 / 下一曲，点击有效 |
| 任务栏进度 | 播放中任务栏图标有进度，暂停态可区分 |
| Mini 窗 | 可从主窗切出，置顶，能播停切歌，关闭后回主窗 |
| 关闭行为 | 选「托盘」时关窗不退出；选「退出」时进程结束 |
| 开机自启 | 注销重登后应用可自动启动（设置可关） |

---

## 七、相关文档

| 文档 | 内容 |
| --- | --- |
| `gap-vs-echomusic.md` | 全端业务能力差距（搜索多维、歌单 CRUD、逐字歌词等） |
| `设计方案.md` | 移动端原方案；其中「平台能力」表按 Android 写，Windows 以本文为准 |
| Echo `docs/features.md` §12 | Echo 桌面集成能力明细 |
| Echo `docs/windows-taskbar-player.md` | 任务栏播控横条行为与验收 |
