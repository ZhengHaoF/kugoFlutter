# kugo — 酷狗概念版第三方 Flutter 客户端（学习/研究向）

移动端优先的第三方音乐客户端原型。设计方案与工期见仓库根目录：

- `设计方案.md`
- `工期规划.md`
- `docs/design/` 视觉稿

## 环境

- Flutter 3.24+ / Dart 3.5+（本机验证：Flutter 3.47.1 / Dart 3.13.1）
- Android SDK（API 26+）

## 运行

```powershell
cd app
flutter pub get
flutter run
```

## 当前进度（Phase 2 部分完成）

- [x] Design Tokens + 深色主题
- [x] 路由壳：首页 / 发现 / 我的 + MiniBar
- [x] 假数据四屏 + 歌单详情
- [x] 核心组件库与 AsyncBody 骨架态
- [x] MiniBar Hero 过渡 + 队列 BottomSheet
- [x] 搜索真源（mobilecdn 热词 / 搜索）
- [x] 播放地址解析（wwwapi + tracker 备用）
- [x] just_audio + audio_service（通知栏 / 锁屏）
- [x] PlayerController：队列、四种模式、seq 防竞态、失败自动跳过
- [x] 歌词接口 + LRC 解析 + 播放页预览
- [x] 队列 / 历史 SharedPreferences 持久化 + 冷启动恢复
- [x] 歌单详情真源接口（失败回退本地示例）
- [x] 专辑 / 歌手详情页（真源优先 + mock 回退）
- [x] 登录：游客默认可用；真网关手机号登录（失败明确报错，不造假会话）
- [x] 设置页（音质 / 定时停止 / 歌词翻译 / 关于）+ 播放器睡眠定时
- [x] 首页 / 发现 / 歌单 / 专辑 / 歌手：真源优先，失败显示错误空态
- [x] 播放历史（本地 QueueStore）
- [x] 搜索真源（HTTP mobilecdn）；播放地址仍受本网络过滤限制
- [ ] Phase 3 剩余：私人 FM、封面取色

### 网络说明

开发机当前访问 `*.kugou.com` 可能被网关「URL过滤」或 TLS 掐断，真源会自动回退 mock UI。换可访问网络后用 `dart run tool/probe_api.dart` 探测，详见 `docs/api-notes.md`。

### 说明

- 无 `hash` 的假数据曲目走 **demo 进度条**，便于离线预览 UI。
- 真源曲目（搜索结果）会请求播放地址并用 just_audio 出声；接口若变更只需改 `lib/core/api` 与 `lib/data/repositories`。

## 目录

```text
lib/
├─ core/           # tokens、models、mock
├─ features/       # home / explore / profile / player / search
├─ shared/         # widgets / shell
├─ app.dart
└─ main.dart
```

## 合规

个人学习与研究用途。不提供音频中转或账号托管；请遵守当地法律与平台服务条款。
