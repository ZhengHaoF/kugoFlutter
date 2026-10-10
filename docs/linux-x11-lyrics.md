# kugoFlutter Linux X11 悬浮歌词方案与验收记录

本轮仅推进 P2 的 X11 悬浮歌词，沿用现有双进程、TCP 快照、LRC/KRC 渲染和样式设置，不重写播放器。代码与本记录一并提交到 `feat/linux-x11-lyrics`；基础为 P0/P1 分支提交 `ba4591033ae59db5e185b3c70f1793220aab4a34`，不直接合并主分支。

## 范围与使用

- **入口**：Linux 应用实际使用 GDK X11 后端时，系统设置显示桌面歌词开关，存在托盘时也开放原有托盘入口。没有托盘仍可在设置中开关及解除锁定。
- **透明与置顶**：GTK RGBA visual、Flutter 清空背景和窗口管理器 keep-above 提示；合成器启动时可用才开启 alpha。没有合成器时使用深色歌词卡片，不承诺透明。
- **交互**：未锁定可拖动，锁定时鼠标事件穿透到下方应用；移动到右下角解锁按钮时临时恢复交互。窗口默认顶部居中，支持恢复与重置位置。
- **同步**：复用曲目、歌词、逐字时间、播放/暂停、seek、偏移、翻译和样式快照。字号增大时自动调整窗口高度，避免原来固定 88 像素裁切。
- **排除项**：原生 Wayland 全局悬浮能力、发行安装包、ARM64、GNOME Shell/KDE 扩展和真实账号验收不在本轮范围内。XWayland 若被实际检测为 X11 可以尝试，但没有据此承诺原生 Wayland 能力。

Wayland 使用独立门控：后端未知或原生 Wayland 时不展示该入口，强行使用歌词启动参数会退出而非再开一个主窗。没有用 `XDG_SESSION_TYPE` 猜测应用后端，也没有把 X11 的位置能力冒充 Wayland 支持；原生 xdg-shell 不提供通用的全局绝对定位或始终置顶接口。[xdg-shell 协议](https://wayland.app/protocols/xdg-shell)

## 实施方案与实际改动

### 原生窗口宿主

新增 `app/linux/runner/desktop_lyric_host.{h,cc}`，在 `my_application.cc` 中为歌词进程准备独立 GTK 窗口、移除标题栏，并在首次 Flutter 帧时保持隐藏直到 Dart 初始化完毕。主窗不使用歌词宿主；Linux 实现不返回或复用 Windows HWND。

- **通道**：`kugo/desktop_lyric_host` 实现尺寸、位置、顶部居中、显示/隐藏、置顶、任务栏提示、光标位置、拖动和可见区域检查。
- **输入区域**：GDK input shape 管理输入范围；对 Openbox 这类重设父窗口的管理器，还同步自身 WM frame 的 ShapeInput。只给客户端设空区域时，外层 frame 仍能吞掉点击，已用真实下层窗口收到的 ButtonPress 验证修正。
- **拖动安全**：开始原生拖动前检查鼠标左键仍按下，避免异步 Flutter 手势在按钮释放后启动 WM move 并留下输入抓取。锁定时释放抓取，隐藏/显示与 configure 事件重新应用输入区域。
- **位置持久化**：原生 configure-event 在 150 ms 防抖后发送 `boundsChanged`，子进程经 IPC 回传主窗写 SharedPreferences。不依赖可能被 WM 吃掉的 Flutter onPanEnd；允许有限负坐标以适配左侧/上方屏幕，恢复时检查显示器工作区，越界回默认位。
- **字号与热区**：Linux 字号对应 88–176 逻辑像素高度；歌词视图 Stack 撑满窗口，修正解锁按钮可见位置与光标轮询命中区不一致。

新增系统构建依赖为 `libx11-dev`、`libxext-dev`，runner 显式要求 C++17，不引入新的 Dart package。首次 Ubuntu 22.04 CI 的全量测试通过，但较旧编译器因未声明 C++17 而无法识别 `std::clamp`；已补齐目标标准声明，不能用本地较新编译器的默认行为代替兼容要求。运行时还依赖 X11/Shape 扩展和现有 GTK/媒体库；完整 Flutter bundle 的 lib/data 目录仍必须一起分发，不能只复制 ELF。[Flutter Linux 构建与分发](https://docs.flutter.dev/platform-integration/linux/building)

### 双进程生命周期与 IPC

- **连接校验**：每次 Linux 启动生成随机 32 字节 nonce，经子进程环境传递。TCP 仅绑定 loopback；接入方必须在 3 秒内提交正确 hello，校验通过才替换旧连接，避免无凭据连接中断已有歌词窗。
- **失败恢复**：8 秒未 ready 时结束未响应子进程，子进程退出更新开关状态。歌词进程缺端口/nonce 或连接失败不会进入孤立空窗。
- **退出与重用**：正常隐藏保持进程和 IPC，再次开启保持 Linux 位置；主窗连接断开或收到 close 时歌词进程退出。清理先捕获旧资源再 await，避免旧进程退出回调清掉新连接，Linux 子进程 stdout/stderr 持续 drain 防止长时运行管道堵塞。
- **跨平台边界**：Windows 保留原有顶部居中和进程路径，不强制 nonce 握手；Android overlay 不调整。共享 Dart 歌词视图的布局有小范围改动，真实 Android/Windows 回归仍待完成。

nonce 是防止无凭据 loopback 连接误接的防护，不是对同一用户下恶意进程的安全隔离：同 UID 进程可能读取环境或调试进程。日志不记录 nonce，也不把它放进 CLI 参数；不声称已建立强本地攻击边界。

## 验收结果与证据

本地环境为 Ubuntu 26.04.1 x86_64，Flutter 3.47.7 / Dart 3.13.5；GUI 使用 Xvfb、Openbox、picom 和软件 GL。测试使用隔离 XDG 数据目录及合成歌词/音视频，不包含真实登录凭据；这些结果不是物理显示器、声卡或完整 GNOME/KDE 桌面认证。

| 检查 | 本地结果 | 证据边界 |
|---|---|---|
| 静态分析 | 无问题 | `flutter analyze --no-pub` |
| 全量 Dart/Widget 测试 | 1023 项通过 | 包含 nonce、socket 清理、解锁布局及负坐标回归 |
| Linux Release | 构建成功 | 当前构建机，不承诺跨发行版 ABI |
| 合成器 X11 | 14 条原生检查通过 | 窗口属性、透明像素对照、下层真实点击、解锁、拖动、位置回传、重置、进程重用及 IPC 退出 |
| 无合成器 X11 | 同一组 14 条检查通过 | 使用不透明深色卡片，穿透仍通过 |
| 2 倍 DPI X11 | 同一组 14 条检查通过 | `GDK_SCALE=2 GDK_DPI_SCALE=0.5`，不是混合 DPI 多屏 |
| 正式主窗到子窗 | 位置落盘、主进程停止后子窗退出、重启恢复、子进程异常退出重置开关通过 | 实际生产入口和 SharedPreferences，不是 Node 替代主窗 |
| 非法 IPC 连接 | 被拒绝，已有歌词窗口保留 | 实际正式主窗的 TCP server |
| P0/P1 回归 | X11 与嵌套原生 Wayland 均通过 | libmpv HTTP/解码、虚拟 PCM、MPRIS、SQLite、SharedPreferences 和可见视频纹理 |

证据保存在 `docs/linux-x11-evidence/`，其中 [合成器探针日志](linux-x11-evidence/composited.log)、[卡片降级探针日志](linux-x11-evidence/fallback.log)、[高 DPI 探针日志](linux-x11-evidence/hidpi.log)、[正式主窗探针日志](linux-x11-evidence/main.log) 为自动断言。透明对照、无合成器大字号卡片、高 DPI 和重启后正式主窗截图也随 Git 提交，截图本身不替代事件与像素断言。

`.github/workflows/linux.yml` 在 Ubuntu 22.04/24.04 x64 运行分析、全量测试、Release、三种生产歌词探针及 P0/P1 X11/Wayland 探针，并保存产物。正式主窗的固定坐标 GUI 操作脚本只作本地复跑，不放进跨版本 CI；远端结果以 PR checks 和 Actions 状态为准，新增配置本身不算远端通过。

## 复跑命令

在有上述 SDK 的 Ubuntu 构建机安装 P0/P1 原有依赖及 `picom xdotool x11-utils libx11-dev libxext-dev`，从仓库根目录执行：

```bash
cd app
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
flutter build linux --release --no-pub
xvfb-run -a -s '-screen 0 1440x1000x24' dbus-run-session -- \
  bash tool/run_x11_lyric_probe.sh \
  build/linux/x64/release/bundle/kugo build/lyric-x11
KUGO_COMPOSITOR=0 xvfb-run -a -s '-screen 0 1440x1000x24' \
  dbus-run-session -- bash tool/run_x11_lyric_probe.sh \
  build/linux/x64/release/bundle/kugo build/lyric-fallback
GDK_SCALE=2 GDK_DPI_SCALE=0.5 xvfb-run -a \
  -s '-screen 0 2880x2000x24' dbus-run-session -- \
  bash tool/run_x11_lyric_probe.sh \
  build/linux/x64/release/bundle/kugo build/lyric-hidpi
set -o pipefail
mkdir -p build/lyric-main
xvfb-run -a -s '-screen 0 1440x1000x24' dbus-run-session -- \
  bash tool/run_x11_main_lyric_probe.sh \
  build/linux/x64/release/bundle/kugo build/lyric-main \
  | tee build/lyric-main/probe.log
```

正式主窗脚本依赖固定虚拟屏幕尺寸和初始设置页布局，勿用于已有个人配置或真实账号工作区。管道启用 `pipefail` 才能正确传播验收失败。

## 尚未完成的真实桌面矩阵

- **桌面环境**：真实 GNOME Xorg、KDE X11 的置顶策略、无托盘操作、输入穿透/解锁与窗口关闭；全屏应用可能有独立 WM 置顶策略，不承诺覆盖所有全屏窗口。
- **显示器**：左右/上下布局、拔插恢复、工作区变化、分数缩放与混合 DPI；负坐标测试不等同于多显示器实测。
- **合成器**：运行中开启/关闭合成器未闭环；透明能力在子窗启动时选择，变更后应关闭并重启应用再试。
- **长时与跨平台**：两小时播放/切歌/seek、实际音源 LRC/KRC、实体 GPU 与 Windows/Android 真机回归。当前离线快照与虚拟音频证据不能取代这些检查。
- **后续 P2**：`.deb`/AppImage 等发行打包和原生 Wayland 替代歌词体验仍待另行推进，本 PR 不捎带实施。

交付结论是“X11 悬浮歌词实现及可复跑的虚拟桌面自动验收完成”，不是“全部 Linux 桌面兼容已认证”。采用独立 PR 供审查；P0/P1 PR 若尚未合并，则本 PR 先以该分支为基底，之后再改为 main。
