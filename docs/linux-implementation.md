# kugoFlutter Linux P0/P1 实施与验收记录

> 历史阶段记录：下文“P2 暂不做”“Linux 不开放悬浮歌词”等描述仅指 P0/P1 交付时。后续获授权实施的 X11 歌词方案与验收见 [X11 歌词记录](linux-x11-lyrics.md)，不改写本轮历史测试结果。

本次按授权实施 Linux P0/P1，P2 暂不做。代码基于主分支 `1e8acaf6a5504e62433adcfc26346e67cb5e2ae2`，适配分支为 `feat/linux-p0-p1`；原来的只读评估保存在 [兼容评估](linux-compatibility-assessment.md)，不改写其历史结论。

## 交付与状态

- **P0 代码接入**：Linux runner、原生媒体依赖、启动错误展示、托盘降级和 Linux 桌面歌词门控已实现。
- **P1 代码接入**：MPRIS、后端能力探测、窗口/MV 降级、文件选择错误处理、播放游标修复与原生持久化探针已实现。
- **自动验收**：已执行本地 Release 构建、静态分析、单元/Widget 回归，以及 X11 和原生 Wayland 的真实原生插件探针。测试不使用真实账号，音视频素材为离线合成文件。
- **目标桌面验收**：GNOME/KDE 媒体卡与媒体键、有宿主托盘、多屏/DPI、睡眠唤醒、实体扬声器和至少两小时播放仍待真实桌面验证。不能把代码接入或虚拟桌面通过写成完整桌面验收完成。
- **P2 排除项**：Linux 悬浮歌词原生宿主、透明/穿透、deb/AppImage/Flatpak/Snap 打包、安装升级卸载、打包许可证清单均未实施。

## 实施内容

### 原生工程与可复现构建

- **Linux runner**：新增 `app/linux/`，二进制名 `kugo`，应用 ID `com.kugo.kugo`，注册实际 GDK 后端探测通道，保留命令行参数传递。
- **媒体依赖**：增加 `media_kit_libs_linux 1.2.1` 与 `dbus ^0.7.15`，其余播放器架构不替换；提交应用 `pubspec.lock`，CI 使用 `--enforce-lockfile`。Linux 媒体库仍依赖系统 libmpv，不是自带全部运行依赖的独立安装包。[media_kit Linux 依赖说明](https://pub.dev/packages/media_kit/versions/1.2.6)
- **构建修正**：只对 `tray_manager_plugin` 放宽 AppIndicator 的 deprecated 声明警告为非致命，其余编译告警策略不全局关闭；按插件输出接入 mimalloc 静态库。没有修改缓存中的第三方插件源码。
- **CI**：新增 `.github/workflows/linux.yml`，Ubuntu 22.04/24.04 x64，固定 Flutter 3.47.7，执行依赖解析、分析、全量测试、生产构建、X11/嵌套 Wayland 探针并保存日志及 bundle。新增配置不等于远端 CI 已运行通过，最终运行状态以 PR checks 为准。

远端验收已闭环：代码提交 `e494b338c871deb19d2c5b78a98999945bf7d667` 在 Ubuntu 22.04 和 24.04 均通过锁文件校验、静态分析、1019 项测试、生产 Release 构建及 X11/原生 Wayland 探针，日志均输出 `ALL_CHECKS_PASSED`，并捕获非零音频 PCM。[通过的 GitHub Actions 运行](https://github.com/ZhengHaoF/kugoFlutter/actions/runs/38018536440)

两台 CI 的音频峰值均为 8000；Ubuntu 22.04 的 X11/Wayland 非零样本为 113700/101738，Ubuntu 24.04 为 102320/113238。后续提交仅补充此验收文档，不改变已验证的应用代码；真实桌面边界不因 CI 通过而取消。[对应 CI 日志与产物](https://github.com/ZhengHaoF/kugoFlutter/actions/runs/38018536440)

### 平台能力与降级

- **实际后端探测**：读取 GDK 的实际 X11/Wayland 后端，而非仅凭 `XDG_SESSION_TYPE`。XWayland 进程按其实际 X11 能力处理；未知后端采用保守策略。
- **桌面歌词**：原生歌词桥、独立进程分流、设置与托盘入口仅在 Windows 开放；Android 原有悬浮歌词保持。Linux 应用内歌词不关闭，不尝试调用 Windows HWND 通道。
- **启动失败**：初始化异常写入现有 CrashLog 并显示可读的错误页，不在界面展示可能包含敏感值的完整异常。GTK/链接库缺失导致进程无法进入 Dart 的错误仍需终端排查，不能由 Flutter 错误页兜住。
- **托盘方法与图标**：Linux 不调用不支持的 tooltip/手工 pop-up 方法，使用 PNG 图标；初始化失败不阻塞主窗。支持矩阵来自 [tray_manager 0.5.3](https://pub.dev/packages/tray_manager/versions/0.5.3)。
- **宿主检查**：通过 session D-Bus 查询 `IsStatusNotifierHostRegistered`，不是仅凭 watcher 名称判断；定时刷新并在关闭前重新查询。无宿主时旧的“关闭到托盘”偏好回落为询问，隐藏选项禁用，保留取消和退出。
- **主窗保存**：Wayland 只保存/恢复尺寸与最大化标志，不承诺绝对坐标；退出前显式保存最终尺寸。Wayland 的定位与置顶限制依据 [xdg-shell 协议](https://wayland.app/protocols/xdg-shell)。
- **数据库路径**：原生探针发现 Linux 没有 XDG Documents 配置时会初始化失败，因此 Linux 数据库改用 application support/XDG_DATA_HOME，Android/Windows 路径不变。此前仓库没有正式 Linux runner；用户自建旧 Linux 版本的 Documents 数据库不自动搬迁，升级前应另行备份核对。
- **MV 小窗**：X11 保留定位/置顶，Wayland 为普通可缩放小窗，不宣称系统 PiP 或跨应用始终置顶；失败时恢复窗口并返回普通播放页。
- **文件与唤醒**：文件选择错误转为可读提示，取消返回空列表；Linux 需 zenity/kdialog/qarma，缺失时不崩溃。既有唤醒失败降级保留，未新增沙盒 portal 实现。[file_picker 8.3.7](https://pub.dev/packages/file_picker/versions/8.3.7)

### MPRIS 与播放游标

评估原建议先考察 `audio_service_mpris 0.2.1`。实际检查已解析源码后发现 Stop 分发缺口、track ID 未输出及若干能力声明不能满足本轮要求，因此没有接入该包，改为通过 `dbus` 编写独立 Linux `KugoMediaBridge`，不替换 Windows/移动端媒体桥。

- **真实命令**：Play、Pause、PlayPause、Stop、Next、Previous、相对 Seek、SetPosition、Volume、LoopStatus、Shuffle 均转发到同一个 PlayerController。
- **正确单位**：D-Bus 位置/时长为微秒，控制器使用毫秒；定位验证当前 track ID，过时或越界定位不误作用于其他曲目。
- **元数据**：输出稳定合法的 object-path track ID、标题、歌手、专辑、时长和缓存封面的本地 file URI；不广播播放直链、签名参数或 Cookie。封面仍复用按源 Referer 下载的 CoverCache。
- **能力边界**：Raise/Quit、OpenUri、TrackList/Playlists 未提供，固定速率为 1；这些项明确不可用，不伪报支持。Shuffle 与 LoopStatus 映射到现有互斥队列模式，并非新增可组合的独立播放模式。
- **资源与失败**：只使用现有 session bus，注册失败不阻止主 UI，退出释放 bus。连续位置不通过 PropertiesChanged 高频广播，读取 Position 使用实时游标。
- **原生验收发现的修复**：系统位置预测时钟在音频缓冲期间可能领先引擎；原逻辑将界面游标也绑定到该预测门控，造成实际出声但进度停留。现在界面游标独立接纳单调向前的真实引擎样本，seek 仍可重置；增加回归用例防止复发。

## 已执行验收与证据

本地环境为 Ubuntu 26.04.1 x86_64、Flutter 3.47.7 / Dart 3.13.5。虚拟 X11 使用 Xvfb + Openbox；原生 Wayland 客户端连接嵌套 Weston 的 Wayland socket，而不是 XWayland；音频使用真实 libmpv 解码并由 PulseAudio null sink 的 monitor 捕获 PCM。

| 项目 | 当前证据 | 边界 |
| --- | --- | --- |
| 静态分析 | `flutter analyze --no-pub` 无问题 | tool 目录不在常规 analyze 范围，探针另行真实编译 |
| 全量测试 | 1019 项通过；存储路径/托盘并发收尾后 38 项定向测试通过，远端 CI 再跑全量 | 单元/Widget 证据，不替代实体桌面 |
| 生产 Release | `flutter build linux --release --no-pub` 成功 | 本机构建，不承诺跨发行版 ABI |
| 主应用 UI | X11/原生 Wayland 主界面显示、中文/导航正常；无 session bus 时关闭弹出取消/退出，点击退出进程结束 | 无真实账号登录 |
| 音频 | 严格检查 Referer/UA 的本地 HTTP WAV，libmpv 解码，实际游标推进，PCM 非零 | 合成音频、虚拟输出，不是听觉验收 |
| MPRIS | 真实 session D-Bus 的播放/暂停/切歌/Stop/SetPosition/音量操作通过 | GNOME/KDE 媒体卡、物理媒体键待测 |
| MV | 真实 video 插件输出 320×180 解码纹理，X11/Wayland 截图均可见测试图案 | 软件渲染，不证明各 GPU 的硬件加速 |
| 窗口后端 | 原生探测分别返回 x11/wayland，小窗进入与尺寸恢复通过 | 不覆盖多屏、缩放或所有 compositor |
| 持久化 | 探针读写 SharedPreferences 与 SQLite 关闭重开检查 | 不等于账号凭据/升级验收 |
| 托盘安全 | mock 方法门控、真实私有 D-Bus 宿主属性、无托盘关闭 UI 单元测试 | 真实 GNOME 扩展/KDE 托盘恢复待测 |
| 文件选择 | 异常和取消分支单元测试 | 桌面交互/中文路径/权限拒绝仍需实测 |

较早探针曾仅检查纹理创建，截图出现黑区，因此收紧为等待实际 320×180 帧并检查截图；较早探针也暴露游标门控问题，修复后重新执行。失败记录不作为通过证据。

最终 X11/Wayland 原生探针均输出 `ALL_CHECKS_PASSED`，捕获 PCM 峰值均为 8000，非零样本数分别为 102414 / 107812。这是虚拟音频输出证据，不是实体扬声器听觉证据；SQLite 写入后关闭并重开恢复队列和历史，SharedPreferences 也实际落盘。

可审查的证据随本仓库提交：[X11 探针日志](linux-evidence/x11-probe.log)、[Wayland 探针日志](linux-evidence/wayland-probe.log)、[X11 可见视频截图](linux-evidence/x11-probe.png)、[原生 Wayland 可见视频截图](linux-evidence/wayland-probe.png)、[生产版无托盘关闭截图](linux-evidence/no-tray-close.png)。日志仅保留验收结果，截图使用隔离测试目录和游客态，不包含真实登录信息。

## 本地构建与复跑

构建工具基础要求参见 [Flutter Linux 配置](https://docs.flutter.dev/platform-integration/linux/setup)。以下命令从仓库根目录开始，在有适合版本 SDK 的 Ubuntu 构建机执行：

```bash
sudo apt-get update
sudo apt-get install -y clang cmake ninja-build pkg-config \
  libgtk-3-dev libstdc++-12-dev libmpv-dev libepoxy-dev \
  libayatana-appindicator3-dev libasound2-dev zenity
cd app
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
flutter build linux --release --no-pub
./build/linux/x64/release/bundle/kugo
```

本轮 bundle 尚非安装包；运行时应保留完整的 lib/data 目录，并安装相应系统运行依赖，不要只复制 ELF。[Flutter Linux 构建与分发](https://docs.flutter.dev/platform-integration/linux/building)

原生验收脚本会使用隔离的 XDG 目录、测试音视频与测试音频服务，不读取已有账号。脚本需要 node、ffmpeg、xvfb、openbox、dbus-x11、pulseaudio、pulseaudio-utils、imagemagick、ripgrep；Wayland 检查额外需要 weston：

```bash
flutter build linux --release --no-pub -t tool/linux_integration_probe.dart
xvfb-run -a -s '-screen 0 1440x1000x24' dbus-run-session -- \
  bash tool/run_linux_probe.sh build/linux/x64/release/bundle/kugo build/probe-x11
KUGO_PROBE_BACKEND=wayland xvfb-run -a -s '-screen 0 1600x1200x24' \
  dbus-run-session -- bash tool/run_linux_probe.sh \
  build/linux/x64/release/bundle/kugo build/probe-wayland
# 探针与生产版共用产物目录，完成后必须重新构建正式入口：
flutter build linux --release --no-pub
```

## 收尾门槛与后续真实验收

本次交付状态应表述为“P0/P1 代码接入和可执行自动验收完成，真实桌面矩阵未闭环”，而不是“Linux 全功能兼容”。不直接合并主分支；先通过 PR checks 和代码审查。

- **Ubuntu 目标版本**：以 22.04/24.04 CI 结果确认构建，不以 26.04 ELF 推断旧系统兼容。
- **GNOME/KDE**：分别验证托盘宿主存在/消失、系统媒体卡、恢复与真正退出；无宿主不得产生不可恢复隐藏窗口。
- **音频与桌面**：实体音响/蓝牙、连续播放两小时、睡眠唤醒、网络切换、DPI/多屏与硬件加速。
- **账号**：真实扫码、账号重启恢复、收藏夹分页/权限、UP 主风控，需持有者在自身设备完成；不收集 Cookie 或把普通 SharedPreferences 称为加密密钥库。
- **跨平台**：Android/Windows 真机构建与关键播放/媒体集成回归。本 Linux 环境的测试不能代替这两类真机证据。

这些均为 P0/P1 的剩余验收，不转移到 P2 掩盖。P2 继续搁置，未经再次确认不启动悬浮歌词原生开发或发行打包。
