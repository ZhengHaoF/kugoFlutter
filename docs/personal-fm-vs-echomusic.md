# 私人 FM — 现状与相对 EchoMusic 的差距

> 更新日期：2026-09（对照当前代码）
> 本文取代旧版调研长文；已作废的「DNS 劫持 / `/personal/fm` 不可达 / 纯关键词搜索」结论不再保留。

## 当前形态

私人 FM 是**播放器会话**，不是独立业务页（`FmController` + 播放器队列）。

| 项 | 现状 |
| --- | --- |
| 数据源 | `POST /v2/personal_recommend`（`x-router: persnfm.service.kugou.com`），登录后真实个性化 |
| 回落 | 接口失败/游客 → 关键词歌池；UI **诚实标注**「来源」，不冒充个性化 |
| 双轴 | 档位 `mode`（红心/小众/速览）× 歌池 `song_pool_id`（口味/风格/探索） |
| 反馈 | 红心写 likes；「不喜欢」本地过滤 + `action=garbage` 上报（真接口模式） |
| 不喜欢持久化 | 会话状态落 `SharedPreferences`（`FmSession` 序列化） |
| 入口 | 发现页电台舞台（`quick_entries.dart`，与 `/fm` 同构）+ 桌面侧栏 `/fm` + 播放页 FM 药丸/面板 |
| 队列语义 | 播放器队列即歌池；只追加不环绕；池尾自动续流 |

接口参数与探测细节见 `api-notes.md`「私人 FM」。

## 仍相对 EchoMusic 的差距

| # | 差距 | 说明 |
| --- | --- | --- |
| 1 | 侧盘预告 / 舞台细节 | 已大幅对齐 radio-hero；个别动效与 Resize 侧盘数算法仍可再抛光 |
| 2 | `playtime` / `is_overplay` 等完整播放反馈 | 有 `reportPlay`，字段覆盖可再对照 KuGouMusicApi 补全 |
| 3 | 不喜欢跨设备同步 | 目前仅本地 + 单次上报，不回拉服务端黑名单 |
| 4 | 速览模式 30s 裁剪体验 | 参数已支持，播放端未做限时截断 |

## 相关代码

- `app/lib/features/fm/fm_controller.dart` — 会话状态机
- `app/lib/data/repositories/fm_repository.dart` — 真接口 + 解析
- `app/lib/features/fm/fm_radio_card.dart` / `fm_page.dart` / `player/fm_controls.dart` — UI
- `app/test/fm_*.dart` — 回归
