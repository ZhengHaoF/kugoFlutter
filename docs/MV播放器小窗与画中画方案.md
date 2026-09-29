# MV 播放器：小窗 / 画中画（P2）

> 状态（2026-09）：
> - ✅ **前置重构**：MV Player 应用级化（`mv_player_host.dart`）
> - ✅ **P2-3**：应用内浮动小窗（`mv_mini_window.dart`，移动端路径）
> - ✅ **P2-1**：Android 系统画中画（`floating`）
> - ✅ **P2-2**：桌面窗口级迷你窗（`mv_desktop_mini.dart`，主窗瘦身 + 置顶）
>
> **平台分工**：桌面端「小窗」= 窗口级迷你窗（可移出应用、跨应用置顶）；
> 移动端「小窗」= 应用内浮动层（应用内导航时继续看），真正移出应用走系统 PiP。
>
> 更早完成的前置：P0 横屏全屏 + 沉浸式、P1 手势（双击 ±10s / 横拖快进 / 竖拖音量）、
> 进度条缓冲指示与拖动时间气泡、倍速、静音、控制层自动隐藏、屏幕常亮（wakelock_plus）。

## 一、前置重构：MV Player 应用级化（✅）

**动机**：原 `MvPlayerPage` 把 media_kit `Player`/`VideoController` 攥在页面 State 里，
dispose 即销毁——小窗 / PiP / 「回全页续播」都做不了。三个小窗形态的共同前置就是
把引擎提升到应用级，页面只是 `Video` 的一个挂载点。

**实现**（`app/lib/features/mv/mv_player_host.dart`）：

- `MvPlayerHostController`：Riverpod `Notifier`，应用级单例。持有 `Player` /
  `VideoController` 与全部引擎策略——多地址重试、防盗链头、Windows 软解回退
  （黑屏 3s 判据）、宽高比探测、屏幕常亮、倍速 / 音量 / 静音、错误流。
- `MvPlayerPage` 瘦身为纯 UI：控制层、手势、弹幕、全屏。取流结果经
  `openPlayUrl(brief, play, resumeMs)` 喂给宿主（切清晰度续播在调用点取游标）。
- 高频游标（position / duration / buffered / playing / engineError）通过宿主上的
  ValueListenable 暴露，**不进 Riverpod state**——与音频侧 `PlayerController.position`
  的隔离策略一致，避免整树按帧重建。
- state 只放低频字段：`engineActive` / `mini` / `brief` / `rate` / `volume` / `muted` /
  `videoAspect` / `controllerEpoch`（软解回退重建 VideoController 时 +1，页面据此重挂
  `Video`）。
- 会话状态机：
  - `takeover(brief)`：同曲会话接管（id 或 hash 匹配）——从小窗 / 列表重复入口
    回到全页时**不重拉详情、不重开引擎**，`mvPlayerProvider` 的取流结果也还在，
    进度不回跳；
  - `enterMini()` / `exitMini()`：小窗显隐；打开新 MV 视为全页会话，小窗让位；
  - `shutdown()`：幂等，销毁引擎 + 释放常亮 + 收小窗；页面 pop 时若非小窗即调用；
  - `resetForRetry()`：取流失败重试前复位 open 状态与解码策略。
- 音乐互斥：宿主 `ref.listen(playerControllerProvider)`——音乐起播且视频在播时
  自动暂停视频（小窗形态下避免双声；全页形态本就进页暂停音乐）。
- 单测：`app/test/mv_player_host_test.dart`（状态机无引擎路径、copyWith、
  音量收敛 / 静音恢复）。

## 二、P2-3 应用内浮动小窗（✅，移动端路径）

**行为**：全页播放中点顶栏「小窗」按钮（起播后可用）→ 页面 pop、引擎存活，
App 内任意页面右下角出现可拖动小窗继续播。正常返回（back / 下滑）保持旧行为
（停播），不做行为变更。

**实现**（`app/lib/features/mv/mv_mini_window.dart` + `app.dart`）：

- 挂在 `MaterialApp.builder` 的 Stack 上、所有路由之上；`mini` 位驱动显隐，
  引擎未活时自身零尺寸、不挡交互（`RenderStack` 空白区透传命中测试）。
- 卡片：`Video`（宽高比跟随视频）+ 底部渐变控件条（播放/暂停、回全页、关闭）
  + 2px 进度线；整卡 `onPanUpdate` 拖动、点按回全页；默认贴右下角并抬高
  112px 避开 MiniPlayerBar / DesktopPlayerBar。
- **坑（已修）**：`MaterialApp.builder` 在 Navigator **之外**，那里没有 `Material`
  祖先——卡片里的 `InkWell` 会直接抛「No Material widget found」并被 ErrorWidget
  顶掉（表现为：报错条 + 没视频 + 拖拽失灵）。卡片现在自带
  `Material(color: black)` 包裹。
- 拖动位置以**未夹取**的原始偏移累加，渲染时才夹取，避免拖到边界后「粘住」。
- 回全页：`exitMini()` + 走 `kugoNavigatorKey.currentContext.push('/mv?…')`
  （builder 的 context 在 Navigator 之上，不能直接用），页面 bootstrap 走
  `takeover` 续播。
- 关闭：`shutdown()` 停播并收窗。

## 三、P2-1 Android 系统画中画（✅ 代码已就位，待真机回归）

**行为**：MV 播放中用户按 Home / 切走 → 系统悬浮小窗继续播；点悬浮窗展开回 App。

**实现**：

- 依赖 `floating 6.0.0`；`AndroidManifest.xml` MainActivity 加
  `android:supportsPictureInPicture="true"`（`configChanges` 模板自带，Activity
  不会重建、播放不中断）。
- 页面在**播放中**注册 `Floating().enable(OnLeavePiP(aspectRatio: …))`：进入时机走
  原生 `onUserLeaveHint`，比监听 `AppLifecycleState.inactive` 精准（不会误触权限
  弹窗、通知栏下拉等场景）。暂停或离开 MV 页即 `cancelOnLeavePiP`，避免在
  别的页面按 Home 也触发 PiP（单 Activity 应用的全局副作用）。
- 宽高比：宿主的 `videoAspect` 夹到 Android 支持区间 [1/2.39, 2.39]，放大成整数比
  （`Rational(178, 100)` 型）。
- 构建前置（已修）：file_picker 8.x 的 Android 模块锁 `compileSdk 34`，与新版
  `flutter_plugin_android_lifecycle`（AAR 元数据要求 ≥36）冲突，`:file_picker:checkDebugAarMetadata`
  会直接失败。已在 `android/build.gradle.kts` 里对插件子工程统一把 compileSdk 对齐到 36
  （只影响编译期 API 面，不动 targetSdk / minSdk）；AGP 9 移除了 `BaseExtension` 旧 API，
  故用反射调 `setCompileSdk`。根治办法是升级 file_picker（8 → 13 大版本），另行安排。
- ⚠️ **待真机回归**：国产 ROM（MIUI/EMUI）对 PiP 有白名单；Android 12+ 的
  「划出即 PiP」手势与返回手势的冲突场景。桌面 / 测试环境全部走
  `isAndroidPlatform` 守卫，无副作用。

## 四、P2-2 桌面窗口级迷你窗（✅）

### 行为

- MV 页点「小窗」：**主窗口**瘦成置顶小窗（360 宽、按视频宽高比定高），
  可拖到桌面任意位置、压在其他应用之上；视频继续播。
- 迷你态只保留极简控件：顶部「还原窗口 / 停止并关闭」，底部播放/暂停 + 进度条；
  点画面切换控件显隐，按住画面拖动即移动窗口。
- 还原 = 回原来的窗口尺寸/位置（原来是最大化就还原成最大化）；
  停止并关闭 = 停播 + 还原窗口 + 回上一页。

### 为什么是「主窗瘦身」而不是新开窗口

- `window_manager` 一个 Flutter 实例只管一个窗口；`desktop_multi_window` 多窗口
  方案与 `media_kit` 纹理共享有坑（Flutter 纹理是 per-engine 的，视频纹理不能跨
  engine 渲染）——要真开第二个窗口承载视频，只能写原生窗口 + mpv `wid` 嵌入，
  成本远高于收益，**不推荐**。
- 代价：迷你态下窗口就是播放器，不能同时浏览 App 其它页面（这也是这类
  「mini player 模式」桌面应用的常规取舍）。

### 实现（`mv_desktop_mini.dart` + `mv_player_page.dart`）

- `MvDesktopMini.enter(aspect)`：记录进入前的 `bounds` + 是否最大化 →
  `unmaximize()`（最大化时 `setSize` 不生效）→ `setMinimumSize(220×124)` →
  `setAlwaysOnTop(true)` → `setAspectRatio(aspect)` → `setSize(360×h)` →
  `setAlignment(bottomRight)`（贴屏幕右下角，像系统画中画一样好找）。
- `MvDesktopMini.exit(prev)`：`setAlwaysOnTop(false)` → `setAspectRatio(0)`（解除锁定）
  → `setMinimumSize` 还原成 `DesktopShell.boot` 的 900×640 → 还原 bounds 或最大化。
- 迷你态布局：**独立 build 分支**（`_desktopMini`）——不走页面那套播放器手势，
  否则「拖窗口」会和「横向拖动快进」抢手势。
- **拖动**：窗口原生标题栏是隐藏的（`TitleBarStyle.hidden`），所以迷你态自绘整窗
  拖拽区，`onPanStart → windowManager.startDragging()`。
- 页面 `dispose`（pop / 系统返回）也会还原窗口，避免把主窗留在迷你尺寸。

### 风险（已处理）

- 置顶窗会盖住所有应用：迷你态给了明确的「还原 / 停止并关闭」两个出口。
- Mica/acrylic 在小窗上可能异常：迷你态是纯黑画面 + 视频，不做材质。
- Alt+F4 仍走 `DesktopShell` 的关闭策略（托盘/询问），弹窗会在小窗里显示——
  可接受，主路径是迷你态自绘的关闭按钮。
