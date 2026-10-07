# API 调研笔记

> 仅记录端点与字段形态，**不入库密钥/签名**。接口随时可能变更。

## 当前网络环境（开发机/模拟器 · App 内日志实测）

| 通道 | 结果 |
| --- | --- |
| `http://mobilecdn.kugou.com/api/v3/*` | HTTP 200，但 body 是 **HTML「URL过滤」**（access control policy） |
| 歌词 / 播放域 / HTTPS | 同样被网关策略拦或 TLS 失败 |
| 一般站点（如百度） | 正常 |

**结论**：不是 App 权限问题，是路由器/企业网关对 `*.kugou.com` 的内容过滤。  
App 已识别该 HTML 并抛出「网络网关拦截」，首页/发现会显示明确提示。

**解除方式**

1. 模拟器改连手机热点  
2. 路由器关闭「上网行为管理 / 家长控制 / 流媒体限制」，或放行 `*.kugou.com`  
3. 使用可用代理  

验证：设置 → 网络请求日志 → 测试网络。

## 端点（已在 `lib/core/api/endpoints.dart`）

| 用途 | URL | 参数要点 |
| --- | --- | --- |
| 搜索单曲 | `mobilecdn.kugou.com/api/v3/search/song` | `format=json&keyword=&page=&pagesize=&showtype=1`；返回 `hash`/`320hash`/`sqhash`/`privilege`/`pay_type*` |
| 单曲音质 | `mobilecdn.kugou.com/api/v3/song/info` | `hash=&album_id=&format=json` → `data.extra.{128,320,sq}hash` + privilege（播放页懒加载） |
| 热搜 | `.../api/v3/search/hot` | `format=json&plat=0&count=` |
| 歌单详情 | `.../api/v3/playlist/info` | `specialid=&page=&pagesize=&format=json` |
| 榜单列表 | `.../api/v3/rank/list` | `format=json&plat=0` → **`data.info[]`**（不在根节点）；每项 `rankid`/`rankname`/`imgurl`/`play_times`；真实曲目数在 `extra.resp.all_total` |
| 榜单详情 | `.../api/v3/rank/info` | `rankid=&plat=0&format=json` |
| 榜单歌曲（完整） | `gateway.kugou.com/openapi/kmr/v2/rank/audio` | **POST** + Android 签名 + `kg-tid:369`；body `{rank_id, rank_cid, page, pagesize, type:1, area_code:1, show_portrait_mv:1, show_type_total:1, filter_original_remarks:1}` → `data.total` + `data.songlist[]`（hash/duration 在 `audio_info`）。对齐 KuGouMusicApi `rank_audio.js` / EchoMusic `/rank/audio` |
| 榜单歌曲（旧公开口） | `.../api/v3/rank/song` | `rankid=&page=&pagesize=&plat=0&format=json` → `data.info[]`；**实测 TOP500 只回 total=3**，仅作 fallback；歌手在 `authors[].author_name`，**不能**用 `specialid` |
| 播放地址 | `wwwapi.kugou.com/yy/index.php` | `r=play/getdata&hash=&album_id=&mid=&guid=&platid=4&appid=1014` |
| Tracker 备用 | `trackercdn.kugou.com/i/v2/` | `cmd=23&pid=1&behavior=play&hash=&album_id=&key=` |
| 歌词搜索 | `lyrics.kugou.com/search` | `ver=1&man=yes&client=pc&keyword=&hash=&timelength=` |
| 歌词下载 | `lyrics.kugou.com/download` | `ver=1&client=pc&id=&accesskey=&fmt=lrc&charset=utf8` |

### 播放地址（2026-09 实测）

EchoMusic 播放能力来自 submodule **[MakcRe/KuGouMusicApi](https://github.com/MakcRe/KuGouMusicApi)** 的 `/song/url` → 概念版 `module/song_url.js`：

| 步骤 | 说明 |
| --- | --- |
| 端点 | `https://gateway.kugou.com/v5/url` + header `x-router: trackercdn.kugou.com` |
| 平台 | concept/lite：`appid=3116` `clientver=11440` `pid=411` `page_id=967177915` |
| signKey | `md5(hash + 185672dd44712f60bb1736df5a377e82 + appid + mid + userid)` |
| signature | `md5(LnT6xpN3khm36zse0QzvmgTZ3waWdRSA + 排序key=value + salt)` |
| dfid | **每次请求随机 24 位**（`randomString(24)`），mid 用设备稳定值 |
| mid | `BigInt(md5(guid)).toString()`（十进制） |

App 行为：
1. 带 token 请求 `/v5/url`
2. 失败则换 `ppage_id` 重试
3. 仍失败（SSA 20028）→ **无 token 再签一次**
4. 播放页显示真实错误；`/v5/url` 已进网络日志

| 旧通道 | 结果 |
| --- | --- |
| `wwwapi` `play/getdata` | `err_code=30020` 无 url |
| tracker `cmd=23` + kgcloudv2 key | VIP `status=2` 无 url |

**歌词**：download 返回 JSON，`content` 为 **base64**；`fmt=lrc` 得 LRC 文本，**`fmt=krc` 得 KRC 容器**（`krc1` + 16 字节循环 XOR + zlib，解密见 `lib/core/utils/krc_parser.dart`）。KRC 可含逐字时间轴与 `[language:]` 译文/音译块。只取前 2 个候选，避免刷日志。

## 设备身份（dfid）与风控 20028

2026-09 实测：**未在酷狗注册过的 dfid 会被风控接口拒绝**。

| 请求带的 dfid | `/mcomment/v1/cmtlist` 结果 |
| --- | --- |
| 未注册（本地随机，任意长度/格式） | `status=0 err_code=20028` + 响应头 `ssa-code: bj_tx_event_...` |
| `-`（官方匿名值） | `status=1 err_code=0`，正常返回 |
| `/risk/v2/r_register_dev` 注册得到的真 dfid | `status=1 err_code=0`，正常返回 |

结论：跟 dfid 的**格式**无关，只跟「服务端认不认这个设备」有关。

App 行为（`lib/data/storage/device_identity.dart`）：

1. 首次启动 POST `https://userservice.kugou.com/risk/v2/r_register_dev` 注册设备，
   拿真 dfid 存本地（`lib/data/repositories/device_repository.dart`，移植自
   KuGouMusicApi `module/register_dev.js`）。
2. 注册失败 → 退化成 `-`（评论等风控接口同样接受）。
3. 失败后 6 小时内不再重试，避免拖慢启动。

注意点：

- 注册用的 AES 与 `cryptoAesEncrypt` **不同**：key 为随机 6 位小写，
  `encKey=md5(key)[0:16]`、`iv=md5(key)[16:32]`，输出 base64（`KugoCrypto.playlistAesEncrypt`）。
- `p` 参数用 **RSAES-PKCS1-V1_5**（`KugoCrypto.rsaEncryptPkcs1`），不是裸 RSA。
- 签名要把请求体（那段 base64）拼进去：`signatureAndroidParams(params, data: body)`。
- 播放地址 `/v5/url` **不受影响**：`song_url.js` 本来就用每次随机的 dfid。

`ssa-code` 只在**响应头**里，body 里没有；`SongDetailRepository.lastSsaCode` 会记录它，
并写进 App 内网络日志，方便以后排查风控问题。

## 响应形态（映射层）

- **Content-Type 常为 `text/html`**，body 却是 JSON：客户端必须 `jsonDecode` 字符串体（`KugoClient.getJson` 已处理）。
- 搜索单曲常见路径：`data.info[]`；字段 `hash` / `songname` / `singername` / `duration` / `album_id` / `audio_id` / `mixsongid`
- 播放地址：`data.url` + `data.backup_url`（或嵌套 `urls`）
- 歌词候选：`candidates[]` → `id` + `accesskey` → download 得 LRC 文本

### 多类型搜索（已落地，`SearchType` 四 Tab）

多类型是**五个独立接口**，不是同一接口换 `showtype`（`showtype` 0/1 响应相同，2 只多 `relative.singer` 纠错块）。

| 接口 | 结构 | 备注 |
| --- | --- | --- |
| `/api/v3/search/song` | `data.info[]` + `data.total` | 字段 `hash`/`songname`/`singername`/`duration`/`album_id`/`mvhash` 等 |
| `/api/v3/search/special` | `data.info[]` + `data.total` | 歌单：`specialid`/`specialname`/`playcount`/`songcount`/`imgurl`(含 `{size}`) |
| `/api/v3/search/album` | `data.info[]` + `data.total` | 专辑：`albumid`/`albumname`/`singername`/`songcount`/`imgurl` |
| `/api/v3/search/singer` | **`data` 直接是数组**，无 `total` | 仅 `singerid` + `singername`，无头像/计数 |
| `/api/v3/search/mv` | `data.info[]` + `data.total` | **未做 UI**（无 MV 播放页） |
| `/api/v3/search/lyric` | **404** | 6 个候选主机全 404，永久砍掉歌词搜索 |

歌手详情必须传数字 `singerid`（如 `3520`）；传名字会得到 `{"status":0,"error":"参数错误"}`。
`Track.artistId` + `artistTapFor()` 已统一走 id（见 `shared/widgets/common.dart`）。

### 私人 FM（已落地）

| 项 | 值 |
| --- | --- |
| 端点 | `POST https://gateway.kugou.com/v2/personal_recommend` |
| 路由头 | `x-router: persnfm.service.kugou.com`（拼写少一个 `o`） |
| 平台 | concept/lite：`appid=3116` `clientver=11440` |
| 参数 | `mode=normal/small/peak`、`song_pool_id=0/1/2`、`action=play/garbage`、`remain_songcnt` 等 |
| 鉴权 | 登录 token 时个性化；无 token 返回随机/热歌 |
| 回落 | 接口失败 → 关键词歌池（诚实标注来源，不冒充个性化） |

> 历史笔记里的「`/personal/fm` 本网络不可达 / DNS 劫持」结论已作废：那是路径和 `x-router` 猜错。

### 已知被拒端点（2026-09 实测）

| 端点 | 结果 |
| --- | --- |
| `/api/v3/playlist/square` | HTTP 200，body=`Access Deny ! No Actions !` |
| `/api/v3/playlist/class` | 同上 |
| `/api/v3/playlist/recommend` | 同上 |
| `/api/v3/rank/list` | 可用 |
| `/api/v3/search/song` | 可用 |
| `/api/v3/search/hot` | 可用 |

### 每日推荐（对齐 EchoMusic / KuGouMusicApi）

| 项 | 值 |
| --- | --- |
| 模块 | `module/everyday_recommend.js` |
| 端点 | `POST https://gateway.kugou.com/everyday_song_recommend` |
| 路由头 | `x-router: everydayrec.service.kugou.com` |
| 平台 | lite（`appid=3116` `clientver=11440`），query `platform=ios` |
| 鉴权 | Cookie + query：`token`/`userid`（登录）+ `dfid`/`mid`/`guid` |
| 签名 | android：`signatureAndroidParams(params, data: '')` |
| 响应列表 | `data.list` / `data.songs.list` / `special_list` 等（`extractEverydayList`） |
| 回落 | 接口失败/未登录时仍用公开榜单+心情词歌池 |

## MV / 视频（2026-09-27 探针打通）

> 脚本：`dart run tool/probe_mv.dart`。对齐 KuGouMusicApi `video_url.js` / `video_detail.js` /
> `video_privilege.js` / `kmr_audio_mv.js` / `artist_videos.js` / `search.js`。

### 端点一览

| 能力 | 方法 | 路径 | 路由 / 主机 | 签名 |
| --- | --- | --- | --- | --- |
| MV 搜索（简） | GET | `/api/v3/search/mv` | `mobilecdn.kugou.com` | 无 |
| MV 搜索（富） | GET | `/v1/search/mv` | gateway + `x-router: complexsearch.kugou.com` | android |
| 歌曲关联 MV | POST | `/kmr/v1/audio/mv` | gateway + `x-router: openapi.kugou.com` + **`kg-tid: 38`** | android(body) |
| MV 详情 | POST | `/v1/video` | gateway + `x-router: kmr.service.kugou.com` | body 自带 `key=signParamsKey(clienttime)` |
| MV 特权/清晰度 | POST | `/v1/get_video_privilege` | gateway + `x-router: media.store.kugou.com` | android(body) |
| **MV 播放地址** | GET | `/v2/interface/index` | gateway + `x-router: trackermv.kugou.com` | **`key=signKey(hash,mid)`** + android |
| 歌手 MV 列表 | GET | `/kmr/v1/author/videos` | `openapicdn.kugou.com` | android |

### ID 映射（踩过的坑）

| 字段 | 含义 | 用途 |
| --- | --- | --- |
| `search/mv` 简 `hash` / 富 `MvHash` | **MV 视频 hash**（清晰度无关的主 hash） | `video/url`、`video/privilege` 入参 |
| 富搜索 `MvID` / `video_id` | MV 稳定 id | `video/detail` 的 `data[].video_id` |
| 富搜索 `MixSongID` | 歌曲侧 `album_audio_id` | **`kmr/audio/mv` 必须用这个**；用 `AudioID` 返回 `data:[{}]` |
| 富搜索 `AudioID` / `search/song` `mixsongid` | 另一套音频 id | 不要当 `album_audio_id` 喂给 `kmr/audio/mv` |
| `search/song` 的 `mvhash` | **不是** MV 主 hash | 实测是 `h264.qhd_hash`（某档清晰度），勿直接当播放 hash |
| `mkv.sd_hash` / `h264.*_hash` / `*_hash_265` | 分档清晰度 hash | 切换清晰度时用对应 hash 调 `video/url` |

### 请求要点

- **播放地址**（`/v2/interface/index`）：
  - query：`cmd=123&ext=mp4&ismp3=0&type=1&pid=1&backupdomain=1&hash=<mvHash>` + 公共参数
  - `key = md5(hash + saltKey + appid + mid + userid)`（即 `KugoSign.signKey`）
  - `signature = signatureAndroidParams(全部 query 含 key)`
  - 响应：`data[<hash>].downurl` + `backupdownurl[]`，**实际文件是 `.mkv`**（尽管 `ext=mp4`）
  - 无签名裸请求 → `errcode 20006`
- **歌曲关联 MV**（`/kmr/v1/audio/mv`）body：`{data:[{album_audio_id: MixSongID}], fields:'mkv,tags,h264,h265,authors'}`；响应 `data[0][]` 为多版本列表（`is_recommend` / `authors` / `mkv` / `h264` / `h265`）
- **MV 详情**（`/v1/video`）body 自带鉴权字段（`appid/clientver/clienttime/mid/uuid/dfid/token/key/show_resolution/data`），query 可空也可带公共参数（A/B 两种签名都通）；`uuid = md5(dfid+mid)`，`key = signParamsKey(clienttime)`
- **歌手 MV**：`author_id=3520`（周杰伦）、`tag_idx`：`18` 官方 / `20` 现场 / `23` 饭制 / `42419` 歌手发布 / `''` 全部

### 响应字段（播放链路最小集）

```
search/mv(富) → {MvID, MvHash, MixSongID, MvName, Pic, Duration, MvHashMark}
     ↓
video/detail(video_id) → {video_name, h264/h265/mkv 各档 *_hash, play_times, publish_date}
     ↓
video/privilege(mvHash) → {privilege, level, pay_type, status}
     ↓
video/url(某档 hash) → {downurl, backupdownurl[], filesize}
```

## 探测脚本

```powershell
cd app
dart run tool/probe_api.dart
dart run tool/probe_mv.dart
```

## 下一步（可选）

1. 校准多版本接口字段差异（mapper 已做多候选宽容解析）
2. 真机网络异常场景复测（URL 过滤 / 风控 20028）
3. 自建歌单写入接口调研（若做 CRUD）
4. 歌词优先拉 `fmt=krc`（逐字），失败回落 `fmt=lrc`
5. MV 落地：按上文端点写 `MvSource` capability + 播放页（取流已通）

---

## MV 收藏（2026-09-28 接入）

对齐 KuGouMusicApi `mv_collect.js` / `mv_collect_del.js` / `user_video_collect.js`。

| 能力 | 方法 | 路径 | Host | 鉴权 |
| --- | --- | --- | --- | --- |
| 收藏 | POST | `/v1/collect` | `collectservice.kugou.com` | body AES(`{ctype:2,data:[{obj_id}]}`) + `p=rsa(aes key,uid,token)`；**notSignature** |
| 取消收藏 | POST | `/v1/cancel_collect` | 同上 | 同上 |
| 已收藏列表 | POST | `/collectservice/v2/collect_list_mixvideo` | gateway | android 签名；body `{userid,token,page,pagesize}` |

- **obj_id = 数字 `video_id`**（`normalizeMvCollectId`），不是播放 hash / MixSongID / album_audio_id
- 上限 `Number.MAX_SAFE_INTEGER`（2^53-1），超界拒绝（上游 JS 丢精度）
- 响应用同一 `playlistAesEncrypt` 的 key 解密；解不出时回落明文 JSON

---

## MV 弹幕（2026-09-28 接入）

> 对齐 KuGouMusicApi `module/_comment.js` 的 `buildVideoBarrageListConfig` /
> `buildVideoBarrageSendConfig` 与 `module/video_barrage.js` / `video_barrage_send.js`；
> EchoMusic MV 页（`MvDetail.vue` + `BarrageLayer.vue`）同源。
> 实现：`comment_repository.dart` 的 `fetchMvBarrage` / `sendMvBarrage`；
> 能力面 `MvBarrageSource`；飞层 `features/mv/mv_barrage_layer.dart`。

| 能力 | 方法 | 路径 | 路由头 | 鉴权 |
| --- | --- | --- | --- | --- |
| MV 弹幕列表 | **GET** | `/index.php` | `x-router: m.comment.service.kugou.com` | `key=signParamsKey(clienttime)`；**无 signature** |
| MV 弹幕发送 | **GET** | `/index.php` | 同上 | 正文在 query；**无 key / clienttime** |

- **视频弹幕 = 另一个评论池**，`code = db3664c219a6e350b00ab08d7f723a79`
  （歌曲弹幕是 `articulossong`，歌曲评论是 `fc4be23b…`，三池互不相通）。
- 列表 query：`r=comments/getCommentWithLike` + `code` + `extdata=<MV hash>`
  （或 `childrenid=<video_id>`）+ `p` / `pagesize` + 公共鉴权
  （`kugouid`/`ver=6`/`clienttoken`/`appid`/`clientver`/`mid`/`clienttime`/`key`/`uuid`/`dfid`）。
- 响应顶层平铺：`status` + `childrenid`（即 **video_id**）+ `list[{content, user_id}]`。
  `childrenid` 存下来，发送时复用。
- 发送 query：`r=comments/addcomment` + `code` + `childrenid=<video_id>` +
  `childrenname` + `ver=1.02` + `content` + `pid` + `clientver`/`mid`/`clienttoken`/`kugouid`/`appid`。
- **只给 hash 时**：先按 `extdata=hash` 拉一页（`pagesize=1`），从 `childrenid`
  解析出 video_id 再发。首次解析结果按 hash 缓存（`_videoPoolByHash`）。
- 正文上限 **100 字**（`kBarrageMaxLength`，EchoMusic `BARRAGE_MAX_LENGTH`）；
  池上限 100 条、4 条轨道、基准速度 100px/s、密度间隔 4500/2800/1400ms
  均对齐 EchoMusic（见 `core/models/barrage.dart`）。
- 显示设置（透明度 / 字号 / 速度 / 密度 / 区域）持久化在
  `settings.mvBarrageConfig`，开关在 `settings.mvBarrageEnabled`。

---

## 音乐云盘（已落地：列表/播放/删除/上传 · 2026-09-28）

> 对齐 KuGouMusicApi `module/user_cloud*.js`（2026-09 静态对照）。
> EchoMusic 走 `/user/cloud` 等业务路由；上游真实 host 见下表。
> 探针：`dart run tool/probe_cloud_disk.dart --suite list|url|match|del`
> **实现**：`CloudRepository` + `CloudDiskSource`/`CloudUploadSource`（`CloudPage` / `cloud_upload_picker.dart`）；
> 一/二期全部落地（列表/容量/播放/删除/上传匹配/秒传），三期后置项（索引/回退/音质面板）见 [gap-vs-echomusic.md](gap-vs-echomusic.md) P2 #21。

### 端点总览

| 能力 | 方法 | 上游 | 协议 |
| --- | --- | --- | --- |
| 云盘列表 | POST | `https://mcloudservice.kugou.com/v1/get_list` | **AES body + RSA `p`** |
| 云盘播放地址 | GET | `https://gateway.kugou.com/bsstrackercdngz/v2/query_musicclound_url` | Android signature |
| 云盘删除 | POST | `https://mcloudservice.kugou.com/v1/del_files` | AES body + RSA `p` |
| 曲库匹配（上传前） | POST | `http://kmr.service.kugou.com/v2/album_audio/audio` | JSON body，**无 signature** |
| 上传授权 | GET | `https://gateway.kugou.com/bsstrackercdngz/v1/upload/auth` | Android signature |
| 分片初始化 | POST | `http://bssulbig.kugou.com/v2/multipart/initiate/music` | Android signature |
| 分片上传 | POST | `{external_host}/v3/multipart/upload` | Android signature + binary part |
| 分片完成 | POST | `{external_host}/v3/multipart/complete` | Android signature |
| 写入云盘 | POST | `https://mcloudservice.kugou.com/v1/add_files` | AES body + RSA `p` |

### AES + RSA 信封（列表 / 删除 / 写入共用）

与 `device_repository` / `mv_repository` 的 `playlistAesEncrypt` 同一套：

```text
dataMap → JSON → playlistAesEncrypt → { str: base64(ciphertext), key: 6 位小写随机 }
body   = base64.decode(str)          // 原始密文，不是 base64 字符串
p      = RSA_PKCS1_HEX({"aes": key, "uid": "<userid 字符串>", "token": token}).toUpperCase()
query  = clienttime, mid, key=signParamsKey(clienttime), clientver, appid, p
cookie = token; userid; dfid; KUGOU_API_MID; KUGOU_API_GUID; KUGOU_API_DEV
```

- `key` = `md5(appid + saltLite + clientver + clienttime)`（概念版 salt
  `LnT6xpN3khm36zse0QzvmgTZ3waWdRSA`，即 `KugoSign.signParamsKey`）。
- **`notSignature`**：这组接口 **不带** android `signature`。
- 响应用同一 AES key 解密；解不出回落明文 JSON。
- 实现：`tool/probe_cloud_disk.dart` 的 `buildMcloudEnvelope`。

### 列表 `/v1/get_list`

AES `dataMap`：

```json
{ "page": 1, "pagesize": 30, "getkmr": 1 }
```

鉴权只在 RSA `p` + Cookie，**body 里没有 userid/token**。

响应（`status=1`）预期字段（对照 EchoMusic `mapCloudSong` / MoeKoeMusic，**待探针实测**）：

> **2026-09 实测**（`tool/probe_cloud_disk.dart --suite list`）：`data.list` 是
> **JSON 字符串**（空盘为 `""`），不是原生数组；必须 `jsonDecode` 后再映射，否则
> 歌曲永远解析为空。空盘实测：`list_count=0`、`used_size=0`、
> `availble_size=max_size=64424509440`，另带 `type_size`（各类型容量）。
>

| 业务 | 候选 key |
| --- | --- |
| 列表 | `data.list[]` 或 `data.info[]` |
| 总数 | `data.list_count` |
| 容量 | `data.max_size` / `data.used_size` / `data.availble_size`（注意拼写） |
| 云盘文件 ID | `kv_id` / `kvid` / `fileid` |
| hash | `hash` / `audio_info.hash` |
| hash_std | `hash_std` / `audio_info.hash` |
| 曲库 ID | `audio_id` / `audio_info.audio_id`，`album_audio_id` / `mixsongid` |
| 标题 | `filename` / `name` / `songname` |
| 歌手 | `author_name` / `singername` |
| 专辑 | `album_name` / `album_info.album_name` |
| 封面 | `album_info.sizable_cover`（`{size}` 占位）/ `authors[0].sizable_avatar` |
| 时长 | `timelen`（毫秒）/ `duration` |
| 码率档 | `bitrate`：`3=HQ/320` `4=SQ/flac` `5=HR`（MoeKoe 口径；EchoMusic 5=high） |
| 大小 | `size` |

### 播放地址 `/bsstrackercdngz/v2/query_musicclound_url`

Android signature + 默认公共参数（dfid/mid/uuid/appid/clientver/clienttime[/token/userid]）。

module 固定参数：

| 参数 | 值 |
| --- | --- |
| `hash` | 小写 hash |
| `pid` | `20026` |
| `kv_id` | **固定 `2`**（module 硬编码，忽略入参 fileid） |
| `bucket` | `musicclound` |
| `key` | `signCloudKey(hash, 20026)` = `md5("musicclound"+hash+pid+salt)` |
| `ssa_flag` | `is_fromtrack` |
| `version` | `20102` |
| `ssl` | `0` |
| `with_res_tag` | `0` |

盐值：`ebd1ac3134c880bda6a2194537843caa0162e2e7`（`KugoSign.signCloudKey`）。

响应：`status=1` + `data.url` + `data.backup_url[]`（或 `backupUrl`）。

### 删除 `/v1/del_files`

AES `dataMap`：

```json
{ "data": [ { "kv_id": 123, "album_audio_id": 0 } ] }
```

- 入参支持 `fileids` / `fileid` / `kv_ids` / `kv_id`（逗号分隔或数组）。
- **`album_audio_id` 必填**（缺省 0）；数字字段必须是 number。
- 当前 module **不支持** 仅 `hashes` 删除（无 fileid 时直接报「请传入 fileid 或 kv_id」）。
- 删除响应可能带新的 `availble_size` / `used_size` / `max_size`。

### 曲库匹配 `/v2/album_audio/audio`（上传前）

JSON body（无 signature，`x-router: kmr.service.kugou.com`）：

```json
{
  "appid": 3116, "clienttime": 0, "clientver": 11440,
  "data": [ { "hash": "<文件 MD5 或 hash_std>" } ],
  "dfid": "-", "key": "signParamsKey(clienttime)", "mid": "...",
  "show_privilege": 0, "show_author_alias": 0,
  "show_rel_album_audio_info": 0, "show_remarks": 0
}
```

→ `data[]` → 归一化出 `album_audio_id` / `audio_id` / `hash_std` / `author_name` / `audio_name`。

### 上传（二期，五步）

1. **授权** GET `gateway /bsstrackercdngz/v1/upload/auth`
   - `filename` = **文件内容 MD5（小写）**
   - `buVerifyCode` = `md5(appid + "musicclound" + "8ae10344e9738dcb")`
   - → `data.authorization`
2. **初始化分片** POST `bssulbig /v2/multipart/initiate/music`
   - → `external_host` + `upload_id`；**`upload_id` 空 = 秒传**（跳过 3/4）
3. **上传分片** POST `{external_host}/v3/multipart/upload`，**1MB/片**，binary body
4. **完成** POST `{external_host}/v3/multipart/complete`，`md5=filename`
5. **写入云盘** POST `mcloudservice /v1/add_files`（AES+RSA）

`add_files` AES body：

```json
{
  "data": [{
    "name": "歌手 - 歌名.mp3",
    "ext": "mp3",
    "author_name": "歌手",
    "hash": "<bss 返回的 x-bss-filename>",
    "hash_std": "<匹配 hash_std 或文件 MD5>",
    "audio_id": 0,
    "bitrate": 4,
    "album_audio_id": 0,
    "size": 123456,
    "timelen": 0
  }],
  "list_ver": 0
}
```

限制：单文件 **100MB**；`ext` 去点小写。秒传判定：响应 `uploadInfo.upload_id` 为空。

### 探针用法

```powershell
cd app
$env:KUGO_TOKEN = '<token>'
$env:KUGO_USERID = '<userid>'
dart run tool/probe_cloud_disk.dart --suite list
dart run tool/probe_cloud_disk.dart --suite url --hash <HASH>
dart run tool/probe_cloud_disk.dart --suite del --fileid <KV_ID>   # dry-run
dart run tool/probe_cloud_disk.dart --suite del --fileid <KV_ID> --confirm
```

实测后把 `list` 首条完整 JSON 贴回本节，替换「待实测」字段表。

---

## 网易云 MV（2026-09-28 探针打通 · A0）

> 脚本：`dart run tool/probe_netease_mv.dart`
> 对齐 api-enhanced `module/mv_*.js` / `cloudsearch.js`（type=1004）。
> 落地状态与能力口径见 [../网易云接口文档.md](../网易云接口文档.md) §十（A0/A1 已落地，A2 搜索 / A3 收藏未做）。

### ★ weapi 路径坑（第一轮踩过）

api-enhanced / NeteaseCloudMusicApi 的 `request` 对 weapi 做
`'/weapi/' + uri.substr(5)` —— **剥掉 `/api/`**。

| module 写法 | 实际请求 | 本仓 `callWeApi` 应传 |
| --- | --- | --- |
| `/api/v1/mv/detail` | `/weapi/v1/mv/detail` | **`/v1/mv/detail`** |
| `/api/song/enhance/play/mv/url` | `/weapi/song/enhance/play/mv/url` | `/song/enhance/play/mv/url` |
| `/api/artist/mvs` | `/weapi/artist/mvs` | `/artist/mvs` |
| `/api/cloudsearch/pc` | `/weapi/cloudsearch/pc` | `/cloudsearch/pc` |
| `/api/mv/sub` | `/weapi/mv/sub` | `/mv/sub` |
| `/api/cloudvideo/allvideo/sublist` | `/weapi/cloudvideo/allvideo/sublist` | `/cloudvideo/allvideo/sublist` |

传 `/api/...` 会得到 **`code=404 「接口未找到！」`**（第一轮实测）。

### 端点与实测字段

| 端点 | 加密 | 实测 | 说明 |
| --- | --- | --- | --- |
| `POST /weapi/v1/mv/detail` | weapi | ✅ 免登录 | body `{id: mvid}` |
| `POST /weapi/song/enhance/play/mv/url` | weapi | ✅ 免登录 | body `{id, r}`；`r` 会被钳到实际档 |
| `POST /weapi/cloudsearch/pc` | weapi | ✅ 免登录 | `{s, type:1004, limit, offset}` |
| `POST /weapi/cloudsearch/get/web` | weapi | ❌ `50000005` | **不要用**，只认 `/cloudsearch/pc` |
| `POST /weapi/artist/mvs` | weapi | ✅ 免登录 | `{artistId, limit, offset}` |
| `POST /weapi/cloudvideo/allvideo/sublist` | weapi | ⚠️ `301` 未登录 | 需登录态 |
| `POST /weapi/mv/sub` / `/mv/unsub` | weapi | ⚠️ 写操作 | 需登录；`mvId` + `mvIds='["<id>"]'` |
| `songDetail.mv` 字段 | — | ✅ | `0`=无 / `>0`=mvid（`songMvs` 1:1） |

### `mv/detail` 响应（实测 2026-09-28）

顶层 = `{loadingPic..., subed, mp, data, code: 200}`。

`data` 字段：

| 字段 | 实测值示例 | 映射 |
| --- | --- | --- |
| `id` | `14514682` | `MvBrief.id`（mvid） |
| `name` | `晴天` | `MvBrief.name` |
| `artistName` / `artists[].name` | `高伟` / `莫文蔚 / 张洪量` | `MvBrief.artist` |
| `cover` | `http://p4.music.126.net/...jpg` | `MvBrief.coverUrl` |
| `duration` | `192000`（毫秒） | `MvBrief.durationMs` |
| `publishTime` | `2022-03-25` | `MvBrief.publishDate` |
| `desc` / `briefDesc` | 文本或 null | `MvDetail.description` |
| `playCount` / `subCount` / `commentCount` / `shareCount` | 整数 | 统计行 |
| `commentThreadId` | `R_MV_5_14514682` | 评论线程 id |
| `videoGroup[]` | `{id, name, type}` | 可作 tags |

**★ `brs` 是 List 不是 Map，且不含 url**：

```json
"brs": [
  { "size": 10456657.0, "br": 240, "point": 0 },
  { "size": 20453720.0, "br": 480, "point": 0 },
  { "size": 32049460.0, "br": 720, "point": 0 },
  { "size": 10533121.0, "br": 1080, "point": 0 }
]
```

只用来**枚举档位**（`br` + `size`）；播放地址一律走 `mv/url` 现取。
方案文档 §4.2 原先假设 `brs` 是 `{r: url}` Map，**已按实测更正**。

**`mp` 是特权位**（与 `data` 平级）：

```json
"mp": { "pl": 1080, "dl": 1080, "cp": 1, "st": 0, "fee": 0, "unauthorized": false }
```

`pl` = 可播最高码率，`dl` = 可下最高码率。低权限 MV 例：`5436712`（广岛之恋）`pl=480`，
请求 `r=1080` 时 `mv/url` **只回 480**。

### `mv/url` 响应（实测）

```json
{
  "code": 200,
  "data": {
    "id": 14514682,
    "url": "http://vodkgeyttp8.vod.126.net/cloudmusic/obj/core/....mp4?wsSecret=...&wsTime=...",
    "r": 1080,
    "size": 10533121,
    "md5": "",
    "code": 200,
    "expi": 3600,
    "fee": 0,
    "mvFee": 0,
    "st": 0,
    "msg": ""
  }
}
```

| 要点 | 实测结论 |
| --- | --- |
| `data.url` | mp4 直链（`wsSecret` + `wsTime` 签名），**短时效** |
| 时效字段名 | **`expi`（秒）**，不是 `validity`（实测 `validity` 为 null） |
| `r` | **回显实际档**，请求 1080 但权限不足时回 480 |
| `backupUrls` | 无（与酷狗不同，单条 url） |
| 失败形态 | 无 url 时 `data.url` 为空 / `code != 200` |

### `cloudsearch type=1004` 响应（实测）

`result.mvCount` + `result.mvs[]`，列表项字段：

| 字段 | 示例 | 映射 `MvBrief` |
| --- | --- | --- |
| `id` | `14514682` | `id` |
| `name` | `晴天` | `name` |
| `cover` | `http://...jpg` | `coverUrl`（★ 是 `cover`） |
| `artistName` / `artists[].name` | `高伟` | `artist` |
| `duration` | `192000` | `durationMs` |
| `playCount` | `1114797` | 统计 |
| `briefDesc` / `desc` | 可 null | — |
| `mark` / `alias` / `transNames` | — | 可忽略 |

### `artist/mvs` 响应（实测）

`{mvs: [...], hasMore: true}`，列表项字段：

| 字段 | 映射 |
| --- | --- |
| `id` / `name` | `MvBrief.id` / `name` |
| **`imgurl`** | `coverUrl`（★ 与搜索的 `cover` **不同名**） |
| `imgurl16v9` | 备用封面 |
| `artistName` / `artist.name` | `artist` |
| `duration` / `playCount` / `publishTime` | 对应字段 |
| `subed` | 是否已收藏 |
| `status` | 0=正常 / 1=可能不可见 |

### `song.mv`（`songMvs` 1:1）

实测 `songId=25906124`（不要说话）→ `mv=303284`；
`songId=186016`（晴天）→ `mv=0`。

语义确认：**`0` = 无 MV → 空列表；`>0` = mvid → 返回单元素列表**。
不要用 `simi_mv`（相似推荐）冒充多版本。

### 探针用法

```powershell
cd app
# 免登录：详情 + 取流 + 搜索
dart run tool/probe_netease_mv.dart
dart run tool/probe_netease_mv.dart --mvid 14514682 --r 1080

# 单项
dart run tool/probe_netease_mv.dart --suite detail --mvid 14514682
dart run tool/probe_netease_mv.dart --suite search --keyword 晴天
dart run tool/probe_netease_mv.dart --suite artist --artist 6452
dart run tool/probe_netease_mv.dart --suite songmv --song 25906124

# 收藏（sublist 需登录；sub 为写操作）
dart run tool/probe_netease_mv.dart --suite sublist
dart run tool/probe_netease_mv.dart --suite sub --mvid 14514682 --write --collect true
```

### A0 结论（对 A1 mapper 的影响）

1. `MvPlaySource` 的档位从 `brs[].br` 枚举；`hash` 存 `mvid@r`（如 `14514682@1080`）
2. `resolveMvPlayUrl` 拆 `@` 得 mvid + r，调 `mv/url`；返回 `url` + `expi`
3. 搜索封面 key 是 `cover`，歌手 MV 是 `imgurl` —— mapper 要**双 key 回退**
4. `songMvs` 只做 1:1（`song.mv`）；版本切换 UI 对网易自然退化
5. 收藏 / 收藏列表需登录；游客搜索 + 详情 + 取流可播
