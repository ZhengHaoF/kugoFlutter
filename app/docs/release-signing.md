# Release 签名说明

## 当前状态

默认 **debug 签名** 侧载，便于开发调试。

## 正式签名（推荐）

1. 生成 keystore（只需一次）：

```powershell
keytool -genkey -v -keystore android\upload-keystore.jks `
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

2. 在 `app/android/key.properties` 写入（**不要提交仓库**）：

```properties
storePassword=你的库密码
keyPassword=你的密钥密码
keyAlias=upload
# 相对 android/app 的路径；keystore 放在 android/ 下则用 ../upload-keystore.jks
storeFile=../upload-keystore.jks
```

3. `android/app/build.gradle.kts` 已支持：存在 `key.properties` 时 release 使用该 keystore。

4. 构建：

```powershell
cd app
flutter build apk --release
# 产物: build\app\outputs\flutter-apk\app-release.apk
```

## 性能检查清单（M4）

| 项 | 参考 |
| --- | --- |
| 冷启动 | 中端机 < 2.5s（真机/模拟器主观） |
| 列表滚动 | 首页/搜索 60fps 主观流畅 |
| 切歌到出声 | 正常网 P50 < 3s |

自动化集成测试（需设备）可在有 adb 时补充 `integration_test/`；当前以 mock 冒烟 `test/play_smoke_test.dart` 覆盖主路径。
