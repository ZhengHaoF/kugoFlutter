# overtone 应用图标

采用用户确认的 G「唱片螺旋」方案，保留青绿色唱片纹路、薄荷色中心和声波尾部。`icon-g-source.png` 为确认后的透明背景源图，`icon-g-master.png` 为规范化的 1024 × 1024 透明母版。

## 当前覆盖

- Android：五档传统 launcher PNG、Android 8+ 自适应图标、Android 13+ 主题单色图标。自适应前景限制在 108dp 画布中心直径 66dp 的圆形安全区内，非对称声波尾部同样保留。
- Windows：应用 EXE/任务栏与托盘 ICO，含 16、20、24、32、40、48、64、128、256 像素帧。
- 应用内侧栏：展开和折叠状态共用 `AppLogo` 与 `assets/app_icon.png`，不再绘制旧蓝紫音符。
- Windows 运行时：启动后使用 `assets/app_icon.ico` 设置窗口大小图标；插件从当前 Debug/Profile/Release 可执行文件旁的 Flutter assets 解析路径。
- Windows 原生构建：ICO 内容散列进入资源头文件依赖，避免仅更新图标却沿用旧的 `Runner.rc.res`。已有、且带本应用 AUMID（`com.overtone.player`，改名时按 [docs/rename-overtone.md](../../docs/rename-overtone.md) §0.1 保留）的开始菜单快捷方式会更新为当前运行版本与图标，并通知 Shell 刷新；不覆盖无关的同名快捷方式。
- 托盘 PNG：64 × 64 透明图标，沿用既有资源路径。

未修改 iOS 图标或新增 Linux 构建。本次不改应用界面主题色、业务逻辑或通知栏音乐状态图标。

## 再生成

开发环境使用 Python 3 与 Pillow 12.3.0；应用本身不依赖 Python。

```sh
python -m pip install Pillow==12.3.0
python app/tool/generate_app_icons.py
python app/tool/generate_app_icons.py --check
cd app
flutter test --no-pub test/app_icon_assets_test.dart
```

脚本从源图机械生成各平台资产，不需要重新调用图片生成服务。`--check` 比较生成结果与已提交资源的完整字节，Pillow 版本变化可能影响 PNG 编码，因此再生成时保持版本一致。

## 验收范围

资源测试检查 PNG 可解码性、尺寸、透明度、Android 前景安全区、自适应/单色 XML 引用，以及 ICO 全部帧可解码性。侧栏组件测试覆盖展开/折叠 Logo，窗口图标测试覆盖插件路径与各份 ICO 一致性。

拉取更新后，先完整退出旧进程，在 `app` 目录执行以下命令。这是重新生成旧原生构建资源，不是只做 Dart 热重载：

```sh
flutter clean
flutter pub get --enforce-lockfile
flutter run -d windows
```

Windows CI 分别对 Release 和 Debug 使用 `tool/test_windows_app_icons.ps1`，检查 EXE 内嵌图标、实际运行窗口的大小图标，以及当前开始菜单快捷方式目标和图标。Debug 对应默认 `flutter run -d windows`；只交付预先复制好的 Release，Debug 仅验收运行行为。两个探针报告随 Windows 制品保存为 `NATIVE-ICONS.txt` 和 `DEBUG-ICONS.txt`。

此探针不等于在用户设备上验证了 Explorer 的所有已固定快捷方式；旧固定项目若仍使用旧图标，可取消固定后固定当前窗口。不会删除全局图标缓存或强制重启 Explorer。
