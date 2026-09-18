# kugoFulutter

酷狗概念版 **第三方 Flutter 客户端**（个人学习 / 研究向）。

| 文档 | 说明 |
| --- | --- |
| [设计方案.md](设计方案.md) | 产品定位、架构、功能范围 |
| [工期规划.md](工期规划.md) | 里程碑与任务拆解 |
| [app/README.md](app/README.md) | 工程运行说明 |
| [docs/design/](docs/design/) | 视觉稿 |

## 快速开始

```powershell
cd app
flutter pub get
flutter run
```

## 当前状态

- M0–M3：已完成（UI、真源播放、登录、FM、设置、评论等）
- M2 真机验收：搜索 → 出声 → 锁屏 → 杀进程恢复队列 已通过
- M4：正式签名 Release APK 可侧载；性能在模拟器主观验收；analyze 零问题

详见 [工期规划.md](工期规划.md) 与 [app/docs/release-signing.md](app/docs/release-signing.md)。

## 合规声明

个人学习 / 研究向第三方客户端。不提供音频中转或云端账号托管。请遵守当地法律与目标平台服务条款；对外发布请勿使用「酷狗」注册商标作为应用名。

License: MIT（见 [LICENSE](LICENSE)）。
