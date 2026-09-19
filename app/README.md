# kugo — 酷狗概念版第三方 Flutter 客户端（学习/研究向）

移动端优先的第三方音乐客户端。设计方案与工期见根目录：

- [设计方案.md](../设计方案.md)
- [工期规划.md](../工期规划.md)
- [docs/design/](../docs/design/) 视觉稿
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

```powershell
cd app
flutter build apk --release
# 产物: build\app\outputs\flutter-apk\app-release.apk
```

当前已配置 **正式签名**（`android/key.properties` + `upload-keystore.jks`，均不入库）。若需 debug 签名侧载，临时移走 `key.properties` 再构建。详见 [docs/release-signing.md](docs/release-signing.md)。

## 模块

```text
lib/
├─ core/           # tokens · models · api · mock
├─ data/           # repositories · queue store
├─ features/       # explore · profile · player · fm · likes · auth · settings · debug
└─ shared/         # widgets · shell
```

## 当前进度

- [x] 深色概念版 UI（发现/我的/播放/歌单/专辑/歌手；首页已并入发现）
- [x] just_audio + audio_service（通知栏/锁屏）
- [x] 搜索、歌单、榜单、歌词等真源封装（失败明确报错，不造假数据）
- [x] 游客优先；登录：酷狗扫码 / 手机验证码 / 账号密码（真实网关，失败不造假会话）
- [x] 私人 FM、我喜欢、播放历史、设置、网络日志调试
- [x] 每日推荐页（按日轮换公开歌池）、排行榜列表页
- [x] 歌曲详情 + 评论（cmtlist / album_audio_id）
- [x] M2 真机验收：搜索 → 出声 → 锁屏 → 杀进程恢复队列
- [x] M4：正式签名 Release APK（`key.properties` + keystore，勿提交）
- [x] M4：性能主观验收（MuMu 冷启动/滚动/切歌）
- [x] 本地库：队列/历史使用 **Drift (SQLite)**（自动迁移旧 SharedPreferences）
- [ ] 可选：歌词画廊抛光、真机性能复测

### 网络说明

当前部分网络会把 `*.kugou.com` 拦成「URL过滤」HTML。App 已识别并提示；请换热点或路由器白名单。详见 `docs/api-notes.md`。

## 合规

个人学习与研究用途。不提供音频中转或账号托管；请遵守当地法律与平台服务条款。对外发布请勿使用「酷狗」注册商标作为应用名。
