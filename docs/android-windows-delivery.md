# Android 与 Windows 测试应用交付（历史说明）

本文保留旧测试包与此前工作流的历史记录，不是当前正式打包规则。当前仅主分支手动生成 Release 包，Android 使用必需的正式签名并拆分三个 ABI，Windows 提供安装程序和绿色 ZIP，发布默认关闭；请以 [Release 应用交付说明](release-packaging.md) 为准。

## 制品库与获取

同时提供两个入口：[GitHub Releases 测试版](https://github.com/ZhengHaoF/overtone/releases)供直接下载 APK 与 Windows ZIP，GitHub Actions Artifacts 保留原始构建附件。Releases 全部标记为 prerelease，不冒充正式发布、不设置为正式 latest，不配置未知外部制品平台，也不交付 Linux 应用包。

运行入口为 [Android and Windows apps](https://github.com/ZhengHaoF/overtone/actions/workflows/apps.yml)。仅支持主分支 `main` 的手动运行，不在 PR、push 或合并时自动执行。打开 Actions 中该工作流，点击 Run workflow，选择 `main` 后启动；先通过锁文件还原、静态分析及全量测试，再构建两个平台，上传保留 30 天的制品。每个制品含提交 SHA、运行地址、安装说明和 SHA-256 校验记录。

只有在原仓库的 `main` 上手动运行且两个平台成功后才会发布测试版；PR、fork 和功能分支绝不发布。所有 job 都检查仓库、分支和手动事件，即使误选其他分支，执行到本版本规则时也会全部跳过，不分配构建 runner。发布 job 单独申请 `contents: write`，其他 job 仍只有读取权限；复核两端文件完整性、提交/运行来源及 SHA-256，先上传到 draft，再公开为 prerelease，避免出现可见但附件不完整的版本。

测试版 tag 为 `test-<run_number>-<run_attempt>-<short_sha>`，每次重跑单独保留，不覆盖既有公开测试版或正式版本。Releases 附件为 `overtone-android-<short_sha>-test-only.apk`、`overtone-windows-x64-<short_sha>-portable-test-only.zip`、`SHA256SUMS.txt`、`BUILD-INFO.txt`；发布说明包含安装方法、签名与验收边界及构建链接，Windows ZIP 保留完整运行目录。

Actions Artifacts 仍按 30 天策略保留，Releases 附件没有套用该自动到期设置。仓库为公开仓库，测试包也公开发布；它们不含真实账号或用户签名秘密。

## Android

- 制品名 `overtone-android-test-only-<commit>`，内容为通用 Release 模式 APK `overtone-android-test-only.apk`，而不是 AAB 或不能安装的无签名 APK。
- 没有提供正式签名材料，本 CI 明确以 `overtoneAllowTestSigning=true` 使用 debug 测试签名。TEST-ONLY 字样写入制品名及 BUILD-INFO，不能称为正式发布包。
- 上传前用 Android SDK 的 apksigner 验证 APK 签名并打印证书信息；这证明包具有可验证签名，不等于证明正式发布身份。
- 正常正式 Release 缺 `android/key.properties` 时构建失败，不再静默回退 debug 签名。
- CI 测试密钥由 runner 生成，跨运行可能不同，不能承诺覆盖升级。不要为了安装测试包贸然卸载有数据的旧应用；同包名不同签名时系统可能拒绝覆盖。
- 安装：Actions 制品需要先解压 ZIP；Releases 可直接下载 APK，再执行 `adb install -r <下载的APK文件>`，或在设备上打开 APK。实际签名检查、安装运行结果以 Actions 证据为准，不能把编译通过当成真机通过。
- 本应用使用的 Flutter 3.47.7 模板最低 API 24（Android 7.0），安全存储插件自身要求 API 23；最终取两者较高值。自动备份关闭，测试包不植入任何真实账号凭据。

## Windows

- 制品名 `overtone-windows-x64-portable-<commit>`，是 Windows x64 Release 模式完整便携目录。
- 包含 `overtone.exe`、Flutter 引擎和插件 DLL、media_kit 原生库以及 `data/` 资源。不得只取一个 EXE 分发。
- 解压全部目录再打开 overtone.exe。本轮无 Authenticode 签名、无 MSI/安装器，不伪称签名正式版本。
- 缺 VC++ 运行库时安装 Microsoft Visual C++ 2015–2022 x64 Redistributable。Windows 驱动、扬声器、蓝牙、SMTC、悬浮歌词和真实用户权限仍需物理设备验收。
- CI 额外构建隔离测试入口，在 Windows runner 上执行原生安全存储迁移、清除明文、替换读回、退出阻断及原生删除探针。生产目录先复制保存，探针 EXE 不混入交付目录；成功证据 `NATIVE-CREDENTIALS.txt` 随制品上传。此探针不是完整应用试玩或真机验收。

## Linux 边界

2026-10-10 按用户要求移除 `.github/workflows/linux.yml`，并禁用 GitHub 中的 `Linux desktop` 工作流，不再保留 Linux 自动回归或手动原生构建入口。检查和 Android/Windows 制品交付统一由 `apps.yml` 的主分支手动运行承担；其中 quality 使用 Ubuntu runner 运行 Flutter 分析与测试，不构建 Linux 应用。

Linux 应用源码、探针脚本和历史验收记录保留，删除工作流不等于删除 Linux 平台支持。此前的 Linux 构建及制品记录是历史证据，不代表当前仍提供 Linux CI 交付。

## 验收清单

- CI 成功，Android 和 Windows 制品均非空。
- 主分支手动运行后发布成功，Releases 标记 prerelease，四个附件齐全；PR/push 不触发，功能分支手动运行的所有 job 跳过。
- 下载校验 SHA-256、检查 APK 签名信息和 Windows 完整文件清单。
- 实际设备验收登录与退出、重启恢复、播放暂停、位置保持、音质切换、队列及文件恢复。
- 正式 Android 密钥和 Windows 代码签名需另行安全配置。本轮不读取、不创建或公开用户的正式签名秘密。

## 主分支手动运行策略验证

本轮取消 PR 与 push 触发，仅保留 `workflow_dispatch`。五个 job 都要求原仓库、`refs/heads/main` 和手动事件；测试与平台构建依赖关系、制品完整性检查和测试版发布流程保留。

- actionlint 1.7.12 工作流语法与表达式检查通过。
- `flutter test --no-pub test/app_workflow_policy_test.dart --reporter expanded`：4 项通过，覆盖仅手动入口、所有 job 的主分支限制、质量门禁依赖及无其他自动工作流。
- `flutter analyze --no-pub`：无问题；`git diff --check` 通过。
- 停止用户合并 PR #9 后由旧规则自动触发的主分支运行；不为验证新配置另行启动 GitHub 构建。

手动运行仍会在质量门禁及两端构建成功后发布公开测试预发布版，不只是进行检查。历史运行和既有 Release 保留，没有删除。
