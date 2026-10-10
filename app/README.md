# kugo — 酷狗概念版第三方 Flutter 客户端（学习/研究向）

移动端优先的第三方音乐客户端。设计方案与接口说明见根目录：

- [设计方案.md](../设计方案.md)
- [多音源接入方案.md](../多音源接入方案.md)
- [docs/api-notes.md](../docs/api-notes.md) 接口与网络说明

## 环境

- Flutter 3.24+ / Dart 3.12+（本机验证：Flutter 3.44.4 / Dart 3.12.2）
- Android SDK（API 26+）

## 运行

```powershell
cd app
flutter pub get
flutter run -d 127.0.0.1:5557   # 或你的设备 ID
```

## Release 打包

Linux P0/P1 构建与原生探针见 [Linux 实施记录](../docs/linux-implementation.md)。
本轮固定验证 SDK 为 Flutter 3.47.7 / Dart 3.13.5；Linux 不支持悬浮歌词，
Wayland 小窗不承诺绝对定位或始终置顶，真实 GNOME/KDE 与实体音频验收尚待完成。

```bash
flutter pub get --enforce-lockfile
flutter build linux --release --no-pub
./build/linux/x64/release/bundle/kugo
```

```powershell
cd app
flutter build apk --release
# 产物: build\app\outputs\flutter-apk\app-release.apk
```

当前已配置 **正式签名**（`android/key.properties` + `upload-keystore.jks`，均不入库）。若需 debug 签名侧载，临时移走 `key.properties` 再构建。详见 [docs/release-signing.md](docs/release-signing.md)。

## 模块

```text
lib/
├─ core/           # tokens · models · api · mock · source（MusicSource 契约）· cache · platform
├─ data/           # repositories · sources/kugou（KugouSource + KugouSession）· storage（Drift）
├─ features/       # explore · discovery · profile · player · fm · likes · auth · settings · debug …
└─ shared/         # widgets · shell · tray（托盘/关闭行为）· taskbar（Thumbar/进度）
```

## 当前进度

- [x] 概念版 UI（发现/我的/播放/歌单/专辑/歌手；首页已并入发现）
- [x] just_audio + audio_service（Android 通知栏/锁屏）；Windows `media_kit`
- [x] 搜索五 Tab（歌曲/歌单/专辑/歌手/**MV**）、歌单/榜单/歌词等真源（失败明确报错）
- [x] 游客优先；登录：扫码 / 验证码 / 密码（真实网关，失败不造假会话）
- [x] 私人 FM 真推荐 + 关键词回落；我喜欢 / 历史 / 设置 / 网络日志
- [x] 云端我喜欢、收藏歌单/专辑、关注歌手（`user_collections_controller`）
- [x] Windows 桌面壳：侧栏导航 + `/fm` 舞台页 + 底部播控条
- [x] 每日推荐 / 排行榜 / 为你推荐聚合页
- [x] 歌曲详情 + 评论只读
- [x] M2 真机验收：搜索 → 出声 → 锁屏 → 杀进程恢复队列
- [x] M4：正式签名 Release APK；MuMu 性能主观验收
- [x] M5 酷狗音源抽象：`core/source` 契约 + `KugouSource` + `Track.platform` 身份；Player 走 Source
- [x] 多音源：酷狗 + 网易云双源（搜索混排 / 我喜欢分源 / 详情深链 / 网易扫码登录）
- [x] 评论读写：歌曲/歌单/专辑 + 楼层 + 分类/热词 + 弹幕档位 + 网易点赞；热搜按源能力
- [x] MV：酷狗搜索/详情/取流/播放页/多版本/收藏/歌手 MV/弹幕/小窗与画中画；网易详情+取流
- [x] 酷狗音乐云盘：列表/容量/播放/删除/上传（曲库匹配 + 秒传）
- [x] 桌面歌词：Windows 双进程窗（KRC 逐字扫光 + 样式自定义）+ 安卓悬浮歌词 overlay
- [x] 歌词：LRC + **KRC 逐字**（卡拉 OK）+ 译文/音译副行（播放页入口开关）
- [x] 本地库：队列/历史 **Drift (SQLite)**（自动迁移旧 SharedPreferences；含 `platform` 列）
- [ ] 未做：自建歌单 CRUD、倍速 UI、分享、网易 MV 搜索/收藏（见 `docs/gap-vs-echomusic.md`）
- [x] 已砍：本地音乐 / 下载管理占位入口（从「我的」页移除；参考项目无对应实现）

### 网络说明

当前部分网络会把 `*.kugou.com` 拦成「URL过滤」HTML。App 已识别并提示；请换热点或路由器白名单。详见 `docs/api-notes.md`。

## 合规

个人学习与研究用途。不提供音频中转或账号托管；请遵守当地法律与平台服务条款。对外发布请勿使用「酷狗」注册商标作为应用名。
