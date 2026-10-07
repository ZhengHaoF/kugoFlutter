# kugoFulutter

酷狗概念版 **第三方 Flutter 客户端**（个人学习 / 研究向）。

| 文档 | 说明 |
| --- | --- |
| [设计方案.md](设计方案.md) | 产品定位、架构、功能范围（含实现对照） |
| [多音源接入方案.md](多音源接入方案.md) | 多音源契约与架构（阶段 A/B 已落地） |
| [网易云接口文档.md](网易云接口文档.md) | 网易云接口清单与实测状态（含 G8 评论/热搜、MV） |
| [网易云接入排期.md](网易云接入排期.md) | 网易云接入排期与实测记录（阶段 A–U 落地主记录） |
| [哔哩哔哩接入方案.md](哔哩哔哩接入方案.md) | B 站接入架构 + 功能差异（能力映射 / 支持与不支持清单；**规划中，未开工**） |
| [桌面歌词接入方案.md](桌面歌词接入方案.md) | 桌面歌词方案（双进程 TCP IPC，已落地）+ 安卓悬浮歌词 + 透明背景实测无解记录 |
| [app/README.md](app/README.md) | 工程运行说明 |
| [docs/api-notes.md](docs/api-notes.md) | 接口与网络说明（含 MV / 云盘协议） |
| [docs/gap-vs-echomusic.md](docs/gap-vs-echomusic.md) | 业务能力差距 + Windows 系统集成 / 二期 backlog |
| [docs/personal-fm-vs-echomusic.md](docs/personal-fm-vs-echomusic.md) | 私人 FM 现状与差距 |
| [docs/UI评审与优化清单.md](docs/UI评审与优化清单.md) | UI 评审清单（P0/P1 已落地，P2/P3 开放） |
| [docs/功能与动画盘点.md](docs/功能与动画盘点.md) | 功能缺口与动画盘点 |
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
- M5 酷狗音源抽象：已完成（`MusicSource` / `KugouSource` / `platform:id` 身份；Player 全走 Source）
- 多音源：酷狗 + 网易云双源已接入（搜索混排 / 我喜欢分源 / 默认源 / 详情深链分发 / 扫码登录）
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
| 酷狗取流 / 防盗链 | KuGouMusicApi `module/song_url.js` · EchoMusic `api/music.ts` |
| 酷狗 MV 详情 / 取流 / 弹幕 | KuGouMusicApi `video_detail.js` / `video_url.js` / `module/_comment.js` · EchoMusic `MvDetail.vue` + `BarrageLayer.vue` |
| 酷狗云盘 | KuGouMusicApi `user_cloud*.js` · EchoMusic `Cloud.vue` / `cloudUpload.ts` |
| 网易 weapi/eapi 加密 | NeriPlayer `NeteaseCrypto.kt` · NeteaseCloudMusicApi `util/crypto.js` |
| 网易 MV（详情 / 取流 / 收藏） | api-enhanced `module/mv_detail.js` / `mv_url.js` / `mv_sub.js` |
| 网易评论 | NeteaseCloudMusicApi `module/comment_*.js` |
| B 站搜索 / 取流 | NeriPlayer `core/api/bili/` · bilibili-API-collect |

本地参考副本路径（开发机）：`D:\work\EchoMusic` · `D:\work\NeriPlayer` · `D:\work\api-enhanced`

## 合规声明

个人学习 / 研究向第三方客户端。不提供音频中转或云端账号托管。请遵守当地法律与目标平台服务条款；对外发布请勿使用「酷狗」注册商标作为应用名。

License: MIT（见 [LICENSE](LICENSE)）。
