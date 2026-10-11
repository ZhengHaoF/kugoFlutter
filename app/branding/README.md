# kugo 应用图标

采用用户确认的 G「唱片螺旋」方案，保留青绿色唱片纹路、薄荷色中心和声波尾部。`icon-g-source.png` 为确认后的透明背景源图，`icon-g-master.png` 为规范化的 1024 × 1024 透明母版。

## 当前覆盖

- Android：五档传统 launcher PNG、Android 8+ 自适应图标、Android 13+ 主题单色图标。自适应前景限制在 108dp 画布中心直径 66dp 的圆形安全区内，非对称声波尾部同样保留。
- Windows：应用 EXE/任务栏与托盘 ICO，含 16、20、24、32、40、48、64、128、256 像素帧。
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

资源测试检查 PNG 可解码性、尺寸、透明度、Android 前景安全区、自适应/单色 XML 引用，以及 ICO 全部帧可解码性。安装后的手机启动器、Windows 任务栏和托盘实际展示仍需设备验收，旧图标缓存可能需要重新安装或重启 Explorer 后刷新。
