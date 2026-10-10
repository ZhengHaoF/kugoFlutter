# kugoFulutter

酷狗概念版 **第三方 Flutter 客户端**（个人学习 / 研究向）。

| 文档 | 说明 |
| --- | --- |
| [设计方案.md](设计方案.md) | 产品定位、架构、功能范围（含实现对照） |
| [多音源接入方案.md](多音源接入方案.md) | 多音源契约与架构（阶段 A/B 已落地） |
| [网易云接口文档.md](网易云接口文档.md) | 网易云接口清单与实测状态（含 G8 评论/热搜、MV） |
| [哔哩哔哩接入方案.md](哔哩哔哩接入方案.md) | B 站接入架构 + 功能差异；B3/B4 代码补齐，登录态与真机验收待完成，见 [验证记录](docs/bili-integration-validation.md) |
| [桌面歌词接入方案.md](桌面歌词接入方案.md) | 桌面歌词方案（双进程 TCP IPC，已落地）+ 安卓悬浮歌词 + 透明背景实测无解记录 |
| [app/README.md](app/README.md) | 工程运行说明 |
| [docs/linux-compatibility-assessment.md](docs/linux-compatibility-assessment.md) | Linux 实施前兼容评估 |
| [docs/linux-implementation.md](docs/linux-implementation.md) | Linux P0/P1 实施、复跑与验收边界；P2 暂不做 |
| [docs/api-notes.md](docs/api-notes.md) | 接口与网络说明（含 MV / 云盘协议） |
| [docs/gap-vs-echomusic.md](docs/gap-vs-echomusic.md) | 业务能力差距 + Windows 系统集成 / 二期 backlog |
| [docs/personal-fm-vs-echomusic.md](docs/personal-fm-vs-echomusic.md) | 私人 FM 现状与差距 |
| [docs/UI评审与优化清单.md](docs/UI评审与优化清单.md) | UI 评审清单（P0/P1 已落地，P2/P3 开放） |
| [docs/功能与动画盘点.md](docs/功能与动画盘点.md) | 功能缺口与动画盘点 |

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
- M5 酷狗音源抽象：已完成（`MusicSource` / `KugouSource` / `platform:id` 身份；Player 全走 Source）
- 多音源：酷狗 + 网易云双源已接入（搜索混排 / 我喜欢分源 / 默认源 / 详情深链分发 / 扫码登录）
- B 站（哔哩哔哩）：搜索、取流播放、扫码登录、本机凭据恢复及只读收藏夹/合集/系列/UP 主内容已实现。公开搜索/播放、合集与分 P 冒烟通过；UP 主接口实网遇风控，真实登录与 Android/Windows 验收待完成，见 [验证记录](docs/bili-integration-validation.md)。
- 歌词：LRC 逐行 + **KRC 逐字**（卡拉 OK 着色）+ 译文/音译副行
- MV：酷狗侧全链路（搜索/详情/取流/播放页/多版本/收藏/歌手 MV/弹幕/小窗与画中画）；网易侧详情+取流已通，搜索/收藏未做
- 云盘：酷狗音乐云盘一/二期已落地（列表/播放/删除/上传匹配/秒传），三期后置
- 评论：歌曲/歌单/专辑读写 + 楼层 + 筛选 + 网易点赞；热搜按源能力
- 桌面歌词：Windows 双进程窗（KRC 逐字扫光 + 样式自定义）+ 安卓悬浮歌词；**Windows 透明背景实测无解**，当前为不透明/半透明卡片形态
- Windows：桌面壳 + SMTC/托盘/Thumbar（含收藏）/任务栏进度；缺口见 `docs/gap-vs-echomusic.md` §三

详见 [设计方案.md](设计方案.md) §14 与 [app/docs/release-signing.md](app/docs/release-signing.md)。

## 参考项目 / References

本项目是学习研究向的第三方客户端，接口协议与产品形态参考了以下开源项目。
**均为「对齐接口行为 / 借鉴架构思路」，未复制其业务代码**；各自版权归其作者所有。

### 协议与接口

| 项目 | 用途 |
| --- | --- |
| [MakcRe/KuGouMusicApi](https://github.com/MakcRe/KuGouMusicApi) | 酷狗概念版接口协议（歌曲 / 榜单 / MV / 云盘 / 弹幕等 module） |
| [Binaryify/NeteaseCloudMusicApi](https://github.com/Binaryify/NeteaseCloudMusicApi) | 网易云 weapi/eapi 接口协议（搜索 / 评论 / 专辑等） |
| [NeteaseCloudMusicApiEnhanced/api-enhanced](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced) | 网易云接口增强版，**MV 全链路**（详情 / 取流 / 收藏 / 榜单） |
| [chaunsin/netease-cloud-music](https://github.com/chaunsin/netease-cloud-music) | 网易云 Golang 实现（NeriPlayer 网易云侧的协议参考） |
| [SocialSisterYi/bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect) | 哔哩哔哩 API 整理（B 站接入评估） |
| [sansenjian/qq-music-api](https://github.com/sansenjian/qq-music-api) | QQ 音乐接口（NeriPlayer QQ 音乐侧参考） |

### 产品与实现

| 项目 | 用途 |
| --- | --- |
| [hoowhoami/EchoMusic](https://github.com/hoowhoami/EchoMusic) | 桌面端酷狗第三方客户端（产品形态 / 云盘 / MV 弹幕 / 本地服务架构） |
| [cwuom/NeriPlayer](https://github.com/cwuom/NeriPlayer) | 多源 Android 播放器（网易云 / B 站 weapi 链路、扫码登录、歌词匹配） |
| [992359133/MoeKoeMusic](https://github.com/992359133/MoeKoeMusic) | 酷狗第三方客户端（云盘码率档等字段口径对照） |

### 关键代码索引

| 能力 | 参考来源 |
| --- | --- |
| 酷狗取流 / 防盗链 | [MakcRe/KuGouMusicApi](https://github.com/MakcRe/KuGouMusicApi) · [hoowhoami/EchoMusic](https://github.com/hoowhoami/EchoMusic) |
| 酷狗 MV 详情 / 取流 / 弹幕 | [MakcRe/KuGouMusicApi](https://github.com/MakcRe/KuGouMusicApi) · [hoowhoami/EchoMusic](https://github.com/hoowhoami/EchoMusic) |
| 酷狗云盘 | [MakcRe/KuGouMusicApi](https://github.com/MakcRe/KuGouMusicApi) · [hoowhoami/EchoMusic](https://github.com/hoowhoami/EchoMusic) |
| 网易 weapi/eapi 加密 | [cwuom/NeriPlayer](https://github.com/cwuom/NeriPlayer) · [Binaryify/NeteaseCloudMusicApi](https://github.com/Binaryify/NeteaseCloudMusicApi) |
| 网易请求形态 / Cookie 合并 | [cwuom/NeriPlayer](https://github.com/cwuom/NeriPlayer) `core/api/netease/NeteaseClient` |
| 网易扫码登录 | [cwuom/NeriPlayer](https://github.com/cwuom/NeriPlayer) `NeteaseQrLoginClient`（chainId / scanlogin URL / 803 实机走通） |
| 网易歌词 YRC 逐字 | [cwuom/NeriPlayer](https://github.com/cwuom/NeriPlayer) `NeteaseYrcParser` |
| 网易用户歌单 / 我喜欢分流 | [cwuom/NeriPlayer](https://github.com/cwuom/NeriPlayer)（`subscribed == true` = 收藏，`specialType == 5` = 我喜欢的音乐） |
| 网易 MV（详情 / 取流 / 收藏） | [NeteaseCloudMusicApiEnhanced/api-enhanced](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced) |
| 网易评论 | [Binaryify/NeteaseCloudMusicApi](https://github.com/Binaryify/NeteaseCloudMusicApi) |
| B 站搜索 / 取流 | [cwuom/NeriPlayer](https://github.com/cwuom/NeriPlayer) · [SocialSisterYi/bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect) |

**对齐基准**：网易云侧以 `cwuom/NeriPlayer` 的 `core/api/netease/` 为基准（本地 checkout 路径见
《网易云接口文档.md》页首），`chaunsin/netease-cloud-music` 是它的上游协议参考。

**参考实现的边界**（以下各项**未**被参考实现覆盖，是本仓自研，勿当成「已对齐」）：

- 网易评论 / 热搜：不在 NeriPlayer `core/api/netease/` 内，照 `Binaryify/NeteaseCloudMusicApi`
  （`module/comment_new.js` / `module/search_hot.js`）自研。
- B 站评论、红心 / 收藏夹写入、UP 主搜索、音乐向榜单：NeriPlayer 未实现，本仓同样未做，
  能力矩阵见《哔哩哔哩接入方案.md》。

## 合规声明

个人学习 / 研究向第三方客户端。不提供音频中转或云端账号托管。请遵守当地法律与目标平台服务条款；对外发布请勿使用「酷狗」注册商标作为应用名。

License: MIT（见 [LICENSE](LICENSE)）。
