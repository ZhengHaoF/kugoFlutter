# Android 与 Windows 测试应用交付

## 制品库与获取

本轮“制品库”指仓库的 GitHub Actions Artifacts，不创建公开 Release，不配置未知外部制品平台，不交付 Linux 应用包。

运行入口为 [Android and Windows apps](https://github.com/ZhengHaoF/kugoFlutter/actions/workflows/apps.yml)。构建由 PR、主分支 push、`fix/rework-p1-*` push 或手动 dispatch 触发；先通过锁文件还原、静态分析及全量测试，再构建两个平台，上传保留 30 天的制品。每个制品含提交 SHA、运行地址、安装说明和 SHA-256 校验记录。

## Android

- 制品名 `kugo-android-test-only-<commit>`，内容为通用 Release 模式 APK `kugo-android-test-only.apk`，而不是 AAB 或不能安装的无签名 APK。
- 没有提供正式签名材料，本 CI 明确以 `kugoAllowTestSigning=true` 使用 debug 测试签名。TEST-ONLY 字样写入制品名及 BUILD-INFO，不能称为正式发布包。
- 上传前用 Android SDK 的 apksigner 验证 APK 签名并打印证书信息；这证明包具有可验证签名，不等于证明正式发布身份。
- 正常正式 Release 缺 `android/key.properties` 时构建失败，不再静默回退 debug 签名。
- CI 测试密钥由 runner 生成，跨运行可能不同，不能承诺覆盖升级。不要为了安装测试包贸然卸载有数据的旧应用；同包名不同签名时系统可能拒绝覆盖。
- 安装：完整解压制品，执行 `adb install -r kugo-android-test-only.apk`，或在设备上打开 APK。实际签名检查、安装运行结果以 Actions 证据为准，不能把编译通过当成真机通过。
- API 23 或更高，自动备份关闭。测试包不植入任何真实账号凭据。

## Windows

- 制品名 `kugo-windows-x64-portable-<commit>`，是 Windows x64 Release 模式完整便携目录。
- 包含 `kugo.exe`、Flutter 引擎和插件 DLL、media_kit 原生库以及 `data/` 资源。不得只取一个 EXE 分发。
- 解压全部目录再打开 kugo.exe。本轮无 Authenticode 签名、无 MSI/安装器，不伪称签名正式版本。
- 缺 VC++ 运行库时安装 Microsoft Visual C++ 2015–2022 x64 Redistributable。Windows 驱动、扬声器、蓝牙、SMTC、悬浮歌词和真实用户权限仍需物理设备验收。
- CI 额外构建隔离测试入口，在 Windows runner 上执行原生安全存储迁移、清除明文、替换读回、退出阻断及原生删除探针。生产目录先复制保存，探针 EXE 不混入交付目录；成功证据 `NATIVE-CREDENTIALS.txt` 随制品上传。此探针不是完整应用试玩或真机验收。

## Linux 边界

现有 Linux 流程继续保留两版本的静态分析和全量测试。原生构建、原生探针、Linux 制品上传调整为手动 `build_native=true` 才执行，本轮不会主动启动新的 Linux 交付。安全存储插件生成的 Linux 注册代码及 libsecret 编译依赖仍维护，避免依赖变更留下已知编译缺口；这不表示本轮完成 Linux 安全存储原生验收。

## 验收清单

- CI 成功，Android 和 Windows 制品均非空。
- 下载校验 SHA-256、检查 APK 签名信息和 Windows 完整文件清单。
- 实际设备验收登录与退出、重启恢复、播放暂停、位置保持、音质切换、队列及文件恢复。
- 正式 Android 密钥和 Windows 代码签名需另行安全配置。本轮不读取、不创建或公开用户的正式签名秘密。
