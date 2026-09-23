# kugo Windows 端 vs EchoMusic — 功能对齐清单

> 对比日期：2026-09-23 · **状态按代码刷新：2026-09（本轮）**
> 基准：`D:\work\EchoMusic`（Electron + Vue3，Windows 桌面集成层）
> 对象：`D:\work\kugoFulutter\app`（Flutter，Windows runner + media_kit）
> 用途：Windows 桌面体验 backlog；与 `gap-vs-echomusic.md` 互补——那份偏内容/业务能力，本份专讲 **Windows 系统集成**。
>
> 历史说明：`gap-vs-echomusic.md` 曾把托盘、全局快捷键、桌面歌词等标为「形态差异，不追」，前提是 Android 优先。kugo 已有 Windows 壳后，该判断只对「桌面歌词窗口 / 插件浮窗」仍成立，其余需按桌面播放器底线重排。

---

## 一、结论速览

**本轮相对初版的实质变化**：P0 底线能力（SMTC / 托盘 / 关闭到托盘）与 Thumbar / 任务栏进度条已落地。Windows 现在可以当「能后台驻留 + 有系统媒体控制」的播放器用；剩余缺口集中在**全局快捷键、独立窗口形态、窗口材质/状态、自启与电源**。

| 已有 | 位置 |
| --- | --- |
| 能出声（media_kit / libmpv） | `features/player/media_kit_player.dart` |
| 桌面侧边栏 + 底部播控条 | `shared/shell/desktop_sidebar.dart`、`shared/widgets/desktop_player_bar.dart` |
| 窗口内快捷键（空格 / ←→ 快退快进） | `shared/shell/root_shell.dart` |
| 深色标题栏（`DWMWA_USE_IMMERSIVE_DARK_MODE`） | `windows/runner/win32_window.cpp` |
| 微软雅黑 | `core/theme/kugo_theme.dart` |
| **系统媒体 SMTC / 媒体键 / 系统媒体卡** | `audio_service` + `audio_service_win`；`features/player/audio_service_handler.dart`；`core/platform.dart` 的 `hasSystemMediaSession` 含 Windows |
| **系统托盘**（图标 / 菜单 / 播控 / 模式 / 音量 / 退出） | `shared/tray/desktop_tray.dart`、`shared/tray/desktop_shell.dart` |
| **关闭到托盘**（三态设置：每次询问 / 最小化到托盘 / 退出应用，默认**每次询问**） | `settings_controller.closeBehavior` + 设置页「窗口」 + 关闭弹窗（`close_behavior_dialog.dart`） |
| **Thumbar 播控**（上一曲 / 播停 / 下一曲） | `windows/runner/taskbar_host.cpp` + `shared/taskbar/taskbar_bridge.dart` |
| **任务栏进度条**（normal / paused / indeterminate / none） | 同上；Dart 侧 200ms 节流 |
| Windows 音频探针工具 | `tool/windows_audio_probe.dart` |
| 托盘图标资源 | `app/assets/tray_icon.ico` |

仍缺：

| 缺口 | 影响 |
| --- | --- |
| 全局快捷键 | 焦点不在窗口时媒体键外无应用热键 |
| 任务栏封面预览 / 窗口标题曲名 | 任务栏 hover 只有系统缩略图 |
| 任务栏播控横条 | 无贴任务栏迷你条 |
| 独立迷你播放器窗口 | 仅应用内 `DesktopPlayerBar` / `MiniPlayerBar` |
| 窗口材质（Mica / Acrylic） | 标准 Flutter 窗 + 深色标题栏 |
| 自定义标题栏 / 全屏钮 / 界面缩放 | 系统标题栏；无 Ctrl± |
| 记住窗口大小位置 | 每次启动固定 4:3 1280×960 居中 |
| 开机自启 + 启动最小化 | 无 |
| 电源管理（防休眠 / 挂起恢复） | 无 |
| 音频输出设备 / 独占模式 | media_kit 默认输出 |
| 倍速 UI | `setSpeed` 在 Port/引擎已有，无入口 |

```text
听歌闭环（出声/队列/歌词）     ████████████  已对齐
应用内桌面布局（侧栏+底栏）   ████████████  已对齐
系统媒体 SMTC / 媒体键        ████████████  已对齐（audio_service_win）
托盘 + 关闭到托盘             ████████████  已对齐
任务栏 Thumbar + 进度条       ███████████░  已对齐（无收藏钮）
全局快捷键                    ░░░░░░░░░░░░  全缺
独立窗口形态（Mini/桌面歌词） ░░░░░░░░░░░░  全缺
任务栏封面预览 / 播控横条     ░░░░░░░░░░░░  全缺
窗口材质 / 状态 / 缩放        ██░░░░░░░░░░  仅深色标题栏 + 4:3 约束
自启 / 电源 / 设备 / 倍速 UI  ░░░░░░░░░░░░  全缺
```

---

## 二、未对齐清单

图例：✅ 已落地 · ⬜ 未做 · 🟡 部分

### P0 · 听歌时直接缺的能力

| # | 功能 | EchoMusic 实现 | kugo 现状 | 说明 |
| --- | --- | --- | --- | --- |
| 1 | **系统媒体控制 SMTC** | `native/echo-media-controls` + `main/mediaControls.ts`：媒体键、进度、封面 thumbnail、音频类别 | ✅ **已落地**：Windows 走 `audio_service_win`；`hasSystemMediaSession` 含 Windows；`KugoAudioHandler` 推送曲名/歌手/专辑/时长/`artUri` 封面与进度 | 媒体键、系统媒体卡可用。音频焦点（`audio_session`）Windows 仍无实现（`hasAudioFocusSession=false`） |
| 2 | **系统托盘** | `main/tray.ts` + `ipc/tray.ts`：图标、播放状态同步、播放模式、音量、显示/隐藏主窗、桌面歌词开关/锁定、退出 | ✅ **已落地**：`DesktopTray`（`tray_manager`）左键显示主窗、右键菜单；含播停/上下曲/播放模式/音量/退出 | 无桌面歌词项（按「可暂缓」故意去掉）；tooltip 固定 `kugo`，未跟播放态 |
| 3 | **关闭行为** | `closeBehavior: 'tray' \| quit`，设置可选 | ✅ **已落地（Echo 的超集）**：`AppSettings.closeBehavior`（`每次询问 / 最小化到托盘 / 退出应用`，默认 `每次询问`）；设置页「窗口 → 关闭主窗口时」三选一；`每次询问` 时关窗弹出 `close_behavior_dialog`（退出应用 / 最小化到托盘 + 「记住我的选择」，勾选即落盘为常选项）；旧 `closeToTray` 布尔在读设置时迁移 | 依赖托盘已就绪；弹窗经 `kugoNavigatorKey` 挂到 root navigator |
| 4 | **全局快捷键** | `ipc/shortcuts.ts` + `renderer/utils/shortcuts.ts`：15 项命令，窗口内 + 全局双轨，逐项录制与恢复默认；Windows 本地快捷键绕过输入法抢占 | ⬜ 仅窗口内 3 键（空格 / ±5s），见 `root_shell.dart` | 焦点不在窗口时按键无效；无录制 UI。**P0 剩余唯一项** |

### P1 · 任务栏 / 窗口形态（Windows 专属）

| # | 功能 | EchoMusic 实现 | kugo 现状 |
| --- | --- | --- | --- |
| 5 | **Thumbar 播控按钮** | `main/thumbar.ts`：上一曲 / 播放暂停 / 下一曲 + 收藏；纯 JS 生成抗锯齿图标 | 🟡 **已落地 3/4**：`TaskbarHost`（`ITaskbarList3`）上一曲 / 播停 / 下一曲；GDI 抗锯齿 glyph 图标；`TaskbarCreated` 重建后 Refresh。**无收藏钮** |
| 6 | **任务栏进度条** | `main/taskbarProgress.ts`：normal / paused / indeterminate / none，节流更新 | ✅ **已落地**：同 `TaskbarHost::SyncProgress`；Dart 侧 200ms 节流 + 1‰ 变化门槛；paused 最低可见 10‰ |
| 7 | **任务栏封面预览** | `main/taskbarThumbnail.ts` + `taskbarCard.ts`：DWM iconic 缩略图 + Aero Peek 实时预览；窗口标题「歌手 - 歌名」 | ⬜ 无。窗口标题固定 `kugo`（`main.cpp`），未随曲目更新 |
| 8 | **任务栏快捷播控横条** | `main/taskbarMediaBar.ts` + `taskbarDock.ts` + `taskbarShell.ts`：贴任务栏空闲区，可拖出小窗；详见 Echo `docs/windows-taskbar-player.md` | ⬜ 无 |
| 9 | **独立迷你播放器窗口** | `main/miniPlayer.ts`：无边框透明、置顶、跳过任务栏、收起/展开、位置记忆 | ⬜ 仅应用内 `DesktopPlayerBar` / `MiniPlayerBar`，无独立窗 |
| 10 | **窗口材质** | `window/windowsComposition.ts` + `backgroundMaterial.ts`：Win11 Mica/clear、Acrylic、Accent；拖动时暂停 Acrylic；legacy 帧修复 | ⬜ 标准 Flutter 窗 + 深色标题栏，无透明 / 毛玻璃 |
| 11 | **自定义标题栏 / 全屏按钮 / 界面缩放** | `window/titleBar.ts` overlay、全屏钮开关、Ctrl± 缩放并持久化（`window/zoom.ts`） | ⬜ 系统标题栏；无缩放。另有固定 **4:3 窗口约束**（`win32_window.cpp` `WM_SIZING`），Echo 无此限制 |
| 12 | **记住窗口大小位置** | `windowBoundsPersistence.ts`，会话结束前落盘 | ⬜ 每次启动 `main.cpp` 固定 1280×960 逻辑像素、工作区居中 |

### P2 · 系统行为 / 播放引擎增强

| # | 功能 | EchoMusic 实现 | kugo 现状 |
| --- | --- | --- | --- |
| 13 | **开机自启动 + 启动最小化到托盘** | 设置项 `autoLaunch`、`startMinimized` | ⬜ 无（`pubspec` 无 `launch_at_startup`） |
| 14 | **电源管理** | `powerMonitor.ts`：播放防休眠、挂起暂停 / 唤醒恢复、解锁屏兜底 | ⬜ 无 |
| 15 | **会话结束落盘** | `systemShutdown.ts`：关机前写窗口状态 | 🟡 队列已有 `QueueStore` 持久化与冷启动恢复；**无**关机/会话结束钩子，窗口状态未落盘 |
| 16 | **音频输出设备 / 独占模式** | `echo-audio-player`：WASAPI 设备枚举、热插拔、独占输出 | ⬜ media_kit 默认输出，无设备管理（`tool/windows_audio_probe.dart` 仅诊断） |
| 17 | **倍速** | 播放栏 0.1x–5x | ⬜ `audio_player_port.dart` / `media_kit_player.dart` 已有 `setSpeed`，UI 未接线（见 `gap-vs-echomusic.md` #5） |

### 明确可暂缓

| 功能 | 理由 |
| --- | --- |
| 桌面歌词独立窗口 | 需多窗口 + 置顶 + 透明；Flutter 成本高，原 gap 文档 P3 仍成立 |
| 插件浮窗 / 插件系统 | 一期明确不做 |
| 任务栏 layout 外挂 helper（`TaskbarLayout.cs`）完整对等 | 仅服务「播控横条」贴任务栏；横条本身可暂缓 |
| 托盘菜单里的桌面歌词开关/锁定 | 依赖桌面歌词窗，随该项一起再做 |

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

kugo 当前「设置 → 窗口」有 **关闭主窗口时**（每次询问 / 最小化到托盘 / 退出应用）与 **任务栏播放进度**；其余桌面开关尚无挂载点。

### kugo 已落地侧的入口（便于续做时接线）

| 能力 | 主要源文件 | 配套 |
| --- | --- | --- |
| 桌面壳编排 | `shared/tray/desktop_shell.dart` | `main()` 末尾 `DesktopShell.boot` |
| 托盘 | `shared/tray/desktop_tray.dart` | `assets/tray_icon.ico` |
| Thumbar / 进度 | `shared/taskbar/taskbar_bridge.dart`（Dart）→ `windows/runner/taskbar_host.{h,cpp}` | `windows/runner/flutter_window.cpp` 注册 `kugo/taskbar` |
| SMTC | `features/player/audio_service_handler.dart` | `audio_service` + `audio_service_win`；`PlayerController.attachBridge` |
| 平台开关 | `core/platform.dart` | `hasSystemMediaSession` / `hasAudioFocusSession` / `isWindowsPlatform` |
| 关闭行为设置 | `features/settings/settings_controller.dart`、`settings_page.dart`、`shared/tray/close_behavior_dialog.dart` | `settings.closeBehavior`（`ask`/`tray`/`quit`，旧 `settings.closeToTray` 自动迁移） |
| 关闭弹窗入口 | `shared/tray/close_behavior_dialog.dart` + `core/app_navigator.dart` | `DesktopShell.onWindowClose` → `kugoNavigatorKey` → root navigator |

---

## 四、建议对齐顺序

```text
✅ ① SMTC + 媒体键
✅ ② 托盘 + 关闭到托盘
⬜ ③ 全局快捷键（可先 5 项：播停 / 上下曲 / 音量）  ← 当前 P0 首位
🟡 ④ Thumbar + 任务栏进度条（可补收藏钮 / 曲名 tooltip）
⬜ ⑤ 独立 Mini 窗口
⬜ ⑥ 窗口材质 / 记住窗口 / 界面缩放（可顺带去掉 4:3 约束）
⬜ ⑦ 任务栏封面预览 / 播控横条    ← 最重，可最后
⬜ ⑧ 开机自启 / 电源 / 输出设备 / 倍速 UI
```

依赖关系简述：

- ③ 与已落地的 ①② 无硬依赖，可立即做；建议 `hotkey_manager` 或 `RegisterHotKey` 原生通道，与现有窗口内 `Shortcuts` 分轨。
- ④ 已有骨架；补收藏钮需接 `likes_controller`。曲名 tooltip / 封面预览（⑦）依赖窗口标题「歌手 - 歌名」同步。
- ⑤ 依赖窗口管理能力（置顶、跳过任务栏、无边框）；`window_manager` 已引入，可复用。
- ⑥ 的「记住窗口」可在 `DesktopShell` 的 `WindowListener` 上落盘 bounds；材质走 `windows/runner` + DWM，或评估 `bitsdojo_window` / `flutter_acrylic`。
- ⑦ 的「封面预览」依赖封面缓存已有（`core/cache/cover_cache.dart`）；「播控横条」额外需要任务栏几何探测，工作量最大。
- ⑧ 的自启可用 `launch_at_startup`；电源需 `SetThreadExecutionState` 原生通道。

---

## 五、落地路径备忘

| 路线 | 适用 | 备注 |
| --- | --- | --- |
| Flutter 插件 | ③⑤⑥⑧ 的骨架 | 已用：`tray_manager`、`window_manager`、`audio_service_win`。候选：`hotkey_manager`、`launch_at_startup`、`bitsdojo_window` / `flutter_acrylic`。注意 Windows 实现质量参差，上线前需实测 |
| `windows/runner` + MethodChannel 自研 | ④ 补强、⑦、电源/设备等需精确控制的部分 | Thumbar / 进度条已用 `ITaskbarList3`（`kugo/taskbar`）；封面预览用 DWM iconic thumbnail API；电源用 `SetThreadExecutionState` |
| 暂不做 | 桌面歌词窗、插件浮窗、taskbar layout helper | 见「明确可暂缓」 |

已落地实现要点（续做时别踩回去）：

- **SMTC 不必自研 WinRT**：`audio_service_win` 覆盖媒体键 / 系统媒体卡 / 进度；`KugoAudioHandler` 已按车机 AVRCP 语义钉住 3 槽 carousel 与位置推送。若只缺缩略图质量或音频类别，再考虑补 `Windows.Media.Control` 旁路。
- **托盘与关闭行为已同居 `DesktopShell`**：`setPreventClose(true)` 统一拦截关闭，`closeBehavior` 决定 hide / `quit()` / 弹窗（`ask`）。`quit()` 路径会销毁托盘、摘掉任务栏监听，托盘菜单的「退出」直接走 `quit()`，不再二次询问。`ask` 弹窗通过 `kugoNavigatorKey.currentContext` 拿到 root navigator；`_closePromptOpen` 防止弹窗未关时重复关窗叠出多个对话框。
- **任务栏通道是双向的**：Dart → `updateButtons` / `updateProgress` / `refresh`；原生 → `thumbarEvent`（`previous` / `playPause` / `next`）。Explorer 重建任务栏（`TaskbarCreated`）与窗口 restore 时都会 Refresh。
- **进度节流双层**：Dart 200ms + 1‰ 门槛；C++ 再做 mode/permille 去重。paused 最低 10‰，避免黄条看不见。
- **退桌路径别用 `windowManager.destroy()`**：Windows 上它只 `PostQuitMessage(0)`，跳过窗口销毁与引擎收尾，进程会「卡住不退出」（leanflutter/window_manager#478 / #502 / #590）。`DesktopShell.quit()` 在 Windows 改为 `setPreventClose(false)` + `windowManager.close()`，走 `WM_CLOSE → DestroyWindow → WM_DESTROY → FlutterWindow::OnDestroy → PostQuitMessage` 的标准路径；非 Windows 仍用 `destroy()`。
- **`audio_session` 仍无 Windows 实现**（`hasAudioFocusSession=false`），不要在 Windows 路径调 `AudioSession.instance`。
- media_kit（libmpv）只负责解码输出；媒体键 / 系统媒体卡 / 任务栏状态都不在它职责内。
- 窗口默认 **4:3 约束**（`ConstrainToFourByThree`）与 1280×960 启动尺寸写在 runner 里；若做「记住窗口」或自由缩放，需先决定是否保留该约束。

---

## 六、验收口径

### 已对齐（本轮应视为已有底线，回归时抽查）

| 项 | 及格标准 |
| --- | --- |
| 媒体键 / SMTC | 耳机 / 键盘媒体键可播停、上下曲；系统媒体卡可见曲名封面 |
| 托盘 | 关窗后进程在托盘；托盘菜单可播停 / 显示主窗 / 退出 |
| 关闭行为 | 默认「每次询问」关窗弹窗，可选退出 / 最小化到托盘；勾选「记住我的选择」后不再弹窗、重启仍生效；设为「最小化到托盘」时关窗不退出，「退出应用」时进程结束；旧 `closeToTray` 设置能迁移 |
| Thumbar | 悬停任务栏图标出现上一曲 / 播停 / 下一曲，点击有效 |
| 任务栏进度 | 播放中任务栏图标有进度，暂停态可区分 |

### 待对齐（完成后按此验收）

| 项 | 及格标准 |
| --- | --- |
| 全局快捷键 | 焦点在其他窗口时仍可播停；设置页可开关 |
| Thumbar 收藏 | 第四钮可收藏/取消，状态与应用内一致 |
| 任务栏封面预览 | 悬停任务栏出现当前封面 / 窗口标题为「歌手 - 歌名」 |
| 任务栏播控横条 | 可贴任务栏使用，能播停切歌 |
| Mini 窗 | 可从主窗切出，置顶，能播停切歌，关闭后回主窗 |
| 窗口材质 | Win11 下可见 Mica/Acrylic（或明确 fallback 不透明） |
| 记住窗口 | 调整大小位置后重启恢复 |
| 界面缩放 | Ctrl± 可缩放并持久化 |
| 开机自启 | 注销重登后应用可自动启动（设置可关）；可选「启动最小化到托盘」 |
| 电源 | 播放中系统不自动休眠；挂起暂停 / 唤醒可恢复 |
| 倍速 | 播放栏可调 0.1x–5x 并实时生效 |
| 输出设备 | 可枚举并切换默认设备（独占可再后置） |

---

## 七、相关文档

| 文档 | 内容 |
| --- | --- |
| `gap-vs-echomusic.md` | 全端业务能力差距（搜索多维、歌单 CRUD、逐字歌词等） |
| `设计方案.md` | 移动端原方案；其中「平台能力」表按 Android 写，Windows 以本文为准。注：文内「Windows 无 audio_service」已过时，现为 `audio_service_win` |
| Echo `docs/features.md` §12 | Echo 桌面集成能力明细 |
| Echo `docs/windows-taskbar-player.md` | 任务栏播控横条行为与验收 |
