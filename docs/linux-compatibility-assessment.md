# kugoFlutter Linux 兼容评估与实施方案

> 文档性质：实施前只读评估快照。下文的“目前”“本次未修改”均指评估当时的基线，不代表适配分支的当前状态。P0/P1 的实际改动、对候选依赖的修正和验收进度见 [Linux 实施记录](linux-implementation.md)；后续 P2 X11 歌词工作见 [X11 歌词记录](linux-x11-lyrics.md)。

当前代码具有较好的桌面 UI、音源和播放抽象基础，建议继续沿用 Flutter 与 `media_kit`，分阶段增加 Linux 支持。**目前还不能直接构建或认定为 Linux 兼容产品**：缺少 Linux runner，媒体原生依赖未接齐，托盘启动链路存在确定的不支持方法调用，桌面歌词原生实现仍是 Windows 专用。

本次仅评估，不修改项目源码、pubspec、平台目录或 CI，不创建分支或 PR。以下改动均为后续建议，尚未实施。

## 评估范围与证据边界

- **代码基线**：`713ff00f18288001c56ace9f1f989bbb961d07cc`，即 B 站接入 [PR #1 的合并提交](https://github.com/ZhengHaoF/kugoFlutter/commit/713ff00f18288001c56ace9f1f989bbb961d07cc)。
- **最新主分支核对**：收尾时远端已推进至 `1e8acaf6a5504e62433adcfc26346e67cb5e2ae2`；新增提交仅清理文档/视觉稿，没有修改应用源码、依赖或 Linux runner，因此本报告兼容结论仍适用。此前 998 项测试对应的是上面的代码基线，不宣称在新提交上重跑。[最新文档清理提交](https://github.com/ZhengHaoF/kugoFlutter/commit/1e8acaf6a5504e62433adcfc26346e67cb5e2ae2)
- **当前环境**：Ubuntu 26.04.1 LTS / Linux x86_64，Flutter 3.47.7 / Dart 3.13.5；没有完成 Linux GUI 应用启动、真实音频输出或桌面环境矩阵验收。
- **只读检查**：读取源码、实际解析的插件源码及 CMake、平台目录和官方文档，运行原项目构建探测。没有执行 `flutter create` 或修改依赖。
- **构建探测**：`flutter build linux --release --no-pub` 退出码 1，报 `No Linux desktop project configured`；仓库目录检查也未发现跟踪的 `app/linux/`。
- **已有回归证据**：本轮评估开始前，同一提交在此 Linux 环境重新执行静态分析无问题，998 项测试全部通过；游客态 B 站搜索、取流与部分内容接口通过。这些是 Dart/Widget 与协议证据，不是 Linux runner、原生插件、音频设备或桌面歌词的验收证据。

下面分别标注代码事实、插件文档、源码推断与建议。未进入的构建阶段不表述为已失败，未运行的桌面功能也不表述为已通过。

## 总体判断与首版目标

### 建议的支持范围

建议首版面向 Ubuntu 22.04/24.04 LTS x64，优先建立 X11 桌面验收，再增加 GNOME/KDE Wayland 的基础功能验收。Flutter 当前支持矩阵列出 Ubuntu 20.04–24.04 LTS、Debian 10–13 以及 x64/Arm64，但这是框架支持，不等于本项目及全部插件已支持这些组合；当前 Ubuntu 26.04 环境也不在所读取矩阵的 Ubuntu 列表中，不能替代目标版本验收。[Flutter 支持平台矩阵](https://docs.flutter.dev/reference/supported-platforms)

建议首版承诺：

- **基础音乐客户端**：启动、三源搜索/内容浏览、账号二维码 UI、网络播放、队列、历史、我喜欢、应用内歌词与设置。
- **桌面基础体验**：窗口最小化/最大化/关闭、缩放、键盘快捷键、退出与状态恢复。
- **可选桌面集成**：托盘与系统媒体会话采用能力检测和降级，不得成为主应用启动的硬依赖。
- **暂不承诺**：所有发行版通用安装包、ARM64、原生 Wayland 全局悬浮歌词、Windows 式任务栏按钮/进度条、统一毛玻璃效果。

架构上不用重写音源协议层。当前平台检测已经把 Linux 纳入桌面，但 Linux 系统媒体会话和音频焦点明确关闭，属于“有桌面分支、未完成平台集成”的状态。[当前平台能力门控](https://github.com/ZhengHaoF/kugoFlutter/blob/713ff00f18288001c56ace9f1f989bbb961d07cc/app/lib/core/platform.dart)

### 阻塞项排序

| 优先级 | 项目 | 当前发现 | 后续建议 |
| --- | --- | --- | --- |
| P0 | Linux runner | 构建探测在进入 CMake 编译前停止：未配置 Linux 项目 | 在独立适配分支生成并审阅 `app/linux/`，确认应用 ID、参数传递和插件注册 |
| P0 | 媒体原生依赖 | pubspec 只有 Android/Windows 媒体依赖包，没有 Linux 依赖包 | 补齐 Linux 包、libmpv 及视频构建依赖，不更换播放器架构 |
| P0 | 托盘初始化 | `setToolTip` 在 Linux 不支持，当前启动流程直接 await | 按方法能力门控；托盘失败不阻止主 UI；禁用没有恢复入口的“关闭到托盘” |
| P0 | 桌面歌词入口 | UI/桥接按“桌面平台”开放，但原生通道是 HWND/Windows 实现 | Linux 首版关闭悬浮歌词入口及自动恢复，保留应用内歌词 |
| P1 | 桌面完整性 | 系统媒体会话没有 Linux 实现，窗口能力受后端影响 | 增加 MPRIS 适配和 X11/Wayland 分级验收 |
| P2 | 悬浮歌词与发行 | 原生实现、权限、打包和 ABI 兼容尚未处理 | 单独完成 X11 歌词，再评估 Wayland；打包在基本功能稳定后进行 |

媒体依赖缺口可从[当前 pubspec](https://github.com/ZhengHaoF/kugoFlutter/blob/713ff00f18288001c56ace9f1f989bbb961d07cc/app/pubspec.yaml)确认；托盘方法支持与当前调用分别见 [tray_manager 0.5.3 文档](https://pub.dev/packages/tray_manager/versions/0.5.3)和[项目托盘实现](https://github.com/ZhengHaoF/kugoFlutter/blob/713ff00f18288001c56ace9f1f989bbb961d07cc/app/lib/shared/tray/desktop_tray.dart)，歌词原生接口见[DesktopLyricHost](https://github.com/ZhengHaoF/kugoFlutter/blob/713ff00f18288001c56ace9f1f989bbb961d07cc/app/lib/features/desktop_lyric/desktop_lyric_host.dart)。

## 插件与依赖兼容评估

下列版本是本机已解析版本，不是只看 pubspec 的最低版本。文档支持仅表示存在平台实现，不能替代本项目编译和运行；纯 Dart 的网络、模型、状态管理与 UI 包不逐项列出。

| 组件 / 本机版本 | Linux 证据与风险 | 建议 |
| --- | --- | --- |
| media_kit 1.2.6 | 支持 Linux 音频/视频，默认使用系统 libmpv。[版本文档](https://pub.dev/packages/media_kit/versions/1.2.6) | 保留现有 `MediaKitPlayerImpl`，实测出声、进度、切歌、请求头与 seek |
| media_kit_video 1.3.1 | 本机源码有 Linux 插件，但 CMake 受 `MEDIA_KIT_LIBS_AVAILABLE` 控制；缺失时编译降级分支。该版本公开页没有完整 Linux 安装说明。[包页面](https://pub.dev/packages/media_kit_video/versions/1.3.1) | 不能把“编译成功”当成有视频纹理输出；补齐依赖后验收 MV |
| media_kit_libs_linux，目前未依赖 | 提供 Linux 媒体依赖接入；查到版本 1.2.1。[包文档](https://pub.dev/packages/media_kit_libs_linux) | 作为候选新增项验证；不要简单复制 Windows 媒体库配置 |
| window_manager 0.5.2 | 标注支持 Linux，但版本文档未逐项保证 Wayland 定位/置顶等行为。[版本文档](https://pub.dev/packages/window_manager/versions/0.5.2) | 保留窗口管理；能力分级，不能让不支持操作拖垮主窗 |
| tray_manager 0.5.3 | 支持 Linux 图标和菜单；不支持 `setToolTip`、`popUpContextMenu`、`getBounds`；依赖 AppIndicator。[版本文档](https://pub.dev/packages/tray_manager/versions/0.5.3) | 第一轮保持现有版本适配，不顺便迁移新的托盘 API |
| flutter_acrylic 1.1.4 | Linux 有透明效果，但模糊依赖合成器，GTK3 没有统一 backdrop blur API。[版本文档](https://pub.dev/packages/flutter_acrylic/versions/1.1.4) | 主窗继续使用普通不透明底，不把毛玻璃列为首版条件 |
| desktop_multi_window 0.3.1 | 支持 Linux；每窗独立引擎，需要处理插件注册。[版本文档](https://pub.dev/packages/desktop_multi_window/versions/0.3.1) | 当前生产歌词是独立进程，不因这个包存在就认定歌词可用；首轮不切回多引擎路线 |
| audio_service / audio_service_win 0.0.3 | Windows 包提供 SMTC，不自动提供 Linux 会话；本项目 Linux gate 关闭。[Windows 包文档](https://pub.dev/packages/audio_service_win/versions/0.0.3)、[项目门控](https://github.com/ZhengHaoF/kugoFlutter/blob/713ff00f18288001c56ace9f1f989bbb961d07cc/app/lib/core/platform.dart) | 另行增加 MPRIS，不直接在 Linux 打开现有 gate |
| file_picker 8.3.7 | Linux 支持文件、目录与保存选择，不支持清临时文件 API。[版本文档](https://pub.dev/packages/file_picker/versions/8.3.7) | 本机源码实际通过 qarma/kdialog/zenity 拉起对话框，打包需检查至少一个可用实现 |
| path_provider_linux 2.2.2 | 官方 Linux 实现会随 path_provider 自动接入。[版本文档](https://pub.dev/packages/path_provider_linux/versions/2.2.2) | 验收应用支持目录、缓存目录和无写权限场景 |
| shared_preferences_linux 2.4.1 | 有 Linux 实现。[版本文档](https://pub.dev/packages/shared_preferences_linux/versions/2.4.1) | 验收设置/账号恢复与退出清理；当前账号存储不升级为“已加密”承诺 |
| sqlite3_flutter_libs 0.5.42 | 给 Linux 等平台打包原生 SQLite。[版本文档](https://pub.dev/packages/sqlite3_flutter_libs/versions/0.5.42) | 本机 CMake 会下载 SQLite 源码；检查构建联网/缓存以及原生包 ABI |
| volume_controller 3.7.1，传递依赖 | 支持 Linux；本机 Linux CMake 明确 `find_package(ALSA REQUIRED)`。[版本文档](https://pub.dev/packages/volume_controller/versions/3.7.1) | 即便应用未直接调用它，视频依赖也会带入；准备 ALSA 开发库 |
| wakelock_plus 1.5.2 | 支持 Linux，但只保持屏幕唤醒，不保证 CPU 后台存活。[版本文档](https://pub.dev/packages/wakelock_plus/versions/1.5.2) | 本机实现调用桌面 portal；MV 无 portal/无 session bus 时应降级，不阻止播放 |
| screen_retriever_linux 0.2.2，传递依赖 | 有 Linux 实现；公开页未保证各后端的光标/显示器行为。[版本文档](https://pub.dev/packages/screen_retriever_linux/versions/0.2.2) | 涉及多屏与位置时在 X11/Wayland 分别实测 |
| floating 6.0.0 | 仅 Android PiP，不支持 Linux。[版本文档](https://pub.dev/packages/floating/versions/6.0.0) | 保持 Android 门控；Linux 使用桌面 MV 小窗或应用内降级 |
| jni 1.1.0，传递依赖 | 本机解析列表包含 Linux 构建项；源码在 Flutter 构建下查找 JNI 失败可跳过，不能直接判定“必须安装 JDK” | 在完整构建时关注日志，不把 Android 传递依赖误报为 Linux 运行必须依赖 Java |

其中 CMake、对话框程序和 portal 的细节是本次对已解析插件源码的检查结论，公开包页缺少对应细节，未将其伪装成文档承诺。媒体库、GTK、AppIndicator、ALSA 等问题还没有实际进入项目 CMake 编译验证。

## 关键链路与建议设计

### 启动可靠性：优先于外观和系统集成

当前 `main` 在 `runApp` 前初始化 MediaKit，并 await 桌面壳；桌面壳再 await 托盘初始化，因此原生依赖或托盘失败会影响主 UI 启动。[启动顺序](https://github.com/ZhengHaoF/kugoFlutter/blob/713ff00f18288001c56ace9f1f989bbb961d07cc/app/lib/main.dart)、[桌面壳初始化](https://github.com/ZhengHaoF/kugoFlutter/blob/713ff00f18288001c56ace9f1f989bbb961d07cc/app/lib/shared/tray/desktop_shell.dart)

建议区分两类故障：音频引擎缺失应显示明确的依赖/播放错误，不能仅留下空窗；托盘、毛玻璃、媒体会话等增强功能失败，应记录错误并继续进入主界面。当前毛玻璃与任务栏已经有 Windows 门控，可保留；不要为了 Linux 支持强行执行这些 Windows 功能。[已有桌面壳门控](https://github.com/ZhengHaoF/kugoFlutter/blob/713ff00f18288001c56ace9f1f989bbb961d07cc/app/lib/shared/tray/desktop_shell.dart)

建议新增桌面能力对象，至少区分 `trayAvailable`、`trayTooltip`、`systemMediaSession`、`desktopLyric`、`absoluteWindowPosition`、`alwaysOnTop`、`clickThrough`、`windowBlur`。这是建议设计，不是现有接口；检测应结合插件能力、实际 GDK 后端和桌面会话，不仅依据 `Platform.isLinux` 或 `XDG_SESSION_TYPE`。

### 音频与 MV：保留 media_kit，补齐 Linux 链路

建议候选方案是新增 `media_kit_libs_linux` 并准备系统 libmpv，而不是重写为另一个音频播放器。项目已经采用桌面媒体引擎与移动媒体引擎分离的设计，Linux 的 libmpv 系统库使用方式也有官方包文档依据。[media_kit Linux 说明](https://pub.dev/packages/media_kit/versions/1.2.6)

本机源码检查发现：`media_kit_video` 的 Linux 完整实现需要相应 CMake 开关，且需 mpv/epoxy；当前 Linux 插件列表没有 Linux 媒体库包。因此“安装一个 libmpv 系统包”与“接通 Flutter 视频插件完整构建”应同时核验，不能只验证其中一项。

验收至少包含真实出声、播放进度增长、暂停/恢复、切歌、seek、结束自动下一首、音量范围、失效地址与网络中断。B 站还应分别检查裸 bvid / bvid:cid、Referer/UA、防盗链封面；之前 HTTP 206 仅证明请求可达，不证明播放器解码或输出成功。

MV 在第二阶段核验纹理输出、全屏、硬件/软件渲染回退和小窗。Wayland 无法满足全局置顶/定位时，小窗降级为普通可拖动窗口或应用内模式；失败应回滚窗口尺寸和置顶状态，避免主窗停留在异常小窗形态。

### 托盘与关闭策略：当前最明确的运行阻塞

当前 `DesktopTray.init` 无条件 await `setToolTip('kugo')`，没有局部异常处理；插件 0.5.3 的 Linux 原生分发没有该方法，文档也明确不支持它。**推断：补齐 runner 与其他依赖后，这条调用会抛出缺失实现异常并中断正常启动链路**，本次尚未运行 Linux GUI 来复现整条链路。[项目托盘代码](https://github.com/ZhengHaoF/kugoFlutter/blob/713ff00f18288001c56ace9f1f989bbb961d07cc/app/lib/shared/tray/desktop_tray.dart)、[插件方法支持表](https://pub.dev/packages/tray_manager/versions/0.5.3)

建议改为：

- **方法分流**：Linux 不调用 `setToolTip` 和 `popUpContextMenu`，交由 AppIndicator 的原生菜单交互。
- **图标资源**：Linux 使用 PNG 或发行包内图标名，Windows 保留 ICO；当前解析器三平台都使用 ICO，不应把 Linux ICO 一概断言为无法加载，但需要换成明确适用的资源。[项目图标解析](https://github.com/ZhengHaoF/kugoFlutter/blob/713ff00f18288001c56ace9f1f989bbb961d07cc/app/lib/shared/tray/desktop_tray.dart)、[插件示例图标选择](https://pub.dev/packages/tray_manager/versions/0.5.3)
- **启动降级**：托盘初始化异常不阻止 UI，明确保存“托盘不可用”状态。
- **关闭安全**：无可用托盘宿主时，不允许将窗口隐藏到无法恢复的位置；旧设置为 `tray` 也应回退为询问/退出。
- **恢复入口**：菜单始终包含“显示窗口”和“退出”，不能依赖 Windows 式图标点击事件。

GNOME 可能需要 AppIndicator 扩展才能显示图标，编译时存在插件不等于运行时存在可见托盘；扩展不能由应用偷偷安装或启用。[tray_manager 的 GNOME 提醒](https://pub.dev/packages/tray_manager/versions/0.5.3)

### 桌面歌词：应用内歌词可保留，悬浮歌词需要独立移植

当前桥接和设置入口按桌面平台开放，但 `DesktopLyricHost` 的通道方法依赖 HWND、WM_NCHITTEST、全局光标与 Windows 窗口语义。TCP IPC 和 Flutter 歌词渲染可以复用，Linux 原生窗口操作则不能直接复用。[当前歌词原生接口](https://github.com/ZhengHaoF/kugoFlutter/blob/713ff00f18288001c56ace9f1f989bbb961d07cc/app/lib/features/desktop_lyric/desktop_lyric_host.dart)

建议首版关闭 Linux 悬浮歌词开关、托盘菜单项和启动自动恢复，避免旧持久化设置启动一个通道缺失的子进程。后续保持“独立进程 + TCP snapshot”路线，为歌词进程增加 Linux GTK 原生适配并确认命令行参数传递，不切回 `desktop_multi_window` 来同时引入多引擎风险。

X11 版单独验证透明背景、置顶、任务栏隐藏、鼠标输入区域、拖动、锁定与解锁、多屏和缩放。鼠标穿透若导致无法解锁，先降级为可交互的歌词小窗，不将全窗穿透作为默认行为；IPC ready 超时、子进程异常退出和主进程退出均需回收资源。

原生 Wayland 普通 `xdg_toplevel` 不提供全局绝对位置或统一的 always-on-top 请求，不能承诺把 Windows 的定位/悬浮语义原样复制过去。特殊协议或合成器扩展需作为额外适配，不宜成为通用首版方案。[XDG shell 协议](https://wayland.app/protocols/xdg-shell)

建议 Wayland 默认使用应用内歌词或普通歌词窗口；若提供 XWayland 模式，作为独立可选路径验收，不宣称它与 X11 等价。需要平台通道返回“不支持某能力”，而非静默假成功。

### 系统媒体控制：MPRIS 增量接入

目前 Linux 不会初始化系统媒体桥，因此可能有应用内播控，但没有项目提供的系统媒体卡和媒体键桥接。[现有 Linux gate](https://github.com/ZhengHaoF/kugoFlutter/blob/713ff00f18288001c56ace9f1f989bbb961d07cc/app/lib/core/platform.dart)

建议 P1 先验证 `audio_service_mpris` 稳定版候选 0.2.1，复用 `KugoAudioHandler` 与 `KugoMediaBridge`；只有注册并验证 Linux 实现之后，才打开相应 gate。该版本支持播放/暂停、上下首、元数据、位置及 SetPosition，但不支持相对 Seek、Volume、Raise/Quit、Shuffle、TrackList/Playlists，不应宣称完整 MPRIS 能力。[audio_service_mpris 0.2.1 支持表](https://pub.dev/packages/audio_service_mpris/versions/0.2.1)

若基础控制足够，先保留这些限制；若产品要求完整能力，再评估直接 D-Bus 实现或其他已验证方案。Linux 媒体会话也不能等同于 Android 音频焦点和蓝牙 AVRCP，需分开验收。

### 存储、登录与文件选择

目录、SharedPreferences 和 SQLite 已有 Linux 实现，移植重点是实际路径、权限、持久化与原生包构建，不是重写数据模型。[path_provider_linux](https://pub.dev/packages/path_provider_linux/versions/2.2.2)、[shared_preferences_linux](https://pub.dev/packages/shared_preferences_linux/versions/2.4.1)、[SQLite 原生包](https://pub.dev/packages/sqlite3_flutter_libs/versions/0.5.42)

建议将应用 ID 固定，验证配置与缓存分别进入正确目录，安装/升级后不会丢失账号、队列或历史。扫码 UI 与 HTTP 协议可以复用，但真实扫码、账号重启恢复和收藏夹仍需用户实际账号验收；不通过邮件收集 Cookie，也不把 SharedPreferences 改称安全加密存储。

云盘文件选择器在 Linux 使用外部对话框程序，应测试未安装对话框程序、用户取消、中文/空格路径、大文件与权限拒绝。后续如采用沙盒打包，再评估 portal 文件选择方案；不要假设当前非沙盒实现自动适用。

## 分阶段实施与拟修改范围

所有步骤都需要后续授权实施，本次未执行。优先顺序是“稳定启动和真实播放”先于“功能数量与透明效果”。

| 阶段 | 拟修改范围 | 完成门槛 |
| --- | --- | --- |
| P0：最小 Linux 客户端 | 新增 `app/linux/`；pubspec 增加 Linux 媒体依赖；平台能力；main/desktop_shell 的降级；托盘方法/图标；设置与歌词入口门控 | Ubuntu 目标机能构建、显示主界面、真实出声、退出；无托盘仍可正常关闭；无缺失通道造成空窗 |
| P1：桌面可用性 | MPRIS；窗口与 MV 小窗后端降级；文件选择/portal 错误处理；持久化验收 | GNOME/KDE、X11/Wayland 的基础功能通过；系统控制真实作用于播放器；无不可恢复隐藏窗口 |
| P2：悬浮歌词与发行 | Linux 歌词原生宿主；子进程参数/生命周期；发行打包与回归矩阵 | X11 歌词满足明确能力清单；Wayland 限制可见；安装、升级、卸载和运行依赖核验通过 |

建议改动保持局部：不改变音源契约，不把平台判断撒到每个业务页面，不在同一个 PR 内升级全部插件。新增 Linux runner 通过正式分支与 PR 审查；生成文件与应用 ID 都需人工复核，而非在主分支直接执行生成命令。

## 构建与发行方案

### 后续构建环境准备

以下是候选 Ubuntu 构建机准备命令，不是本次已执行操作；具体包名需在目标发行版确认：

```bash
sudo apt-get update
sudo apt-get install -y \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev libstdc++-12-dev \
  libmpv-dev libepoxy-dev \
  libayatana-appindicator3-dev libasound2-dev \
  zenity

flutter doctor -v
```

基础编译工具依据 [Flutter Linux 配置文档](https://docs.flutter.dev/platform-integration/linux/setup)，libmpv 依据 [media_kit 1.2.6 文档](https://pub.dev/packages/media_kit/versions/1.2.6)，AppIndicator 依据 [tray_manager 0.5.3 文档](https://pub.dev/packages/tray_manager/versions/0.5.3)。epoxy、ALSA 与 zenity 为本次解析源码发现的补充项；运行环境还需检查实际音频服务、session D-Bus、图形驱动和相应 desktop portal。

准备环境之后，在适配分支中才生成 Linux runner，接齐依赖与门控，再执行：

```bash
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build linux --release
```

依赖解析建议固定应用锁文件、Flutter 版本与目标构建镜像，避免本次机器解析出来的传递插件变化成为不可复现问题。mimalloc 是 media_kit 文档提出的可选内存分配优化，不列为 P0 必须项；先做长时间播放观测，再决定是否加入。[media_kit 的 mimalloc 建议](https://pub.dev/packages/media_kit/versions/1.2.6)

### 发行策略

建议最初发布 Ubuntu x64 测试包，优先选择能声明系统依赖的 `.deb`，同时可提供完整 bundle 供内部测试。必须包含 `bundle` 的可执行文件、`lib` 与 `data`，不能只交付单个 ELF 文件；并检查主程序和原生插件共享库的动态依赖。[Flutter Linux 发行说明](https://docs.flutter.dev/platform-integration/linux/building)

在最低承诺发行版构建并在新版本验证，不使用当前 Ubuntu 26.04 构建结果承诺兼容 Ubuntu 22.04。libmpv 由 Dart 动态加载，单看主程序 `ldd` 不足以证明它存在，应同时做运行时初始化探针；检查 GLIBC/GLIBCXX 要求、GTK、AppIndicator、ALSA、epoxy 和编码支持。

AppImage、Flatpak、Snap 暂后置：它们会引入图标名、沙盒文件权限、session D-Bus/MPRIS、托盘与 GPU/音频访问等额外验收。若打包 libmpv/FFmpeg 等媒体库，发行前需整理所选构建的许可证及 notices，不能把“依赖能安装”当成打包合规结论。

## Linux 验收矩阵与退出标准

| 测试维度 | 建议覆盖 | 通过标准 |
| --- | --- | --- |
| 编译 | Ubuntu 22.04/24.04 x64，固定 SDK/锁文件 | Release 构建成功；完整 bundle；依赖无缺失 |
| 主窗 | GNOME 与 KDE；X11、原生 Wayland分别测试 | 中文正常、可拖动/缩放/关闭；DPI/多屏不产生不可见窗口 |
| 托盘 | 有托盘宿主、无托盘宿主/扩展 | 有宿主可恢复/退出；无宿主不崩、不进入无法恢复的隐藏状态 |
| 音频 | 三音源、不同格式与请求头 | 出声、进度、seek、切歌、结束推进、音量与错误恢复正确 |
| MV | 视频纹理、全屏、小窗、无硬件加速 | 不黑屏；能力受限时能降级并恢复主窗 |
| MPRIS | 媒体卡、播停、上下首、SetPosition | 系统操作对应同一播放器；已知不支持项不虚报 |
| 账号/存储 | 扫码、退出、重启、路径权限、升级 | 凭据与账号不串；清理正确；队列/历史稳定恢复 |
| 文件/云盘 | 对话框存在与缺失、中文路径、取消/无权限 | 错误可读，不崩溃；支持范围明确 |
| 歌词 | 应用内；后续 X11 悬浮；Wayland 降级 | 应用内可用；悬浮能力未完成不展示可用入口；无孤儿进程 |
| 稳定性 | 连续播放至少 2 小时、睡眠唤醒、网络切换 | 不泄漏式增长、不假播放、不遗留后台进程 |
| 跨平台回归 | 原有 Android/Windows 的编译及关键链路 | Linux 适配不改变既有平台能力与会话处理 |

CI 可以完成 analyze/test/build、依赖检查与部分虚拟显示启动冒烟，但不能替代真实桌面下的出声、媒体键、托盘宿主、多屏与 Wayland 限制验收。建议把“构建通过”“基础功能通过”“完整桌面集成通过”作为三个独立状态，而不是一个 Linux 兼容勾选框。

## 最终建议

**建议推进 Linux，但先做 P0 最小可用版本，而不是追求 Windows 功能全量搬迁。** 最先解决 runner、Linux 媒体依赖、托盘启动异常与歌词能力门控；这一阶段不重构音源层，也不需要改变既有播放控制器契约。

本次没有修改仓库代码、生成 Linux 平台目录或创建 PR。当前结论为“架构可行、存在明确接入缺口、尚未 Linux 构建/运行验收”；得到实施确认后，再按 P0、P1、P2 分别交付可审核的 PR。
