# Release 签名说明

## 当前状态（M4）

| 项 | 状态 |
| --- | --- |
| 正式签名 | **已配置**：`android/key.properties` + `android/upload-keystore.jks`（均已 gitignore，勿提交） |
| Release 构建 | `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk` |
| 回退 | 删除或改名 `key.properties` 后构建，将回落 **debug 签名** |

## 生成 / 更换 keystore

```powershell
keytool -genkeypair -v -keystore android\upload-keystore.jks `
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

在 `app/android/key.properties` 写入（**不要提交仓库**）：

```properties
storePassword=你的库密码
keyPassword=你的密钥密码
keyAlias=upload
storeFile=../upload-keystore.jks
```

`android/app/build.gradle.kts`：存在 `key.properties` 时 release 使用该 keystore。

## 构建与安装

```powershell
cd app
flutter build apk --release
# 产物: build\app\outputs\flutter-apk\app-release.apk
adb -s 127.0.0.1:5557 install -r build\app\outputs\flutter-apk\app-release.apk
```

## 性能检查清单（M4）

| 项 | 参考 | MuMu 验收（2026-09） |
| --- | --- | --- |
| 冷启动 | 中端机 < 2.5s | **906 ms**（MuMu，`am start -W`，release 包） |
| 列表滚动 | 首页/搜索 60fps 主观流畅 | 无卡死、无明显掉帧 |
| 切歌到出声 | 正常网 P50 < 3s | 可达网络下可出声；冷启动恢复/暂停图标已修 |

自动化集成测试（需设备）可在有 adb 时补充 `integration_test/`；当前以 mock 冒烟 `test/play_smoke_test.dart` 覆盖主路径。

**建议**：真机再跑一轮冷启动 `am start -W` 与播放主路径；正式对外分发前请自备 keystore 并离线备份密码。
