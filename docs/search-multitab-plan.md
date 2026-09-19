# 搜索多维度（P1 #6）改造评估

> 状态：**仅评估，未动代码**
> 参考：`D:\work\EchoMusic`（v2.3.2-beta.5）
> 现场：`kugoFlutter` @ 62bdceb

## 一、结论先行

**可以做，成本中等（约 1.5–2 人日），但 tab 集应比 EchoMusic 少一档。**

三条结论：

1. **不需要"扩展 `searchSong` 的 `type` 参数"** —— 原 backlog 写的这条路是错的。
   酷狗 mobilecdn 的多类型搜索是**五个独立接口**，不是同一接口换参数（见下节实测证据）。
2. **歌词 tab 必须砍掉** —— 本网络环境（以及所有可达主机）都没有歌词搜索接口，
   且项目已有一个「按 hash 查歌词」的能力，语义不同，不能复用。
3. **歌手 tab 是这次改造的隐藏最大收益** —— 它顺手修掉了一个**波及 7 处的真 bug**：
   全项目所有「点歌手」的入口跳的都是 `/artist/<歌手名字>`，而
   `fetchArtist()` 要的是 **singerid**（纯数字），所以歌手详情页目前
   **100% 加载失败**。实测证据见 §3.4。

建议 tab 集：**歌曲 / 歌单 / 专辑 / 歌手**（4 个），MV 与歌词不做。

---

## 二、实测证据（关键，决定了方案形态）

### 2.1 多类型是五个独立接口，`showtype` 不是类型开关

用 PowerShell 直连 `mobilecdn.kugou.com` 逐个探测（本次全部实测通过）：

| 接口 | HTTP | 顶层结构 | 是否可用 |
| --- | --- | --- | --- |
| `/api/v3/search/song` | 200 | `data.info[]` + `data.total` | ✅ |
| `/api/v3/search/special` | 200 | `data.info[]` + `data.total` | ✅ |
| `/api/v3/search/album` | 200 | `data.info[]` + `data.total` | ✅ |
| `/api/v3/search/singer` | 200 | **`data` 直接是数组** + **无 total** | ✅ |
| `/api/v3/search/mv` | 200 | `data.info[]` + `data.total` | ✅ |
| `/api/v3/search/lyric` | **404** | — | ❌ |

**`showtype` 实测不是类型开关**：`showtype=0` 与 `showtype=1` 返回**逐字节相同**的响应；
`showtype=2` 只是额外多返回一个 `relative.singer` 纠错块（"你是不是想找 DJ晴天"），
`data.info` 仍是同一批歌曲。所以**不要**试图用 `showtype` 切类型。

> 这一点直接推翻了 gap 文档里"扩展 `searchSong` 接口的 `type` 参数"的写法。

### 2.2 歌词搜索确实不存在

试了 6 个主机全部 404：`mobilecdn` / `wwwapi` / `trackercdn` /
`songsearch.kugou.com` / `msearchcdn.kugou.com` / `mobiles.kugou.com`。

`endpoints.dart` 里已有 `searchLyric = '/api/v3/search/lyric'` 常量但**从未被调用**
（全项目 grep 无引用）—— 大概率就是当年试出来 404 后留下的死常量。

**注意区分两个不同语义**：
- 我们要的「歌词搜索」= 按**关键词**找歌（`search/lyric`）→ **拿不到**
- 项目已有的 `lyricSearch = '/search'` @ `lyrics.kugou.com` = 按 **hash** 取歌词文本 → 能拿到，但这是另一回事

EchoMusic 能做歌词 tab 是因为它有自建后端 `server/`（`request.get('/search', {params:{keywords, type}})`），
后端走的是**签名网关**那条路。kugoFlutter 只用公开无签名 HTTP 接口，没有这条路。

### 2.3 各接口字段（已实测，可直接照抄写 mapper）

**special（歌单）** —— `data.info[]`：
```
specialid, specialname, playcount, songcount, nickname,
imgurl (含 {size} 占位), intro, gid, suid, publishtime, contain
```
→ 与现有 `mapPlaylistInfo()` 的字段名**高度重合**（它也吃 `specialid`/`specialname`/
`playcount`/`songcount`/`nickname`/`imgurl`/`intro`），可复用度约 90%。

**album（专辑）** —— `data.info[]`：
```
albumid, albumname, singername, songcount, imgurl,
publishtime, intro, auxiliary, singerid, privilege
```
→ 路由 `/album/:id` 需要 `albumid`，字段齐全。

**singer（歌手）** —— `data` **直接是数组**，元素只有：
```json
{"singername": "周杰伦", "singerid": 3520}
```
→ **没有头像、没有歌曲数、没有粉丝数**。UI 只能用「文字列表 / 文字+占位圆」，
不能像 EchoMusic 那样出带图的卡片。这是接口层面的硬约束，不要试图从别处补图
（每补一张图就多一次请求，等于 N+1）。

**mv** —— `data.info[]`：
```
hash, filename, singername, duration(秒), imgurl(含 {size}),
album_id, publishdate, historyheat, is_ugc, intro
```
→ 字段够用，但**本项目没有 MV 播放页**，做了也点不进去。故不做。

**song** 补充发现：搜索响应里带 `mvhash` 字段（晴天有 MV）。
如果想做「歌曲行上的 MV 角标 → 打开 MV」，数据是现成的，但同样缺落地页。

### 2.4 `data.total` 可用于精确分页

song / special / album / mv 都返回 `data.total`（实测 `480` / `480` / `500` / `500`）。
singer **不返回 total**。

这点比 EchoMusic 的现状更省事 —— EchoMusic 在 `searchHelpers.ts:43`
专门写了个 `extractSearchTotal()` 兼容 8 种字段名，因为它后端要适配多平台。
我们用单一源，直接读 `data.total` 即可。

---

## 三、现状盘点

### 3.1 UI 层：单 tab，且是 `setState` 裸管理

`lib/features/search/search_page.dart` 共 222 行，全页只有搜索框 + 一个 `ListView`。
状态全是局部字段：`_loading` / `_searched` / `_error` / `_results` / `_hot`。

**没有分页**、**没有 repository 抽象**（直接 `final _repo = searchRepository`）、
**没有 notifier**。加 4 个 tab 若继续用 `setState` 平铺，会变成 4 份
`_loadingX` / `_errorX` / `_resultsX` —— 明显的坏味道。

### 3.2 数据层：`_extractList` 对 singer 会失效

`search_repository.dart:78` 的 `_extractList()` 依次找 `data.info` → `info` → `list`。
而 singer 接口的 `data` **本身就是数组**，`data['info']` 不存在 →
**当前 `_extractList` 对 singer 返回空**。必须扩展。

### 3.3 已具备的复用资产（好消息）

- **三个详情页路由都在**：`/playlist/:id`、`/album/:id`、`/artist/:id`（`app.dart:79/85/91`）
- **`PlaylistBrief` 模型已存在**（`track.dart:84`）
- **`mapPlaylistInfo()` 已存在**（`mappers.dart:124`）且字段吻合 special 接口
- **`AlbumDetail` / `ArtistDetail` 模型与 repository 方法都已实现**
  （`catalog_repository.dart`：`fetchAlbum` / `fetchArtist`）

也就是说 **数据层的"落地页"已经全部建好，缺的只是"搜索入口"这一层**。这是本次改造成本可控的根本原因。

### 3.4 现有 bug：歌手跳转传错了东西（**波及 7 个调用点**）

全项目所有「点歌手头像/名字」的入口，传的都是**歌手名字**当 id：

| 文件 | 行 |
| --- | --- |
| `features/search/search_page.dart` | 162 |
| `features/song/song_detail_page.dart` | 242 |
| `features/recommend/daily_recommend_page.dart` | 206 |
| `features/likes/likes_page.dart` | 82 |
| `features/playlist/playlist_detail_page.dart` | 195 |
| `features/album/album_detail_page.dart` | 177 |
| `features/explore/explore_page.dart` | 215 |

统一写法都是：
```dart
'/artist/${Uri.encodeComponent(track.artist)}'   // ← 传的是名字
```
而链路另一端当 **singerid** 用：
```dart
// artist_detail_page.dart:39
final remote = await catalogRepository.fetchArtist(widget.id);
// catalog_repository.dart:117-120
buildUrl(KugoEndpoints.mobileCdn, KugoEndpoints.singerInfo, {
  'singerid': id,          // ← 传了中文名字
  'format': 'json',
});
```

**实测证据**（本次直连接口验证）：

| 请求 | 响应 |
| --- | --- |
| `singer/info?singerid=3520` | HTTP 200，**3068 字节**正常数据（`singername:周杰伦`、`songcount:1833`、完整 `profile` 简介） |
| `singer/info?singerid=周杰伦` | HTTP 200，**39 字节**：`{"errcode":0,"status":0,"error":"参数错误"}` |

→ `fetchArtist` 内部 `singerInfo` 返回空 → `data` 为空 → `name` 落到默认值 `'歌手'`、
`avatar` 落到 id 本身 → **最终 `remote.songs.isEmpty` → 页面显示「歌手加载失败：接口不可用或无公开数据」**。

**结论：7 个入口全都在跳一个必然报错的页面。**

但要说清楚一点：**这不是"多 tab 改造"引入的，而是既有的 bug**，跟搜索 tab 无关。
之所以这次值得一起修，是因为：
- 歌手 tab 天然就拿得到 `singerid`，做 tab 时顺手就有正确值可用；
- 但**歌曲 tab / 歌单 tab 等处的 `onArtistTap` 拿不到 singerid** ——
  `Track` 模型里**没有存 singers 的 id**（`mapMobileSearchSong` 只取了
  `singername` 拼成 `artist` 字符串，`mappers.dart:62-66`）。

所以完整修复需要**两件事**：
1. `Track` 增加 `artistId`（从搜索响应的 `singers[].id` /
   `AuthorId` / `singerid` 取，EchoMusic 的 `mapSearchSong` 就是这么做的，
   见 `mappers/song.ts:635-660`）；
2. 7 个调用点改为 `track.artistId`（为空时**不跳转**或降级为搜索该歌手名）。

第 2 步是纯机械替换，但第 1 步要动 `Track` 模型与 mapper，**会外溢到本次 tab 改造之外**。
建议：**把歌手跳转修复拆成独立的一次提交**（见 §五 的提交拆分建议），
不要混进 tab 的 diff 里，否则 review 会很难看清。

---

## 四、方案设计

### 4.1 Tab 集与落地页对照

| Tab | 接口 | 落地页 | 说明 |
| --- | --- | --- | --- |
| 歌曲 | `search/song` | 播放器 | 已有 |
| 歌单 | `search/special` | `/playlist/:specialid` | ✅ 页已存在 |
| 专辑 | `search/album` | `/album/:albumid` | ✅ 页已存在 |
| 歌手 | `search/singer` | `/artist/:singerid` | ✅ 页已存在，**顺带修 bug** |
| ~~歌词~~ | ❌ 无接口 | — | **不做** |
| ~~MV~~ | `search/mv` ✓ | ❌ 无播放页 | **不做**（数据够，缺落地页） |

### 4.2 数据层改动

新文件 `lib/core/models/search_result.dart`（或塞进 `track.dart`，看团队偏好）：
```dart
class SearchPage<T> {          // 单类型的一页结果
  final List<T> items;
  final int total;
  final bool hasMore;
}
class ArtistBrief {            // singer 接口只有这两个字段
  final String id;
  final String name;
}
class AlbumBrief { id, name, coverUrl, artist, trackCount, publishDate }
```

`mappers.dart` 新增：
- `mapAlbumBrief(json)` —— 吃 `albumid`/`albumname`/`singername`/`songcount`/`imgurl`
- `mapArtistBrief(json)` —— 吃 `singerid`/`singername`，就这两个
- special 直接复用现有 `mapPlaylistInfo()`（先核对一遍 `gid` 与 `specialid` 的取舍）

`search_repository.dart` 新增：
```dart
enum SearchType { song, playlist, album, artist }

Future<SearchPage<Track>>        searchSongs(kw, {page});
Future<SearchPage<PlaylistBrief>> searchPlaylists(kw, {page});
Future<SearchPage<AlbumBrief>>    searchAlbums(kw, {page});
Future<SearchPage<ArtistBrief>>   searchArtists(kw, {page});
```
外加 **`_extractList` 必须改**：加一条 `if (dataNode is List) return dataNode;`，
否则 singer 永远空结果。

### 4.3 状态层：建议上 Riverpod notifier

理由不是"架构洁癖"，而是**实测需求**：EchoMusic 的
`paginationState[type]`（`Search.vue:85-88`）为六个 tab 各存一份
`{page, hasMore, loadingMore, loading, loaded, total}`。

4 个 tab × 6 个字段，用 `setState` 平铺会变成 24 个局部变量 + 4 套几乎重复的
load-more 分支。建议：
```dart
// lib/features/search/search_controller.dart
final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);

class TabState {                  // 每个 tab 一份
  final List<Object> items;
  final int page, total;
  final bool loading, loadingMore, loaded;
  final String error;
}
class SearchState {
  final SearchType active;
  final String keyword;
  final Map<SearchType, TabState> tabs;   // 懒加载：首次切到才请求
}
```
**关键行为（照抄 EchoMusic 的语义，实测合理）**：
- **懒加载**：切到某 tab 才首次请求，不是一次并发打 4 个接口
- **各 tab 独立分页**：翻到第 3 页切走再切回，仍在第 3 页
- **换关键词清空全部 tab**
- **切 tab 不重复请求**已 loaded 的 tab

### 4.4 UI 层改动

`search_page.dart` 改造点：
1. 搜索框下加 `TabBar`（4 tab，`isScrollable: false` 够用），或自定义 chip 行
   （项目已有 `KugoRadius.chip` 与若干 chip 样式，视觉效果更贴现有风格）
2. 各 tab 一个 `ListView`，滚到底 `NotificationListener<ScrollNotification>` 触发 load-more
3. 结果卡片：歌单/专辑可复用现有 `CoverBox` + 两行文字的横向卡片；
   歌手**按接口约束只能纯文字**（`ListTile` + 圆形占位头像）
4. 空态/错误态复用现有 `AsyncBody`（`shared/widgets/async_body.dart`）
5. **歌手点击传 `singerid`，顺手修 bug**

### 4.5 分页尺寸

沿用 `SEARCH_PAGE_SIZE = 30`（与 EchoMusic 一致，与现有 `searchSongs` 默认 `pageSize: 30` 一致）。
`hasMore` 判定：`page * 30 < total`（有 total 时）；singer 无 total →
退化为 `items.length >= 30`。

---

## 五、工作量与排期建议

| 步骤 | 内容 | 预估 |
| --- | --- | --- |
| 1 | 数据层：3 个 mapper + `_extractList` 修复 + 4 个 repository 方法 | 0.5 人日 |
| 2 | 状态层：`SearchController` + `TabState` + 懒加载/独立分页 | 0.5 人日 |
| 3 | UI 层：TabBar + 3 种结果卡片 + 分页触发 | 0.5–1 人日 |
| 3.5 | **（可选）歌手跳转 bug 修复**：`Track.artistId` + 7 个调用点 | 0.5 人日 |
| 4 | 测试（mapper 单测、tab 切换、分页、懒加载不重复请求） | 0.5 人日 |
| | **合计** | **约 2 人日**（含歌手修复 **2.5 人日**） |

**建议拆三次提交**：
- **commit A**：`Track.artistId` + 7 个调用点修复 + 对应测试
  （独立可验证：从任意入口点歌手，详情页能真出数据了）
- **commit B**：数据层（mapper + repository + `_extractList`）
- **commit C**：状态层 + UI tab（功能主体）

这样即便 tab UI 方案要改，前两次提交的价值已经落地、不会被推翻。
commit A 本身就已经是一个**独立可发布的质量修复**，价值不依赖 tab 改造是否推进。

---

## 六、风险与决策点

### 决策点 1：Tab 集要不要包含 MV？
- **建议不做**。`search/mv` 接口实测可用、字段齐全，但**本项目没有 MV 播放页**，
  用户点进去是死路 —— 比"没有这个 tab"体验更差。
- 如果将来要做 MV 播放（是 P1 之外的新工程），届时打开 tab 只需接一个已有 mapper。

### 决策点 2：歌词 tab 是否永久放弃？
- 在"不引入签名网关"的约束下，**是**。
- 若将来 P1 #7 自建歌单已经把签名链路打通（`gateway.kugou.com`），
  可以回头评估签名版 `search/lyric` 是否可达 —— 但**不要为歌词搜索单独打通签名链路**。

### 决策点 3：歌单 tab 用 `specialid` 还是 `gid` 做路由 id？
- special 接口同时给 `specialid`（数字，如 `7845129`）和 `gid`
  （如 `collection_3_509005046_32_0`）。
- 现有 `PlaylistBrief.id` 在 `mapPlaylistInfo` 里取的是
  `global_collection_id → specialid → id` 优先级。
- **需要先验证 `/playlist/:id` 详情页吃哪个**，否则会重演歌手那个 bug。
  ⚠️ **这是实施前必须落地的一步验证**（读 `playlist_detail_page.dart` +
  `fetchPlaylist` 即可确认，10 分钟）。

### 风险 1：singer 接口信息量过少
只有 `singername` + `singerid`。UI 上会显得比 EchoMusic 单薄。
**不要为了"好看"去给每个歌手补一次 `singerInfo` 请求**（N+1，30 条结果就是 30 个请求）。
接受文字列表。

### 风险 2：`_extractList` 的修改会波及现有调用方
`_extractList` 同时被 `searchSongs` / `hotKeywords` 使用。
新增 `if (dataNode is List) return dataNode;` 分支对现有调用是**纯增量**
（原来走到这个分支只会返回 `const []`），但仍需回归 `hotKeywords` 与歌曲搜索。

### 风险 3：没验证过 special/album 详情页在**公开无登录**下的可用性
`catalog_repository.fetchAlbum/fetchArtist` 走的是同一个 `mobileCdn`，
理论上同源同权限，但实测未做。建议实施第一步就顺手各打一次接口确认。

---

## 七、与 EchoMusic 的差异对照（供参考）

| 维度 | EchoMusic | kugoFlutter 计划 |
| --- | --- | --- |
| Tab 数 | 6（歌曲/歌单/专辑/歌手/歌词/MV） | **4**（砍歌词、MV） |
| 数据来源 | 自建后端 `/search?type=` → 签名网关 | 直连 mobilecdn 5 个公开接口 |
| 分页状态 | 6 份 `paginationState` + `PagedSongLoader` | 4 份 `TabState`，无需单独 loader |
| total 兼容 | `extractSearchTotal()` 兼容 8 种字段名 | 直接读 `data.total`（singer 除外） |
| 结果排序 | 歌曲支持点表头排序（`sortSongs`） | **不做**（移动端列头排序体验差） |
| 吸顶 tab | `showPinnedTabs`（滚动 80px 后吸顶） | 可不做，或复用 `SliverAppBar` |

---

## 八、实施前必做的三项验证

1. **`/playlist/:id` 吃 `specialid` 还是 `gid`**（读 `playlist_detail_page.dart`）
2. **无登录态下 `fetchAlbum` 是否真能返回数据**（打一次接口；
   歌手那条本次已实测通过：`singerid=3520` → 3068 字节正常数据）
3. **回归 `hotKeywords`**（因为要改 `_extractList`）

---

## 九、本次实测已验证 / 未验证清单

**已实测通过（可直接依赖）**
- ✅ `search/song` / `search/special` / `search/album` / `search/singer` / `search/mv` 五个接口
- ✅ `showtype` **不是**类型开关（0 与 1 响应逐字节相同）
- ✅ `search/lyric` 在 6 个候选主机上全部 404
- ✅ `singer/info?singerid=3520` 返回 3068 字节正常数据
- ✅ `singer/info?singerid=周杰伦` 返回 `{"status":0,"error":"参数错误"}`
- ✅ special 响应的 `imgurl` / album 的 `imgurl` / mv 的 `imgurl` 含 `{size}` 占位
  → 可直接喂现有 `normalizeCoverUrl()`

**未验证（实施时第一步就测）**
- ⬜ `/playlist/:id` 详情页接受 `specialid` 还是 `gid`
- ⬜ `album/info` 与 `album/songs` 在无登录态的可用性（`fetchAlbum` 链路）
- ⬜ singer 搜索结果的 `singerid` 是否能直接喂 `/artist/:id`（**大概率可以**，
      与 `singer/info` 同参数名，但仍需实测一次）

---

## 附：本次探测命令备忘

```powershell
# 五个类型接口（全部 200）
http://mobilecdn.kugou.com/api/v3/search/song?format=json&keyword=晴天&page=1&pagesize=2&showtype=1
http://mobilecdn.kugou.com/api/v3/search/special?format=json&keyword=晴天&page=1&pagesize=2
http://mobilecdn.kugou.com/api/v3/search/album?format=json&keyword=晴天&page=1&pagesize=2
http://mobilecdn.kugou.com/api/v3/search/singer?format=json&keyword=周杰伦&page=1&pagesize=2
http://mobilecdn.kugou.com/api/v3/search/mv?format=json&keyword=晴天&page=1&pagesize=2

# 歌词搜索（全部 404）
http://mobilecdn.kugou.com/api/v3/search/lyric   ← 404
http://wwwapi.kugou.com/api/v3/search/lyric      ← 404
http://trackercdn.kugou.com/api/v3/search/lyric  ← 404
http://songsearch.kugou.com/api/v3/search/lyric  ← 404
http://msearchcdn.kugou.com/api/v3/search/lyric  ← 404
http://mobiles.kugou.com/api/v3/search/lyric     ← 404
```
