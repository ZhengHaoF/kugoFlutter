# 网易云 MV 接入方案

> 参考实现：`D:\work\api-enhanced`（`module/mv_*.js` · `module/cloudsearch.js` · `util/request.js`）
> 协议源：[NeteaseCloudMusicApiEnhanced/api-enhanced](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced)
> 能力契约：`app/lib/core/source/capabilities.dart` `MvSearchSource` / `MvDetailSource` / `MvCollectSource`
> 前置：网易 weapi 链路已通（`NeteaseClient.callWeApi`），见 [网易云接口文档.md](网易云接口文档.md)

**一句话**：api-enhanced 的 MV 链路完整可用（详情 / 取流 / 收藏 / 榜单 / 歌手 MV / 推荐），
与酷狗 MV 共用 `Mv*Source` 能力面 + `/mv` 播放页，增量工作量主要在 mapper 与
「hash 语义」适配；**弹幕是酷狗独有**，网易不实现。

---

## 1. 结论

| 项 | 结论 |
| --- | --- |
| 可用性 | ✅ 完整：详情、取流（含清晰度）、收藏/取消、收藏列表、歌手 MV、排行榜、最新/推荐、相似 MV |
| 接入方式 | **直连网易 weapi**（抄端点 + 参数），不部署 api-enhanced 服务 |
| 与现有架构 | 直接填 `NeteaseSource` 的 `MvSearchSource` / `MvDetailSource` / `MvCollectSource` |
| 明确不做 | MV 弹幕（`MvBarrageSource` 不实现，UI 自动隐藏——能力面注释已约定） |
| 风险 | 网易风控 / 登录态；`mv_url` 有效期短；weapi 路径前缀坑（见 §5） |

---

## 2. 协议盘点（api-enhanced `module/` 实测源码）

全部走 **weapi**（`createOption(query, 'weapi')`），请求层与现有 `NeteaseClient.callWeApi` 同构。

### 2.1 核心播放链路（一期必做）

| 用途 | api-enhanced 模块 | 端点 | 入参 | 出参要点 |
| --- | --- | --- | --- | --- |
| **MV 详情** | `mv_detail.js` | `POST /api/v1/mv/detail` | `id=mvid` | `data.name/cover/desc/artist/brs/playCount/duration` |
| **MV 取流** | `mv_url.js` | `POST /api/song/enhance/play/mv/url` | `id=mvid`，`r=1080`（清晰度） | `data.url`（mp4 直链，**短时效**） |
| **MV 收藏** | `mv_sub.js` | `POST /api/mv/sub` 或 `/api/mv/unsub` | `mvId`，`mvIds='["<id>"]'`，`t=1/0` | `code=200` |
| **已收藏列表** | `mv_sublist.js` | `POST /api/cloudvideo/allvideo/sublist` | `limit/offset/total` | `data[]` 含 mvid、名称、封面 |

### 2.2 发现 / 列表（二期，按需）

| 用途 | 模块 | 端点 | 入参 |
| --- | --- | --- | --- |
| 搜 MV | `cloudsearch.js` | `POST /api/cloudsearch/pc` | `s=关键词`，**`type=1004`**，`limit/offset` |
| 歌手 MV | `artist_mv.js` | `POST /api/artist/mvs` | `artistId/limit/offset` |
| MV 排行榜 | `top_mv.js` | `POST /api/mv/toplist` | `area/limit/offset` |
| 最新 MV | `mv_first.js` | `POST /api/mv/first` | `area/limit` |
| 推荐 MV | `personalized_mv.js` | `POST /api/personalized/mv` | （空） |
| 相似 MV | `simi_mv.js` | `POST /api/discovery/simiMV` | `mvid` |
| 全部 MV | `mv_all.js` | `POST /api/mv/all` | `tags{地区,类型,排序}/limit/offset` |

### 2.3 辅助（可选）

| 用途 | 模块 | 端点 | 说明 |
| --- | --- | --- | --- |
| 赞/评/转计数 | `mv_detail_info.js` | `/api/comment/commentthread/info` | `threadid=R_MV_5_<mvid>` |
| MV 简要百科 | `ugc_mv_get.js` | `/api/rep/ugc/mv/get` | 简介补充 |
| 歌手新 MV | `artist_new_mv.js` | `/api/sub/artist/new/works/mv/list` | 关注歌手的新 MV |

---

## 3. 与酷狗 MV 的差异（关键设计点）

| 维度 | 酷狗（已落地） | 网易云 | 对策 |
| --- | --- | --- | --- |
| **主键** | `hash`（32 位，分档 hash） | **`mvid`（纯数字）** | `MvBrief.id = mvid`；`MvPlaySource.hash` **存 mvid**（兼容现有 `resolveMvPlayUrl(hash)` 签名） |
| **多版本** | `songMvs` 多版本（官方/现场/饭制） | 歌曲→MV 是 **1:1**（`song.mv`） | `songMvs` 返回单元素列表；版本切换 UI 自然退化为不显示 |
| **清晰度** | 分档 hash（fhd/hd/…各自 hash） | **同一 mvid + `r` 参数**（240/480/720/1080） | `MvDetail.sources` 按 `r` 拆多档，`hash` 均为 mvid，`label` 区分；`resolveMvPlayUrl` 时从 `MvPlaySource` 取 `r` |
| **取流返回** | `downurl` + `backupdownurl[]` | `data.url` 单条 | `backupUrls` 留空 |
| **防盗链** | 需 UA/Referer | weapi Cookie 即可，直链一般无需额外头 | `headers: const {}` |
| **弹幕** | `/video/barrage` 读写 | **无对应能力** | 不实现 `MvBarrageSource` |
| **收藏 ID** | 数字 `video_id` | 数字 `mvid` | 复用 `normalizeMvCollectId` |

---

## 4. 能力面映射（`capabilities.dart`）

| 能力方法 | 网易实现 | 优先级 |
| --- | --- | --- |
| `MvDetailSource.fetchMvDetail` | `mv_detail` + 按 `brs` 拆 `sources` | **P0** |
| `MvDetailSource.resolveMvPlayUrl` | `mv_url`（`id=mvid, r=档位`） | **P0** |
| `MvSearchSource.searchMvs` | `cloudsearch type=1004` | **P1** |
| `MvSearchSource.songMvs` | `songDetail.mv` → 单版本 | **P1** |
| `MvSearchSource.fetchArtistMvs` | `artist_mv` | **P1** |
| `MvCollectSource.setMvCollected` | `mv_sub` | **P1** |
| `MvCollectSource.fetchCollectedMvIds` | `mv_sublist` | **P1** |
| `MvBarrageSource` | ❌ 不实现 | — |

### 4.1 `MvPlaySource.hash` 语义扩展

现有签名 `resolveMvPlayUrl(String hash)` 对酷狗是「分档 hash」，对网易应是「mvid + 清晰度」。

**方案**：`hash` 字段存 `"<mvid>"`，`MvPlaySource` 已有 `height/bitrate` 可推 `r`；
或在 `NeteaseSource` 内私有维护 `mvid → r` 映射（`resolveMvPlayUrl` 收到的是哪档 hash 就请求对应 `r`）。

推荐做法（侵入最小）：

```dart
// NeteaseSource.resolveMvPlayUrl
// hash 形如 "5436712@1080" —— mvid + 档位，酷狗侧不受影响（酷狗 hash 无 @）
final parts = hash.split('@');
final mvid = parts.first;
final r = int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 1080;
```

`_extractSources`（或新建 `_mvSourcesOf`）生成：

```dart
MvPlaySource(
  hash: '$mvid@1080',  // 与酷狗 hash 空间不冲突（无 @）
  label: '1080P',
  codec: 'h264',
  height: 1080,
  ...
)
```

### 4.2 mapper 要点（`mv_detail` → `MvDetail`）

> **2026-09-28 A0 实测更正**：`brs` 是 **List**（`[{size, br, point}]`），
> **不含 url**，只枚举档位；播放地址一律 `mv/url` 现取。字段实测见
> [docs/api-notes.md](docs/api-notes.md)「网易云 MV」节。

| MvDetail / MvBrief 字段 | 网易来源 |
| --- | --- |
| `brief.id` | `data.id`（mvid） |
| `brief.name` | `data.name` |
| `brief.artist` | `data.artists[].name` join（回退 `artistName`） |
| `brief.coverUrl` | `data.cover`（搜索口是 `cover`，歌手 MV 是 `imgurl`，双 key 回退） |
| `brief.durationMs` | `data.duration`（毫秒） |
| `brief.publishDate` | `data.publishTime` |
| `sources` | `data.brs[]` 的 `br`（240/480/720/1080）→ 每档一个 `MvPlaySource` |
| `description` | `data.desc` / `data.briefDesc` |
| `playCountLabel` | `data.playCount` → `formatCount` |
| `collectionCountLabel` | `data.subCount` |
| `downloadCountLabel` | 网易无，留空 |
| `authors` | `data.artists[].name` |

**`brs` 实测形态**（`14514682` 晴天）：

```json
"brs": [
  { "size": 10456657.0, "br": 240, "point": 0 },
  { "size": 20453720.0, "br": 480, "point": 0 },
  { "size": 32049460.0, "br": 720, "point": 0 },
  { "size": 10533121.0, "br": 1080, "point": 0 }
]
```

**特权位 `mp`**（与 `data` 平级）：`pl` 可播最高码率 / `dl` 可下最高码率。
低权限例：`5436712` 广岛之恋 `pl=480`，请求 `r=1080` 时 `mv/url` 只回 480
（**`r` 会被钳到实际档**）。`sources` 枚举建议以 `brs[].br` 为准、`mp.pl` 封顶。

---

## 5. 实现要点与坑

### 5.1 weapi 路径前缀（**A0 第一轮已踩**）

api-enhanced / NeteaseCloudMusicApi 的 `request` 对 weapi 做
`'/weapi/' + uri.substr(5)` —— **剥掉 `/api/`**：

- module 写 `/api/v1/mv/detail` → 实际打 `music.163.com/weapi/v1/mv/detail`
- 传 `/api/...` 给本仓 `callWeApi` 会得到 **`code=404 「接口未找到！」`**

本仓 `callWeApi` 只补 `/weapi` 前缀、**不剥 `/api`**，故 path 必须传**已剥前缀**的
`/v1/mv/detail` / `/song/enhance/play/mv/url` / `/artist/mvs` / `/cloudsearch/pc` 等。
完整对照表见 [docs/api-notes.md](docs/api-notes.md)「★ weapi 路径坑」。

### 5.2 `mv_url` 时效

直链短时效（分钟级）。策略：

1. 取流成功后 **立即 open**（现有 `_openFromState` 流程已如此）
2. 切清晰度 / 软解重开时**重新取流**（不要缓存 url 跨会话）
3. 可选：播放中断且错误像过期 → 自动重取一次

### 5.3 清晰度枚举顺序

按 `r` 从高到低排（对齐酷狗 `isClearerThan`）：
`1080 → 720 → 480 → 240`；无 `brs` 时给默认单档 `1080`。

### 5.4 登录态

- 搜 MV / 详情 / 取流：**游客可播**（与网易音频一致）
- 收藏：需登录（`mv_sub`），未登录抛 `LoginRequired`
- 复用现有 `AuthTokenHolder` / Cookie 合并逻辑（参照 NeriPlayer `mergeNeteaseRequestCookies`）

### 5.5 `songMvs` 的 1:1 语义

网易歌曲详情里 `mv` 字段：`0` = 无 MV，否则为 mvid。返回：

- `mv == 0` → 空列表（UI 出「暂无 MV」）
- `mv > 0` → 用 `mv_detail` 装一个 `MvBrief` 放进列表

不要拉 `simi_mv` 当「多版本」——那是**相似推荐**，不是同曲多版本，语义不符。

---

## 6. 接入排期

| 阶段 | 内容 | 交付 | 预估 |
| --- | --- | --- | --- |
| **A0 探针** | `tool/probe_netease_mv.dart`：详情 / 取流 / 收藏 / 搜 MV 打真接口，补 `docs/api-notes.md` 实测字段 | 探针脚本 + 实测记录 | 0.5d |
| **A1 播放闭环** | `mv_detail` + `mv_url` mapper；`NeteaseSource` 实现 `MvDetailSource`；hash=`mvid@r` | 网易歌→MV→播放页可播 | 1.5d |
| **A2 入口与搜索** | `songMvs`（1:1）+ `searchMvs`（type=1004）+ `fetchArtistMvs`；实现 `MvSearchSource` | 搜索 Tab / 列表项 / 详情页 MV 入口 | 1d |
| **A3 收藏** | `mv_sub` + `mv_sublist`；实现 `MvCollectSource` | 收藏按钮 + 收藏列表 | 0.5d |
| **B 二期** | `top_mv` / `mv_first` / `personalized_mv` / `simi_mv`；MV 评论 | 发现页 MV 板块 | 1.5d |

**A1 依赖 A0**（字段以探针为准）；A2 / A3 可并行。

---

## 7. 代码落点

| 文件 | 动作 |
| --- | --- |
| `app/lib/core/api/netease/netease_client.dart` | 新增 `mvDetail` / `mvUrl` / `mvSub` / `mvSublist` / `searchMvs` / `artistMvs`（`callWeApi`） |
| `app/lib/core/api/netease/netease_mappers.dart` | 新增 `mapNeteaseMvDetail` / `mapNeteaseMvBrief` / `mapNeteaseMvUrl` |
| `app/lib/data/sources/netease/netease_source.dart` | 实现 `MvSearchSource` / `MvDetailSource` / `MvCollectSource` |
| `app/lib/core/models/mv_models.dart` | 原则上不动；若 `@` 方案不妥再加 `MvPlaySource.resolution` |
| `app/tool/probe_netease_mv.dart` | 新建探针 |
| `docs/api-notes.md` | 补「网易云 MV」节实测字段 |
| `app/test/netease_mv_mapper_test.dart` | mapper 单测 |

---

## 8. 风险

| # | 风险 | 影响 | 缓解 |
| --- | --- | --- | --- |
| 1 | 字段形态与文档不符（`brs` / `url` 结构漂移） | mapper 返工 | A0 探针先跑；字段多 key 回退 |
| 2 | `mv_url` 风控 / 需会员清晰度 | 高码率失败 | `r` 降档重试（1080→720→480） |
| 3 | 游客取流受限 | 未登录不能播 | 与音频一致的登录引导 |
| 4 | `@` 分隔符与未来 hash 冲突 | 解析歧义 | 酷狗 hash 为 `[0-9a-f]{32}`，无 `@`；加断言 |
| 5 | 弹幕能力缺口被当成 bug | 体验预期 | 能力面已约定「未实现则隐藏」；文案可注明 |

---

## 9. 与既有文档的关系

| 文档 | 关系 |
| --- | --- |
| [多音源接入方案.md](多音源接入方案.md) | 本方案是其 `Mv*Source` 能力面在网易侧的实例化 |
| [网易云接口文档.md](网易云接口文档.md) | 本文档 A0 实测结果应回写该文档 |
| [哔哩哔哩接入方案.md](哔哩哔哩接入方案.md) | 同结构对照；B 站 MV/视频另有语义，不混用 |
| `docs/gap-vs-echomusic.md` §13 | 酷狗 MV 已闭环；网易 MV 是多音源扩展，不属 EchoMusic 对齐项 |

---

## 附录 A · api-enhanced MV 模块索引

```
module/mv_detail.js          POST /api/v1/mv/detail
module/mv_url.js             POST /api/song/enhance/play/mv/url     (r=1080)
module/mv_sub.js             POST /api/mv/sub | /api/mv/unsub
module/mv_sublist.js         POST /api/cloudvideo/allvideo/sublist
module/mv_first.js           POST /api/mv/first
module/mv_all.js             POST /api/mv/all
module/top_mv.js             POST /api/mv/toplist
module/personalized_mv.js    POST /api/personalized/mv
module/simi_mv.js            POST /api/discovery/simiMV
module/artist_mv.js          POST /api/artist/mvs
module/artist_new_mv.js      POST /api/sub/artist/new/works/mv/list
module/mv_detail_info.js     POST /api/comment/commentthread/info   (R_MV_5_<id>)
module/ugc_mv_get.js         POST /api/rep/ugc/mv/get
module/cloudsearch.js        POST /api/cloudsearch/pc               (type=1004)
module/comment_mv.js         MV 评论
```

本地路径：`D:\work\api-enhanced\module\`
