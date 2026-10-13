# kugo → 泛音（Overtone）改名实施文档

> 文档版本：v1.0 · 实施计划（待执行，按 Step 顺序逐项改）
> 决策来源：2026-10-13 项目名评估结论（对外名称定为「泛音 / Overtone」）
> 用户确认：**老用户本地数据不做兼容**，DB 可直接切换路径。
>
> **背景**：项目已从单酷狗源演进为酷狗 + 网易云 + 哔哩哔哩三音源（`MusicPlatform { kugou, netease, bili }`），
> 旧名 `kugo` 既名不副实，也与 README「合规声明」及 [设计方案](../设计方案.md) §1.4
> 「对外发布请勿使用『酷狗』注册商标作为应用名」的自我要求冲突。本次改名同时是补合规债。

---

## 0. 命名决策

| 项 | 新值 | 说明 |
| --- | --- | --- |
| 对外名称（中文） | **泛音** | Android label / iOS 显示名 / 窗口标题 / 通知渠道 / MPRIS Identity |
| 对外名称（英文） | **Overtone** | Runner.rc ProductName、安装包描述、Release 标题 |
| 仓库目录 / GitHub | `overtone`（`ZhengHaoF/overtone`） | 顺带修掉 `kugoFulutter` 的拼写错误 |
| pubspec `name` | `overtone` | `app/lib` 用相对 import 不受影响；但 `app/test`(127 个文件) 与 `app/tool`(16 个脚本) 共 **602 行 `package:kugo/` 绝对导入**必须同 commit 替换，见 §3.1 |
| 应用级 Dart 符号 | `Overtone*` | `KugoTheme` → `OvertoneTheme` 等，见 §5 映射表 |
| 酷狗平台级符号 | `Kugou*` | `KugoSign` → `KugouSign` 等，与既有 `KugouSource` / `KugouSession` 对齐 |
| 局部变量 | `theme` | `final kugo = KugoTheme.of(context)` → `final theme = OvertoneTheme.of(context)` |
| camelCase 小写标识符 | `overtone*` | `kugoNavigatorKey` → `overtoneNavigatorKey` 等，见 §5.4 |
| 方法通道 / 跨进程环境变量 | `overtone/*`、`OVERTONE_LYRIC_*` | Dart 与原生**必须同一 commit** 改，见 §6 |
| 存储键 / 设备指纹 | 见 §1.1 | `dev` 字段建议改为 `overtoneFlutter`，依据见 §1.2 |

### 0.1 明确不改（附理由，避免反复）

| 项 | 保持 | 理由 |
| --- | --- | --- |
| Android `applicationId` | `com.kugo.kugo` | 改动要求老用户卸载重装，侧载场景零收益 |
| iOS bundle id | `com.kugo.kugo` | 同上 |
| Windows AUMID | `com.kugo.player` | 用户不可见、无合规问题；改 AUMID 会让旧 `kugo.lnk` 过不了身份校验成为僵尸快捷方式，并重置 SMTC 媒体标识 |
| Android Kotlin 包名 | `com.kugo.kugo` | 跟随 applicationId |
| MPRIS `DesktopEntry` | `com.kugo.kugo` | 与 applicationId 保持一致 |
| 签名 keystore | `FlutterMusic.jks` / `upload-keystore.jks` | 文件名与签名身份无关，不动 |
| `app/android/key.properties` | 密码字面量 `kugo-1wgvixzfyte70o4j` | 该文件被 `.gitignore` 忽略、未入库，是本地密钥；**改了 keystore 立即失效**，绝对不动 |
| `docs/api-notes.md` 等约 90 处 `kugou` | 原样 | 平台词，非项目代号，改了反而错 |

---

## 1. 老用户数据（已确认不兼容）

- `app/lib/data/storage/kugo_db.dart:181` 的 `<support>/kugo/kugo.sqlite`
  直接改为 `<support>/overtone/overtone.sqlite`，**不写迁移逻辑**。
- 旧目录 `kugo/` 成为孤儿数据。可选：首次启动检测到旧目录时弹一次提示「旧版本数据未迁移」。
- 升级后果：本地播放队列、历史、收藏缓存丢失，需重新登录从云端拉取。

### 1.1 存储键与设备指纹：先定原则，再逐项定夺

**原则：只改「会流出本机」和「用户可见」的，不改「纯本地存储键名」。**
存储键名不上传、不展示、无合规压力；改它们却会让老用户丢登录态 / 重置设备身份。
而「老用户数据不兼容」针对的是 drift DB（队列 / 历史 / 收藏）——SharedPreferences 与
secure storage 不在其内，没必要连带牺牲。

| 位置 | 现状 | 会流出本机吗 | 建议 |
| --- | --- | --- | --- |
| `credential_store.dart:30` | secure storage 键 `'kugo.credentials.$key'` | 否 | **保留**。改了全体用户强制重新登录，键名却无任何合规 / 展示问题 |
| `device_identity.dart:33-38` | 六个 prefs 键 `kugo_device_dfid` / `_guid` / `_mid` / `_dev` / `_dfid_registered` / `_dfid_tried_at` | 否 | **保留**。老用户由此延续已注册的 `dfid`，避免酷狗风控对评论 / 歌单接口返回 `err_code=20028`（见该类注释） |
| `device_identity.dart:60` | `dev = 'kugoFlutter'` | **是**（API 头 + 登录签名） | **改为 `overtoneFlutter`**，依据见 §1.2；老用户本地已存的值不变，只影响新安装 |
| `device_identity.dart:55` | guid 随机种子 `'kugo-flutter-${now}-…'` | 否（只做 md5 熵输入，不作为值上报） | 可改 `overtone-flutter-`，无兼容影响 |
| `auth_token_holder.dart:8-9, 83-84` | 默认 `kugo_flutter_mid` / `kugo_flutter_guid` | 间接（登录后被真实值覆盖，仅未登录时的默认值） | 改为 `overtone_flutter_*` |
| `live_probe_controller.dart:82-83` | 调试探针参数 `'mid': 'kugo_mid'` / `'guid': 'kugo_guid'` | 是（仅调试探针） | 可改 `overtone_mid` / `overtone_guid`（低风险） |

**因此最终验收时，`kugo_device_*` / `kugo.credentials.` 这两类键名属于「预期保留」**，
不是漏改，见 §10。

### 1.2 `dev` 字段说明（为什么从「建议保留」改为「建议改」）

`dev` 是本应用与酷狗 API 通信时持久化的 5 个设备标识之一（`dfid` / `guid` / `mid` / `dev` / `mac`）。
首次启动生成后写入 SharedPreferences 键 `kugo_device_dev`，**此后永久沿用**——
`DeviceIdentity.reset()`（设置里的「清除设备」）都不清除它。它出现在三类地方：

1. **HTTP 头 `KUGOU_API_DEV=kugoFlutter`**：cloud / fm / login / playlist / discovery / user /
   recommend 等 10+ 个 repository 的请求都带；
2. **请求体字段 `'dev': device.dev`**：`login_repository.dart:311`（验证码登录）、`:375`（密码登录）；
3. **登录签名的明文原料**：`login_repository.dart:282` 把
   `${guid}|0f607264fc6318a92b9e13c65db7cd3c|${mac}|${dev}|$timestamp` AES 加密成 `t2` 参数。

**参考实现的实测证据**：本项目的主要参考实现 [EchoMusic](D:/work/EchoMusic)
`src/main/server.ts:44` 硬编码 `const SERVER_DEV = 'EchoMusic'`，并以
`KUGOU_API_DEV=EchoMusic` 发给每一个请求。这说明：

- 该字段是**客户端自定义标识**，不是服务端签发、也不做格式校验——任意应用名字符串在生产环境可用；
- 参考实现用的就是它自己的应用名，那么把 `kugoFlutter` 留在每个请求头里，
  恰是本次改名要清除的遗留品牌信息。

**残留风险与缓解**：EchoMusic 未实现 `login_by_verifycode` / `t2` 签名登录
（已 grep 确认无此代码路径），所以第 3 处用法没有参考覆盖。缓解办法：
改完后真机冒烟一次**短信验证码登录 + 密码登录**；若失败，`git revert` 单独这一行即可，
不涉及任何数据迁移（老用户本地存的值本来就不会变）。

---

## 2. Step 1：对外名称（用户可见字符串，零风险）

| 文件 | 行 | 现状 | 改为 |
| --- | --- | --- | --- |
| `app/android/app/src/main/AndroidManifest.xml` | 12 | `android:label="kugo"` | `android:label="泛音"` |
| `app/ios/Runner/Info.plist` | 10 | `CFBundleDisplayName` = `Kugo` | `泛音` |
| `app/ios/Runner/Info.plist` | 18 | `CFBundleName` = `kugo` | `泛音` |
| `app/windows/runner/Runner.rc` | 93–99 | CompanyName / FileDescription / InternalName / OriginalFilename / ProductName / LegalCopyright 共 6 个 `kugo` | ProductName 等显示字段用 `泛音 Overtone`；CompanyName / LegalCopyright 用 `com.overtone`；OriginalFilename 在 Step 3 随 `BINARY_NAME` 改 |
| `app/windows/runner/main.cpp` | 60 | `window.Create(L"kugo", …)` 主窗标题 | `L"泛音"` |
| `app/windows/runner/main.cpp` | 43 | `window.Create(L"kugo-lyric", …)` 歌词窗标题 | `L"overtone-lyric"` |
| `app/linux/runner/my_application.cc` | 71, 75 | 标题栏 / 窗口标题 `"kugo"` | `"泛音"` |
| `app/windows/runner/app_identity.cpp` | 16 | `kAppDisplayName = L"kugo"` | `L"泛音"`（**第 14 行 AUMID 不动**） |
| `app/lib/main.dart` | 198 | `androidNotificationChannelName: 'kugo 播放'` | `'泛音 播放'`（第 197 行 channelId `com.kugo.player` **不动**，与 AUMID 对齐） |
| `app/lib/shared/widgets/settings_pickers.dart` | 182 | About 页「定位」= `酷狗概念版第三方客户端` | `多音源第三方客户端` |
| `app/lib/features/player/linux_media_bridge.dart` | 151 | MPRIS `'Identity': 'kugo'` | `'Overtone'` |
| `app/lib/features/player/linux_media_bridge.dart` | 79 | `$mprisRoot.kugo.instance$pid` | `$mprisRoot.overtone.instance$pid` |
| `app/windows/runner/desktop_media_host.cpp` | 120 | 播控横条窗口标题 `L"kugo 播控横条"` | `L"泛音 播控横条"` |
| `app/windows/runner/desktop_media_host.cpp` | 246 / `.h` 62 | 播控条默认标题 `L"kugo"` | `L"泛音"` |
| `app/windows/runner/desktop_media_host.cpp` | 14 | 播控条窗口类名 `L"KugoDesktopMediaBar"` | `L"OvertoneDesktopMediaBar"`（两侧同文件内自洽） |
| `app/lib/shared/tray/desktop_tray.dart` | 111 | 托盘提示 `trayManager.setToolTip('kugo')` | `'泛音'` |
| `app/lib/core/diagnostics/startup_gate.dart` | 81, 84 | 启动失败/启动中提示 `'kugo 启动失败…'` / `'正在启动 kugo…'` | `'泛音 启动失败…'` / `'正在启动泛音…'` |
| `app/lib/shared/branding/app_logo.dart` | 18 | Logo 无障碍标签 `semanticLabel: 'kugo'` | `'泛音'` |
| `app/lib/shared/tray/desktop_shell.dart` | 223 | SMTC / MPRIS 媒体标题 `'kugo · $name'` / `'kugo · $name · $artist'` | `'泛音 · …'` |
| `app/lib/shared/tray/close_behavior_dialog.dart` | 36 | 关闭行为对话框标题 `'关闭 kugo'`（测试 `close_behavior_dialog_test.dart:36,48,70` 断言同一字符串，需同步） | `'关闭 泛音'` |
| `app/lib/features/debug/network_log_dialog.dart` | 151 | 网络日志复制 / 导出头 `'== kugo 网络日志 ==\n\n$text'` | `'== 泛音 网络日志 ==…'` |
| `README.md` | 109 | 合规声明「对外发布请勿使用『酷狗』注册商标作为应用名」 | 「应用名『泛音』与各音乐平台无关联」 |

顺手可改（可选）：`settings_pickers.dart:181` About 页「形态」= `Android · 移动端优先` 已过时（Windows / Linux 已落地），改为 `Android · Windows · Linux`。

**本轮已全文核对的文件**（确认无其他引用，不必再查）：`AndroidManifest.xml` 全文仅 label 一处；
`Info.plist` 仅 DisplayName / CFBundleName 两处；`res/values/colors.xml` 与 `values-night/` 只有
引用 `KugoPalette` 的注释（随第二轮正则一起改即保持一致）；`res/xml/` 与 proguard 规则不存在；
Kotlin 侧除包名 `com.kugo.kugo` 外只有 `lyric_overlay` 通道；`AppDelegate.swift`、
`linux/runner/main.cc`、`flutter_window.h`、`win32_window.h` 无引用。
Android 构建配置层（`app/android/build.gradle.kts`、`settings.gradle.kts`、`gradle.properties`）
与 `.github/`（仅 `workflows/apps.yml` 一个文件）已确认无遗漏；iOS 生成物中的绝对路径见 §7 第 0 步。

**验收**：`rg -niP '"kugo"|kugo\.exe|kugo 播放|kugo 播控' app README.md` 只应剩 Step 3 待改项；`flutter run -d windows` 窗口标题、托盘提示、SMTC、播控横条显示「泛音」。

---

## 3. Step 2：pubspec 与文档标题

### 3.1 pubspec `name` 与 `package:kugo/` 绝对导入（必须同一 commit）

`app/lib` 全部用相对 import，改 pubspec `name` 不影响它；**但 `app/test` 127 个文件和
`app/tool` 16 个脚本共 602 行用的是 `package:kugo/...` 绝对导入**（如
`app/test/flutter_test_config.dart:5`、`app/test/p1_storage_test.dart:9`、
`app/tool/windows_audio_probe.dart:26`）。pubspec 改名后这些导入**全部编译失败**。

| 文件 | 现状 | 改为 |
| --- | --- | --- |
| `app/pubspec.yaml` | 1 `name: kugo`；2 description「酷狗概念版第三方 Flutter 客户端（学习/研究向）」 | `name: overtone`；「多音源第三方 Flutter 客户端（学习/研究向）」 |
| `app/test/**`（127 个文件） | `import 'package:kugo/…'` 共 586 行 | `import 'package:overtone/…'` |
| `app/tool/**`（16 个脚本） | `import 'package:kugo/…'` 共 16 行 | `import 'package:overtone/…'` |

替换命令（一条正则即可，注意别碰 `package:kugo/…kugou…` 里的平台词——
只替换 `package:kugo/` 前缀本身）：

```powershell
# PowerShell 7；仓库内 .dart 均为 UTF-8 无 BOM，必须显式指定编码，
# 否则 Windows PowerShell 5.1 会写成 UTF-16，中文注释全变乱码。
rg -l "package:kugo/" app/test app/tool | ForEach-Object {
  (Get-Content $_ -Raw -Encoding utf8) -replace "package:kugo/", "package:overtone/" |
    Set-Content $_ -NoNewline -Encoding utf8NoBOM
}
```

改完必须 `flutter pub get` 重新生成 `.dart_tool/package_config.json`，否则 IDE 与
`flutter test` 仍按旧包名解析。

### 3.2 文档标题

| 文件 | 现状 | 改为 |
| --- | --- | --- |
| `README.md` | 1 标题 `# kugoFulutter`；3 副标题「酷狗概念版第三方 Flutter 客户端」；7 中 `kugo.exe` 与 releases 链接 | `# 泛音 Overtone`；「多音源第三方 Flutter 客户端」；`kugo.exe` 与链接在 Step 3 / Step 6 改 |
| `app/README.md` | 1 标题 `# kugo — 酷狗概念版第三方 Flutter 客户端` | `# 泛音 Overtone — 多音源第三方 Flutter 客户端` |
| `设计方案.md` | 3 项目代号 `kugo`（仓库目录 `kugoFulutter`）；46 §1.4 合规段「内部代号 `kugo`，对外名称建议另拟」；141 目录树 `kugoFulutter/`；354–364 `KugoColors` / `KugoRadius` / `KugoSpacing` | 代号改 `overtone`；§1.4 该句结案为「对外名称已定为泛音 Overtone」；目录树同步；符号名随 Step 4 |
| `多音源接入方案.md` | 3 页首「项目：`kugoFulutter`（酷狗概念版 Flutter 客户端）」 | 「项目：`overtone`（多音源第三方 Flutter 客户端）」 |
| `app/branding/README.md` | 11「带 kugo AUMID 的开始菜单快捷方式」 | 描述改为 AUMID 保持 `com.kugo.player`、显示名与快捷方式名更新 |

**其余文档清单**（实测共 23 个 `.md` 含代号引用，除上表外还有）：
`docs/release-packaging.md`(6)、`docs/android-windows-delivery.md`(8)、
`docs/linux-implementation.md`(9)、`docs/linux-x11-lyrics.md`(8)、
`docs/linux-compatibility-assessment.md`(13)、`docs/gap-vs-echomusic.md`(9)、
`docs/rework-assessment-2026-10-10.md`(14)、`docs/rework-p0-implementation.md`(4)、
`docs/rework-p1-implementation.md`(3)、`docs/rework-p1-security-startup-implementation.md`(1)、
`docs/UI评审与优化清单.md`(24)、`docs/功能与动画盘点.md`(4)、
`docs/windows-desktop-media-implementation.md`(2)、`docs/api-notes.md`(8)、
`docs/explore-source-switch.md`(1)、`docs/personal-fm-vs-echomusic.md`(2)、
`docs/bili-integration-validation.md`(2)、`桌面歌词接入方案.md`(9)、
`网易云接口文档.md`(1)。
处理规则：**只改「项目名 / 代号 / 仓库名 / 产物名」叙述，`kugou` 平台词一律不动**；
历史实施文档里引用的旧符号名（`KugoTheme` 等）可同 C3 一并 sed，或在文首加一行
「符号名为改名前的历史名称」，避免逐一 review。

**注意别误伤**：`哔哩哔哩接入方案.md` 虽被 `rg -i kugo` 命中 4 次，但全部是 `kugou`
平台词（已用 `kugo(?!u)` 复核为零命中），**不需要任何改动**。同理 `docs/api-notes.md`
的 8 处、`网易云接口文档.md` 的 1 处也需先分辨是代号还是平台词再动手。

**验收**：`flutter pub get` 后 `.dart_tool/package_config.json` 中 name 为 `overtone`；`flutter analyze --no-pub` 无问题（改名不影响 import）。

---

## 4. Step 3：构建标识（随下个 Release 切换）

### 4.1 Windows 可执行文件与安装包

| 文件 | 行 | 现状 | 改为 |
| --- | --- | --- | --- |
| `app/windows/CMakeLists.txt` | 7 | `set(BINARY_NAME "kugo")` | `"overtone"`（exe 名、install 目标随之变更） |
| `app/linux/CMakeLists.txt` | 7 | `set(BINARY_NAME "kugo")` | `"overtone"`（Linux 可执行文件同样是 kugo，易漏） |
| `app/windows/runner/CMakeLists.txt` | 8–10 | `KUGO_APP_ICON_FILE` / `KUGO_APP_ICON_SHA256` | `OVERTONE_APP_ICON_FILE` / `OVERTONE_APP_ICON_SHA256` |
| `app/windows/runner/app_icon_version.h.in` | 2 | `KUGO_APP_ICON_SHA256` 占位符 | 同步改为 `OVERTONE_APP_ICON_SHA256` |
| `app/windows/runner/Runner.rc` | 100 | `VALUE "AppIconVersion", KUGO_APP_ICON_SHA256` | 同上（该变量共 3 处：CMakeLists 定义 + .h.in 占位 + .rc 引用，漏一处图标版本校验就断） |
| `app/linux/runner/desktop_lyric_host.h` | 1–2 | include guard `KUGO_DESKTOP_LYRIC_HOST_H_` | `OVERTONE_DESKTOP_LYRIC_HOST_H_` |
| `app/tool/windows_installer.iss` | 11 | `!FileExists(SourceDir + "\kugo.exe")` | `overtone.exe` |
| 同上 | 19–24 | `AppId=kugo.ZhengHaoF`；`AppName`；`AppVerName`；`DefaultDirName={localappdata}\Programs\kugo`；`DefaultGroupName=kugo` | `AppId=overtone.ZhengHaoF`；`AppName=泛音`；`DefaultDirName` / `DefaultGroupName` 用 `overtone` |
| 同上 | 30, 32 | `OutputBaseFilename=kugo-{#AppVersion}-windows-x64-setup`；`UninstallDisplayIcon={app}\kugo.exe` | `overtone-…-setup`；`overtone.exe` |
| 同上 | 47, 48, 51 | 开始菜单 / 桌面快捷方式名 `kugo`、`Launch kugo` | `泛音`；`AppUserModelID` 两处仍为 `com.kugo.player`（不动） |
| `app/windows/runner/Runner.rc` | 98 | `OriginalFilename "kugo.exe"` | `"overtone.exe"` |

**僵尸快捷方式清理**：AUMID 不变但快捷方式文件名从 `kugo.lnk` 改为 `overtone.lnk` 后，
`app_identity.cpp:39 EnsureStartMenuShortcut` 只会创建新快捷方式，旧的 `kugo.lnk` 会残留。
需在该文件补一段一次性清理：若旧路径 `kugo.lnk` 存在且其 AUMID 为 `com.kugo.player`，删除之。

### 4.2 CI 与 Gradle 属性

`.github/workflows/apps.yml` 共 40 处，`app/android/app/build.gradle.kts` 共 4 处：

| 现字符串 | 新字符串 | 位置 |
| --- | --- | --- |
| `KUGO_VERSION` / `KUGO_BUILD_NUMBER` | `OVERTONE_VERSION` / `OVERTONE_BUILD_NUMBER` | apps.yml 22–23、36、85、147、169–170、287、316 等 |
| `KUGO_STORE_PASSWORD` / `KUGO_KEY_ALIAS` / `KUGO_KEY_PASSWORD` | `OVERTONE_STORE_PASSWORD` / `OVERTONE_KEY_ALIAS` / `OVERTONE_KEY_PASSWORD` | apps.yml 64–66 |
| `kugoAllowTestSigning` | `overtoneAllowTestSigning` | `build.gradle.kts:16,35`；apps.yml 63 `ORG_GRADLE_PROJECT_kugoAllowTestSigning` |
| `KUGO_KEYSTORE_FILE` | `OVERTONE_KEYSTORE_FILE` | **shell → Gradle 环境变量契约**：`app/tool/prepare_android_signing.sh:16` 写入 `$GITHUB_ENV`，`app/android/app/build.gradle.kts:20` 用 `providers.environmentVariable` 读取。两边必须同一次改动，否则 `hasReleaseSigning` 判 false，**Android Release 会静默回退到 debug 签名**（该文件头部注释已警告此行为） |
| `kugo-release-keystore.jks` | `overtone-release-keystore.jks` | apps.yml 90 |
| `kugo.exe` | `overtone.exe` | apps.yml 157、166、174、184、205 |
| `kugo-android-release-` / `kugo-native-media-` / `kugo-windows-x64-release-` / `kugo-release-v` | `overtone-…` | apps.yml 93、122、151、247、266、276 |
| `kugo-$KUGO_VERSION-android-*.apk` / `kugo-$KUGO_VERSION-windows-x64-*.exe|zip` | `overtone-$OVERTONE_VERSION-*` | apps.yml 231、236、289–293 |
| `--title "kugo $KUGO_VERSION"` | `--title "Overtone $OVERTONE_VERSION"` | apps.yml 316 |

**注意**：apps.yml 26、56、99、129、255 共 5 处 `github.repository == 'ZhengHaoF/kugoFlutter'`
守卫必须与 Step 6 的仓库改名**同一次改动**提交，否则 workflow_dispatch 手动打包直接不触发。

### 4.2.1 策略测试 `app_workflow_policy_test.dart` 必须同步改（否则 CI 改名后测试红）

这个测试会**读取真实的 CI / Gradle / 安装包 / 探针文件内容**做字面量断言。下列 4 条在对应
改名落地后会失败，必须与源头改动同一 commit 更新：

| 测试行 | 断言内容 | 何时失败 | 改成 |
| --- | --- | --- | --- |
| `:8` | `const guard = "github.repository == 'ZhengHaoF/kugoFlutter' && …"` | Step 6 仓库改名后 | `'ZhengHaoF/overtone'`（与 apps.yml 5 处守卫同步） |
| `:74` | `contains("ORG_GRADLE_PROJECT_kugoAllowTestSigning: 'false'")` | `kugoAllowTestSigning` → `overtoneAllowTestSigning` 后 | `"ORG_GRADLE_PROJECT_overtoneAllowTestSigning: 'false'"` |
| `:130` | `contains('Remove-KugoProbeDirectory')` | cmdlet 改名后 | `'Remove-OvertoneProbeDirectory'` |
| `:135` | `contains('Stop-KugoProbeProcess')` | cmdlet 改名后 | `'Stop-OvertoneProbeProcess'` |

另有一条**语义失效但不报错**：`:98` 的 `isNot(contains('kugo-android-test-only-'))`
意在禁止 workflow 引用测试专用 APK；改名后测试夹具变成 `overtone-android-test-only.apk`
（见 `app/tool/package_test_release.sh:25`、`test_package_test_release.sh:27`），
断言应同步换成新名字，否则它检查的是一个永远不会出现的旧字符串。

**不受影响的断言**（因为对应标识我们保留）：`:119-127` 用正则从
`windows/runner/app_identity.cpp` 抓 AUMID 并与安装包里的 `AppUserModelID` 比对——
AUMID 保持 `com.kugo.player`，这条继续通过；`:99-101` 断言的 Gradle 签名逻辑字符串不含代号。

### 4.3 打包与验收脚本

`app/tool/` 下 46 个脚本（共 51 个文件，`package_release.sh` / `package_test_release.sh` /
`test_package_release.sh` / `test_package_test_release.sh` / `test_windows_installer.ps1` /
`test_windows_app_icons.ps1` / `probe_*.dart` 等）中的 `kugo.exe`、`kugo-<version>-*.zip|exe|apk`、
`KUGO_VERSION` / `KUGO_BUILD_NUMBER` 全部替换。探针脚本里还散着 camelCase 实例名（`kugoClient`）和
UA 片段（`kugo-netease-probe`，见 `core/api/netease/netease_client.dart:96`、
`netease_mappers.dart:29`），一并替换。

`app/tool/native_media_probe/`（`CMakeLists.txt`、`probe.cpp`）与
`app/tool/linux_integration_probe.dart`、`run_linux_probe.sh`、`run_x11_lyric_probe.sh`、
`x11_lyric_probe.mjs`、`x11_input_fixture.cc` 中的 `kugo.exe` 路径、日志文件名同步替换；
`app/lib/features/desktop_lyric/spike/spike_launcher.dart:10` 的调试日志绝对路径
`C:\Users\zheng\kugo_spike.log` → `overtone_spike.log`。

**探针环境变量家族**（本轮复查穷举 `\bKUGO[A-Z_]*` 得到，全部位于 `app/tool/`，
属于本地开发探针，不影响 App 本体；但 shell 与脚本是**读写配对**，必须同文件组一起改）：

| 变量 | 写入方 | 读取方 |
| --- | --- | --- |
| `KUGO_TOKEN` / `KUGO_USERID` / `KUGO_GUID` / `KUGO_DFID` | 开发者手动 export | `probe_cloud_disk.dart:62-66`、`probe_user_collections.py:18-25` |
| `KUGO_LISTID` | 同上 | `probe_user_collections.py:186` |
| `KUGO_FM_TOKEN` / `KUGO_FM_USERID` / `KUGO_FM_GUID` / `KUGO_FM_DFID` | 同上 | `probe_personal_fm.py:8,19-22` |
| `KUGO_PROBE_BACKEND` | `run_linux_probe.sh:23`（默认 `x11`） | 同脚本内判断 |
| `KUGO_PROBE_VIDEO` | `run_linux_probe.sh:42` export | `linux_integration_probe.dart:293-294` |
| `KUGO_COMPOSITOR` | `run_x11_lyric_probe.sh:14` | `x11_lyric_probe.mjs:127` |
| `KUGO_DEV` | 开发者手动 export | `probe_user_collections.py:26`（`dev` 值覆盖开关） |

**不要改的**：`KUGOU_API_MID` / `KUGOU_API_GUID` / `KUGOU_API_DEV` 是酷狗 API 协议定义的
请求头名（`Kugou` 后有 `u`，`kugo(?!u)` 不会命中），改了请求直接失效。

测试夹具是 `mktemp -d` 现生成的（见 `test_package_release.sh:4`），**没有已提交的二进制需要搬**。
`app/tool/probe_kugou_guest.dart` 是酷狗平台探针，名字里的 `kugou` 保留不动。

### 4.4 DB 路径

`app/lib/data/storage/kugo_db.dart:181`：`p.join(dir.path, 'kugo', 'kugo.sqlite')`
→ `p.join(dir.path, 'overtone', 'overtone.sqlite')`。见 §1，不兼容旧数据。

**验收**：`flutter build windows --release` 产物为 `overtone.exe`；
`bash app/tool/package_release.sh` 生成 `overtone-<ver>-windows-x64-{setup.exe,portable.zip}`；
`flutter build apk --release` 安装后 launcher 名称为「泛音」。

---

## 5. Step 4：Dart 符号改名（最大一步）

涉及 `app/lib` 105 个文件 + `app/test` 128 个文件（另有 `app/tool` 46 个脚本）。
**分四轮替换，顺序不能反。**

> **执行顺序 ≠ 小节编号**：按 **§5.1 第一轮 → §5.2 第二轮 → §5.4 第四轮 → §5.3 第三轮** 跑，
> 第三轮（局部变量）破坏面最大，必须放最后。小节编号按「轮次」命名，方便对照；
> 完整前置条件与误伤清单见 §5.3，可直接执行的脚本见 §5.6。

### 5.1 第一轮：酷狗平台级（10 个符号，必须先改）

这些是酷狗平台客户端 / 协议符号，与既有 `KugouSource` / `KugouSession` 对齐，**不是**应用代号。
以下次数为 `app/lib` + `app/test` + `app/tool` 实测，小计 415 处：

| 现符号 | 次数 | 新符号 | 定义位置 |
| --- | --- | --- | --- |
| `KugoSign` | 171 | `KugouSign` | `core/api/kugou/kugo_sign.dart` |
| `KugoEndpoints` | 113 | `KugouEndpoints` | `core/api/endpoints.dart` |
| `FakeKugoClient` | 27 | `FakeKugouClient` | `app/test/fakes/fake_kugo_client.dart:11` |
| `KugoClient` | 25 | `KugouClient` | `core/api/kugou/kugo_client.dart` |
| `decodeKugoBody` | 24 | `decodeKugouBody` | `core/api/kugou/kugo_client.dart:40` |
| `KugoCrypto` | 22 | `KugouCrypto` | `core/api/kugou/kugo_crypto.dart` |
| `KugoApiException` | 16 | `KugouApiException` | `core/api/kugou/kugo_client.dart:9` |
| `kugoClient` | 9 | `kugouClient` | `KugouClient` 的实例变量，小写开头，需单独列（正则第二轮抓不到） |
| `describeKugoErrorCode` | 4 | `describeKugouErrorCode` | `data/repositories/user_repository.dart:17` |
| `parseKugoDateTime` | 4 | `parseKugouDateTime` | `features/profile/profile_stats.dart:137` |

目录与文件重命名：`app/lib/core/api/kugo/` → `app/lib/core/api/kugou/`，其中
`kugo_sign.dart` → `kugou_sign.dart`、`kugo_crypto.dart` → `kugou_crypto.dart`、
`kugo_client.dart` → `kugou_client.dart`（`credential_transport.dart` 名字不变）；
`app/test/fakes/fake_kugo_client.dart` → `fake_kugou_client.dart`。

可选：把 `core/api/endpoints.dart` 的 `KugoEndpoints` 移进 `core/api/kugou/kugou_endpoints.dart`，
与 `core/api/netease/` 的目录结构对齐。

### 5.2 第二轮：应用级（正则替换，后改）

正则 `Kugo(?![a-z])` → `Overtone`。该前瞻保证第一轮产物 `Kugou*`（`Kugo` 后紧跟小写 `u`）不被误伤，
同时命中 `KugoTheme`、`showKugoBottomSheet`（`Kugo` 后是大写 `B`）、`_KugoClickableState`、
`buildKugoTheme`、独立 `Kugo` 等全部剩余标识符。小计约 1100 处：

| 现符号 | 次数 | 新符号 | 备注 |
| --- | --- | --- | --- |
| `KugoSpacing` | 529 | `OvertoneSpacing` | |
| `KugoTheme` | 219 | `OvertoneTheme` | |
| `KugoRadius` | 91 | `OvertoneRadius` | |
| `KugoDb` | 48 | `OvertoneDb` | 不含 `KugoDbManager` |
| `KugoHeroTags` | 47 | `OvertoneHeroTags` | |
| `showKugoBottomSheet` | 24 | `showOvertoneBottomSheet` | 定义于 `shared/widgets/common.dart:943` |
| `KugoAudioHandler` | 18 | `OvertoneAudioHandler` | |
| `KugoHScroll` | 18 | `OvertoneHScroll` | |
| `KugoClickable` | 16 | `OvertoneClickable` | |
| `KugoHWheelMode` | 14 | `OvertoneHWheelMode` | |
| `KugoApp` | 13 | `OvertoneApp` | |
| `KugoPalette` | 13 | `OvertonePalette` | |
| `buildKugoTheme` | 12 | `buildOvertoneTheme` | 定义于 `app.dart` |
| `KugoDesktopSideSheetChrome` | 7 | `OvertoneDesktopSideSheetChrome` | |
| `KugoMediaBridge` | 6 | `OvertoneMediaBridge` | |
| `KugoProbeDirectory` | 6 | `OvertoneProbeDirectory` | PowerShell cmdlet `Remove-KugoProbeDirectory` 同步 |
| `KugoProbeProcess` | 6 | `OvertoneProbeProcess` | PowerShell cmdlet `Stop-KugoProbeProcess` 同步 |
| `KugoDbManager` | 4 | `OvertoneDbManager` | |
| `KugoSheetChrome` | 4 | `OvertoneSheetChrome` | |
| `applyKugoSystemUi` | 4 | `applyOvertoneSystemUi` | `app.dart` / `main.dart:97` |
| `KugoIconAction` / `KugoIconButton` | 2 / 2 | `OvertoneIconAction` / `OvertoneIconButton` | |
| `_KugoClickableState` / `_KugoHScrollState` | 2 / 2 | `_OvertoneClickableState` / `_OvertoneHScrollState` | 私有 State 类 |
| 独立 `Kugo` | 1 | `Overtone` | |

文件重命名：`app/lib/data/storage/kugo_db.dart` → `overtone_db.dart`
（`kugo_db.g.dart` 由 build_runner 重新生成，**不要手改**）；
`app/lib/data/storage/queue_store.dart:31` 的 `KugoDb()` 跟随。

### 5.3 第三轮：局部变量（只在 Dart 文件，且必须在 Step 1 / 3 / 5 的字符串改动之后）

`\bkugo\b` → `theme`，实测约 1194 处。覆盖 `final kugo = KugoTheme.of(context);`、
`KugoTheme kugo` 形参、`kugo: kugo` 命名实参（含 widget 构造函数上的 `final KugoTheme kugo;`
字段，需同步改为 `final OvertoneTheme theme;`）。

**⚠ 正则误伤陷阱（本轮复查新发现）**：`\bkugo\b` 的边界规则会命中一批**字符串里的 kugo**，
把它们变成 `theme`，造成静默破坏：

| 会被误伤 | 后果 |
| --- | --- |
| `package:kugo/…`（602 行绝对导入） | 变成 `package:theme/…`，**全部测试与探针编译失败** |
| `'kugo/taskbar'` 等 6 个通道字符串 | 变成 `'theme/taskbar'`，IPC 静默失效 |
| `'kugo.sqlite'` / `"kugo.exe"` / `'kugo 播放'` / `'kugo 播控横条'` / `'kugo'` | 用户可见文案与路径错乱 |
| **`'kugo.credentials.$key'`**（`credential_store.dart:30`，§1.1 决定**保留**的 secure storage 键） | 变成 `theme.credentials.`，**全体老用户登录态静默丢失**（App 不崩，只是重新要求登录） |
| **`'kugo-flutter-${now}-…'`**（`device_identity.dart:55`，guid 随机种子） | 变成 `theme-flutter-…`；若想要 `overtone-flutter-…` 必须先做字符串替换 |
| `'kugo-dbus-test'` / `'kugo-android-test-only-'`（连字符结尾） | 变成 `theme-dbus-test` 等；仅测试夹具名，无害但非预期 |

安全的是：`kugo_device_dfid`（后随 `_`，`_` 是词字符，无边界）和 `KUGO_LYRIC_*`（全大写，大小写敏感不匹配）。

**第四轮还有一个撞名**：`(?<![A-Za-z])kugo(?=[A-Za-Z])` → `overtone` 会把所有
`kugoFlutter` 变成 `overtoneFlutter`。`dev` 字段值（§1.2）正是要这个结果，但
**`app/test/app_workflow_policy_test.dart:8` 里的 `'ZhengHaoF/kugoFlutter'`（GitHub 仓库名）
必须例外——仓库改名为 `overtone`，不是 `overtoneFlutter`**。
因此 §4.2.1 的 guard 更新必须**先于**第四轮完成（更新后该处已无 `kugoFlutter`）。

**硬性执行顺序汇总**（每一轮开跑前，前一条件必须已满足）：
§3.1 `package:kugo/` 替换 → Step 1 用户可见字符串 → Step 3 产物名 → Step 5 通道名 →
§4.2.1 策略测试 4 条断言（含 `ZhengHaoF/kugoFlutter` → `ZhengHaoF/overtone`）→
第一轮平台级符号 → 第二轮 `Kugo(?![a-z])` → 第四轮 camelCase → **第三轮 `\bkugo\b` 放最后**
（它破坏面最大，且此时字符串都已处理完）。
若已经跑错，用 `git checkout -- app/test app/tool app/lib` 回退后按序重来，不要手工修补。
跑完自查：`rg -n "package:theme/|'theme/|theme\.sqlite|theme\.credentials|theme-flutter|overtoneFlutter" app`
应只剩 `dev` 字段值处的 `overtoneFlutter`。

### 5.4 第四轮：camelCase 小写标识符 + 文件重命名 + 全文件类型覆盖

**（a）camelCase 小写标识符**：第二/三轮的正则都要求 `Kugo` 后紧跟非小写字母或独立成词，
抓不到 `kugoNavigatorKey` 这类小写开头的标识符。第四轮正则
`(?<![A-Za-z])kugo(?=[A-Za-z])` → `overtone`，仅命中「后面还跟着字母」的小写 kugo：

| 现标识符 | 次数 | 新标识符 | 定义位置 |
| --- | --- | --- | --- |
| `kugoFontFamily` | 15 | `overtoneFontFamily` | `core/theme/kugo_theme.dart:12` |
| `kugoFontFamilyFallback` | 14 | `overtoneFontFamilyFallback` | `core/theme/kugo_theme.dart:15` |
| `kugoNavigatorKey` | 6 | `overtoneNavigatorKey` | `core/app_navigator.dart:9` |
| `kugoPaletteFor` | 4 | `overtonePaletteFor` | `main.dart:202` 等 |

该前瞻 deliberately 不碰 `kugo_device_dfid`（后随 `_`）、`'kugo 播放'`（后随空格）、
`kugo.sqlite`（后随 `.`）、`KUGO_LYRIC_PROCESS`（全大写）——这些由 Step 1 / 3 / 5 显式处理。
注意 `device_identity.dart:60` 的 `dev = 'kugoFlutter'` 是**字符串**，会被本轮命中，
是否改动见 §1.1 决策表。

**（b）文件重命名清单**（初版评估漏项，全部为应用级）：

| 现文件 | 新文件 | 引用它的文件数（import 必须同步改） |
| --- | --- | --- |
| `app/lib/core/theme/kugo_theme.dart` | `overtone_theme.dart` | **60** |
| `app/lib/core/theme/kugo_tokens.dart` | `overtone_tokens.dart` | **41** |
| `app/lib/shared/widgets/kugo_h_scroll.dart` | `overtone_h_scroll.dart` | 10 |
| `app/lib/shared/widgets/kugo_clickable.dart` | `overtone_clickable.dart` | 7 |
| `app/lib/data/storage/kugo_db.dart` | `overtone_db.dart` | 8（另需改文件内 `part 'kugo_db.g.dart'` 指令） |
| `app/lib/data/storage/kugo_db.g.dart` | `overtone_db.g.dart` | 由 build_runner 重新生成，**不要手改** |
| `app/test/kugo_h_scroll_test.dart` | `overtone_h_scroll_test.dart` | — |
| `app/test/fakes/fake_kugo_client.dart` | `fake_kugou_client.dart` | 8 |

import 路径替换（相对路径与 `package:overtone/…` 绝对路径都要改，§3.1 只换了包名前缀）：

```powershell
$map = @{ kugo_theme = "overtone_theme"; kugo_tokens = "overtone_tokens"
          kugo_clickable = "overtone_clickable"; kugo_h_scroll = "overtone_h_scroll"
          kugo_db = "overtone_db"; fake_kugo_client = "fake_kugou_client" }
foreach ($k in $map.Keys) {
  Rename-InFiles "$k\.dart" "$($map[$k]).dart" @("app/lib", "app/test", "app/tool")
}
```

**（c）全文件类型覆盖**：大写 `Kugo` 不只出现在 `.dart`——实测还分布在
`.cpp`（2 处，播控条窗口类名）、`.plist`（1 处，CFBundleDisplayName）、
`.ps1`（4 处，`Remove-KugoProbeDirectory` / `Stop-KugoProbeProcess`）、
`.xml`（2 处，`colors.xml` 注释引用 `KugoPalette`）。
第二轮正则必须覆盖这些文件类型，不能只跑 `app/lib` 和 `app/test`，否则注释与代码脱节。
同理 `core/api/kugou/` 内文件头注释里的 `Kugo*` 旧名也要同步。

**（d）正则覆盖不到的字符串**（`kugo` 后随 `_`，无词边界也不后随字母，属预期残留）：

| 位置 | 内容 | 处理 |
| --- | --- | --- |
| `app/test/cover_viewer_test.dart:32` | 临时目录名 `'kugo_viewer_test'` | 四轮正则均不命中，保留或手动改 |
| `app/test/cover_cache_test.dart:57,244` | 临时目录名 `'kugo_cover_test'` / `'kugo_cover_empty'` | 同上 |
| `app/test/crash_log_test.dart:19` | 临时目录名 `'kugo_crashlog_test'` | 同上 |
| `app/test/linux_media_bridge_test.dart:251` | 临时目录名 `'kugo-dbus-test'` | **会被第三轮命中**（连字符是词边界）→ `theme-dbus-test`，无害但非预期，可接受 |
| `app/test/linux_media_bridge_test.dart:266,271` | 测试显式传入的 bus name `'$mprisRoot.kugo.test'` | 同上，会变 `theme.test`；改 lib 的 `.instance$pid` 不影响它 |
| `app/tool/package_test_release.sh:25`、`test_package_test_release.sh:27,40,66`、`app/test/app_workflow_policy_test.dart:98` | 测试夹具 APK 名 `kugo-android-test-only.apk` | 连字符结尾，第三轮会命中；随 Step 3 脚本改名，并同步 §4.2.1 那条断言的语义 |
| `app/tool/probe_user_collections.py:26` | 环境变量名 `KUGO_DEV`（探针专用覆盖开关） | 全大写，四轮均不命中；随 Step 3 脚本改名 |

### 5.5 重新生成 drift 代码并全量验证

```powershell
cd app
dart run build_runner build --delete-conflicting-outputs
flutter analyze --no-pub
flutter test --no-pub
```

参考基线：rework 文档记录的全量测试为 1,070 项，改名后应全绿。
分轮复查命令（每轮跑完都应无输出）：

```powershell
rg -nP "Kugo(?![a-z])" app/lib app/test app/tool   # 第一、二轮后：无 Kugo* 残留（Kugou* 不受影响）
rg -nP "(?<![A-Za-z])kugo(?=[A-Za-z])" app/lib app/test app/tool  # 第四轮后：无 camelCase 残留
```

### 5.6 四轮替换脚本模板（编码安全，可直接执行）

```powershell
# PowerShell 7。仓库 .dart 均为 UTF-8 无 BOM，显式指定编码避免中文注释乱码。
function Rename-InFiles {
  param([string]$Pattern, [string]$Replacement, [string[]]$Paths)
  $files = rg -l $Pattern $Paths --glob '!*.g.dart'   # 生成文件不手改，交给 build_runner
  foreach ($f in $files) {
    $c = Get-Content $f -Raw -Encoding utf8
    $n = [regex]::Replace($c, $Pattern, $Replacement)
    if ($n -ne $c) { Set-Content $f -Value $n -NoNewline -Encoding utf8NoBOM }
  }
  "  $Pattern -> $Replacement ：$($files.Count) 个文件"
}

$dirs = @("app/lib", "app/test", "app/tool")

# ⚠ 前置条件（不在本脚本内，必须先单独完成，见 §5.3 顺序汇总）：
#   1) §3.1 package:kugo/ → package:overtone/（602 行）
#   2) Step 1 用户可见字符串、Step 3 产物名、Step 5 通道名
#   3) §4.2.1 策略测试 4 条断言（含 ZhengHaoF/kugoFlutter → ZhengHaoF/overtone）

# 第一轮：酷狗平台级（先改，否则第二轮会把 Kugou* 误切成 Overtoneu*）
$platformMap = [ordered]@{
  KugoSign = "KugouSign"; KugoEndpoints = "KugouEndpoints"; FakeKugoClient = "FakeKugouClient"
  KugoClient = "KugouClient"; decodeKugoBody = "decodeKugouBody"; KugoCrypto = "KugouCrypto"
  KugoApiException = "KugouApiException"; describeKugoErrorCode = "describeKugouErrorCode"
  parseKugoDateTime = "parseKugouDateTime"; kugoClient = "kugouClient"
}
foreach ($k in $platformMap.Keys) { Rename-InFiles $k $platformMap[$k] $dirs }

# 第二轮：应用级（前瞻 (?![a-z]) 保护第一轮产物 Kugou*）
Rename-InFiles "Kugo(?![a-z])" "Overtone" $dirs

# 第四轮：camelCase 小写标识符。kugoFlutter → overtoneFlutter（dev 字段值，§1.2 正是要这个结果；
#         ZhengHaoF/kugoFlutter 必须已在前置条件里改成 ZhengHaoF/overtone）
Rename-InFiles "(?<![A-Za-z])kugo(?=[A-Za-z])" "overtone" $dirs

# 第三轮：局部变量 → theme。⚠ 放最后！它破坏面最大（\bkugo\b 会吃掉 package:kugo/、
#        'kugo/taskbar'、'kugo.credentials.' 等字符串），此时字符串应已全部处理完。
Rename-InFiles "\bkugo\b" "theme" @("app/lib", "app/test")
```

跑完立刻 `git diff --stat` 核对规模（预期 lib+test+tool 约 2,700 处变动），
再进 build_runner 与全量测试。

---

## 6. Step 5：方法通道（原子操作，Dart 与原生必须同一 commit）

通道名跨 Dart / C++ / Kotlin 两侧，**拆开提交会静默失效**（channel not found，
桌面歌词、任务栏、悬浮窗假死但 App 不崩）。

| 通道名 | 新通道名 | Dart 侧 | 原生侧 |
| --- | --- | --- | --- |
| `kugo/taskbar` | `overtone/taskbar` | `app/lib/shared/taskbar/taskbar_bridge.dart:8` | `app/windows/runner/flutter_window.cpp:233` |
| `kugo/desktop_lyric_host` | `overtone/desktop_lyric_host` | `app/lib/features/desktop_lyric/desktop_lyric_host.dart:10`（另 :3 注释） | `app/windows/runner/desktop_lyric_host.cpp:22`；`app/linux/runner/desktop_lyric_host.cc:279` |
| `kugo/lyric_overlay` | `overtone/lyric_overlay` | `app/lib/features/desktop_lyric/android_overlay/android_overlay_host.dart:8`（另 :3 注释） | `app/android/app/src/main/kotlin/com/kugo/kugo/lyric/LyricOverlayPlugin.kt:130`（另 :13 注释） |
| `kugo/linux_desktop` | `overtone/linux_desktop` | `app/lib/core/desktop_capabilities.dart:50` | `app/linux/runner/my_application.cc:117` |
| `kugo/spike_lyric` | `overtone/spike_lyric` | `app/lib/features/desktop_lyric/spike/spike_lyric_window.dart:23` | 无原生注册（Dart 子窗口自洽） |
| `kugo/desktop_lyric` | `overtone/desktop_lyric` | `app/lib/features/desktop_lyric/desktop_lyric_protocol.dart:8` | 无原生注册（Dart 子窗口自洽） |

### 6.1 跨进程环境变量契约（同类原子操作，易漏）

主进程与歌词子进程之间还靠三个环境变量握手，Dart 侧定义在
`app/lib/features/desktop_lyric/desktop_lyric_ipc.dart:28-30`，原生侧读取在
`app/windows/runner/utils.cpp:46` 与 `utils.h:20` 的注释。**同样必须同一 commit 改**，
否则子进程起不来或 IPC 握手失败：

| 现变量 | 新变量 | 定义 / 消费方 |
| --- | --- | --- |
| `KUGO_LYRIC_PROCESS` | `OVERTONE_LYRIC_PROCESS` | `desktop_lyric_ipc.dart:28`；`utils.cpp:46`；`utils.h:20`；`lyric_window_controller.dart:102`（另 :130, :149 也消费同一常量） |
| `KUGO_LYRIC_IPC_PORT` | `OVERTONE_LYRIC_IPC_PORT` | `desktop_lyric_ipc.dart:29`；`main.dart:63`；`lyric_window_app.dart` 侧消费 |
| `KUGO_LYRIC_IPC_TOKEN` | `OVERTONE_LYRIC_IPC_TOKEN` | `desktop_lyric_ipc.dart:30`；`lyric_window_app.dart:80` |

`desktop_lyric_bridge.dart:237` 的 `...Platform.environment` 是整体透传，无需逐个列名，跟着上述常量走即可。

### 6.2 原生内部的跨文件契约（同类原子操作，实施中新发现）

| 契约 | 位置 | 说明 |
| --- | --- | --- |
| GTK 对象数据键 `"kugo-lyric"` | `app/linux/runner/desktop_lyric_host.cc:125,141,254`（写入）、`app/linux/runner/my_application.cc:41`（读取） | Linux 侧用 `g_object_set_data` / `g_object_get_data` 标记歌词窗，键名两边必须一致，否则歌词窗识别失效。与 Windows 侧 `L"kugo-lyric"`（窗口标题，Step 1 已改）是**不同机制、同名字符串**，别只改一处 |
| Linux 歌词窗标题 `"kugo X11 lyrics"` | `app/linux/runner/desktop_lyric_host.cc:255`（设置）、`app/tool/run_x11_main_lyric_probe.sh:25,40,66,72`（xdotool 按标题搜窗口） | 标题是探针定位窗口的契约，两边必须同改 |
| MPRIS bus 名 `$mprisRoot.kugo.instance$pid` | `app/lib/features/player/linux_media_bridge.dart:79`（lib）、`app/tool/linux_integration_probe.dart:223`（探针镜像） | 探针复刻了 lib 的 bus 名规则，需同步 |
| 原生探针窗口类名 / CMake 项目名 | `app/tool/native_media_probe/probe.cpp:45`（`KugoNativeMediaProbeOwner`）、`app/tool/native_media_probe/CMakeLists.txt:2`（`kugo_native_media_probe`） | 大写 K 与小写下划线两种形式，`kugo-` 批量替换抓不到，需显式改 |

**验收**：`rg -n "kugo/" app`、`rg -n "KUGO_LYRIC" app` 均无输出；Windows 桌面歌词窗口、任务栏缩略图按钮、
Android 悬浮歌词、Linux 桌面能力探测逐一真机/真桌面验证。

---

## 7. Step 6：仓库与远端

0. **本地绝对路径清理**（目录改名的连带影响，动手前先做）：
   - `docs/gap-vs-echomusic.md:5` 写死了 `对象：D:\work\kugoFulutter\app`，改为 `D:\work\overtone\app`；
     `README.md:1` 标题同步。
   - `app/ios/Flutter/` 下的 `flutter_export_environment.sh`、`Generated.xcconfig`、
     `ephemeral/flutter_native_integration.env` 也含 `D:\work\kugoFulutter\app`，
     但这三个文件**未被 git 跟踪**（Flutter 生成物），`flutter pub get` 会自动重建，无需手改。
1. 本地目录 `kugoFulutter` → `overtone`（工作副本关闭 IDE 后 `git mv` 或直接重命名目录）。
2. GitHub：Settings → Repository name → `ZhengHaoF/kugoFlutter` 改 `ZhengHaoF/overtone`。
   旧地址 GitHub 自动 301，历史链接不失效。
3. apps.yml 5 处 `github.repository == 'ZhengHaoF/kugoFlutter'` → `'ZhengHaoF/overtone'`（与第 2 步同一次改动）。
4. `README.md:7` releases 链接 `https://github.com/ZhengHaoF/kugoFlutter/releases` → `overtone`。
5. `docs/release-packaging.md`、`docs/android-windows-delivery.md` 等文档中的仓库/产物引用同步。

---

## 8. 提交切分与回滚

| Commit | 内容 | 风险 | 回滚 |
| --- | --- | --- | --- |
| C1 | Step 1 + Step 2（含 §3.1 的 602 行 `package:kugo/` 导入替换） | 零风险（导入替换是机械的，编译期即可发现漏网） | `git revert` |
| C2 | Step 3（构建标识 + 僵尸快捷方式清理 + DB 路径 + `KUGO_KEYSTORE_FILE` 契约 + §4.2.1 策略测试同步） | 中，需回归打包链路 | `git revert`；旧产物名链接失效（历史 Release 资产不受影响） |
| C3 | Step 4（Dart 符号 + build_runner 重新生成） | 高，最大 diff（平台级 415 处 + 应用级约 1100 处 + 局部变量约 1200 处 + camelCase 39 处） | `git revert`；不影响运行时数据 |
| C4 | Step 5 + §1.1 存储键（方法通道 + 环境变量契约，Dart 与原生同 commit） | 高，**禁止拆分** | `git revert` |
| C5 | Step 6（仓库改名 + workflow 守卫 + README 链接） | 低 | 改回仓库名即可 |

建议 C3 单独开分支、单独 PR，review 时只看「符号名是否一一对应」，不看业务逻辑。

---

## 9. 遗留事项

- **applicationId / bundle id / AUMID 永久保留**，建议在 `设计方案.md` §1.4 或新建 ADR 记录理由，
  避免以后反复提出。
- **Logo 不用换**：现有「唱片螺旋 + 声波」与「泛音」（声波涟漪）意象天然契合。
- `docs/api-notes.md`、`网易云接口文档.md` 等约 90 处 `kugou` 平台词保持不动。
- 若将来计划上架应用商店，再评估 applicationId 变更，并需提供本地数据导出/导入方案。
- `docs/rework-*.md` 等历史实施文档中引用的旧符号名（`KugoTheme` 等）会与代码脱节，
  可选择同 C3 一并 sed，或在文首加一行「符号名为改名前的历史名称」。

---

## 10. 最终验收闸门（全部 Step 完成后跑）

```powershell
# 全仓除「明确不改」项外，不应再有任何 kugo 引用。
# --no-ignore 必须加：app/android/key.properties 被 .gitignore 忽略，
# 不加则 rg 默认跳过它，验收会漏掉这个本地密钥文件（它是预期保留项，需确认未被误改）。
rg -niP "kugo(?!u)" . --hidden --no-ignore --iglob '!.git/**' --iglob '!.dart_tool/**' --iglob '!**/build/**'
```

预期仅剩：`com.kugo.kugo`（applicationId / 包名 / Linux APPLICATION_ID / MPRIS DesktopEntry）、
`com.kugo.player`（AUMID / 通知 channelId）、`probe_kugou_guest.dart`、
`app/android/key.properties` 里的密钥字面量（§0.1 明确不改）、
`kugo_device_*` 与 `kugo.credentials.` 两类存储键名（§1.1 按「本地键名不改」原则保留）、
以及 `kugo_cover_test` 等测试临时目录名（§5.4d，正则抓不到的预期残留）。

改动前基线：全仓共 **338** 个文件含 `kugo`（非 `kugou`）引用——
`app/` 309、`docs/` 23（含本文档）、根目录 5 个 md（`README.md` / `设计方案.md` /
`多音源接入方案.md` / `桌面歌词接入方案.md` / `网易云接口文档.md`）、`.github` 1。
（本地未入库的 `.u1s1/` 不在验收范围内，用户已明确忽略。）
其中 `package:kugo/` 绝对导入 602 行 / 143 个文件（`app/test` 127 + `app/tool` 16）。

逐项核对：

- [ ] `flutter analyze --no-pub` 零问题
- [ ] `flutter test --no-pub` 全量通过（基线 1,070 项）
- [ ] `flutter build apk --release` 安装后 launcher 名「泛音」，通知渠道「泛音 播放」
- [ ] `flutter run -d windows`：主窗标题、歌词窗、播控横条、托盘提示、SMTC 媒体标题（`泛音 · 歌名 · 歌手`）、
      关闭对话框标题（「关闭 泛音」）均显示「泛音」；开始菜单存在 `overtone.lnk` 且旧 `kugo.lnk` 已被清理
- [ ] `flutter run -d linux`：窗口标题「泛音」，MPRIS 媒体标识 Identity = Overtone
- [ ] Windows 桌面歌词窗口可正常拉起（验证 `OVERTONE_LYRIC_*` 环境变量契约）
- [ ] Android 悬浮歌词可正常拉起（验证 `overtone/lyric_overlay` 通道）
- [ ] 任务栏缩略图按钮、Linux 桌面能力探测正常
- [ ] workflow_dispatch 手动打包跑通，产物名为 `overtone-<version>-*`
- [ ] **`app/test/app_workflow_policy_test.dart` 4 条断言已同步**（§4.2.1：guard / gradle 属性 / 两个 cmdlet 名），`flutter test` 中该文件通过
- [ ] **短信验证码登录 + 账号密码登录真机冒烟**（`dev` 值进了 `t2` 登录签名，见 §1.2；失败则单独回退 `device_identity.dart:60` 一行）
