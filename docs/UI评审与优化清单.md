# kugo UI 评审与优化清单（Android / Windows）

评审范围：`app/lib` 全部 UI 层（主题、壳层、播放器、各 feature 页），对照 `app/windows` 桌面配置。
评审日期：2026-09-26。行号对应评审时的 HEAD。

> **进度**：第一轮 P0（#1–#6）已于 2026-09-26 落地，`flutter analyze` 0 issue、
> `flutter test --no-pub` 435 全绿。第二条 P2 里的两处写死主色（#12 的 main.dart /
> history_page）顺手一并修了。第二轮桌面感（#7–#11）与第三轮打磨仍未动。

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

### 2. ✅ Windows 端八处横向列表，零滚动条（已修复）
新增 `shared/widgets/kugo_h_scroll.dart`，已接到全部 8 处。

* 桌面端 `Scrollbar`（`thumbVisibility: true`）；内容不溢出时 `ScrollbarPainter._needPaint`
  会自己跳过，不用手写溢出判断；移动端不画，触屏靠拖拽。
* 滚轮策略分两档：`dx` 占优（触摸板横滑）一定转横向；`dy` 占优（鼠标滚轮）只有
  `wheelToHorizontal: true` 才接管 —— 嵌在竖向页面里的筛选条/页签会把页面滚动劫走。
  目前只有 FM 盘阵开了 `wheelToHorizontal`。
* 位移走 `position.pointerScroll(delta)` 而不是 `animateTo`：前者 `forcePixels` 后会
  `goBallistic`，吸附 physics 才有机会收尾（`animateTo` 会停在两盘之间）。
`shared/widgets/common.dart:275`（被 8 个页面复用）、`search_page.dart`、
`explore_page.dart` ×2、`discovery_page.dart`、`recommend_hub_page.dart`、
`playlist_detail_page.dart`、`fm/fm_radio_card.dart`。

症状：Windows 鼠标滚轮不作用于横向 ListView，触摸板横滑之外基本没法滚。筛选条、
搜索类型页签、黑胶盘阵都属于「看不见还有内容」的状态。

建议两步：
1. 封一个 `KugoScrollbar`（横向 thinning + hover 才显形），先补到所有横向列表和
   桌面主列表；
2. 更治本的做法是让横向列表响应滚轮：`Listener` 吃 `PointerScrollEvent`，
   `scrollDelta.dy` 转成 `animateTo(offset + dy)`（桌面 `PlayerBar` 的音量控件
   已经是这套写法，可以照抄，见 `desktop_player_bar.dart:364`）。

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

### 7. 内容限宽只有设置页做了
全项目 `DesktopContentConstraint` 仅 `features/settings/settings_page.dart:32` 一处
（`maxWidth: 800`）。

症状：搜索结果、播放历史、我喜欢、歌曲详情在 2560px 上一路铺到屏幕两端，
歌名和时长相距两米；而设置页是窄条——同一应用两种宽屏观感。

建议：定一套内容宽度档位（浏览型不限宽 / 列表型 960 / 阅读型 720），按页面类型套，
并在 `responsive.dart` 里补相应 named constructor。

### 8. 悬停态、光标、tooltip 没成体系
现状：同为卡片，`recommend_hub_page.dart:772` 用 `InkWell`（有系统光标），
`discovery_page.dart:1049`、`rank_list_page.dart:233`、`fm_radio_card.dart:1256` 用
`GestureDetector`（无光标、无 hover）；同为返回按钮，
`playlist_detail_page.dart:548` 没 tooltip，`profile_detail_page.dart:182` 有。

建议：封 `KugoClickable`（内部 MouseRegion + 手型光标 + `AnimatedContainer` hover 底纹）
和 `KugoIconButton`（强制 tooltip），然后把上述散点统一换掉。这是本轮性价比最高的一项。

### 9. 键盘可达性只有三个快捷键
`root_shell.dart:138` 只绑了空格（播放/暂停）与左右方向键（±5s）。

建议补：`/` 或 Ctrl+F 聚焦搜索、Esc 关闭弹层/退出歌词、`J/K` 上下首、
`Ctrl+←/→` 切 tab；并把 `app.dart:279` 桌面端 `ExcludeSemantics` 去掉或缩小到 sidecar 范围——
现在整个 Flutter 语义树被摘掉，屏幕阅读器完全读不到内容。

### 10. 标题栏与主题割裂
标题栏由 Win32 绘制，颜色跟随**系统**主题而不是应用主题。用户「跟随系统」模式下还好，
一旦在应用内锁定深色、系统是浅色，就出现深内容套白标题栏。

建议二选一：
- 保守：`windowManager.setTitle('kugo')` + 接受系统标题栏，至少标题不再为空；
- 激进：`setTitleBarStyle(TitleBarStyle.hidden)` 后自绘标题栏行（侧栏顶部 logo 那块
  已经有位置），在 Widows 11 上用 `flutter_acrylic`/`WindowEffect` 做 Mica 背景——
  网易云音乐 PC、Spotify 都是这条路线。

### 11. 侧栏细节
`shared/shell/desktop_sidebar.dart`
- 宽度写死 220、不可折叠；建议加「图标模式」（宽 64）。
- 文案写死「概念版 · Windows」（`:83`）—— `isDesktopView` 是按宽度判定的，
  macOS/Linux 混进去会显示错；改成平台动态取值。
- 选中态用 `Border(left: 3px)`（`:269`）会挤占内容，选中项标题比未选中右移 3px，
  视觉上有轻微抖动；改用左侧独立的指示条（Positioned 绝对定位）。

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
  滑动过程中整页重建，同时 `TabBarView` 的 children 是一次性构建而非 builder，
  切页时五个网格全量重建。改成 `children` → builder + 只 watch 索引。
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
2. 横向列表加滚动条 + 滚轮转横向（#2）
3. 歌词手动滚动宽限期（#3）
4. Windows 窗口标题与最小尺寸（#4）
5. 柱状图宽度封顶（#5）+ 歌手页工具栏 Flexible（#6）

**第二轮 · 桌面感（两到三天）**
6. 内容宽度档位化（#7）
7. `KugoClickable` / `KugoIconButton` 统一 hover+tooltip（#8）
8. 快捷键补全 + 去掉桌面端 ExcludeSemantics（#9）
9. 标题栏方案落地（#10）+ 侧栏折叠/指示条/文案（#11）

**第三轮 · 打磨（按需）**
10. 色值与 Hero tag 收进 token（#12-#14）
11. 动画与重建范围（骨架屏 / Tab / FM / 队列）
12. Android 预测式返回与 SplashScreen 迁移

建议每个主题单独 commit，避免一次大改难以回退。
