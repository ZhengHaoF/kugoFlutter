# kugoFulutter

酷狗概念版 **第三方 Flutter 客户端**（个人学习 / 研究向）。

| 文档 | 说明 |
| --- | --- |
| [设计方案.md](设计方案.md) | 产品定位、架构、功能范围（含实现对照） |
| [工期规划.md](工期规划.md) | 里程碑与任务拆解 |
| [app/README.md](app/README.md) | 工程运行说明 |
| [docs/api-notes.md](docs/api-notes.md) | 接口与网络说明 |
| [docs/gap-vs-echomusic.md](docs/gap-vs-echomusic.md) | 业务能力差距 / 二期 backlog |
| [docs/windows-gap-vs-echomusic.md](docs/windows-gap-vs-echomusic.md) | Windows 系统集成差距 |
| [docs/design/](docs/design/) | 视觉稿 |

## 快速开始

```powershell
cd app
flutter pub get
flutter run
```

## 当前状态

- M0–M3：已完成（UI、真源播放、登录、FM 真推荐、设置、评论、云端收藏等）
- M2 真机验收：搜索 → 出声 → 锁屏 → 杀进程恢复队列 已通过
- M4：正式签名 Release APK 可侧载；性能在模拟器主观验收；analyze 零问题
- Windows：桌面壳可运行（media_kit）；系统集成能力见 `docs/windows-gap-vs-echomusic.md`

详见 [工期规划.md](工期规划.md) 与 [app/docs/release-signing.md](app/docs/release-signing.md)。

## 合规声明

个人学习 / 研究向第三方客户端。不提供音频中转或云端账号托管。请遵守当地法律与目标平台服务条款；对外发布请勿使用「酷狗」注册商标作为应用名。

License: MIT（见 [LICENSE](LICENSE)）。
