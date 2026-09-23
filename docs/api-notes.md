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

**歌词**：download 返回 JSON，`content` 为 **base64 LRC**；只取前 2 个候选，避免刷日志。

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

## 探测脚本

```powershell
cd app
dart run tool/probe_api.dart
```

## 下一步（可选）

1. 校准多版本接口字段差异（mapper 已做多候选宽容解析）
2. 真机网络异常场景复测（URL 过滤 / 风控 20028）
3. 自建歌单写入接口调研（若做 CRUD）
