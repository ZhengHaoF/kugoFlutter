# kugo UI 评审与优化清单（Android / Windows）

评审范围：`app/lib` 全部 UI 层（主题、壳层、播放器、各 feature 页），对照 `app/windows` 桌面配置。
评审日期：2026-09-26。行号对应评审时的 HEAD。

> **进度**：第一轮 P0（#1–#6）已于 2026-09-26 落地，`flutter analyze` 0 issue、
> `flutter test --no-pub` 435 全绿。第二条 P2 里的两处写死主色（#12 的 main.dart /
> history_page）顺手一并修了。第二轮桌面感（#7–#11）与第三轮打磨仍未动。
> 2026-09-27：#2 二次重构（滚动条 → 拖拽/滚轮/渐隐，见 §2），全量 537 测试全绿。
> 2026-09-28：对照代码补记 —— P3「TabController 逐帧 setState」其实已修
> （见 §5），清单原先漏记；同轮其余 P3/P2 项状态属实。
> 2026-09-28：第二轮桌面感 #7–#11 已落地（见 §3），`flutter analyze` 0 issue、
> `flutter test --no-pub` 551 全绿。第三轮 P2/P3 剩余项仍未动。
> 同日真机闪退：去掉 ExcludeSemantics 触发 Windows AXTree 崩溃，已恢复并
> 记入 §3 #9；Mica 改为延后 + 多档回落。详见各条「踩坑」。

---

## 一、先确认哪些东西别动（这些是对的设计）

改动前先记住这套约束，否则容易把好的部分改坏：

| 项 | 位置 | 为什么值得保留 |
|---|---|---|
| 颜色全部 token 化，通过 ThemeExtension 读取 | `core/theme/kugo_tokens.dart`、`kugo_theme.dart` | `Theme.of(context)` 自动注册依赖，`const` widget 也不会在主题切换后变旧 |
| 高频播放进度走独立 ValueNotifier，不塞进 `PlayerState` | `features/player/player_controller.dart` | 各页 `ref.watch` 只在切歌/播放暂停时重建，不会跟着每帧进度重绘整个页面 |
| 桌面自写 `DesktopPageTransitionsBuilder`（不缩放、不平铺快照） | `core/theme/kugo_theme.dart:129` | Hero 落点零亚像素抖动； settled 帧直接画 child |
| 迷你播放条按亮度 Key 重挂 | `shared/shell/root_shell.dart:227` | 主题切换后不会残留旧调色板 |
| 桌面滚轮平滑 | `shared/widgets/smooth_scroll.dart` | 桌面端手感的关键一环，别为了加滚动条把它替换掉 |
| 空态/错误态/音源停用态有专门组件 | `shared/widgets/async_body.dart`、`common.dart:189` | 不是白屏也不是一串 toast |
| 播放失败的降级提示与「下一首重试」 | `full_player_page.dart:860` | 详情页很少有人做 |

---

## 二、P0 · 影响「能不能用」

### 1. ✅ 移动端二级页整条迷你播放条消失（已修复）
`shared/shell/root_shell.dart`

全屏路由（`/player`、`/player/lyrics`、`/login`、`/netease-login`）挂在 shell 之外，
不会渲染 `RootShell`，所以进来的路径必属两个主 branch —— 直接删掉字面值判断即可；
二级页保留 MiniPlayerBar + 音源提示，**只隐藏底部 tab dock**（深页带 tab 会把层级画错）。

`desktop_navigation_test` 里断言旧行为的用例已改成新行为（dock 消失、迷你条保留）。

```dart
final isMainTab = widget.location == '/explore' || ... ;
if (!isMainTab) return Scaffold(body: widget.child);   // 无 MiniPlayerBar，无音源提示
```

命中路由：`/search` `/discovery` `/daily` `/ranks` `/rank/:id` `/playlist/:id`
`/album/:id` `/artist/:id` `/song` `/recommend` `/history` `/likes` `/settings`
`/profile/detail`。

症状：在歌单里点一首歌 → 返回歌单，底部没有任何播放入口与状态；也看不到
「当前音源」那行小字。桌面端因为底部播放条常驻，这条断档只有移动端会撞上。

建议：判断依据换成**当前所在 branch**（`StatefulShellRoute` 的 branch index），
而不是路由字面值——主 tab 的两个分支里所有路由都应带条，只有全屏路由
（`/player`、`/login`）才隐藏。

### 2. ✅ Windows 端八处横向列表：滚动条 → 拖拽/滚轮/边缘渐隐（2026-09-27 重构）
`shared/widgets/kugo_h_scroll.dart`（`KugoHScroll`，8 处横排共用，改一处全生效）。

首轮（2026-09-26）给所有横排加了常显细 Scrollbar + `wheelToHorizontal`；一天后用户
反馈滚动条割裂卡片行，要求改成鼠标滚轮/点击滑动。本轮**推倒滚动条**，换成三件套：

* **去滚动条**：删 `Scrollbar`/`ScrollbarTheme`（桌面端曾 `thumbVisibility: true`）。
  可发现性由「溢出侧边缘渐隐」补偿（`fadeEdges`，`ShaderMask` + dstIn，
  渐隐宽度 [KugoHScroll.fadeLength]；范式同 `lyrics_view.dart`）。
  chips/页签行显式 `fadeEdges: false`——渐隐会啃胶囊圆角，且它们很少溢出。
* **鼠标拖拽**：框架默认 `dragDevices` **不含 mouse**（Flutter 源码
  `scroll_configuration.dart` 的 `_kTouchLikeDeviceTypes`），桌面「按住拖动」必须
  显式放开。`ScrollConfiguration.copyWith(dragDevices: +mouse)` **只包横排容器**，
  不全局开（框架注释警告全局放开会毁掉文本选择）。
* **滚轮滚横排**（`KugoHWheelMode.silky`）：包 `SilkyScroll(direction: horizontal,
  behavior: always)`——悬停时 silky 的 hover-stack 抑制外层页面滚动，滚到边缘由
  `forwardAlwaysMouseWheelDeltaAtEdge` 把剩余 delta 放行回页面。
  **不能自己写 `pointerSignalResolver.register` 手搓**：外层竖向页面（
  `smooth_scroll.dart`）的滚轮是 silky 用裸 `Listener` 接的，不参与 resolver 竞争，
  内层注册得再干净页面也照样滚 → 双重滚动。
* **FM 盘阵走 `KugoHWheelMode.raw`**（自研 `pointerScroll` 路径）：silky 的
  `SilkyScrollPosition.pointerScroll` 对 mouse 事件直接吞掉，`_OneStepSnapPhysics`
  的「甩动后吸附」会断链。且 FM 整屏独占，本来无页面劫持问题。
* **顺带修一个双倍速 bug**：旧实现 dx（触摸板横滑）由「框架 Scrollable + 裸
  Listener」双重处理 → 横滑速度 ×2。现在 dx 一律交给框架。

**踩过的最大的坑（写组件的一定要看）**：渐隐层最初按需插入/移除 `ShaderMask`，
插入那一刻 Flutter 把 ShaderMask 下面整棵子树（ListView + silky State +
ScrollPosition）**卸载重挂**——滚轮 tick 一次就被 dispose、offset 归零、拖拽失效。
修法：**包装层常驻，只让 shaderCallback 的渐变内容随状态变**。`test/
kugo_h_scroll_test.dart` 的「渐隐层常驻：滚动连续不重置」用例钉死这条。

测试（`test/kugo_h_scroll_test.dart`，6 例）：滚轮 hijack / 边缘放行 / 鼠标拖拽
（注意 widget test 里鼠标拖拽要**分两次 move**——单次大 moveBy 过不了手势基线）/
点击不误触 / dx 单份 / chips 行不劫持页面。
裸写 silky 之前先读 `docs/...` 无相关记录——依据在 pub 缓存源码
`silky_scroll-2.6.4/lib/src/`（`silky_scroll_widget.dart` 的 `_onPointerSignal`
四步分流、`silky_scroll_state.dart` 的 hover-stack 守卫、`silky_input_handler.dart`
的 `MouseWheelVerticalDeltaBehavior`）。

调用点：`common.dart:278`（音源 chips）、`discovery_page.dart:559`、
`song_detail_page.dart:744`、`playlist_detail_page.dart:458`、
`search_page.dart:265`、`explore_page.dart` ×2（卡片带）、
`fm/fm_radio_card.dart:795`（`wheelMode: raw`）。

**2026-09-28 修正（实测推翻「滚轮滚横排」这一条）**：发现页两条卡片带原先传
`KugoHWheelMode.silky`，即 `mouseWheelVerticalDeltaBehavior.always`——竖向滚轮被
横排劫持，必须先把横排滚到边缘，剩余 delta 才放行回页面。用户反馈「往下滚到横排
又变横向滚动，体验很差」。横排嵌在竖滚页面里**不该劫持竖向滚轮**：框架默认
（`scrollable.dart` 横向只认 dx）和 silky 默认（`forwardToVerticalAncestorOrSelf`）
本来都不劫持，这是当初对包默认值的显式覆盖。两条卡片带已回退为默认 `none`：
滚轮归页面，横滚走 **Shift+滚轮**（框架 `pointerAxisModifiers` 白送）/ 触控板两指
横滑 / 鼠标按住拖拽，可发现性仍由边缘渐隐兜底。`KugoHWheelMode.silky` 仅保留给
FM 等整屏独占场景（那里没有"滚轮被吃掉过不去"的陷阱）。组件与
`kugo_h_scroll_test.dart` 不变，本次只改调用点。

### 3. ✅ 桌面端歌词不能手动滚动（已修复）
`shared/widgets/lyrics_view.dart`

「用户手动态」：宽限期 4s，期间不自动居中，右下角浮出「回到当前行」按钮；
4s 后自动恢复跟随，点按钮则立刻恢复。检测分两路——滚轮/触摸板用
`Listener.onPointerSignal`（不带 `dragDetails`），拖拽用
`ScrollStartNotification.dragDetails != null`。
按钮放在 `Stack` 里、`ShaderMask` 之外，否则会被上下渐隐遮罩吃掉透明度。
build 里两处 `addPostFrameCallback` 收敛成去重后的 `_queueRecenter()`（原先行高/视口
连续变化时会在一帧内排好几次，互相抢滚动）。

`ScrollConfiguration` 关掉 scrollbars，`NotificationListener` 又把滚动通知全吞了
（`onNotification: (_) => true`），同时 92-101 行按播放进度自动居中。

症状：手动往上翻歌词看前几行，下一次进度 tick 立刻把你拽回去——看起来像卡住了。

建议：经典的「用户介入宽限期」——检测到用户拖动/滚动后进入手动态，
暂停自动跟随 3~5 秒（或在歌词区浮出「回到当前行」按钮才恢复），并把 shadow mask
的下缘留出可点区域。

### 4. ✅ Windows 窗口没有尺寸约束与标题（已修复）
`shared/tray/desktop_shell.dart:_start`

```dart
await windowManager.waitUntilReadyToShow(
  const WindowOptions(title: 'kugo', minimumSize: Size(900, 640)),
);
```

刻意**不设** `size` / `center`：保留用户上次调过的窗口尺寸与位置（`waitUntilReadyToShow`
每个字段只在非空时应用，见 window_manager 0.5.2 源码:140-158）。

### 5. ✅ 历史页柱状图在宽屏被拉成大色块（已修复）
`features/history/history_page.dart`

每根柱子保持 Expanded 的等分节奏，但内容再加一层
`Center + ConstrainedBox(maxWidth: 36)`：宽屏下柱子本身仍是 28px 宽、70px 高，
只是中间留白变多，读起来还是柱状图。

### 6. ✅ 歌手页工具栏窄屏必溢出（已修复）
`features/artist/artist_detail_page.dart:_SongsToolbar`

`LayoutBuilder` + `<520px` 折两行（标题+排序 / 搜索+定位）；搜索框从写死 180 宽
改成 `Flexible + ConstrainedBox([96, 220])`，空间不足时优先变窄而不是溢出。

---

## 三、P1 · 桌面端「像不像桌面软件」

> **2026-09-28 第二轮落地**：#7–#11 全部完成。`flutter analyze` 0 issue、
> 551 测试全绿。实现摘要见各条「✅」后的新说明。

### 7. ✅ 内容限宽档位化（2026-09-28）
`core/theme/responsive.dart`：`DesktopContentConstraint.list(960)` /
`.reading(720)` / `.form(800)` 三档 named constructor。

套用：历史 / 我喜欢 / 搜索 → list；歌曲详情 / 个人中心 → reading；设置 → form。
歌单 / 专辑 / 歌手详情保持浏览型满宽（封面头图 + 曲目列，收窄反而空）。
全项目 `DesktopContentConstraint` 仅 `features/settings/settings_page.dart:32` 一处
（`maxWidth: 800`）。

症状：搜索结果、播放历史、我喜欢、歌曲详情在 2560px 上一路铺到屏幕两端，
歌名和时长相距两米；而设置页是窄条——同一应用两种宽屏观感。

建议：定一套内容宽度档位（浏览型不限宽 / 列表型 960 / 阅读型 720），按页面类型套，
并在 `responsive.dart` 里补相应 named constructor。

### 8. ✅ 悬停态、光标、tooltip 成体系（2026-09-28）
`shared/widgets/kugo_clickable.dart`：
- **`KugoClickable`**：MouseRegion + 手型光标 + AnimatedContainer hover 底纹
  （与侧栏同一套黑洗，浅/深各一档 alpha）。
- **`KugoIconButton`**：强制 tooltip 的 Material 图标钮。
- **`KugoIconAction`**：非 Material 工具条小钮（hover 圆角洗 + tooltip）。

已替换：`PlaylistCard`/`TrackTile`/`SearchResultRow`（common）、榜单卡、
发现页专辑/歌手卡、推荐枢纽入口卡、FM 卡内圆钮、搜索 tab 芯片、源筛选芯片、
探索排行卡；歌单/专辑/歌手返回钮补 tooltip。

### 9. ✅ 键盘可达性补全（2026-09-28）
`root_shell.dart` 桌面 Shortcuts：
- 空格 播放/暂停；←/→ ±5s（原有）
- `J`/`N` 下一首，`K`/`P` 上一首
- `/` 或 `Ctrl+F` 进搜索
- `Esc` pop / 回主 tab
- `Ctrl+←/→` 切主 tab

`app.dart` **保留**桌面端 `ExcludeSemantics`（见下方「踩坑」）。

> **踩坑（2026-09-28 装完立刻闪退）**：#9 原计划去掉整树 `ExcludeSemantics`
> 以恢复屏幕阅读器。装到 Windows 真机后高频触发
> `accessibility_bridge.cc Failed to update ui::AXTree … will not be in the
> tree and is not the new root`，随后 `Lost connection to device` 闪退。
> Win32 embedder 的 AXTree 更新跟不上 Flutter 语义树的高频变化（hover /
> 列表 / 动画），不是可读性取舍问题，是稳定边界。**已恢复 ExcludeSemantics**；
> 要开屏幕阅读器须先修桥（或只对 sidecar 范围开语义）。

### 10. ✅ 标题栏自绘 + Mica（2026-09-28，激进方案）
- `WindowOptions(titleBarStyle: hidden, windowButtonVisibility: false)`
- `shared/shell/desktop_title_bar.dart`：36px 自绘条（拖拽 / 双击最大化 /
  最小化 / 最大化 / 关闭），关闭仍走 `setPreventClose` → 托盘链路。
- `flutter_acrylic` + `WindowEffect.mica`（Win11）；初始化失败静默回落默认背景。
  主题切换时 `dark` 参数跟 `settings.materialThemeMode`。

### 11. ✅ 侧栏细节（2026-09-28）
`shared/shell/desktop_sidebar.dart`
- 可折叠「图标模式」宽 64（顶栏折叠钮），展开 220。
- 副标题按平台取值（Windows/macOS/Linux），不再写死 Windows。
- 选中指示条改为 `Positioned` 绝对定位 3px 竖条，不再 `Border(left:)` 挤内容。

> **踩坑（折叠态布局雪崩）**：折叠分支曾在 `Row` 里写
> `SizedBox(width: double.infinity)` 想居中图标——`Row` 主轴非紧约束，
> 直接 `BoxConstraints forces an infinite width`，整棵侧栏 layout 失败并
> 连环 `RenderBox was not laid out`。另外 64px 里塞「logo+文案+按钮」必然
> Flex overflow。修法：折叠态不要 Row，`Center + Icon`；顶栏折叠态只留
> logo + 小按钮；外层再包一层 `SizedBox(width:)` 钉死宽度。
> 回归：`test/desktop_sidebar_collapse_test.dart`（展开/折叠/再展开）。

---

## 四、P2 · Android 现代化与一致性

| 项 | 位置 | 说明 |
|---|---|---|
| 预测式返回 | `android/app/src/main/AndroidManifest.xml` | 未开 `android:enableOnBackInvokedCallback="true"`，Android 13+ 没有返回手势预览 |
| 启动画面 | `res/values/styles.xml` | 仍是旧 `LaunchTheme`/`NormalTheme`，未迁移 Android 12+ SplashScreen API；深色优先的用户启动瞬间可能吃到浅色 windowBackground |
| 通知主色写死 | ~~`main.dart:82`~~ ✅ 改为 `kugoPaletteFor(brightness).primary` | 原写死值是深色主题 primary，浅色下通知是块深蓝 |
| 主色写死 | ~~`history/history_page.dart:437`~~ ✅ 改为 `kugo.primary` | 同上，「预估时长」卡片 |
| 红心色三部曲 | `likes_page.dart:555`、`full_player_page.dart:1128`/`:1207` | `0xFFE87A90` 抄了三份，应进 `KugoPalette` |
| 危险操作色 | `history_page.dart:309`、`profile_detail_page.dart:193` | 直接用 `Colors.redAccent`，应加 `KugoPalette.danger` 并区分深浅色 |
| Hero tag 字面量 | `song_detail_page.dart:202` 等 4 处 | `'player-cover-$id'` 手写，没走 `KugoHeroTags` |
| 圆角家族失控 | `profile_detail_page`、`recommend_hub_page`、`fm_page`、`history_page` 多处 | 实际用了 4/6/8/9/10/12/14/16/20/24，`KugoRadius` 只有 chip/card/tile/cover 四档；建议补 sheet/panel/badge 三档并全局替换 |

---

## 五、P3 · 动画与性能打磨

- **骨架屏每行一个 AnimationController**（`async_body.dart:76-81`）：6 行 6 个常驻
  ticker，且三个详情页首屏各挂一份。改成一个 controller + 相位偏移。
- **TabController 逐帧 setState**（`discovery_page.dart:104`、`likes_page.dart:84`）：
  ✅ **前半已修**（2026-09-28 补记）：`likes_page._onTabChanged` 与
  `discovery_page._handleTabTick` 都改成「索引真变才 `setState`」，滑动 offset
  每帧不再整页重建。**后半仍在**：`TabBarView` 的 children 仍是一次性构建而非
  builder，切页时五个网格全量重建。改成 `children` → builder + 只 watch 索引。
- **FM 页动画不休眠**（`fm_page.dart:52-59`）：18s 旋转 + 1.1s 频谱 `repeat()`，
  被 `/player` 完全盖住后仍在跑；频谱还每帧重建 Row。加 `TickerMode`/可见性判断。
- **队列弹层全量构建**（`queue_sheet.dart:52`）：`shrinkWrap: true` 的 ListView
  塞进 Flexible，300 首队列打开瞬间一次性布局。
- **播放页进度条无拖拽预览**：`desktop_player_bar.dart` 做了 `_isDraggingProgress`，
  但 `full_player_page` 的 Slider 是直连 `seekTo`，手指按下即跳转、易误触。
- **构建期副作用**（`lyrics_view.dart:164-183`）：在 `build()` 里写 `_lastViewport`
  并 `addPostFrameCallback`，配置连变时会连续触发滚动修正。

---

## 六、建议的落地顺序

按「改完用户立刻能感觉到」排序，每轮独立可发布：

**第一轮 · 可用性（半天到一天）**
1. 迷你播放条改为按 branch 判定（#1）
2. 横向列表交互（#2，09-27 重构为拖拽/Shift+滚轮/渐隐，无滚动条；09-28 卡片带回退不再劫持竖向滚轮）
3. 歌词手动滚动宽限期（#3）
4. Windows 窗口标题与最小尺寸（#4）
5. 柱状图宽度封顶（#5）+ 歌手页工具栏 Flexible（#6）

**第二轮 · 桌面感（两到三天）** ✅ 2026-09-28 完成
6. 内容宽度档位化（#7）
7. `KugoClickable` / `KugoIconButton` 统一 hover+tooltip（#8）
8. 快捷键补全（#9；ExcludeSemantics 因 AXTree 闪退保留，见 §3）
9. 标题栏方案落地（#10）+ 侧栏折叠/指示条/文案（#11）

**第三轮 · 打磨（按需）**
10. 色值与 Hero tag 收进 token（#12-#14）
11. 动画与重建范围（骨架屏 / Tab / FM / 队列）
12. Android 预测式返回与 SplashScreen 迁移

建议每个主题单独 commit，避免一次大改难以回退。
