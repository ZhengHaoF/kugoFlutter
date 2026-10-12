# Android 与 Windows Release 应用交付

## 手动打包与发布

入口为 [Android and Windows apps](https://github.com/ZhengHaoF/kugoFlutter/actions/workflows/apps.yml)，仅原仓库 `main` 主分支可以手动启动。推送、PR 和合并不触发；所有 job 继续检查仓库、分支和手动事件。

在 Run workflow 中选择 `main`，填写 `version`（例如 `0.1.0`，只接受 `major.minor.patch`），默认不勾选 `publish`。构建编号使用递增的 Actions run number，并传给 Flutter 的 `--build-name` 和 `--build-number`，使包内版本与文件名一致；这两个参数的含义见 [Flutter 官方打包说明](https://docs.flutter.dev/deployment/android)。

默认只生成 Actions 构建附件，成功后下载 `kugo-release-v<version>-<commit>` 可获得三种 APK、Windows 安装程序、绿色 ZIP、签名指纹、SHA-256 和构建来源。Actions Artifacts 仍保留 30 天；勾选 `publish` 才在完整验证成功后发布 `v<version>` 正式 GitHub Release，不再创建 `test-*` 标签或 prerelease。先上传 draft，再公开；拒绝覆盖已发布版本，也拒绝重用其他提交的同名 tag/draft。

如果 Android 缺少签名配置，该 job 明确失败，聚合打包和发布不会进行。Windows job 不依赖 Android job，仍可单独完成并上传其安装程序和绿色 ZIP 到 `kugo-windows-x64-release-<commit>`，前提是质量和原生探针通过。

## Android APK 与正式签名

- **armeabi-v7a**：ARM 32 位 APK。
- **arm64-v8a**：ARM 64 位 APK。
- **x86_64**：x86 64 位 APK，不是 32 位 x86 APK。

这三种架构对应 Flutter 官方支持的 Release 拆包输出；本轮使用 `flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64,android-x64`，不承诺不存在的 32 位 x86 Release 包。各 ABI 与输出文件名参见 [Flutter 官方文档](https://docs.flutter.dev/deployment/android)。

文件名为 `kugo-<version>-android-<abi>.apk`，最低 Android 7.0 / API 24。每个 APK 都必须通过 apksigner 验证，拒绝默认 Android Debug 证书；三种 APK 的签名指纹必须一致，并记录在 `ANDROID-SIGNING.txt`。

仓库需要由拥有正式签名密钥的人在 Settings → Secrets and variables → Actions 安全配置以下 Secrets，不要通过邮件或提交文件发送密钥及密码：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 现有正式 keystore 的 Base64 内容 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | 正式密钥别名 |
| `ANDROID_KEY_PASSWORD` | 该密钥密码 |

也兼容已有的 `KEYSTORE_B64`、`KEYSTORE_PASSWORD`、`KEY_ALIAS`、`KEY_PASSWORD` 命名；如果两种命名同时存在，优先使用 `ANDROID_*`。本轮只检查了 Secret 名称，没有读取或导出 Secret 内容。

CI 只把 keystore 解码到 runner 临时目录，通过环境变量给 Gradle 提供密码，不生成包含密码的 key.properties，不把 keystore 上传为制品，结束时清理临时文件。任何必填项缺失或无效都会失败，不再允许正式工作流退回 debug 签名。已有本地 key.properties 仍兼容；本地显式测试签名选项保留，但工作流明确关闭它。

正式签名应稳定复用并妥善备份，不应每次构建生成新密钥。旧测试包使用 debug 密钥，新正式密钥可能无法覆盖安装；不要为换包贸然卸载有数据的应用，商店上传密钥与直接分发 APK 签名也应按既有发行计划区分，这些边界见 [Flutter 签名说明](https://docs.flutter.dev/deployment/android)。

## Windows 安装程序与绿色 ZIP

Windows 交付当前仍为 x64：

- **安装程序**：`kugo-<version>-windows-x64-setup.exe`，使用 Inno Setup；按当前用户安装到 LocalAppData 下，创建开始菜单快捷方式，提供可选桌面快捷方式和卸载入口，不默认申请管理员权限。架构限制使用 `x64compatible`，指令含义见 [Inno Setup 文档](https://jrsoftware.org/ishelp/topic_setup_architecturesallowed.htm)。
- **绿色版**：`kugo-<version>-windows-x64-portable.zip`，含完整 kugo.exe、Flutter 与插件 DLL、media_kit 原生库和 data/；解压后直接运行，不需要安装程序。不得只拿 EXE 分发。
- **构建隔离**：先保存正式主应用 Release 目录，再构建安全存储探针和 Debug 图标验收程序；安装程序及 ZIP 始终从保存目录取文件，不混入探针或 Debug EXE。
- **安装验收**：Windows runner 静默安装到临时目录，核对全部文件 SHA-256，启动已安装程序并复核图标，然后卸载；缺任一验收记录，不允许聚合打包发布。

当前工作流未配置 Windows Authenticode 签名，安装程序和程序仍未做代码签名，可能出现系统安全提示，机制见 [Microsoft 的 SmartScreen 说明](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)。Release 模式、正式 GitHub Release、安装程序以及“已代码签名”是不同概念，不能混称为已签名发行；安装程序不捆绑未知 VC++ 安装器，缺运行库时按 Microsoft 官方说明安装 Visual C++ 2015–2022 x64 Runtime。

## 验证与边界

聚合脚本核对版本、构建号、提交 SHA、运行来源、所有必需文件的校验覆盖、三种 ABI 的签名证据、完整原生探针和安装验收记录；发现缺包、损坏、签名不一致、来源混用或缺验收就停止，不发布不完整版本。

本轮不主动启动 GitHub 构建或发布，没有读取正式签名密钥或进行真实签名，因此不能声称已经生成、签名或下载验证真实正式 APK。Android Gradle 正式签名构建，以及 Windows 安装程序的真实编译、安装和卸载，要在签名项配置齐全后的主分支手动运行中执行，离线脚本测试不替代该验收。

本轮本地验证：全量 Flutter 测试 1,181 项通过；定向工作流策略测试 7 项通过；正式打包与 APK 验证包装器的 26 项离线检查通过，历史测试包脚本 7 项检查通过；静态分析无问题；actionlint、Bash 语法及 PowerShell 安装验收脚本和工作流内联步骤的语法检查通过。APK 验证包装器使用明确标记的模拟 apksigner，只验证拒绝与打包控制流，不冒充真实密钥的密码学验收。

旧 `test-*` 标签与测试版附件本轮保留，等待用户确认删除范围。删除 Release 会移除其 APK、ZIP 和校验记录，删除 tag 会移除版本引用，但不会删除 main 或已合并代码。
